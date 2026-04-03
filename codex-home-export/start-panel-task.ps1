param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Title,
    [string]$Goal = '',
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [ValidateSet('trial', 'target')]
    [string]$TaskNamespace = 'target',
    [ValidateSet('low', 'medium', 'high', 'critical')]
    [string]$RiskLevel = 'low',
    [switch]$SkipAutoRepair,
    [switch]$ForceVerify
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..'
}
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$verifyScriptPath = Join-Path $scriptRootPath 'verify-cutover.ps1'
$installScriptPath = Join-Path $scriptRootPath 'install-to-home.ps1'
$newTaskScriptPath = Join-Path $scriptRootPath 'new-task.ps1'
$renderPanelResponseScriptPath = Join-Path $scriptRootPath 'render-panel-response.ps1'
$versionSourcePath = Join-Path $scriptRootPath 'VERSION.json'
$agentsSourcePath = Join-Path $scriptRootPath 'AGENTS.md'
$configSourcePath = Join-Path $scriptRootPath 'config.toml'
$runtimeVersionPath = Join-Path $resolvedTargetCodexHome 'config\cx-version.json'
$runtimeAgentsPath = Join-Path $resolvedTargetCodexHome 'AGENTS.md'
$runtimeConfigPath = Join-Path $resolvedTargetCodexHome 'config.toml'
$runtimeMetaRootPath = Join-Path $resolvedTargetCodexHome 'config\marshal-mode'
$taskStartStatePath = Join-Path $runtimeMetaRootPath 'task-start-state.json'
$activeTaskFilePath = Join-Path $resolvedRepoRootPath '.codex\chancellor\active-task.txt'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Get-ActiveTaskId([string]$Path) {
    if (-not (Test-Path $Path)) {
        return ''
    }

    return ((Get-Content $Path | Select-Object -First 1) | ForEach-Object { $_.Trim() })
}

function Read-JsonFileOrNull([string]$Path) {
    if (-not (Test-Path $Path)) {
        return $null
    }

    return (Get-Content -Raw -Path $Path | ConvertFrom-Json)
}

function Write-RenderedPanelLines([hashtable]$Arguments) {
    foreach ($renderedLine in @(& $renderPanelResponseScriptPath @Arguments)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$renderedLine)) {
            Write-Output $renderedLine
        }
    }
}

function Write-Utf8NoBomJson([string]$Path, [object]$Payload) {
    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $jsonText = ($Payload | ConvertTo-Json -Depth 6)
    [System.IO.File]::WriteAllText($Path, $jsonText, $utf8NoBom)
}

function Get-Sha256TextOrEmpty([string]$Path) {
    if (-not (Test-Path $Path)) {
        return ''
    }

    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Get-DefaultLightCheckTargets() {
    return @(
        [ordered]@{ name = '版本镜像'; source_path = 'VERSION.json'; runtime_path = 'config/cx-version.json' }
        [ordered]@{ name = '规则总纲'; source_path = 'AGENTS.md'; runtime_path = 'AGENTS.md' }
        [ordered]@{ name = '主配置'; source_path = 'config.toml'; runtime_path = 'config.toml' }
        [ordered]@{ name = '入口路由脚本'; source_path = 'invoke-panel-command.ps1'; runtime_path = 'config/marshal-mode/invoke-panel-command.ps1' }
        [ordered]@{ name = '开工脚本'; source_path = 'start-panel-task.ps1'; runtime_path = 'config/marshal-mode/start-panel-task.ps1' }
        [ordered]@{ name = '渲染脚本'; source_path = 'render-panel-response.ps1'; runtime_path = 'config/marshal-mode/render-panel-response.ps1' }
    )
}

function Get-LightCheckTargetDefinitions([object]$SourceVersionInfo) {
    if (($null -ne $SourceVersionInfo) -and ($null -ne $SourceVersionInfo.light_check_targets) -and (@($SourceVersionInfo.light_check_targets).Count -gt 0)) {
        return @($SourceVersionInfo.light_check_targets)
    }

    return @(Get-DefaultLightCheckTargets)
}

function Resolve-LightCheckTargets([object[]]$TargetDefinitions, [string]$ScriptRootPath, [string]$ResolvedTargetCodexHome) {
    $resolvedTargets = @()
    foreach ($targetDefinition in $TargetDefinitions) {
        $sourceRelativePath = [string]$targetDefinition.source_path
        $runtimeRelativePath = [string]$targetDefinition.runtime_path
        $targetName = if ([string]::IsNullOrWhiteSpace([string]$targetDefinition.name)) { $sourceRelativePath } else { [string]$targetDefinition.name }
        $sourcePath = Join-Path $ScriptRootPath (($sourceRelativePath -replace '/', '\'))
        $runtimePath = Join-Path $ResolvedTargetCodexHome (($runtimeRelativePath -replace '/', '\'))
        $resolvedTargets += [pscustomobject]@{
            Name = $targetName
            SourceRelativePath = $sourceRelativePath
            RuntimeRelativePath = $runtimeRelativePath
            SourcePath = $sourcePath
            RuntimePath = $runtimePath
            SourceHash = Get-Sha256TextOrEmpty -Path $sourcePath
            RuntimeHash = Get-Sha256TextOrEmpty -Path $runtimePath
        }
    }

    return @($resolvedTargets)
}

function Test-LightCheckTargetsSatisfied([object]$TaskStartState, [object[]]$ResolvedTargets) {
    if ($null -eq $TaskStartState) {
        return $false
    }

    if (-not ($TaskStartState.PSObject.Properties.Name -contains 'light_check_hashes')) {
        return $false
    }

    $stateItems = @($TaskStartState.light_check_hashes)
    if ($stateItems.Count -ne $ResolvedTargets.Count) {
        return $false
    }

    foreach ($resolvedTarget in $ResolvedTargets) {
        if ([string]::IsNullOrWhiteSpace($resolvedTarget.SourceHash) -or [string]::IsNullOrWhiteSpace($resolvedTarget.RuntimeHash)) {
            return $false
        }

        if ($resolvedTarget.SourceHash -ne $resolvedTarget.RuntimeHash) {
            return $false
        }

        $stateItem = @(
            $stateItems |
                Where-Object {
                    ($_.source_path -eq $resolvedTarget.SourceRelativePath) -and
                    ($_.runtime_path -eq $resolvedTarget.RuntimeRelativePath)
                } |
                Select-Object -First 1
        )
        if ($stateItem.Count -eq 0) {
            return $false
        }

        if (($stateItem[0].source_sha256 -ne $resolvedTarget.SourceHash) -or ($stateItem[0].runtime_sha256 -ne $resolvedTarget.RuntimeHash)) {
            return $false
        }
    }

    return $true
}

function New-LightCheckHashesPayload([object[]]$ResolvedTargets) {
    return @(
        $ResolvedTargets | ForEach-Object {
            [ordered]@{
                name = $_.Name
                source_path = $_.SourceRelativePath
                runtime_path = $_.RuntimeRelativePath
                source_sha256 = $_.SourceHash
                runtime_sha256 = $_.RuntimeHash
            }
        }
    )
}

foreach ($requiredPath in @($verifyScriptPath, $installScriptPath, $newTaskScriptPath, $renderPanelResponseScriptPath, $versionSourcePath, $agentsSourcePath, $configSourcePath, $runtimeAgentsPath, $runtimeConfigPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少一句话开工所需脚本：$requiredPath"
    }
}

Write-Info "RepoRoot=$resolvedRepoRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info ("TaskTitle={0}" -f $Title)

$sourceVersionInfo = Read-JsonFileOrNull -Path $versionSourcePath
$runtimeVersionInfo = Read-JsonFileOrNull -Path $runtimeVersionPath
$taskStartState = Read-JsonFileOrNull -Path $taskStartStatePath
$lightCheckTargetDefinitions = Get-LightCheckTargetDefinitions -SourceVersionInfo $sourceVersionInfo
$lightCheckTargets = Resolve-LightCheckTargets -TargetDefinitions $lightCheckTargetDefinitions -ScriptRootPath $scriptRootPath -ResolvedTargetCodexHome $resolvedTargetCodexHome
$currentSourceVersion = if ($null -ne $sourceVersionInfo) { $sourceVersionInfo.cx_version } else { '' }
$currentRuntimeVersion = if ($null -ne $runtimeVersionInfo) { $runtimeVersionInfo.cx_version } else { '' }
$currentSourceRoot = $scriptRootPath
$currentSourceAgentsHash = Get-Sha256TextOrEmpty -Path $agentsSourcePath
$currentSourceConfigHash = Get-Sha256TextOrEmpty -Path $configSourcePath
$currentRuntimeAgentsHash = Get-Sha256TextOrEmpty -Path $runtimeAgentsPath
$currentRuntimeConfigHash = Get-Sha256TextOrEmpty -Path $runtimeConfigPath

Write-Host ''
Write-RenderedPanelLines @{
    Kind = 'task-entry'
    VersionPath = $versionSourcePath
    RepoRootPath = $resolvedRepoRootPath
    TargetCodexHome = $resolvedTargetCodexHome
}
Write-RenderedPanelLines @{
    Kind = 'process-quote'
    Phase = 'task_entry'
    VersionPath = $versionSourcePath
}
Write-RenderedPanelLines @{
    Kind = 'process-quote'
    Phase = 'analysis'
    VersionPath = $versionSourcePath
}

$canSkipVerify = $false
if (-not $ForceVerify) {
    if (($null -ne $taskStartState) -and ($taskStartState.verify_status -eq 'passed') -and ($taskStartState.cx_version -eq $currentSourceVersion) -and ($taskStartState.runtime_version -eq $currentRuntimeVersion) -and ($taskStartState.source_root -eq $currentSourceRoot) -and ($currentSourceVersion -eq $currentRuntimeVersion) -and (Test-LightCheckTargetsSatisfied -TaskStartState $taskStartState -ResolvedTargets $lightCheckTargets)) {
        $canSkipVerify = $true
    }
}

$repairUsed = $false
$verifySkipped = $false
$verifyErrorMessage = ''
Write-RenderedPanelLines @{
    Kind = 'process-quote'
    Phase = 'breakdown'
    VersionPath = $versionSourcePath
}
if ($canSkipVerify) {
    $verifySkipped = $true
    Write-Info ("检测到当前版本 {0} 已完成上次自检，本次直接进入记任务与执行。" -f $currentSourceVersion)
}
else {
    try {
        & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome
    }
    catch {
        $verifyErrorMessage = $_.Exception.Message.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($verifyErrorMessage)) {
        if ($verifyErrorMessage -like 'auth.json 不存在*') {
            throw '当前还没登录官方 Codex，不能自动开工。请先完成登录，再回面板重试“传令：我要做 XX”。'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($verifyErrorMessage)) {
        if ($SkipAutoRepair) {
            throw ("自动验真未通过：{0}" -f $verifyErrorMessage)
        }

        Write-WarnLine ("自动验真未通过，开始尝试一次安全修复：{0}" -f $verifyErrorMessage)
        & $installScriptPath -TargetCodexHome $resolvedTargetCodexHome
        & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome
        $repairUsed = $true
        $runtimeVersionInfo = Read-JsonFileOrNull -Path $runtimeVersionPath
        $currentRuntimeVersion = if ($null -ne $runtimeVersionInfo) { $runtimeVersionInfo.cx_version } else { '' }
        $currentRuntimeAgentsHash = Get-Sha256TextOrEmpty -Path $runtimeAgentsPath
        $currentRuntimeConfigHash = Get-Sha256TextOrEmpty -Path $runtimeConfigPath
        $lightCheckTargets = Resolve-LightCheckTargets -TargetDefinitions $lightCheckTargetDefinitions -ScriptRootPath $scriptRootPath -ResolvedTargetCodexHome $resolvedTargetCodexHome
    }

    $taskStartStatePayload = [ordered]@{
        verified_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        verify_status = 'passed'
        cx_version = $currentSourceVersion
        runtime_version = $currentRuntimeVersion
        source_root = $currentSourceRoot
        target_codex_home = $resolvedTargetCodexHome
        source_agents_hash = $currentSourceAgentsHash
        source_config_hash = $currentSourceConfigHash
        runtime_agents_hash = $currentRuntimeAgentsHash
        runtime_config_hash = $currentRuntimeConfigHash
        repair_used = $repairUsed
        light_check_hashes = New-LightCheckHashesPayload -ResolvedTargets $lightCheckTargets
    }
    Write-Utf8NoBomJson -Path $taskStartStatePath -Payload $taskStartStatePayload
}

$newTaskArguments = @{
    Title = $Title
    RepoRootPath = $resolvedRepoRootPath
    TaskNamespace = $TaskNamespace
    RiskLevel = $RiskLevel
    PanelMode = $true
}
if (-not [string]::IsNullOrWhiteSpace($Goal)) {
    $newTaskArguments['Goal'] = $Goal
}

Write-RenderedPanelLines @{
    Kind = 'process-quote'
    Phase = 'dispatch'
    VersionPath = $versionSourcePath
}
& $newTaskScriptPath @newTaskArguments
Write-RenderedPanelLines @{
    Kind = 'process-quote'
    Phase = 'wrap_up'
    VersionPath = $versionSourcePath
}

$activeTaskId = Get-ActiveTaskId -Path $activeTaskFilePath
$lastCheckValue = if ($verifySkipped) {
    if (($null -ne $taskStartState) -and (-not [string]::IsNullOrWhiteSpace([string]$taskStartState.verified_at))) {
        [string]$taskStartState.verified_at
    }
    else {
        '沿用上次已通过状态'
    }
}
else {
    [string]$taskStartStatePayload.verified_at
}
$autoRepairValue = if ($repairUsed) { '已执行一次必要修整，并复查通过' } else { '无' }
$matchedLightCheckTargets = @(
    $lightCheckTargets |
        Where-Object {
            (-not [string]::IsNullOrWhiteSpace($_.SourceHash)) -and
            ($_.SourceHash -eq $_.RuntimeHash)
        }
)
$keyFileConsistencyValue = if ($matchedLightCheckTargets.Count -eq $lightCheckTargets.Count) { '一致' } else { '待复核' }
$currentTaskValue = if (-not [string]::IsNullOrWhiteSpace($activeTaskId)) { '{0}（{1}）' -f $activeTaskId, $Title } else { $Title }

Write-Ok '一句话开工已完成。'
Write-RenderedPanelLines @{
    Kind = 'status'
    VersionPath = $versionSourcePath
    RepoRootPath = $resolvedRepoRootPath
    TargetCodexHome = $resolvedTargetCodexHome
    CxVersion = $currentSourceVersion
    LastCheck = $lastCheckValue
    AutoRepair = $autoRepairValue
    KeyFileConsistency = $keyFileConsistencyValue
    CurrentMode = '丞相'
    CurrentTask = $currentTaskValue
}
Write-RenderedPanelLines @{
    Kind = 'closeout'
    VersionPath = $versionSourcePath
    CompletedText = ('已完成“{0}”的开工准备。' -f $Title)
    ResultText = ('当前任务已记录为 {0}。' -f $currentTaskValue)
    NextStepText = '留在当前会话，直接判断瓶颈并开始，不用切到 PowerShell。'
}
