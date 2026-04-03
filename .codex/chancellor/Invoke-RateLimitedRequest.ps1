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
$repositoryRootPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# 全局队列状态（使用文件锁保护）
$global:RateLimitStatePath = Join-Path $repositoryRootPath '.codex/chancellor/.rate-limit-state.json'

function Invoke-WithRateLimitStateLock {
    param(
        [scriptblock]$Action
    )

    $mutexName = "Global\RateLimitState"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $lockAcquired = $false

    try {
        $lockAcquired = $mutex.WaitOne()
        return & $Action
    }
    finally {
        if ($lockAcquired) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Get-RateLimitStateUnsafe {
    if (Test-Path $global:RateLimitStatePath) {
        $state = Get-Content $global:RateLimitStatePath -Raw | ConvertFrom-Json
        return @{
            LastRequestTime = [DateTime]::Parse($state.LastRequestTime)
            ActiveRequests = [int]$state.ActiveRequests
        }
    }

    return @{
        LastRequestTime = [DateTime]::MinValue
        ActiveRequests = 0
    }
}

function Set-RateLimitStateUnsafe {
    param(
        [DateTime]$LastRequestTime,
        [int]$ActiveRequests
    )

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

function Acquire-RateLimitSlot {
    param(
        [int]$MinInterval,
        [int]$MaxConcurrency
    )

    while ($true) {
        $acquireResult = Invoke-WithRateLimitStateLock -Action {
            $state = Get-RateLimitStateUnsafe
            $now = Get-Date

            if ($state.ActiveRequests -ge $MaxConcurrency) {
                return @{
                    Acquired = $false
                    SleepMs = 500
                    Reason = 'concurrency'
                    ActiveRequests = $state.ActiveRequests
                }
            }

            $elapsed = $now - $state.LastRequestTime
            if ($elapsed.TotalMilliseconds -lt $MinInterval) {
                return @{
                    Acquired = $false
                    SleepMs = [Math]::Ceiling($MinInterval - $elapsed.TotalMilliseconds)
                    Reason = 'interval'
                    ActiveRequests = $state.ActiveRequests
                }
            }

            Set-RateLimitStateUnsafe -LastRequestTime $now -ActiveRequests ($state.ActiveRequests + 1)
            return @{
                Acquired = $true
                SleepMs = 0
                Reason = 'acquired'
                ActiveRequests = $state.ActiveRequests + 1
            }
        }

        if ($acquireResult.Acquired) {
            return $acquireResult
        }

        if ($acquireResult.Reason -eq 'concurrency') {
            Write-Warning "当前并发数已达上限（$($acquireResult.ActiveRequests)/$MaxConcurrency），等待 $($acquireResult.SleepMs)ms"
        }
        else {
            Write-Host "等待 $([int]$acquireResult.SleepMs) ms 以满足最小请求间隔"
        }

        Start-Sleep -Milliseconds $acquireResult.SleepMs
    }
}

function Release-RateLimitSlot {
    Invoke-WithRateLimitStateLock -Action {
        $state = Get-RateLimitStateUnsafe
        Set-RateLimitStateUnsafe -LastRequestTime $state.LastRequestTime -ActiveRequests ([Math]::Max(0, $state.ActiveRequests - 1))
        return $null
    } | Out-Null
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
            # 原子地抢占并发槽位与最小请求间隔
            Acquire-RateLimitSlot -MinInterval $MinInterval -MaxConcurrency $MaxConcurrency | Out-Null

            try {
                # 执行请求
                $result = & $Action @Params
                Write-Host "✓ API 请求成功"
                return $result
            }
            finally {
                # 减少活跃请求计数
                Release-RateLimitSlot
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
