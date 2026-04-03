# 文件并发安全追加函数
# 用途：在多 Agent 并行场景下，安全地追加内容到文件
# 实现：PowerShell Mutex + 指数退避重试

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $true)]
    [string]$Content,

    [int]$MaxRetries = 3,
    [int]$InitialBackoffMs = 100
)

$ErrorActionPreference = 'Stop'

function Write-SafeAppend {
    param(
        [string]$Path,
        [string]$Text,
        [int]$Retries,
        [int]$BackoffMs
    )

    $mutexName = "Global\FileAppend_" + ($Path -replace '[\\/:*?"<>|]', '_')
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $retryCount = 0
    $currentBackoff = $BackoffMs

    while ($retryCount -lt $Retries) {
        try {
            # 尝试获取互斥锁（最多等待 5 秒）
            $acquired = $mutex.WaitOne(5000)

            if (-not $acquired) {
                throw "无法获取文件锁：$Path（超时 5 秒）"
            }

            try {
                # 在锁保护下追加内容
                Add-Content -Path $Path -Value $Text -Encoding UTF8
                Write-Host "✓ 成功追加内容到：$Path"
                return $true
            }
            finally {
                # 释放互斥锁
                $mutex.ReleaseMutex()
            }
        }
        catch {
            $retryCount++

            if ($retryCount -ge $Retries) {
                Write-Error "文件追加失败（已重试 $Retries 次）：$Path`n错误：$($_.Exception.Message)"
                throw
            }

            Write-Warning "文件追加失败，等待 $currentBackoff ms 后重试（第 $retryCount/$Retries 次）"
            Start-Sleep -Milliseconds $currentBackoff

            # 指数退避
            $currentBackoff = $currentBackoff * 2
        }
    }

    return $false
}

try {
    # 确保目标文件所在目录存在
    $directory = Split-Path -Parent $FilePath
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    # 执行安全追加
    Write-SafeAppend -Path $FilePath -Text $Content -Retries $MaxRetries -BackoffMs $InitialBackoffMs
}
catch {
    Write-Error "Invoke-SafeFileAppend 执行失败：$($_.Exception.Message)"
    exit 1
}
