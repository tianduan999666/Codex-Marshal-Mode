param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$ExpectedVersion,
    [string]$ExpectedSourceRoot,
    [switch]$RequireBackupRoot,
    [switch]$MaintainerMode
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

function Stop-FriendlyCutoverCheck {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string]$NextStep = ''
    )

    Write-Host ''
    Write-Host "[ERROR] $Summary" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host ("[WARN] 原因：{0}" -f $Detail) -ForegroundColor Yellow
    }

    if (-not [string]::IsNullOrWhiteSpace($NextStep)) {
        Write-Info ("下一步：{0}" -f $NextStep)
    }

    exit 1
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

function Format-FriendlyList([string[]]$Items) {
    $orderedItems = @(
        $Items |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    return ($orderedItems -join '、')
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
        Stop-FriendlyCutoverCheck `
            -Summary '验真缺少必要文件，说明当前安装还没完整落地。' `
            -Detail ("缺少必需文件：{0}" -f $requiredPath) `
            -NextStep '先执行 install.cmd 或 upgrade.cmd，把丞相文件重新同步到本机。'
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
        Stop-FriendlyCutoverCheck `
            -Summary '验真缺少必要文件，说明源仓或运行态文件不完整。' `
            -Detail ("缺少必需文件：{0}" -f $requiredPath) `
            -NextStep '先补齐仓库文件或重跑 install.cmd / upgrade.cmd，再重新验真。'
    }
}

if ($runtimeVersionInfo.cx_version -ne $expectedVersionValue) {
    Stop-FriendlyCutoverCheck `
        -Summary '运行态版本和当前真源版本没对齐。' `
        -Detail ("期望 {0}，实际 {1}" -f $expectedVersionValue, $runtimeVersionInfo.cx_version) `
        -NextStep '先重跑 install.cmd 或 upgrade.cmd，让运行态版本追上真源。'
}

if ($runtimeVersionInfo.source_of_truth -ne 'codex-home-export') {
    Stop-FriendlyCutoverCheck `
        -Summary '运行态真源标记不对，当前不能算接管完成。' `
        -Detail ("source_of_truth={0}" -f $runtimeVersionInfo.source_of_truth) `
        -NextStep '先重新安装当前仓版本，再重新验真。'
}

if ($runtimeInstallRecord.source_root -ne $expectedSourceRootValue) {
    Stop-FriendlyCutoverCheck `
        -Summary '安装记录指向的源仓不对，当前运行态可能接的是旧仓。' `
        -Detail ("期望 {0}，实际 {1}" -f $expectedSourceRootValue, $runtimeInstallRecord.source_root) `
        -NextStep '先用当前仓重新执行 install.cmd 或 upgrade.cmd。'
}

if ($runtimeInstallRecord.cx_version -ne $expectedVersionValue) {
    Stop-FriendlyCutoverCheck `
        -Summary '安装记录里的版本和当前真源版本不一致。' `
        -Detail ("期望 {0}，实际 {1}" -f $expectedVersionValue, $runtimeInstallRecord.cx_version) `
        -NextStep '先重跑 install.cmd 或 upgrade.cmd。'
}

if ($runtimeManifestInfo.version -ne $expectedVersionValue) {
    Stop-FriendlyCutoverCheck `
        -Summary '运行态 manifest 版本和真源版本不一致。' `
        -Detail ("期望 {0}，实际 {1}" -f $expectedVersionValue, $runtimeManifestInfo.version) `
        -NextStep '先重新安装当前版本，再重试验真。'
}

foreach ($requiredManagedFile in $managedRelativeNames + @('config/chancellor-mode/install-record.json')) {
    if (-not ($runtimeInstallRecord.managed_files -contains $requiredManagedFile)) {
        Stop-FriendlyCutoverCheck `
            -Summary '安装记录不完整，当前没法确认受管文件都已落地。' `
            -Detail ("安装记录里少了受管文件落地记录（字段：managed_files，缺少：{0}）。" -f $requiredManagedFile) `
            -NextStep '先重跑 install.cmd，让安装记录重新生成。'
    }
}

$expectedHashByPath = @{}
foreach ($fileMapping in $managedFileMappings) {
    $expectedHashByPath[$fileMapping.RelativeName] = Get-Sha256Text -Path $fileMapping.SourcePath
}

$runtimeDriftPaths = New-Object System.Collections.Generic.List[string]
$missingSyncedHashPaths = New-Object System.Collections.Generic.List[string]
$recordHashDriftPaths = New-Object System.Collections.Generic.List[string]
foreach ($fileMapping in $managedFileMappings) {
    $hashPath = $fileMapping.RelativeName
    $runtimeHash = Get-Sha256Text -Path $fileMapping.TargetPath
    if ($runtimeHash -ne $expectedHashByPath[$hashPath]) {
        if ($MaintainerMode) {
            [void]$runtimeDriftPaths.Add($hashPath)
        }
        else {
            Stop-FriendlyCutoverCheck `
                -Summary '运行态文件和源仓不同步。' `
                -Detail ("不同步文件：{0}" -f $hashPath) `
                -NextStep '先重跑 install.cmd 或 upgrade.cmd；如果仍不通过，再执行 rollback.cmd。'
        }
    }

    if ($runtimeInstallRecord.PSObject.Properties.Name -contains 'synced_hashes') {
        $recordHashItem = @($runtimeInstallRecord.synced_hashes | Where-Object { $_.path -eq $hashPath } | Select-Object -First 1)
        if ($recordHashItem.Count -eq 0) {
            if ($MaintainerMode) {
                [void]$missingSyncedHashPaths.Add($hashPath)
                continue
            }
            else {
                Stop-FriendlyCutoverCheck `
                    -Summary '安装记录不完整，当前没法确认同步结果。' `
                    -Detail ("安装记录里少了同步哈希记录（字段：synced_hashes，缺少：{0}）。" -f $hashPath) `
                    -NextStep '先重跑 install.cmd，让安装记录重新生成。'
            }
        }

        if ($recordHashItem[0].sha256 -ne $expectedHashByPath[$hashPath]) {
            if ($MaintainerMode) {
                [void]$recordHashDriftPaths.Add($hashPath)
            }
            else {
                Stop-FriendlyCutoverCheck `
                    -Summary '安装记录里的哈希和当前真源不一致。' `
                    -Detail ("哈希不匹配文件：{0}" -f $hashPath) `
                    -NextStep '先重跑 install.cmd 或 upgrade.cmd，再重新验真。'
            }
        }
    }
}

if ($MaintainerMode -and (($runtimeDriftPaths.Count -gt 0) -or ($missingSyncedHashPaths.Count -gt 0) -or ($recordHashDriftPaths.Count -gt 0))) {
    $detailParts = New-Object System.Collections.Generic.List[string]
    if ($runtimeDriftPaths.Count -gt 0) {
        [void]$detailParts.Add(("运行态不同步文件：{0}" -f (Format-FriendlyList -Items $runtimeDriftPaths)))
    }
    if ($missingSyncedHashPaths.Count -gt 0) {
        [void]$detailParts.Add(("安装记录缺少同步哈希记录（字段：synced_hashes）：{0}" -f (Format-FriendlyList -Items $missingSyncedHashPaths)))
    }
    if ($recordHashDriftPaths.Count -gt 0) {
        [void]$detailParts.Add(("安装记录哈希不匹配文件：{0}" -f (Format-FriendlyList -Items $recordHashDriftPaths)))
    }

    Stop-FriendlyCutoverCheck `
        -Summary '运行态受管文件存在漂移。' `
        -Detail ($detailParts -join '；') `
        -NextStep '先重跑 install.cmd 或 upgrade.cmd；如果仍不通过，再执行 rollback.cmd。'
}

if ($RequireBackupRoot) {
    if ([string]::IsNullOrWhiteSpace($runtimeInstallRecord.backup_root)) {
        Stop-FriendlyCutoverCheck `
            -Summary '当前没有可回滚备份，所以这次不能算完整验真通过。' `
            -Detail '安装记录里少了备份目录路径（字段：backup_root）。' `
            -NextStep '先重新执行 install.cmd，让系统补一份新备份。'
    }

    if (-not (Test-Path $runtimeInstallRecord.backup_root)) {
        Stop-FriendlyCutoverCheck `
            -Summary '安装记录里写了备份目录，但这份备份已经找不到了。' `
            -Detail ("备份目录路径不存在（backup_root={0}）。" -f $runtimeInstallRecord.backup_root) `
            -NextStep '先重新执行 install.cmd，生成新的可回滚备份。'
    }
}

if (-not (Test-Path $authPath)) {
    Stop-FriendlyCutoverCheck `
        -Summary '当前还没完成 Codex 登录，所以这次不能算验真通过。' `
        -Detail ("auth.json 不存在：{0}" -f $authPath) `
        -NextStep '先完成登录，再重跑 self-check.cmd 或 verify-cutover.ps1。'
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
Write-Info '本次只检查丞相自身运行态，不会改你的项目。'
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
