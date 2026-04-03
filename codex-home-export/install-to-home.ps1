param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$ApplyTemplateConfig,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$versionSourcePath = Join-Path $sourceRoot 'VERSION.json'
$manifestSourcePath = Join-Path $sourceRoot 'manifest.json'
$runtimeMetaRoot = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode'
$runtimeConfigPath = Join-Path $resolvedTargetCodexHome 'config.toml'
$legacyRuntimeMetaRoot = Join-Path $resolvedTargetCodexHome 'config\marshal-mode'
$runtimeInstallRecordPath = Join-Path $runtimeMetaRoot 'install-record.json'
$runtimeTaskStartStatePath = Join-Path $runtimeMetaRoot 'task-start-state.json'
$legacyTaskStartStatePath = Join-Path $legacyRuntimeMetaRoot 'task-start-state.json'
$backupRoot = Join-Path $resolvedTargetCodexHome "backup\local-production-cutover-$timestamp"
$resolvedRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $sourceRoot '..'))

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

function Get-TomlScalarValue([string]$Path, [string]$KeyName) {
    if (-not (Test-Path $Path)) {
        return ''
    }

    $content = Get-Content -Raw -Encoding UTF8 -Path $Path
    $pattern = '(?m)^\s*' + [regex]::Escape($KeyName) + '\s*=\s*["'']([^"'']+)["'']'
    $match = [regex]::Match($content, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return ''
}

function Get-ConfigSnapshot([string]$Path) {
    if (-not (Test-Path $Path)) {
        return [pscustomobject]@{
            exists = $false
            provider = ''
            auth_method = ''
            model = ''
        }
    }

    return [pscustomobject]@{
        exists = $true
        provider = Get-TomlScalarValue -Path $Path -KeyName 'model_provider'
        auth_method = Get-TomlScalarValue -Path $Path -KeyName 'preferred_auth_method'
        model = Get-TomlScalarValue -Path $Path -KeyName 'model'
    }
}

function Get-GitTextOrEmpty([string[]]$Arguments) {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        return ''
    }

    $result = @(& git @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return ''
    }

    return (($result | Select-Object -First 1) | ForEach-Object { [string]$_ }).Trim()
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
            TargetPath = Join-Path $RuntimeMetaRoot 'config.template.toml'
            RelativeName = 'config/chancellor-mode/config.template.toml'
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
$legacyRuntimeMetaExists = Test-Path $legacyRuntimeMetaRoot
$legacyRuntimeMetaFiles = if ($legacyRuntimeMetaExists) { @(Get-ChildItem -Path $legacyRuntimeMetaRoot -File -Recurse -ErrorAction SilentlyContinue) } else { @() }
$sourceBranch = Get-GitTextOrEmpty -Arguments @('-C', $resolvedRepoRoot, 'branch', '--show-current')
$sourceCommit = Get-GitTextOrEmpty -Arguments @('-C', $resolvedRepoRoot, 'rev-parse', 'HEAD')
$sourceRemote = Get-GitTextOrEmpty -Arguments @('-C', $resolvedRepoRoot, 'remote', 'get-url', 'origin')
$templateConfigSnapshot = Get-ConfigSnapshot -Path (Join-Path $sourceRoot 'config.toml')
$runtimeConfigBeforeSnapshot = Get-ConfigSnapshot -Path $runtimeConfigPath

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
Write-Info '全局 config.toml 已改为用户自有配置；默认只同步模板参考件，不再静默改 provider / model / auth。'
Write-Info '运行态说明：`task-start-state.json` 属于本地开工状态缓存；不在 manifest 受管清单内，本轮不会覆盖。'

if ($DryRun) {
    foreach ($fileMapping in $managedFileMappings) {
        Write-Info ("DryRun 将写入：{0}" -f $fileMapping.TargetPath)
    }
    if ($ApplyTemplateConfig) {
        Write-WarnLine ("DryRun 将显式套用模板配置到：{0}" -f $runtimeConfigPath)
    }
    else {
        Write-Info ("DryRun 默认保留现有全局配置：{0}" -f $runtimeConfigPath)
    }
    Write-Info "DryRun 将写入：$runtimeInstallRecordPath"

    Write-Ok 'DryRun 检查通过，未执行实际写入。'
    exit 0
}

New-Item -ItemType Directory -Force -Path $resolvedTargetCodexHome | Out-Null
foreach ($fileMapping in $managedFileMappings) {
    [void](Backup-FileIfExists -PathToBackup $fileMapping.TargetPath -RelativeName $fileMapping.RelativeName)
}
[void](Backup-FileIfExists -PathToBackup $runtimeConfigPath -RelativeName 'config.toml')
[void](Backup-FileIfExists -PathToBackup $runtimeInstallRecordPath -RelativeName 'config\chancellor-mode\install-record.json')

foreach ($fileMapping in $managedFileMappings) {
    Ensure-ParentDirectory -Path $fileMapping.TargetPath
    Copy-Item -Force $fileMapping.SourcePath $fileMapping.TargetPath
}

$templateConfigApplied = $false
if ($ApplyTemplateConfig) {
    Copy-Item -Force (Join-Path $sourceRoot 'config.toml') $runtimeConfigPath
    $templateConfigApplied = $true
}
$runtimeConfigAfterSnapshot = Get-ConfigSnapshot -Path $runtimeConfigPath

$migratedLegacyTaskStartState = $false
if ((Test-Path $legacyTaskStartStatePath) -and (-not (Test-Path $runtimeTaskStartStatePath))) {
    $migratedLegacyTaskStartState = Copy-FileIfExists -SourcePath $legacyTaskStartStatePath -TargetPath $runtimeTaskStartStatePath
}

$syncedRelativeNames = @($managedFileMappings | ForEach-Object { $_.RelativeName })
if ($templateConfigApplied) {
    $syncedRelativeNames += 'config.toml'
}

$syncedHashes = @(
    $managedFileMappings | ForEach-Object {
        [ordered]@{
            path = $_.RelativeName
            sha256 = Get-Sha256Text -Path $_.TargetPath
        }
    }
)
if ($templateConfigApplied) {
    $syncedHashes += [ordered]@{
        path = 'config.toml'
        sha256 = Get-Sha256Text -Path $runtimeConfigPath
    }
}

$providerWouldChange = (
    $runtimeConfigBeforeSnapshot.exists -and
    (-not [string]::IsNullOrWhiteSpace($runtimeConfigBeforeSnapshot.provider)) -and
    (-not [string]::IsNullOrWhiteSpace($templateConfigSnapshot.provider)) -and
    ($runtimeConfigBeforeSnapshot.provider -ne $templateConfigSnapshot.provider)
)

$installRecord = [ordered]@{
    installed_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    source_root = $sourceRoot
    source_repo_root = $resolvedRepoRoot
    target_codex_home = $resolvedTargetCodexHome
    cx_version = $versionInfo.cx_version
    mode = $versionInfo.mode
    stage = $manifestInfo.stage
    source_of_truth = $versionInfo.source_of_truth
    source_branch = $sourceBranch
    source_commit = $sourceCommit
    source_remote = $sourceRemote
    runtime_meta_dir = 'config/chancellor-mode'
    backup_root = $backupRoot
    config_template_path = 'config/chancellor-mode/config.template.toml'
    config_template_applied = $templateConfigApplied
    runtime_config_preserved = ((-not $templateConfigApplied) -and $runtimeConfigBeforeSnapshot.exists)
    runtime_config_missing_before_install = (-not $runtimeConfigBeforeSnapshot.exists)
    provider_change_risk_detected = $providerWouldChange
    runtime_provider_before = $runtimeConfigBeforeSnapshot.provider
    runtime_provider_after = $runtimeConfigAfterSnapshot.provider
    runtime_auth_method_before = $runtimeConfigBeforeSnapshot.auth_method
    runtime_auth_method_after = $runtimeConfigAfterSnapshot.auth_method
    template_provider = $templateConfigSnapshot.provider
    template_auth_method = $templateConfigSnapshot.auth_method
    legacy_marshal_mode_detected = $legacyRuntimeMetaExists
    legacy_marshal_mode_file_count = $legacyRuntimeMetaFiles.Count
    migrated_legacy_task_start_state = $migratedLegacyTaskStartState
    synced_files = @($syncedRelativeNames)
    managed_files = @(
        @($syncedRelativeNames) + @('config/chancellor-mode/install-record.json')
    )
    synced_hashes = @($syncedHashes)
}

Set-Utf8BomContent -Path $runtimeInstallRecordPath -Content ($installRecord | ConvertTo-Json -Depth 5)
Write-Ok '已同步生产母体受管文件与安装记录。'
Write-Info "安装记录：$runtimeInstallRecordPath"
Write-Info ("模板配置已同步：{0}" -f (Join-Path $runtimeMetaRoot 'config.template.toml'))
if ($templateConfigApplied) {
    Write-WarnLine '本次已按显式参数套用仓内模板配置，会改动全局 provider / model / auth。'
    if ($providerWouldChange) {
        Write-WarnLine ("检测到 provider 已从 {0} 切到 {1}。" -f $runtimeConfigBeforeSnapshot.provider, $runtimeConfigAfterSnapshot.provider)
    }
    Write-Info ("当前全局配置：provider={0}；auth={1}" -f $(if ([string]::IsNullOrWhiteSpace($runtimeConfigAfterSnapshot.provider)) { '未声明' } else { $runtimeConfigAfterSnapshot.provider }), $(if ([string]::IsNullOrWhiteSpace($runtimeConfigAfterSnapshot.auth_method)) { '未声明' } else { $runtimeConfigAfterSnapshot.auth_method }))
}
elseif ($runtimeConfigBeforeSnapshot.exists) {
    Write-Ok '已保留你现有的全局 config.toml；本次不会覆盖 provider / model / auth。'
    Write-Info ("当前全局配置：provider={0}；auth={1}" -f $(if ([string]::IsNullOrWhiteSpace($runtimeConfigBeforeSnapshot.provider)) { '未声明' } else { $runtimeConfigBeforeSnapshot.provider }), $(if ([string]::IsNullOrWhiteSpace($runtimeConfigBeforeSnapshot.auth_method)) { '未声明' } else { $runtimeConfigBeforeSnapshot.auth_method }))
    if ($providerWouldChange) {
        Write-WarnLine ("仓内模板 provider={0} 与你当前 provider={1} 不同；由于默认保留现有配置，本次未切换。" -f $templateConfigSnapshot.provider, $runtimeConfigBeforeSnapshot.provider)
    }
}
else {
    Write-WarnLine '未发现现有全局 config.toml；当前安装仍不会自动套用仓内 provider 模板。'
    Write-Info '如需显式写入模板配置，请重新执行 install.cmd -ApplyTemplateConfig。'
}
if ($legacyRuntimeMetaExists) {
    Write-WarnLine ("检测到旧 `config/marshal-mode` 残留：{0}" -f $legacyRuntimeMetaRoot)
    if ($migratedLegacyTaskStartState) {
        Write-Info '本次已自动迁移可复用的 `task-start-state.json` 到新路径。'
    }
    else {
        Write-Info '本次未发现需要自动迁移的旧状态文件。'
    }
    Write-WarnLine '当前不会自动删除旧目录；若确认旧版本已废弃，请由 Codex 在维护层协助你清理。'
}
if ($migratedLegacyTaskStartState) {
    Write-Info '已把旧 `config/marshal-mode/task-start-state.json` 迁到新主路径 `config/chancellor-mode/task-start-state.json`。'
}
Write-Info ("对外入口已落地：{0}" -f (Join-Path $resolvedTargetCodexHome 'install.cmd'))
Write-WarnLine '如需验证生产真源是否接管成功，请继续执行 self-check.cmd 或 verify-cutover.ps1。'
