param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$InstallRecordPath,
    [string]$BackupRoot,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
if ([string]::IsNullOrWhiteSpace($InstallRecordPath)) {
    $InstallRecordPath = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode\install-record.json'
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

function Stop-FriendlyRollback {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string]$NextStep = ''
    )

    Write-Host ("[ERROR] {0}" -f $Summary) -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原因：{0}" -f $Detail)
    }
    if (-not [string]::IsNullOrWhiteSpace($NextStep)) {
        Write-Info ("下一步：{0}" -f $NextStep)
    }

    exit 1
}

function Ensure-ParentDirectory([string]$Path) {
    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
}

if (-not (Test-Path $InstallRecordPath)) {
    Stop-FriendlyRollback `
        -Summary '当前找不到安装记录，没法判断该回滚哪些文件。' `
        -Detail ("缺少安装记录：{0}" -f $InstallRecordPath) `
        -NextStep '先确认这台机器是否装过丞相；如果装过但记录丢了，先不要硬回滚。'
}

$installRecord = Get-Content -Raw -Encoding UTF8 -Path $InstallRecordPath | ConvertFrom-Json
$resolvedBackupRoot = if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $installRecord.backup_root } else { $BackupRoot }
if ([string]::IsNullOrWhiteSpace($resolvedBackupRoot)) {
    Stop-FriendlyRollback `
        -Summary '当前没有可用备份目录，回滚现在不能继续。' `
        -Detail '安装记录缺少 backup_root，且未显式传入 -BackupRoot。' `
        -NextStep '先找到一份可用备份，再执行 rollback-from-backup.ps1。'
}

if (-not (Test-Path $resolvedBackupRoot)) {
    Stop-FriendlyRollback `
        -Summary '备份目录不存在，当前不能继续回滚。' `
        -Detail ("BackupRoot={0}" -f $resolvedBackupRoot) `
        -NextStep '先确认备份目录路径是否正确；确认前不要继续执行回滚。'
}

$managedFiles = @()
if ($installRecord.managed_files) {
    $managedFiles = @($installRecord.managed_files)
} elseif ($installRecord.synced_files) {
    $managedFiles = @($installRecord.synced_files) + @('config/chancellor-mode/install-record.json')
} else {
    $managedFiles = @(
        'config/cx-version.json'
        'config/chancellor-mode/manifest.json'
        'config/chancellor-mode/README.md'
        'config/chancellor-mode/start-panel-task.ps1'
        'config/chancellor-mode/install-record.json'
    )
}

Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info "InstallRecordPath=$InstallRecordPath"
Write-Info "BackupRoot=$resolvedBackupRoot"
Write-Info '本次只回滚丞相自身受管文件，不会改你的项目。'

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
Write-Info '建议下一步：先执行 `self-check.cmd`，确认回滚后的运行态已经恢复稳定。'
