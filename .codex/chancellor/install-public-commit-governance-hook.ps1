param(
    [string]$RepoRootPath = ''
)

$ErrorActionPreference = 'Stop'

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..\..'
}
$repoRootPath = (Resolve-Path $RepoRootPath).Path
$hookDirectoryPath = Join-Path $repoRootPath '.git\hooks'
$hookFilePath = Join-Path $hookDirectoryPath 'pre-push'
$backupTimestampText = Get-Date -Format 'yyyyMMdd-HHmmss'
$gateScriptRelativePath = '.codex/chancellor/invoke-public-commit-governance-gate.ps1'

if (-not (Test-Path $hookDirectoryPath)) {
    throw "缺少 Git hook 目录：$hookDirectoryPath"
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

Write-Host "已安装 pre-push 治理门禁：$hookFilePath"
if ($backupFilePath -ne '') {
    Write-Host "已备份原 hook：$backupFilePath"
}
Write-Host "门禁脚本：$gateScriptRelativePath"
