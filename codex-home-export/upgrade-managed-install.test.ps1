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

function Invoke-GitCommand {
    param(
        [string]$RepoRootPath,
        [string[]]$Arguments,
        [string]$Message
    )

    & git -C $RepoRootPath @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ("{0}：git {1}" -f $Message, ($Arguments -join ' '))
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

function Write-Utf8BomFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, $utf8Bom)
}

try {
    New-Item -ItemType Directory -Force -Path $sourceRootPath | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $installRecordPath) | Out-Null

    foreach ($requiredSourceFileName in @('install-to-home.ps1', 'verify-cutover.ps1', 'verify-panel-command-smoke.ps1', 'verify-provider-auth.ps1')) {
        Write-Utf8BomFile -Path (Join-Path $sourceRootPath $requiredSourceFileName) -Content "Write-Host 'placeholder'"
    }

    $installRecord = @{
        source_root = $sourceRootPath
    } | ConvertTo-Json -Depth 3
    Write-Utf8BomFile -Path $installRecordPath -Content $installRecord

    & git -C $tempRootPath init $repoRootPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw '测试仓库初始化失败。'
    }

    Invoke-GitCommand -RepoRootPath $repoRootPath -Arguments @('config', 'user.email', 'codex@example.com') -Message '设置 git user.email 失败'
    Invoke-GitCommand -RepoRootPath $repoRootPath -Arguments @('config', 'user.name', 'Codex Test') -Message '设置 git user.name 失败'
    Invoke-GitCommand -RepoRootPath $repoRootPath -Arguments @('add', '--', 'codex-home-export') -Message '加入基线文件失败'
    Invoke-GitCommand -RepoRootPath $repoRootPath -Arguments @('commit', '-m', 'baseline') -Message '提交基线失败'

    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'dirty-public.ps1') -Content "Write-Host 'public'"
    Write-Utf8BomFile -Path (Join-Path $repoRootPath '.codex\chancellor\record-exception-state.ps1') -Content "Write-Host 'maint'"
    Write-Utf8BomFile -Path (Join-Path $repoRootPath '.codex\chancellor\active-task.txt') -Content 'task-001'
    Write-Utf8BomFile -Path (Join-Path $repoRootPath 'docs\dirty-note.md') -Content '# dirty'
    Write-Utf8BomFile -Path (Join-Path $repoRootPath 'dirty.txt') -Content 'dirty'

    $commandOutput = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $upgradeScriptPath -TargetCodexHome $targetCodexHomePath 2>&1
    )
    $actualExitCode = $LASTEXITCODE

    Assert-ExitCode -Actual $actualExitCode -Expected 1 -Message '脏工作区升级应停止'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '检测到源仓有未提交改动，本次升级已停止。' -Message '应提示升级已停止'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '公开入口/生产母体(1)' -Message '应汇总公开入口改动'
    Assert-OutputContains -Lines $commandOutput -ExpectedText 'codex-home-export/dirty-public.ps1' -Message '应列出公开入口改动路径'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '维护层在研(1)' -Message '应汇总维护层改动'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '.codex/chancellor/record-exception-state.ps1' -Message '应列出维护层改动路径'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '本地任务/运行态(1)' -Message '应汇总运行态改动'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '.codex/chancellor/active-task.txt' -Message '应列出运行态改动路径'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '文档/方案(1)' -Message '应汇总文档改动'
    Assert-OutputContains -Lines $commandOutput -ExpectedText 'docs/dirty-note.md' -Message '应列出文档改动路径'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '其他待人工判断(1)' -Message '应汇总待人工判断改动'
    Assert-OutputContains -Lines $commandOutput -ExpectedText 'dirty.txt' -Message '应列出待人工判断改动路径'
    Assert-OutputContains -Lines $commandOutput -ExpectedText 'status --short --untracked-files=all' -Message '应提示先查看完整未跟踪改动'
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
