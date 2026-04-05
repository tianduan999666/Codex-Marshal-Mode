param(
    [string]$RepoRootPath = '.',
    [switch]$ClearStaleLock
)

$ErrorActionPreference = 'Stop'

function Resolve-GitDirectoryPath {
    param([string]$RepoRootPath)

    $resolvedRepoRootPath = (Resolve-Path $RepoRootPath).Path
    $dotGitPath = Join-Path $resolvedRepoRootPath '.git'

    if (Test-Path $dotGitPath -PathType Container) {
        return (Resolve-Path $dotGitPath).Path
    }

    if (Test-Path $dotGitPath -PathType Leaf) {
        $dotGitContent = Get-Content -Raw -Encoding UTF8 -Path $dotGitPath
        if ($dotGitContent -match '^\s*gitdir:\s*(.+?)\s*$') {
            $gitDirCandidate = $Matches[1].Trim()
            if (-not [System.IO.Path]::IsPathRooted($gitDirCandidate)) {
                $gitDirCandidate = Join-Path $resolvedRepoRootPath $gitDirCandidate
            }
            return (Resolve-Path $gitDirCandidate).Path
        }
    }

    throw "未找到有效 Git 目录：$resolvedRepoRootPath"
}

function Get-ActiveGitProcesses {
    return @(
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -like 'git*' } |
            Where-Object { $null -ne $_ } |
            ForEach-Object {
                $startTime = $null
                try {
                    $startTime = $_.StartTime
                }
                catch {
                    $startTime = $null
                }

                [pscustomobject]@{
                    ProcessName = [string]$_.ProcessName
                    Id = [int]$_.Id
                    StartTime = $startTime
                }
            }
    )
}

function Get-LockRelevantGitProcesses {
    param(
        [object[]]$GitProcesses,
        [string]$IndexLockPath,
        [int]$StartTimeLeewaySeconds = 15
    )

    $lockWriteTime = (Get-Item -LiteralPath $IndexLockPath).LastWriteTime
    $relevantProcessThreshold = $lockWriteTime.AddSeconds(-1 * $StartTimeLeewaySeconds)

    return @(
        $GitProcesses |
            Where-Object {
                ($null -eq $_.StartTime) -or ($_.StartTime -ge $relevantProcessThreshold)
            }
    )
}

$resolvedRepoRootPath = (Resolve-Path $RepoRootPath).Path
$gitDirectoryPath = Resolve-GitDirectoryPath -RepoRootPath $resolvedRepoRootPath
$indexLockPath = Join-Path $gitDirectoryPath 'index.lock'

Write-Output ("仓库根：{0}" -f $resolvedRepoRootPath)
Write-Output ("Git 目录：{0}" -f $gitDirectoryPath)

if (-not (Test-Path $indexLockPath -PathType Leaf)) {
    Write-Output '结果：未发现 `.git/index.lock`。'
    Write-Output '结论：当前可继续按串行提交流程推进。'
    Write-Output '下一步：继续按 `git add` → `git commit` → `git pull --rebase origin main` → `git push origin main` 串行执行。'
    return
}

$activeGitProcesses = Get-LockRelevantGitProcesses -GitProcesses (Get-ActiveGitProcesses) -IndexLockPath $indexLockPath
Write-Output ("锁文件：{0}" -f $indexLockPath)

if ($activeGitProcesses.Count -gt 0) {
    $processSummary = ($activeGitProcesses | ForEach-Object { '{0}({1})' -f $_.ProcessName, $_.Id }) -join '、'
    Write-Output ("结果：检测到 `.git/index.lock`，且仍有 Git 相关进程在运行：{0}" -f $processSummary)
    Write-Output '结论：当前不要清理锁文件，也不要继续重复 Git 命令。'
    Write-Output '下一步：先等待相关 Git 进程结束，再重新执行本脚本复核。'
    return
}

if (-not $ClearStaleLock) {
    Write-Output '结果：检测到 `.git/index.lock`，但当前未发现活动中的 Git 相关进程。'
    Write-Output '结论：这更像 stale lock；可以清理，但脚本默认不会直接删除。'
    Write-Output '下一步：确认没有其他 Git 窗口仍在执行后，执行 `powershell.exe -ExecutionPolicy Bypass -File .\.codex\chancellor\resolve-git-index-lock.ps1 -ClearStaleLock`。'
    return
}

$backupDirectoryPath = Join-Path $gitDirectoryPath 'chancellor-lock-backups'
if (-not (Test-Path $backupDirectoryPath -PathType Container)) {
    New-Item -ItemType Directory -Path $backupDirectoryPath -Force | Out-Null
}

$backupFilePath = Join-Path $backupDirectoryPath ('index.lock.{0}.bak' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Copy-Item -LiteralPath $indexLockPath -Destination $backupFilePath -Force
Remove-Item -LiteralPath $indexLockPath -Force

Write-Output '结果：已清理 stale `.git/index.lock`。'
Write-Output ("备份文件：{0}" -f $backupFilePath)
Write-Output '结论：当前可回到串行提交流程继续。'
Write-Output '下一步：先执行 `git status` 确认仓状态正常，再继续 `git commit` 或 `git pull --rebase`。'
