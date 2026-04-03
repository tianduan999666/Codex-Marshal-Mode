param(
    [string]$RepoRootPath = ''
)

$ErrorActionPreference = 'Stop'

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..\..'
}

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlyInstallHook {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string[]]$NextSteps = @()
    )

    Write-Host ''
    Write-Host "[ERROR] $Summary" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原因：{0}" -f $Detail)
    }

    foreach ($nextStep in $NextSteps) {
        Write-Info $nextStep
    }

    exit 1
}

if (-not (Test-Path -LiteralPath $RepoRootPath)) {
    Stop-FriendlyInstallHook `
        -Summary '指定的仓库路径不存在，当前没法安装 pre-push 门禁。' `
        -Detail ("RepoRootPath 不存在：{0}" -f $RepoRootPath) `
        -NextSteps @(
            '先确认仓库路径写对了。',
            '确认目标目录已经完成 git clone 后再重新安装。'
        )
}

$repoRootPath = (Resolve-Path -LiteralPath $RepoRootPath).Path
$hookDirectoryPath = Join-Path $repoRootPath '.git\hooks'
$hookFilePath = Join-Path $hookDirectoryPath 'pre-push'
$backupTimestampText = Get-Date -Format 'yyyyMMdd-HHmmss'
$gateScriptRelativePath = '.codex/chancellor/invoke-public-commit-governance-gate.ps1'

if (-not (Test-Path $hookDirectoryPath)) {
    Stop-FriendlyInstallHook `
        -Summary '当前目录还不能安装 pre-push 门禁。' `
        -Detail ("缺少 Git hook 目录：{0}" -f $hookDirectoryPath) `
        -NextSteps @(
            '先确认这里是不是目标 Git 仓库的根目录。',
            '如果仓库还没初始化，请先完成 git clone 或 git init。'
        )
}

$backupFilePath = ''
if (Test-Path $hookFilePath) {
    $backupFilePath = "$hookFilePath.bak-$backupTimestampText"
    Copy-Item $hookFilePath $backupFilePath -Force
}

$hookLines = @(
    '#!/bin/sh',
    'repo_root="$(git rev-parse --show-toplevel)"',
    'gate_script="$repo_root/.codex/chancellor/invoke-public-commit-governance-gate.ps1"',
    '',
    'while read local_ref local_sha remote_ref remote_sha',
    'do',
    '  if [ "$local_sha" = "0000000000000000000000000000000000000000" ]; then',
    '    continue',
    '  fi',
    '',
    '  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$gate_script" -PushLocalSha "$local_sha" -PushRemoteSha "$remote_sha"',
    '  status=$?',
    '  if [ $status -ne 0 ]; then',
    '    echo "pre-push 治理门禁未通过，已阻止推送。"',
    '    exit $status',
    '  fi',
    'done',
    '',
    'exit 0'
)

$hookText = $hookLines -join "`n"
$asciiEncoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($hookFilePath, $hookText, $asciiEncoding)

Write-Info ("已安装 pre-push 治理门禁：{0}" -f $hookFilePath)
if ($backupFilePath -ne '') {
    Write-Info ("已备份原 hook：{0}" -f $backupFilePath)
}
Write-Info ("门禁脚本：{0}" -f $gateScriptRelativePath)
