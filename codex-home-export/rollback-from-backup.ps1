param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$InstallRecordPath,
    [string]$BackupRoot,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
if ([string]::IsNullOrWhiteSpace($InstallRecordPath)) {
    $InstallRecordPath = Join-Path $resolvedTargetCodexHome 'config\marshal-mode\install-record.json'
}

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Ensure-ParentDirectory([string]$Path) {
    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
}

if (-not (Test-Path $InstallRecordPath)) {
    throw "缺少安装记录：$InstallRecordPath"
}

$installRecord = Get-Content -Raw -Encoding UTF8 -Path $InstallRecordPath | ConvertFrom-Json
$resolvedBackupRoot = if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $installRecord.backup_root } else { $BackupRoot }
if ([string]::IsNullOrWhiteSpace($resolvedBackupRoot)) {
    throw '安装记录缺少 backup_root，且未显式传入 -BackupRoot。'
}

$managedFiles = @()
if ($installRecord.managed_files) {
    $managedFiles = @($installRecord.managed_files)
} elseif ($installRecord.synced_files) {
    $managedFiles = @($installRecord.synced_files) + @('config/marshal-mode/install-record.json')
} else {
    $managedFiles = @(
        'config/cx-version.json'
        'config/marshal-mode/manifest.json'
        'config/marshal-mode/README.md'
        'config/marshal-mode/start-panel-task.ps1'
        'config/marshal-mode/install-record.json'
    )
}

Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info "InstallRecordPath=$InstallRecordPath"
Write-Info "BackupRoot=$resolvedBackupRoot"

$rollbackPlan = foreach ($relativePath in $managedFiles) {
    $normalizedRelativePath = ($relativePath -replace '/', '\\').TrimStart('\\')
    $targetPath = Join-Path $resolvedTargetCodexHome $normalizedRelativePath
    $backupPath = Join-Path $resolvedBackupRoot $normalizedRelativePath

    if (Test-Path $backupPath) {
        [pscustomobject]@{
            relative_path = $normalizedRelativePath
            action = 'restore'
            target_path = $targetPath
            backup_path = $backupPath
        }
        continue
    }

    if (Test-Path $targetPath) {
        [pscustomobject]@{
            relative_path = $normalizedRelativePath
            action = 'delete'
            target_path = $targetPath
            backup_path = $backupPath
        }
    }
}

if (-not $rollbackPlan -or $rollbackPlan.Count -eq 0) {
    Write-WarnLine '未发现需要回滚的受控文件。'
    exit 0
}

foreach ($item in $rollbackPlan) {
    Write-Info ("{0} -> {1}" -f $item.action.ToUpperInvariant(), $item.relative_path)
}

if ($DryRun) {
    Write-Ok 'DryRun 检查通过，未执行真实回滚。'
    exit 0
}

foreach ($item in $rollbackPlan) {
    if ($item.action -eq 'restore') {
        Ensure-ParentDirectory -Path $item.target_path
        Copy-Item -Force $item.backup_path $item.target_path
        continue
    }

    if (Test-Path $item.target_path) {
        Remove-Item -Force $item.target_path
    }
}

Write-Ok '回滚完成。'
Write-WarnLine '当前仅回滚最小骨架同步文件；完整生产接管内容仍未纳入回滚范围。'
