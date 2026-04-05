$ErrorActionPreference = 'Stop'

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetScriptPath = Join-Path $scriptRootPath 'resolve-git-index-lock.ps1'

if (-not (Test-Path $targetScriptPath)) {
    throw "缺少待测脚本：$targetScriptPath"
}

function Assert-OutputContains {
    param(
        [string[]]$Lines,
        [string]$ExpectedText,
        [string]$Message
    )

    if (-not ($Lines | Where-Object { $_.Contains($ExpectedText) })) {
        $joinedOutput = $Lines -join [Environment]::NewLine
        throw "$Message`n期望包含：$ExpectedText`n实际输出：`n$joinedOutput"
    }
}

function Invoke-LockCase {
    param(
        [string]$TargetScriptPath,
        [string]$RepoRootPath,
        [switch]$ClearStaleLock
    )

    $commandOutput = if ($ClearStaleLock) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TargetScriptPath -RepoRootPath $RepoRootPath -ClearStaleLock *>&1 | Out-String
    }
    else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TargetScriptPath -RepoRootPath $RepoRootPath *>&1 | Out-String
    }

    return @(
        ($commandOutput -split "`r?`n") |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Start-BlockingGitProcess {
    $gitExecutablePath = Get-Command git -CommandType Application |
        Select-Object -First 1 -ExpandProperty Source

    if ([string]::IsNullOrWhiteSpace($gitExecutablePath)) {
        throw '未找到可执行的 git 命令，无法运行活动进程场景测试。'
    }

    $gitProcess = Start-Process -FilePath $gitExecutablePath -ArgumentList 'cat-file', '--batch' -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 500

    try {
        return Get-Process -Id $gitProcess.Id -ErrorAction Stop
    }
    catch {
        throw '活动进程场景未能稳定拉起 git 进程，测试无法继续。'
    }
}

function Stop-BlockingGitProcess {
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) {
        return
    }

    if (-not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $Process.Id -Timeout 5 -ErrorAction SilentlyContinue
    }
}

$testRootPath = Join-Path $env:TEMP ('cx-index-lock-' + [guid]::NewGuid().ToString('N'))
$repoRootPath = Join-Path $testRootPath 'repo'
$gitDirectoryPath = Join-Path $repoRootPath '.git'
$indexLockPath = Join-Path $gitDirectoryPath 'index.lock'
$blockingGitProcess = $null

try {
    New-Item -ItemType Directory -Path $gitDirectoryPath -Force | Out-Null

    $missingRepoPath = Join-Path $testRootPath 'missing-repo'
    $missingRepoLines = Invoke-LockCase -TargetScriptPath $targetScriptPath -RepoRootPath $missingRepoPath
    Assert-OutputContains -Lines $missingRepoLines -ExpectedText '指定的仓库路径不存在，当前没法检查 index.lock。' -Message '缺路径场景应提示仓库路径不存在'

    $noLockLines = Invoke-LockCase -TargetScriptPath $targetScriptPath -RepoRootPath $repoRootPath
    Assert-OutputContains -Lines $noLockLines -ExpectedText '未发现 `.git/index.lock`' -Message '无锁场景应提示可继续'

    Set-Content -Path $indexLockPath -Value 'locked' -Encoding UTF8
    $blockingGitProcess = Start-BlockingGitProcess
    try {
        $activeProcessLines = Invoke-LockCase -TargetScriptPath $targetScriptPath -RepoRootPath $repoRootPath
        Assert-OutputContains -Lines $activeProcessLines -ExpectedText '仍有 Git 相关进程在运行' -Message '活动进程场景应阻止清锁'
    }
    finally {
        Stop-BlockingGitProcess -Process $blockingGitProcess
        $blockingGitProcess = $null
    }

    $staleLockLines = Invoke-LockCase -TargetScriptPath $targetScriptPath -RepoRootPath $repoRootPath
    Assert-OutputContains -Lines $staleLockLines -ExpectedText '这更像 stale lock' -Message '无活动进程时应判为 stale lock'

    $clearLines = Invoke-LockCase -TargetScriptPath $targetScriptPath -RepoRootPath $repoRootPath -ClearStaleLock
    Assert-OutputContains -Lines $clearLines -ExpectedText '已清理 stale `.git/index.lock`' -Message '清理场景应提示成功'
    if (Test-Path $indexLockPath) {
        throw '执行清理后 index.lock 仍然存在。'
    }

    $backupDirectoryPath = Join-Path $gitDirectoryPath 'chancellor-lock-backups'
    $backupFiles = @(Get-ChildItem -Path $backupDirectoryPath -File -ErrorAction Stop)
    if ($backupFiles.Count -lt 1) {
        throw '执行清理后未生成备份文件。'
    }

    Write-Host 'PASS: resolve-git-index-lock.test.ps1' -ForegroundColor Green
}
finally {
    Stop-BlockingGitProcess -Process $blockingGitProcess
    if (Test-Path $testRootPath) {
        Remove-Item -LiteralPath $testRootPath -Recurse -Force
    }
}
