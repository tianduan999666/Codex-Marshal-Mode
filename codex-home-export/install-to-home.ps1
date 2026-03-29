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
$readmeSourcePath = Join-Path $sourceRoot 'README.md'
$runtimeVersionTargetPath = Join-Path $resolvedTargetCodexHome 'config\cx-version.json'
$runtimeMetaRoot = Join-Path $resolvedTargetCodexHome 'config\marshal-mode'
$runtimeManifestTargetPath = Join-Path $runtimeMetaRoot 'manifest.json'
$runtimeReadmeTargetPath = Join-Path $runtimeMetaRoot 'README.md'
$runtimeInstallRecordPath = Join-Path $runtimeMetaRoot 'install-record.json'
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

function Set-Utf8NoBomContent([string]$Path, [string]$Content) {
    Ensure-ParentDirectory -Path $Path
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
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

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Path $Path | ConvertFrom-Json)
}

foreach ($sourcePath in @($versionSourcePath, $manifestSourcePath, $readmeSourcePath)) {
    if (-not (Test-Path $sourcePath)) {
        throw "缺少源文件：$sourcePath"
    }
}
$versionInfo = Read-JsonFile -Path $versionSourcePath
$manifestInfo = Read-JsonFile -Path $manifestSourcePath

if (-not $versionInfo.cx_version) {
    throw "VERSION.json 缺少 cx_version：$versionSourcePath"
}

Write-Info "SourceRoot=$sourceRoot"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info "CxVersion=$($versionInfo.cx_version)"
Write-Info '当前脚本只同步最小骨架，不覆盖 auth.json、sessions 或其他用户隐私文件。'

if ($DryRun) {
    foreach ($targetPath in @($runtimeVersionTargetPath, $runtimeManifestTargetPath, $runtimeReadmeTargetPath, $runtimeInstallRecordPath)) {
        Write-Info "DryRun 将写入：$targetPath"
    }

    Write-Ok 'DryRun 检查通过，未执行实际写入。'
    exit 0
}

New-Item -ItemType Directory -Force -Path $resolvedTargetCodexHome | Out-Null
[void](Backup-FileIfExists -PathToBackup $runtimeVersionTargetPath -RelativeName 'config\cx-version.json')
[void](Backup-FileIfExists -PathToBackup $runtimeManifestTargetPath -RelativeName 'config\marshal-mode\manifest.json')
[void](Backup-FileIfExists -PathToBackup $runtimeReadmeTargetPath -RelativeName 'config\marshal-mode\README.md')
[void](Backup-FileIfExists -PathToBackup $runtimeInstallRecordPath -RelativeName 'config\marshal-mode\install-record.json')

Ensure-ParentDirectory -Path $runtimeVersionTargetPath
Ensure-ParentDirectory -Path $runtimeManifestTargetPath
Copy-Item -Force $versionSourcePath $runtimeVersionTargetPath
Copy-Item -Force $manifestSourcePath $runtimeManifestTargetPath
Copy-Item -Force $readmeSourcePath $runtimeReadmeTargetPath

$installRecord = [ordered]@{
    installed_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    source_root = $sourceRoot
    target_codex_home = $resolvedTargetCodexHome
    cx_version = $versionInfo.cx_version
    mode = $versionInfo.mode
    stage = $manifestInfo.stage
    source_of_truth = $versionInfo.source_of_truth
    backup_root = $backupRoot
    synced_files = @(
        'config/cx-version.json'
        'config/marshal-mode/manifest.json'
        'config/marshal-mode/README.md'
    )
}

Set-Utf8NoBomContent -Path $runtimeInstallRecordPath -Content ($installRecord | ConvertTo-Json -Depth 4)
Write-Ok '已同步 cx-version.json、manifest.json、README.md 与安装记录。'
Write-Info "安装记录：$runtimeInstallRecordPath"
Write-WarnLine '当前仅完成单机最小骨架同步；尚未包含回滚脚本与完整验板闭环。'
