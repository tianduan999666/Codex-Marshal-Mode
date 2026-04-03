$ErrorActionPreference = 'Stop'

function Assert-ExitCode {
    param(
        [int]$Actual,
        [int]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw ("{0}：期望退出码 {1}，实际 {2}。" -f $Message, $Expected, $Actual)
    }
}

function Assert-OutputContains {
    param(
        [string[]]$Lines,
        [string]$ExpectedText,
        [string]$Message
    )

    $joinedOutput = ($Lines -join [Environment]::NewLine)
    if ($joinedOutput -notlike ('*' + $ExpectedText + '*')) {
        throw ("{0}：未找到 `{1}`。" -f $Message, $ExpectedText)
    }
}

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$upgradeScriptPath = Join-Path $scriptRootPath 'upgrade-managed-install.ps1'
$tempRootPath = Join-Path ([System.IO.Path]::GetTempPath()) ('upgrade-managed-install-test-' + [System.Guid]::NewGuid().ToString('N'))
$repoRootPath = Join-Path $tempRootPath 'repo'
$sourceRootPath = Join-Path $repoRootPath 'codex-home-export'
$targetCodexHomePath = Join-Path $tempRootPath 'codex-home'
$installRecordPath = Join-Path $targetCodexHomePath 'config\chancellor-mode\install-record.json'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

try {
    New-Item -ItemType Directory -Force -Path $sourceRootPath | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $installRecordPath) | Out-Null

    foreach ($requiredSourceFileName in @('install-to-home.ps1', 'verify-cutover.ps1', 'verify-panel-command-smoke.ps1', 'verify-provider-auth.ps1')) {
        [System.IO.File]::WriteAllText(
            (Join-Path $sourceRootPath $requiredSourceFileName),
            "Write-Host 'placeholder'",
            $utf8Bom
        )
    }

    $installRecord = @{
        source_root = $sourceRootPath
    } | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($installRecordPath, $installRecord, $utf8Bom)

    & git -C $tempRootPath init $repoRootPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw '测试仓库初始化失败。'
    }

    [System.IO.File]::WriteAllText((Join-Path $repoRootPath 'dirty.txt'), 'dirty', $utf8Bom)

    $commandOutput = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $upgradeScriptPath -TargetCodexHome $targetCodexHomePath 2>&1
    )
    $actualExitCode = $LASTEXITCODE

    Assert-ExitCode -Actual $actualExitCode -Expected 1 -Message '脏工作区升级应停止'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '检测到源仓有未提交改动，本次升级已停止。' -Message '应提示升级已停止'
    Assert-OutputContains -Lines $commandOutput -ExpectedText 'status --short' -Message '应提示先查看改动'
    Assert-OutputContains -Lines $commandOutput -ExpectedText 'stash push --include-untracked' -Message '应提示手动 stash'
    Assert-OutputContains -Lines $commandOutput -ExpectedText 'restore .' -Message '应提示手动 restore'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '重新 git clone 当前仓' -Message '应提示重新 clone'
}
finally {
    if (Test-Path $tempRootPath) {
        Remove-Item -LiteralPath $tempRootPath -Recurse -Force
    }
}

Write-Host 'PASS: upgrade-managed-install.test.ps1'
