param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$versionSourcePath = Join-Path $sourceRoot 'VERSION.json'
$manifestSourcePath = Join-Path $sourceRoot 'manifest.json'
$runtimeMetaRoot = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode'
$legacyRuntimeMetaRoot = Join-Path $resolvedTargetCodexHome 'config\marshal-mode'
$runtimeInstallRecordPath = Join-Path $runtimeMetaRoot 'install-record.json'
$runtimeTaskStartStatePath = Join-Path $runtimeMetaRoot 'task-start-state.json'
$legacyTaskStartStatePath = Join-Path $legacyRuntimeMetaRoot 'task-start-state.json'
$backupRoot = Join-Path $resolvedTargetCodexHome "backup\local-production-cutover-$timestamp"

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

function Set-Utf8BomContent([string]$Path, [string]$Content) {
    Ensure-ParentDirectory -Path $Path
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8Bom)
}

function Backup-FileIfExists([string]$PathToBackup, [string]$RelativeName) {
    if (-not (Test-Path $PathToBackup)) {
        return $false
    }

    $destination = Join-Path $backupRoot $RelativeName
    Ensure-ParentDirectory -Path $destination
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    Copy-Item -Force $PathToBackup $destination
    return $true
}

function Copy-FileIfExists([string]$SourcePath, [string]$TargetPath) {
    if (-not (Test-Path $SourcePath)) {
        return $false
    }

    Ensure-ParentDirectory -Path $TargetPath
    Copy-Item -Force $SourcePath $TargetPath
    return $true
}

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json)
}

function Get-Sha256Text([string]$Path) {
    $fileStream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha256.ComputeHash($fileStream)
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $fileStream.Dispose()
    }

    return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
}

function Get-ManagedFileMappings {
    param(
        [string]$SourceRoot,
        [string]$ResolvedTargetCodexHome,
        [string]$RuntimeMetaRoot,
        [object]$ManifestInfo
    )

    $specialTargetByIncludedPath = @{
        'VERSION.json' = @{
            TargetPath = Join-Path $ResolvedTargetCodexHome 'config\cx-version.json'
            RelativeName = 'config/cx-version.json'
        }
        'AGENTS.md' = @{
            TargetPath = Join-Path $ResolvedTargetCodexHome 'AGENTS.md'
            RelativeName = 'AGENTS.md'
        }
        'config.toml' = @{
            TargetPath = Join-Path $ResolvedTargetCodexHome 'config.toml'
            RelativeName = 'config.toml'
        }
        'install.cmd' = @{
            TargetPath = Join-Path $ResolvedTargetCodexHome 'install.cmd'
            RelativeName = 'install.cmd'
        }
        'upgrade.cmd' = @{
            TargetPath = Join-Path $ResolvedTargetCodexHome 'upgrade.cmd'
            RelativeName = 'upgrade.cmd'
        }
        'self-check.cmd' = @{
            TargetPath = Join-Path $ResolvedTargetCodexHome 'self-check.cmd'
            RelativeName = 'self-check.cmd'
        }
        'rollback.cmd' = @{
            TargetPath = Join-Path $ResolvedTargetCodexHome 'rollback.cmd'
            RelativeName = 'rollback.cmd'
        }
    }

    $fileMappings = @()
    foreach ($includedPathValue in @($ManifestInfo.included)) {
        $includedPath = [string]$includedPathValue
        if ([string]::IsNullOrWhiteSpace($includedPath)) {
            continue
        }

        $normalizedIncludedPath = $includedPath -replace '/', '\'
        $sourcePath = Join-Path $SourceRoot $normalizedIncludedPath
        if ($specialTargetByIncludedPath.ContainsKey($includedPath)) {
            $targetInfo = $specialTargetByIncludedPath[$includedPath]
        }
        else {
            $targetInfo = @{
                TargetPath = Join-Path $RuntimeMetaRoot $normalizedIncludedPath
                RelativeName = 'config/chancellor-mode/{0}' -f (($includedPath -replace '\\', '/').TrimStart('/'))
            }
        }

        $fileMappings += [ordered]@{
            SourcePath = $sourcePath
            TargetPath = $targetInfo.TargetPath
            RelativeName = $targetInfo.RelativeName
        }
    }

    return @($fileMappings)
}

$versionInfo = Read-JsonFile -Path $versionSourcePath
$manifestInfo = Read-JsonFile -Path $manifestSourcePath
$managedFileMappings = Get-ManagedFileMappings -SourceRoot $sourceRoot -ResolvedTargetCodexHome $resolvedTargetCodexHome -RuntimeMetaRoot $runtimeMetaRoot -ManifestInfo $manifestInfo

foreach ($sourcePath in @($versionSourcePath, $manifestSourcePath) + @($managedFileMappings | ForEach-Object { $_.SourcePath })) {
    if (-not (Test-Path $sourcePath)) {
        throw "缺少源文件：$sourcePath"
    }
}

if (-not $versionInfo.cx_version) {
    throw "VERSION.json 缺少 cx_version：$versionSourcePath"
}

Write-Info "SourceRoot=$sourceRoot"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info "CxVersion=$($versionInfo.cx_version)"
Write-Info ("当前脚本会按 manifest 受管清单同步 {0} 个文件，不覆盖 auth.json、sessions 或其他用户隐私文件。" -f $managedFileMappings.Count)
Write-Info '运行态说明：`task-start-state.json` 属于本地开工状态缓存；不在 manifest 受管清单内，本轮不会覆盖。'

if ($DryRun) {
    foreach ($fileMapping in $managedFileMappings) {
        Write-Info ("DryRun 将写入：{0}" -f $fileMapping.TargetPath)
    }
    Write-Info "DryRun 将写入：$runtimeInstallRecordPath"

    Write-Ok 'DryRun 检查通过，未执行实际写入。'
    exit 0
}

New-Item -ItemType Directory -Force -Path $resolvedTargetCodexHome | Out-Null
foreach ($fileMapping in $managedFileMappings) {
    [void](Backup-FileIfExists -PathToBackup $fileMapping.TargetPath -RelativeName $fileMapping.RelativeName)
}
[void](Backup-FileIfExists -PathToBackup $runtimeInstallRecordPath -RelativeName 'config\chancellor-mode\install-record.json')

foreach ($fileMapping in $managedFileMappings) {
    Ensure-ParentDirectory -Path $fileMapping.TargetPath
    Copy-Item -Force $fileMapping.SourcePath $fileMapping.TargetPath
}

$migratedLegacyTaskStartState = $false
if ((Test-Path $legacyTaskStartStatePath) -and (-not (Test-Path $runtimeTaskStartStatePath))) {
    $migratedLegacyTaskStartState = Copy-FileIfExists -SourcePath $legacyTaskStartStatePath -TargetPath $runtimeTaskStartStatePath
}

$installRecord = [ordered]@{
    installed_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    source_root = $sourceRoot
    target_codex_home = $resolvedTargetCodexHome
    cx_version = $versionInfo.cx_version
    mode = $versionInfo.mode
    stage = $manifestInfo.stage
    source_of_truth = $versionInfo.source_of_truth
    runtime_meta_dir = 'config/chancellor-mode'
    backup_root = $backupRoot
    migrated_legacy_task_start_state = $migratedLegacyTaskStartState
    synced_files = @($managedFileMappings | ForEach-Object { $_.RelativeName })
    managed_files = @(
        @($managedFileMappings | ForEach-Object { $_.RelativeName }) + @('config/chancellor-mode/install-record.json')
    )
    synced_hashes = @(
        $managedFileMappings | ForEach-Object {
            [ordered]@{
                path = $_.RelativeName
                sha256 = Get-Sha256Text -Path $_.TargetPath
            }
        }
    )
}

Set-Utf8BomContent -Path $runtimeInstallRecordPath -Content ($installRecord | ConvertTo-Json -Depth 5)
Write-Ok '已同步生产母体受管文件与安装记录。'
Write-Info "安装记录：$runtimeInstallRecordPath"
if ($migratedLegacyTaskStartState) {
    Write-Info '已把旧 `config/marshal-mode/task-start-state.json` 迁到新主路径 `config/chancellor-mode/task-start-state.json`。'
}
Write-Info ("对外入口已落地：{0}" -f (Join-Path $resolvedTargetCodexHome 'install.cmd'))
Write-WarnLine '如需验证生产真源是否接管成功，请继续执行 self-check.cmd 或 verify-cutover.ps1。'
