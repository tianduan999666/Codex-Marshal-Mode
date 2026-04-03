# API 限流队列管理器
# 用途：在多 Agent 并行场景下，避免触发 API 限流（429 错误）
# 实现：请求队列 + 指数退避 + 并发数限制

param(
    [Parameter(Mandatory = $true)]
    [scriptblock]$RequestAction,

    [Parameter(Mandatory = $false)]
    [hashtable]$RequestParams = @{},

    [int]$MinIntervalMs = 1000,
    [int]$MaxConcurrent = 2,
    [int]$MaxRetries = 3,
    [int]$InitialBackoffMs = 5000
)

$ErrorActionPreference = 'Stop'

# 全局队列状态（使用文件锁保护）
$global:RateLimitStatePath = ".codex/chancellor/.rate-limit-state.json"

function Get-RateLimitState {
    $mutexName = "Global\RateLimitState"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)

    try {
        $mutex.WaitOne() | Out-Null

        if (Test-Path $global:RateLimitStatePath) {
            $state = Get-Content $global:RateLimitStatePath -Raw | ConvertFrom-Json
            return @{
                LastRequestTime = [DateTime]::Parse($state.LastRequestTime)
                ActiveRequests = $state.ActiveRequests
            }
        }
        else {
            return @{
                LastRequestTime = [DateTime]::MinValue
                ActiveRequests = 0
            }
        }
    }
    finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

function Set-RateLimitState {
    param(
        [DateTime]$LastRequestTime,
        [int]$ActiveRequests
    )

    $mutexName = "Global\RateLimitState"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)

    try {
        $mutex.WaitOne() | Out-Null

        $state = @{
            LastRequestTime = $LastRequestTime.ToString("o")
            ActiveRequests = $ActiveRequests
        }

        $directory = Split-Path -Parent $global:RateLimitStatePath
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        $state | ConvertTo-Json | Set-Content $global:RateLimitStatePath -Encoding UTF8
    }
    finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

function Invoke-RateLimitedRequest {
    param(
        [scriptblock]$Action,
        [hashtable]$Params,
        [int]$MinInterval,
        [int]$MaxConcurrency,
        [int]$Retries,
        [int]$BackoffMs
    )

    $retryCount = 0
    $currentBackoff = $BackoffMs

    while ($retryCount -lt $Retries) {
        try {
            # 检查并发数限制
            $state = Get-RateLimitState

            while ($state.ActiveRequests -ge $MaxConcurrency) {
                Write-Warning "当前并发数已达上限（$($state.ActiveRequests)/$MaxConcurrency），等待 500ms"
                Start-Sleep -Milliseconds 500
                $state = Get-RateLimitState
            }

            # 检查请求间隔
            $elapsed = (Get-Date) - $state.LastRequestTime
            if ($elapsed.TotalMilliseconds -lt $MinInterval) {
                $sleepMs = $MinInterval - $elapsed.TotalMilliseconds
                Write-Host "等待 $([int]$sleepMs) ms 以满足最小请求间隔"
                Start-Sleep -Milliseconds $sleepMs
            }

            # 增加活跃请求计数
            Set-RateLimitState -LastRequestTime (Get-Date) -ActiveRequests ($state.ActiveRequests + 1)

            try {
                # 执行请求
                $result = & $Action @Params
                Write-Host "✓ API 请求成功"
                return $result
            }
            finally {
                # 减少活跃请求计数
                $state = Get-RateLimitState
                Set-RateLimitState -LastRequestTime $state.LastRequestTime -ActiveRequests ([Math]::Max(0, $state.ActiveRequests - 1))
            }
        }
        catch {
            $errorMessage = $_.Exception.Message

            # 检测 429 限流错误
            if ($errorMessage -match '429' -or $errorMessage -match 'rate.?limit' -or $errorMessage -match 'too.?many.?requests') {
                $retryCount++

                if ($retryCount -ge $Retries) {
                    Write-Error "API 限流错误（已重试 $Retries 次）：$errorMessage"
                    throw
                }

                Write-Warning "检测到 API 限流，等待 $currentBackoff ms 后重试（第 $retryCount/$Retries 次）"
                Start-Sleep -Milliseconds $currentBackoff

                # 指数退避
                $currentBackoff = $currentBackoff * 2
            }
            else {
                # 非限流错误，直接抛出
                throw
            }
        }
    }
}

try {
    Invoke-RateLimitedRequest `
        -Action $RequestAction `
        -Params $RequestParams `
        -MinInterval $MinIntervalMs `
        -MaxConcurrency $MaxConcurrent `
        -Retries $MaxRetries `
        -BackoffMs $InitialBackoffMs
}
catch {
    Write-Error "Invoke-RateLimitedRequest 执行失败：$($_.Exception.Message)"
    exit 1
}
