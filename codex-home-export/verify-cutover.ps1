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
$agentsSourcePath = Join-Path $sourceRoot 'AGENTS.md'
$configSourcePath = Join-Path $sourceRoot 'config.toml'
$runtimeVersionPath = Join-Path $resolvedTargetCodexHome 'config\cx-version.json'
$runtimeManifestPath = Join-Path $resolvedTargetCodexHome 'config\marshal-mode\manifest.json'
$runtimeReadmePath = Join-Path $resolvedTargetCodexHome 'config\marshal-mode\README.md'
$runtimeAgentsPath = Join-Path $resolvedTargetCodexHome 'AGENTS.md'
$runtimeConfigPath = Join-Path $resolvedTargetCodexHome 'config.toml'
$runtimeInstallRecordPath = Join-Path $resolvedTargetCodexHome 'config\marshal-mode\install-record.json'
$authPath = Join-Path $resolvedTargetCodexHome 'auth.json'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Get-Sha256Text([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

foreach ($requiredPath in @($versionSourcePath, $agentsSourcePath, $configSourcePath, $runtimeVersionPath, $runtimeManifestPath, $runtimeReadmePath, $runtimeAgentsPath, $runtimeConfigPath, $runtimeInstallRecordPath)) {
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

foreach ($requiredManagedFile in @('config/cx-version.json', 'config/marshal-mode/manifest.json', 'config/marshal-mode/README.md', 'AGENTS.md', 'config.toml', 'config/marshal-mode/install-record.json')) {
    if (-not ($runtimeInstallRecord.managed_files -contains $requiredManagedFile)) {
        throw "安装记录缺少 managed_files 项：$requiredManagedFile"
    }
}

$expectedHashByPath = @{
    'AGENTS.md' = Get-Sha256Text -Path $agentsSourcePath
    'config.toml' = Get-Sha256Text -Path $configSourcePath
}
$runtimeHashByPath = @{
    'AGENTS.md' = Get-Sha256Text -Path $runtimeAgentsPath
    'config.toml' = Get-Sha256Text -Path $runtimeConfigPath
}
foreach ($hashPath in $expectedHashByPath.Keys) {
    if ($runtimeHashByPath[$hashPath] -ne $expectedHashByPath[$hashPath]) {
        throw "运行件哈希不匹配：$hashPath"
    }

    if ($runtimeInstallRecord.PSObject.Properties.Name -contains 'synced_hashes') {
        $recordHashItem = @($runtimeInstallRecord.synced_hashes | Where-Object { $_.path -eq $hashPath } | Select-Object -First 1)
        if ($recordHashItem.Count -eq 0) {
            throw "安装记录缺少 synced_hashes 项：$hashPath"
        }

        if ($recordHashItem[0].sha256 -ne $expectedHashByPath[$hashPath]) {
            throw "安装记录哈希不匹配：$hashPath"
        }
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
Write-Ok '最小主链验真通过。'
Write-Info '默认日常入口：回官方 Codex 面板直接说 `丞相：我要做 XX`。'
Write-Info '同版本第一次开工会先验真；后续同版本任务默认跳过重复验真，直接建任务。'
Write-Info '若发现可修复漂移，会先安全修复，再继续。'
Write-Info '若当前就在维护层，也可执行 `new-task.ps1 -Title "你的任务标题"` 直接起任务。'
Write-Info '若发现异常：先重跑 `verify-cutover.ps1`，仍异常再执行 `rollback-from-backup.ps1`。'
