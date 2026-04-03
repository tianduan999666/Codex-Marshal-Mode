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
$runtimeVersionPath = Join-Path $resolvedTargetCodexHome 'config\cx-version.json'
$runtimeAgentsPath = Join-Path $resolvedTargetCodexHome 'AGENTS.md'
$runtimeMetaRootPath = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode'
$taskStartStatePath = Join-Path $runtimeMetaRootPath 'task-start-state.json'
$activeTaskFilePath = Join-Path $resolvedRepoRootPath '.codex\chancellor\active-task.txt'
$authPath = Join-Path $resolvedTargetCodexHome 'auth.json'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlyTaskStart {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string[]]$NextSteps = @()
    )

    Write-Host ''
    Write-Host "[ERROR] $Summary" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原始错误：{0}" -f $Detail)
    }

    foreach ($nextStep in $NextSteps) {
        Write-Info $nextStep
    }

    exit 1
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

    return (Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json)
}

function Write-RenderedPanelLines([hashtable]$Arguments) {
    foreach ($renderedLine in @(& $renderPanelResponseScriptPath @Arguments)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$renderedLine)) {
            Write-Output $renderedLine
        }
    }
}

function Write-RenderedPanelLinesSafe {
    param(
        [hashtable]$Arguments,
        [string]$Summary,
        [string[]]$NextSteps = @()
    )

    try {
        Write-RenderedPanelLines @Arguments
    }
    catch {
        Stop-FriendlyTaskStart `
            -Summary $Summary `
            -Detail $_.Exception.Message.Trim() `
            -NextSteps $NextSteps
    }
}

function Invoke-ManagedTaskStep {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments = @{},
        [string]$Summary,
        [string[]]$NextSteps = @(),
        [switch]$ReturnExitCode
    )

    $global:LASTEXITCODE = 0
    try {
        & $ScriptPath @Arguments
    }
    catch {
        Stop-FriendlyTaskStart `
            -Summary $Summary `
            -Detail $_.Exception.Message.Trim() `
            -NextSteps $NextSteps
    }

    $childExitCode = $LASTEXITCODE
    if ($ReturnExitCode) {
        return $childExitCode
    }

    if ($childExitCode -ne 0) {
        exit $childExitCode
    }

    return 0
}

function Write-Utf8BomJson([string]$Path, [object]$Payload) {
    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $jsonText = ($Payload | ConvertTo-Json -Depth 6)
    [System.IO.File]::WriteAllText($Path, $jsonText, $utf8Bom)
}

function Get-Sha256TextOrEmpty([string]$Path) {
    if (-not (Test-Path $Path)) {
        return ''
    }

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

foreach ($requiredPath in @($verifyScriptPath, $installScriptPath, $newTaskScriptPath, $renderPanelResponseScriptPath, $versionSourcePath, $agentsSourcePath, $runtimeAgentsPath)) {
    if (-not (Test-Path $requiredPath)) {
        Stop-FriendlyTaskStart `
            -Summary '一句话开工缺少必要文件，当前还不能继续。' `
            -Detail ("缺少一句话开工所需脚本：{0}" -f $requiredPath) `
            -NextSteps @(
                '先执行 `self-check.cmd` 或 `install.cmd` 补齐入口文件。',
                '补齐后再回面板重试当前任务。'
            )
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
$currentRuntimeAgentsHash = Get-Sha256TextOrEmpty -Path $runtimeAgentsPath

Write-Host ''
Write-RenderedPanelLinesSafe -Arguments @{
    Kind = 'task-entry'
    VersionPath = $versionSourcePath
    RepoRootPath = $resolvedRepoRootPath
    TargetCodexHome = $resolvedTargetCodexHome
} -Summary '丞相已经接到任务，但开工口径渲染这一步没跑通。' -NextSteps @(
    '先执行 `self-check.cmd` 看入口文件是否完整。',
    '如果刚改过版本模板，先补齐后再回面板重试。'
)
Write-RenderedPanelLinesSafe -Arguments @{
    Kind = 'process-quote'
    Phase = 'analysis'
    VersionPath = $versionSourcePath
} -Summary '丞相已经接到任务，但过程提示语渲染失败了。' -NextSteps @(
    '先检查版本模板和渲染脚本是否同一批。',
    '修好后再重新发起当前任务。'
)

$canSkipVerify = $false
if (-not $ForceVerify) {
    if (($null -ne $taskStartState) -and ($taskStartState.verify_status -eq 'passed') -and ($taskStartState.cx_version -eq $currentSourceVersion) -and ($taskStartState.runtime_version -eq $currentRuntimeVersion) -and ($taskStartState.source_root -eq $currentSourceRoot) -and ($currentSourceVersion -eq $currentRuntimeVersion) -and (Test-LightCheckTargetsSatisfied -TaskStartState $taskStartState -ResolvedTargets $lightCheckTargets)) {
        $canSkipVerify = $true
    }
}

$repairUsed = $false
$verifySkipped = $false
Write-RenderedPanelLinesSafe -Arguments @{
    Kind = 'process-quote'
    Phase = 'breakdown'
    VersionPath = $versionSourcePath
} -Summary '丞相已经接到任务，但拆解阶段提示语渲染失败了。' -NextSteps @(
    '先检查版本模板和渲染脚本。',
    '修好后再重新发起当前任务。'
)
if ($canSkipVerify) {
    $verifySkipped = $true
    Write-Info ("检测到当前版本 {0} 已完成上次自检，本次直接进入记任务与执行。" -f $currentSourceVersion)
}
else {
    if (-not (Test-Path $authPath)) {
        Stop-FriendlyTaskStart `
            -Summary '当前还没登录官方 Codex，不能自动开工。' `
            -NextSteps @(
                '先完成 Codex 登录。',
                '登录后再回面板重试“传令：修一下登录页”。'
            )
    }

    $verifyExitCode = Invoke-ManagedTaskStep `
        -ScriptPath $verifyScriptPath `
        -Arguments @{ TargetCodexHome = $resolvedTargetCodexHome } `
        -Summary '开工前自检脚本自己报错了。' `
        -NextSteps @(
            '先执行 `self-check.cmd` 看完整结果。',
            '如果刚换过文件或版本，先别直接开工。'
        ) `
        -ReturnExitCode

    if ($verifyExitCode -ne 0) {
        if ($SkipAutoRepair) {
            Stop-FriendlyTaskStart `
                -Summary '自动验真未通过，本次已按要求停止，不做自动修整。' `
                -NextSteps @(
                    '先执行 `self-check.cmd` 看详细原因。',
                    '确认稳定后，再重新发起当前任务。'
                )
        }

        Write-WarnLine '自动验真未通过，开始尝试一次安全修复。'
        Invoke-ManagedTaskStep `
            -ScriptPath $installScriptPath `
            -Arguments @{ TargetCodexHome = $resolvedTargetCodexHome } `
            -Summary '自动修整在同步丞相文件这一步自己报错了。' `
            -NextSteps @(
                '先执行 `install.cmd` 或 `rollback.cmd` 修好本机运行态。',
                '修好后再回面板重新发起任务。'
            )

        $verifyExitCode = Invoke-ManagedTaskStep `
            -ScriptPath $verifyScriptPath `
            -Arguments @{ TargetCodexHome = $resolvedTargetCodexHome } `
            -Summary '自动修整后的复检脚本自己报错了。' `
            -NextSteps @(
                '先执行 `self-check.cmd` 看详细原因。',
                '如果仍不通过，再执行 `rollback.cmd`。'
            ) `
            -ReturnExitCode

        if ($verifyExitCode -ne 0) {
            exit $verifyExitCode
        }

        $repairUsed = $true
        $runtimeVersionInfo = Read-JsonFileOrNull -Path $runtimeVersionPath
        $currentRuntimeVersion = if ($null -ne $runtimeVersionInfo) { $runtimeVersionInfo.cx_version } else { '' }
        $currentRuntimeAgentsHash = Get-Sha256TextOrEmpty -Path $runtimeAgentsPath
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
        runtime_agents_hash = $currentRuntimeAgentsHash
        repair_used = $repairUsed
        light_check_hashes = New-LightCheckHashesPayload -ResolvedTargets $lightCheckTargets
    }
    Write-Utf8BomJson -Path $taskStartStatePath -Payload $taskStartStatePayload
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

Write-RenderedPanelLinesSafe -Arguments @{
    Kind = 'process-quote'
    Phase = 'dispatch'
    VersionPath = $versionSourcePath
} -Summary '丞相已经完成自检，但调度阶段提示语渲染失败了。' -NextSteps @(
    '先执行 `self-check.cmd` 检查入口文件。',
    '修好后再重新发起当前任务。'
)
Invoke-ManagedTaskStep `
    -ScriptPath $newTaskScriptPath `
    -Arguments $newTaskArguments `
    -Summary '任务记录脚本自己报错了。' `
    -NextSteps @(
        '先检查任务模板和任务目录是否完整。',
        '修好后再重新发起当前任务。'
    )
Write-RenderedPanelLinesSafe -Arguments @{
    Kind = 'process-quote'
    Phase = 'wrap_up'
    VersionPath = $versionSourcePath
} -Summary '任务已经记下来了，但收束提示语渲染失败了。' -NextSteps @(
    '先检查版本模板和渲染脚本。',
    '修好后再重新发起当前任务。'
)

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
Write-RenderedPanelLinesSafe -Arguments @{
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
} -Summary '一句话开工已经完成，但状态栏渲染失败了。' -NextSteps @(
    '先执行 `self-check.cmd` 检查渲染链路。',
    '修好后再重新查看状态。'
)
Write-RenderedPanelLinesSafe -Arguments @{
    Kind = 'closeout'
    VersionPath = $versionSourcePath
    CompletedText = ('已完成“{0}”的开工准备。' -f $Title)
    ResultText = ('当前任务已记录为 {0}。' -f $currentTaskValue)
    NextStepText = '留在当前会话，直接判断瓶颈并开始，不用切到 PowerShell。'
} -Summary '一句话开工已经完成，但收口文案渲染失败了。' -NextSteps @(
    '先执行 `self-check.cmd` 检查渲染链路。',
    '修好后再重新发起当前任务。'
)
