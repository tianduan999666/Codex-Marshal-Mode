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
$manifestSourcePath = Join-Path $sourceRoot 'manifest.json'
$runtimeMetaRoot = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode'
$runtimeVersionPath = Join-Path $resolvedTargetCodexHome 'config\cx-version.json'
$runtimeManifestPath = Join-Path $runtimeMetaRoot 'manifest.json'
$runtimeInstallRecordPath = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode\install-record.json'
$runtimeTaskStartStatePath = Join-Path $runtimeMetaRoot 'task-start-state.json'
$authPath = Join-Path $resolvedTargetCodexHome 'auth.json'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
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

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json)
}

function Ensure-ParentDirectory([string]$Path) {
    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
}

function Write-Utf8BomJson([string]$Path, [object]$Payload) {
    Ensure-ParentDirectory -Path $Path
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $jsonText = ($Payload | ConvertTo-Json -Depth 6)
    [System.IO.File]::WriteAllText($Path, $jsonText, $utf8Bom)
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

function Get-DefaultLightCheckTargets() {
    return @(
        [ordered]@{ name = '版本镜像'; source_path = 'VERSION.json'; runtime_path = 'config/cx-version.json' }
        [ordered]@{ name = '规则总纲'; source_path = 'AGENTS.md'; runtime_path = 'AGENTS.md' }
        [ordered]@{ name = '入口路由脚本'; source_path = 'invoke-panel-command.ps1'; runtime_path = 'config/chancellor-mode/invoke-panel-command.ps1' }
        [ordered]@{ name = '开工脚本'; source_path = 'start-panel-task.ps1'; runtime_path = 'config/chancellor-mode/start-panel-task.ps1' }
        [ordered]@{ name = '渲染脚本'; source_path = 'render-panel-response.ps1'; runtime_path = 'config/chancellor-mode/render-panel-response.ps1' }
    )
}

function Get-LightCheckTargetDefinitions([object]$SourceVersionInfo) {
    if (($null -ne $SourceVersionInfo) -and ($null -ne $SourceVersionInfo.light_check_targets) -and (@($SourceVersionInfo.light_check_targets).Count -gt 0)) {
        return @($SourceVersionInfo.light_check_targets)
    }

    return @(Get-DefaultLightCheckTargets)
}

function New-LightCheckHashesPayload([object[]]$TargetDefinitions, [string]$SourceRoot, [string]$ResolvedTargetCodexHome) {
    return @(
        $TargetDefinitions | ForEach-Object {
            $sourceRelativePath = [string]$_.source_path
            $runtimeRelativePath = [string]$_.runtime_path
            $sourcePath = Join-Path $SourceRoot (($sourceRelativePath -replace '/', '\'))
            $runtimePath = Join-Path $ResolvedTargetCodexHome (($runtimeRelativePath -replace '/', '\'))
            [ordered]@{
                name = [string]$_.name
                source_path = $sourceRelativePath
                runtime_path = $runtimeRelativePath
                source_sha256 = Get-Sha256Text -Path $sourcePath
                runtime_sha256 = Get-Sha256Text -Path $runtimePath
            }
        }
    )
}

foreach ($requiredPath in @($versionSourcePath, $manifestSourcePath, $runtimeVersionPath, $runtimeManifestPath, $runtimeInstallRecordPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少必需文件：$requiredPath"
    }
}

$sourceVersionInfo = Read-JsonFile -Path $versionSourcePath
$sourceManifestInfo = Read-JsonFile -Path $manifestSourcePath
$runtimeVersionInfo = Read-JsonFile -Path $runtimeVersionPath
$runtimeManifestInfo = Read-JsonFile -Path $runtimeManifestPath
$runtimeInstallRecord = Read-JsonFile -Path $runtimeInstallRecordPath
$managedFileMappings = Get-ManagedFileMappings -SourceRoot $sourceRoot -ResolvedTargetCodexHome $resolvedTargetCodexHome -RuntimeMetaRoot $runtimeMetaRoot -ManifestInfo $sourceManifestInfo
$managedRelativeNames = @($managedFileMappings | ForEach-Object { $_.RelativeName })
$requiredRuntimePaths = @($managedFileMappings | ForEach-Object { $_.TargetPath }) + @($runtimeInstallRecordPath)
$requiredSourcePaths = @($managedFileMappings | ForEach-Object { $_.SourcePath })
$expectedVersionValue = if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) { $sourceVersionInfo.cx_version } else { $ExpectedVersion }
$expectedSourceRootValue = if ([string]::IsNullOrWhiteSpace($ExpectedSourceRoot)) { $sourceRoot } else { $ExpectedSourceRoot }

foreach ($requiredPath in $requiredSourcePaths + $requiredRuntimePaths) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少必需文件：$requiredPath"
    }
}

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

foreach ($requiredManagedFile in $managedRelativeNames + @('config/chancellor-mode/install-record.json')) {
    if (-not ($runtimeInstallRecord.managed_files -contains $requiredManagedFile)) {
        throw "安装记录缺少 managed_files 项：$requiredManagedFile"
    }
}

$expectedHashByPath = @{}
foreach ($fileMapping in $managedFileMappings) {
    $expectedHashByPath[$fileMapping.RelativeName] = Get-Sha256Text -Path $fileMapping.SourcePath
}

foreach ($fileMapping in $managedFileMappings) {
    $hashPath = $fileMapping.RelativeName
    $runtimeHash = Get-Sha256Text -Path $fileMapping.TargetPath
    if ($runtimeHash -ne $expectedHashByPath[$hashPath]) {
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

$lightCheckTargetDefinitions = Get-LightCheckTargetDefinitions -SourceVersionInfo $sourceVersionInfo
$taskStartStatePayload = [ordered]@{
    verified_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    verify_status = 'passed'
    cx_version = $expectedVersionValue
    runtime_version = $runtimeVersionInfo.cx_version
    source_root = $expectedSourceRootValue
    target_codex_home = $resolvedTargetCodexHome
    source_agents_hash = Get-Sha256Text -Path (Join-Path $sourceRoot 'AGENTS.md')
    runtime_agents_hash = Get-Sha256Text -Path (Join-Path $resolvedTargetCodexHome 'AGENTS.md')
    repair_used = $false
    light_check_hashes = New-LightCheckHashesPayload -TargetDefinitions $lightCheckTargetDefinitions -SourceRoot $sourceRoot -ResolvedTargetCodexHome $resolvedTargetCodexHome
}
Write-Utf8BomJson -Path $runtimeTaskStartStatePath -Payload $taskStartStatePayload

Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info "CxVersion=$($runtimeVersionInfo.cx_version)"
Write-Info "BackupRoot=$($runtimeInstallRecord.backup_root)"
Write-Info ("ManagedFileCount={0}" -f $managedFileMappings.Count)
Write-Info '运行态说明：`task-start-state.json` 只用于同版本轻量复核缓存；不属于 manifest 受管文件，也不参与公开提交。'
Write-Info '全局 config.toml 属于用户自有配置；当前验真不会再把 provider / model / auth 当作丞相模式受管项。'
Write-Info "健康状态已回写：$runtimeTaskStartStatePath"
Write-Ok '生产母体受管文件验真通过。'
Write-Info '默认日常入口：回官方 Codex 面板直接说 `传令：修一下登录页`。'
Write-Info ("维护层四个动作：{0} / {1} / {2} / {3}" -f 'install.cmd', 'upgrade.cmd', 'self-check.cmd', 'rollback.cmd')
Write-Info '对外流程：先确认丞相能正常接到传令 → 再确认丞相自身状态良好 → 接着把丞相调整到最佳工作状态 → 丞相记录这次要做的任务 → 丞相开始执行任务。'
Write-Info '固定边界：丞相在检查阶段只检查自己，不会查看你的项目；执行阶段只按你的传令办事，不会擅自审查项目。'
Write-Info '若当前就在维护层，也可执行 `new-task.ps1 -Title "你的任务标题"` 直接起任务。'
Write-Info '若发现异常：先重跑 `self-check.cmd`，仍异常再执行 `rollback.cmd`。'
