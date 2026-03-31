param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$ExpectedVersion,
    [string]$ExpectedSourceRoot,
    [switch]$RequireBackupRoot
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$versionSourcePath = Join-Path $sourceRoot 'VERSION.json'
$runtimeVersionPath = Join-Path $resolvedTargetCodexHome 'config\cx-version.json'
$runtimeManifestPath = Join-Path $resolvedTargetCodexHome 'config\marshal-mode\manifest.json'
$runtimeReadmePath = Join-Path $resolvedTargetCodexHome 'config\marshal-mode\README.md'
$runtimeInstallRecordPath = Join-Path $resolvedTargetCodexHome 'config\marshal-mode\install-record.json'
$authPath = Join-Path $resolvedTargetCodexHome 'auth.json'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

foreach ($requiredPath in @($versionSourcePath, $runtimeVersionPath, $runtimeManifestPath, $runtimeReadmePath, $runtimeInstallRecordPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少必需文件：$requiredPath"
    }
}

$sourceVersionInfo = Get-Content -Raw -Path $versionSourcePath | ConvertFrom-Json
$runtimeVersionInfo = Get-Content -Raw -Path $runtimeVersionPath | ConvertFrom-Json
$runtimeManifestInfo = Get-Content -Raw -Path $runtimeManifestPath | ConvertFrom-Json
$runtimeInstallRecord = Get-Content -Raw -Path $runtimeInstallRecordPath | ConvertFrom-Json
$expectedVersionValue = if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) { $sourceVersionInfo.cx_version } else { $ExpectedVersion }
$expectedSourceRootValue = if ([string]::IsNullOrWhiteSpace($ExpectedSourceRoot)) { $sourceRoot } else { $ExpectedSourceRoot }

if ($runtimeVersionInfo.cx_version -ne $expectedVersionValue) {
    throw "cx-version 不匹配：期望 $expectedVersionValue，实际 $($runtimeVersionInfo.cx_version)"
}

if ($runtimeVersionInfo.source_of_truth -ne 'codex-home-export') {
    throw "source_of_truth 不匹配：$($runtimeVersionInfo.source_of_truth)"
}

if ($runtimeInstallRecord.source_root -ne $expectedSourceRootValue) {
    throw "安装记录 source_root 不匹配：期望 $expectedSourceRootValue，实际 $($runtimeInstallRecord.source_root)"
}

if ($runtimeInstallRecord.cx_version -ne $expectedVersionValue) {
    throw "安装记录 cx_version 不匹配：期望 $expectedVersionValue，实际 $($runtimeInstallRecord.cx_version)"
}

if ($runtimeManifestInfo.version -ne $expectedVersionValue) {
    throw "运行态 manifest 版本不匹配：期望 $expectedVersionValue，实际 $($runtimeManifestInfo.version)"
}

foreach ($requiredManagedFile in @('config/cx-version.json', 'config/marshal-mode/manifest.json', 'config/marshal-mode/README.md', 'config/marshal-mode/install-record.json')) {
    if (-not ($runtimeInstallRecord.managed_files -contains $requiredManagedFile)) {
        throw "安装记录缺少 managed_files 项：$requiredManagedFile"
    }
}

if ($RequireBackupRoot) {
    if ([string]::IsNullOrWhiteSpace($runtimeInstallRecord.backup_root)) {
        throw '安装记录缺少 backup_root。'
    }

    if (-not (Test-Path $runtimeInstallRecord.backup_root)) {
        throw "backup_root 不存在：$($runtimeInstallRecord.backup_root)"
    }
}

if (-not (Test-Path $authPath)) {
    throw "auth.json 不存在：$authPath"
}

Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info "CxVersion=$($runtimeVersionInfo.cx_version)"
Write-Info "BackupRoot=$($runtimeInstallRecord.backup_root)"
Write-Ok '切换验板通过。'
Write-Info '下一步：打开官方 Codex 面板，新开一个全新会话。'
Write-Info '人工验板顺序：先输入 `丞相版本`，再输入 `丞相检查`，必要时再输入 `丞相状态`。'
Write-Info '若发现漂移：先重跑 `verify-cutover.ps1`，仍异常再执行 `rollback-from-backup.ps1`。'
