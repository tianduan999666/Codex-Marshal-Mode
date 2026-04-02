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
$runtimeMetaRoot = Join-Path $resolvedTargetCodexHome 'config\marshal-mode'
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

function Get-Sha256Text([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
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
                RelativeName = 'config/marshal-mode/{0}' -f (($includedPath -replace '\\', '/').TrimStart('/'))
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
[void](Backup-FileIfExists -PathToBackup $runtimeInstallRecordPath -RelativeName 'config\marshal-mode\install-record.json')

foreach ($fileMapping in $managedFileMappings) {
    Ensure-ParentDirectory -Path $fileMapping.TargetPath
    Copy-Item -Force $fileMapping.SourcePath $fileMapping.TargetPath
}

$installRecord = [ordered]@{
    installed_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    source_root = $sourceRoot
    target_codex_home = $resolvedTargetCodexHome
    cx_version = $versionInfo.cx_version
    mode = $versionInfo.mode
    stage = $manifestInfo.stage
    source_of_truth = $versionInfo.source_of_truth
    backup_root = $backupRoot
    synced_files = @($managedFileMappings | ForEach-Object { $_.RelativeName })
    managed_files = @(
        @($managedFileMappings | ForEach-Object { $_.RelativeName }) + @('config/marshal-mode/install-record.json')
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

Set-Utf8NoBomContent -Path $runtimeInstallRecordPath -Content ($installRecord | ConvertTo-Json -Depth 5)
Write-Ok '已同步生产母体受管文件与安装记录。'
Write-Info "安装记录：$runtimeInstallRecordPath"
Write-WarnLine '如需验证生产真源是否接管成功，请继续执行 verify-cutover.ps1。'
