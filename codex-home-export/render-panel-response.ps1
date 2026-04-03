param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('hint', 'task-entry', 'version', 'status', 'upgrade', 'process-quote', 'closeout')]
    [string]$Kind,
    [ValidateSet('', 'task_entry', 'analysis', 'breakdown', 'dispatch', 'wrap_up', 'closeout')]
    [string]$Phase = '',
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$VersionPath = '',
    [string]$CxVersion = '',
    [string]$LastCheck = '',
    [string]$AutoRepair = '',
    [string]$KeyFileConsistency = '',
    [string]$CurrentMode = '',
    [string]$CurrentTask = '',
    [string]$CompletedText = '',
    [string]$ResultText = '',
    [string]$NextStepText = ''
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..'
}
if ([string]::IsNullOrWhiteSpace($VersionPath)) {
    $sourceVersionPath = Join-Path $scriptRootPath 'VERSION.json'
    $runtimeVersionPath = Join-Path (Split-Path -Parent $scriptRootPath) 'cx-version.json'
    if (Test-Path $sourceVersionPath) {
        $VersionPath = $sourceVersionPath
    }
    else {
        $VersionPath = $runtimeVersionPath
    }
}
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$resolvedVersionPath = [System.IO.Path]::GetFullPath($VersionPath)
$taskStartStatePath = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode\task-start-state.json'

function Read-PanelResponseJsonFile([string]$Path) {
    if (-not (Test-Path $Path)) {
        return $null
    }

    return (Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json)
}

function Stop-FriendlyPanelRender {
    param(
        [string]$Summary,
        [string]$Detail = ''
    )

    $messageParts = @($Summary)
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $messageParts += ("原因：{0}" -f $Detail)
    }

    throw ($messageParts -join ' ')
}

function Get-PanelResponseStringOrDefault([string]$Value, [string]$Fallback) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Fallback
    }

    return $Value
}

function Get-PanelResponseArrayOrDefault([object]$Value, [object[]]$Fallback) {
    if ($null -eq $Value) {
        return $Fallback
    }

    $items = @($Value | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($items.Count -eq 0) {
        return $Fallback
    }

    return $items
}

function Get-PanelResponseSha256OrEmpty([string]$Path) {
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

function Resolve-PanelResponseTemplateLine([string]$Template, [hashtable]$TokenMap) {
    $resolved = $Template
    foreach ($tokenName in $TokenMap.Keys) {
        $resolved = $resolved.Replace('<' + $tokenName + '>', [string]$TokenMap[$tokenName])
    }

    return $resolved
}

function Get-PanelResponseTemplateMapByLabel([string[]]$TemplateLines) {
    $templateMap = @{}
    foreach ($templateLine in $TemplateLines) {
        if ($templateLine -match '^\s*([^：:]+)\s*[：:]\s*') {
            $templateMap[$matches[1].Trim()] = $templateLine
        }
    }

    return $templateMap
}

function Get-PanelResponseDefaultLightCheckTargets() {
    return @(
        [ordered]@{ name = '版本镜像'; source_path = 'VERSION.json'; runtime_path = 'config/cx-version.json' }
        [ordered]@{ name = '规则总纲'; source_path = 'AGENTS.md'; runtime_path = 'AGENTS.md' }
        [ordered]@{ name = '入口路由脚本'; source_path = 'invoke-panel-command.ps1'; runtime_path = 'config/chancellor-mode/invoke-panel-command.ps1' }
        [ordered]@{ name = '开工脚本'; source_path = 'start-panel-task.ps1'; runtime_path = 'config/chancellor-mode/start-panel-task.ps1' }
        [ordered]@{ name = '渲染脚本'; source_path = 'render-panel-response.ps1'; runtime_path = 'config/chancellor-mode/render-panel-response.ps1' }
    )
}

function Get-PanelResponseLightCheckTargets([object]$VersionInfo) {
    if (($null -ne $VersionInfo) -and ($null -ne $VersionInfo.light_check_targets)) {
        $targets = @($VersionInfo.light_check_targets)
        if ($targets.Count -gt 0) {
            return $targets
        }
    }

    return @(Get-PanelResponseDefaultLightCheckTargets)
}

function Get-PanelResponseStateSourceRoot([object]$TaskStartState, [string]$ScriptRootPath) {
    if (($null -ne $TaskStartState) -and (-not [string]::IsNullOrWhiteSpace([string]$TaskStartState.source_root)) -and (Test-Path ([string]$TaskStartState.source_root))) {
        return [System.IO.Path]::GetFullPath([string]$TaskStartState.source_root)
    }

    return $ScriptRootPath
}

function Get-PanelResponseStateTargetCodexHome([object]$TaskStartState, [string]$ResolvedTargetCodexHome) {
    if (($null -ne $TaskStartState) -and (-not [string]::IsNullOrWhiteSpace([string]$TaskStartState.target_codex_home)) -and (Test-Path ([string]$TaskStartState.target_codex_home))) {
        return [System.IO.Path]::GetFullPath([string]$TaskStartState.target_codex_home)
    }

    return $ResolvedTargetCodexHome
}

function Test-PanelResponseTaskStartStateLightCheckSatisfied([object]$TaskStartState, [string]$SourceRootPath, [string]$TargetCodexHomePath) {
    if ($null -eq $TaskStartState) {
        return $false
    }

    if ($TaskStartState.verify_status -ne 'passed') {
        return $false
    }

    if (-not ($TaskStartState.PSObject.Properties.Name -contains 'light_check_hashes')) {
        return $false
    }

    $stateItems = @($TaskStartState.light_check_hashes)
    if ($stateItems.Count -eq 0) {
        return $false
    }

    foreach ($stateItem in $stateItems) {
        $sourceRelativePath = [string]$stateItem.source_path
        $runtimeRelativePath = [string]$stateItem.runtime_path
        $sourcePath = Join-Path $SourceRootPath ($sourceRelativePath -replace '/', '\')
        $runtimePath = Join-Path $TargetCodexHomePath ($runtimeRelativePath -replace '/', '\')
        $sourceHash = Get-PanelResponseSha256OrEmpty -Path $sourcePath
        $runtimeHash = Get-PanelResponseSha256OrEmpty -Path $runtimePath

        if ([string]::IsNullOrWhiteSpace($sourceHash) -or [string]::IsNullOrWhiteSpace($runtimeHash)) {
            return $false
        }

        if (($stateItem.source_sha256 -ne $sourceHash) -or ($stateItem.runtime_sha256 -ne $runtimeHash)) {
            return $false
        }

        if ($sourceHash -ne $runtimeHash) {
            return $false
        }
    }

    return $true
}

function Get-PanelResponseKeyFileConsistencyText([object]$VersionInfo, [object]$TaskStartState, [string]$ScriptRootPath, [string]$ResolvedTargetCodexHome, [string]$ExplicitValue) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitValue)) {
        return $ExplicitValue
    }

    $sourceRootPath = Get-PanelResponseStateSourceRoot -TaskStartState $TaskStartState -ScriptRootPath $ScriptRootPath
    $targetCodexHomePath = Get-PanelResponseStateTargetCodexHome -TaskStartState $TaskStartState -ResolvedTargetCodexHome $ResolvedTargetCodexHome

    if (Test-PanelResponseTaskStartStateLightCheckSatisfied -TaskStartState $TaskStartState -SourceRootPath $sourceRootPath -TargetCodexHomePath $targetCodexHomePath) {
        return '一致'
    }

    foreach ($targetDefinition in @(Get-PanelResponseLightCheckTargets -VersionInfo $VersionInfo)) {
        $sourcePath = Join-Path $sourceRootPath (([string]$targetDefinition.source_path) -replace '/', '\')
        $runtimePath = Join-Path $targetCodexHomePath (([string]$targetDefinition.runtime_path) -replace '/', '\')
        $sourceHash = Get-PanelResponseSha256OrEmpty -Path $sourcePath
        $runtimeHash = Get-PanelResponseSha256OrEmpty -Path $runtimePath
        if ([string]::IsNullOrWhiteSpace($sourceHash) -or ($sourceHash -ne $runtimeHash)) {
            return '待复核'
        }
    }

    return '一致'
}

function Get-PanelResponseLastCheckText([object]$TaskStartState, [string]$ExplicitValue) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitValue)) {
        return $ExplicitValue
    }

    if (($null -ne $TaskStartState) -and (-not [string]::IsNullOrWhiteSpace([string]$TaskStartState.verified_at))) {
        return [string]$TaskStartState.verified_at
    }

    return '未发现记录'
}

function Get-PanelResponseAutoRepairText([object]$TaskStartState, [string]$ExplicitValue) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitValue)) {
        return $ExplicitValue
    }

    if ($null -eq $TaskStartState) {
        return '未发现记录'
    }

    if ($TaskStartState.repair_used) {
        return '最近一次检查已自动修复'
    }

    return '无'
}

function Get-PanelResponseCurrentTaskText([string]$ResolvedRepoRootPath, [string]$ExplicitValue) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitValue)) {
        return $ExplicitValue
    }

    $activeTaskPath = Join-Path $ResolvedRepoRootPath '.codex\chancellor\active-task.txt'
    if (-not (Test-Path $activeTaskPath)) {
        return '无'
    }

    $activeTaskId = ((Get-Content $activeTaskPath | Select-Object -First 1) | ForEach-Object { $_.Trim() })
    if ([string]::IsNullOrWhiteSpace($activeTaskId)) {
        return '无'
    }

    return $activeTaskId
}

function Get-PanelResponseBaseTokenMap([object]$VersionInfo, [string]$ExplicitCxVersion) {
    return @{
        opening_line = Get-PanelResponseStringOrDefault -Value ([string]$VersionInfo.opening_line) -Fallback '🪶 军令入帐。亮，即刻接管全局。'
        boundary_prompt = Get-PanelResponseStringOrDefault -Value ([string]$VersionInfo.boundary_prompt) -Fallback '提示：丞相在检查阶段只检查自己，不会查看你的项目；执行阶段只按你的传令办事，不会擅自审查项目。'
        new_chat_hint = Get-PanelResponseStringOrDefault -Value ([string]$VersionInfo.new_chat_hint) -Fallback '例如：传令：计算1+1=?'
        task_entry_prefix = Get-PanelResponseStringOrDefault -Value ([string]$VersionInfo.task_entry_prefix) -Fallback '传令：'
        source_of_truth = Get-PanelResponseStringOrDefault -Value ([string]$VersionInfo.source_of_truth) -Fallback 'codex-home-export'
        version_truth_path = 'codex-home-export/VERSION.json'
        cx_version = Get-PanelResponseStringOrDefault -Value $ExplicitCxVersion -Fallback (Get-PanelResponseStringOrDefault -Value ([string]$VersionInfo.cx_version) -Fallback '未知版本')
    }
}

function Get-PanelResponseStatusTokenMap([object]$VersionInfo, [object]$TaskStartState, [string]$ScriptRootPath, [string]$ResolvedTargetCodexHome, [string]$ResolvedRepoRootPath, [string]$ExplicitLastCheck, [string]$ExplicitAutoRepair, [string]$ExplicitKeyFileConsistency, [string]$ExplicitCurrentMode, [string]$ExplicitCurrentTask) {
    return @{
        last_check = Get-PanelResponseLastCheckText -TaskStartState $TaskStartState -ExplicitValue $ExplicitLastCheck
        auto_repair = Get-PanelResponseAutoRepairText -TaskStartState $TaskStartState -ExplicitValue $ExplicitAutoRepair
        key_file_consistency = Get-PanelResponseKeyFileConsistencyText -VersionInfo $VersionInfo -TaskStartState $TaskStartState -ScriptRootPath $ScriptRootPath -ResolvedTargetCodexHome $ResolvedTargetCodexHome -ExplicitValue $ExplicitKeyFileConsistency
        current_mode = Get-PanelResponseStringOrDefault -Value $ExplicitCurrentMode -Fallback '丞相'
        current_task = Get-PanelResponseCurrentTaskText -ResolvedRepoRootPath $ResolvedRepoRootPath -ExplicitValue $ExplicitCurrentTask
    }
}

function Get-PanelResponseHintLines([object]$VersionInfo, [hashtable]$BaseTokens) {
    $templateLines = if (($null -ne $VersionInfo.standard_response_templates) -and ($null -ne $VersionInfo.standard_response_templates.hint)) {
        Get-PanelResponseArrayOrDefault -Value $VersionInfo.standard_response_templates.hint -Fallback @('<new_chat_hint>')
    }
    else {
        @('<new_chat_hint>')
    }

    return @($templateLines | ForEach-Object { Resolve-PanelResponseTemplateLine -Template $_ -TokenMap $BaseTokens })
}

function Get-PanelResponseTaskEntryLines([object]$VersionInfo, [hashtable]$BaseTokens, [bool]$NeedsCheck = $false) {
    $templateKey = if ($NeedsCheck) { 'task_entry_with_check' } else { 'task_entry' }
    $fallbackLines = @('<opening_line>', '<boundary_prompt>', '军令已明，亮先接手。')

    if (($null -ne $VersionInfo.standard_response_templates) -and ($null -ne $VersionInfo.standard_response_templates.$templateKey)) {
        $templateLines = Get-PanelResponseArrayOrDefault -Value $VersionInfo.standard_response_templates.$templateKey -Fallback $fallbackLines
    } else {
        $templateLines = $fallbackLines
    }

    return @($templateLines | ForEach-Object { Resolve-PanelResponseTemplateLine -Template $_ -TokenMap $BaseTokens })
}

function Get-PanelResponseVersionLines([object]$VersionInfo, [hashtable]$BaseTokens) {
    $templateLines = if (($null -ne $VersionInfo.standard_response_templates) -and ($null -ne $VersionInfo.standard_response_templates.version)) {
        Get-PanelResponseArrayOrDefault -Value $VersionInfo.standard_response_templates.version -Fallback @('版本号：<cx_version>', '版本来源：<source_of_truth>', '真源路径：<version_truth_path>')
    }
    else {
        @('版本号：<cx_version>', '版本来源：<source_of_truth>', '真源路径：<version_truth_path>')
    }

    return @($templateLines | ForEach-Object { Resolve-PanelResponseTemplateLine -Template $_ -TokenMap $BaseTokens })
}

function Get-PanelResponseUpgradeLines([object]$VersionInfo, [hashtable]$BaseTokens) {
    $templateLines = if (($null -ne $VersionInfo.standard_response_templates) -and ($null -ne $VersionInfo.standard_response_templates.upgrade)) {
        Get-PanelResponseArrayOrDefault -Value $VersionInfo.standard_response_templates.upgrade -Fallback @(
            '触发方式：只在用户主动输入 `传令：升级` 时触发'
            '处理边界：只处理丞相自身升级或同步，不擅自升级用户项目'
            '默认策略：未收到明确升级传令时，不自动升级'
        )
    }
    else {
        @(
            '触发方式：只在用户主动输入 `传令：升级` 时触发'
            '处理边界：只处理丞相自身升级或同步，不擅自升级用户项目'
            '默认策略：未收到明确升级传令时，不自动升级'
        )
    }

    return @($templateLines | ForEach-Object { Resolve-PanelResponseTemplateLine -Template $_ -TokenMap $BaseTokens })
}

function Get-PanelResponseStatusFallbackTemplateLine([string]$SlotName) {
    $slotTokenMap = @{
        '版本' = 'cx_version'
        '上次检查' = 'last_check'
        '自动修复' = 'auto_repair'
        '关键文件一致性' = 'key_file_consistency'
        '当前模式' = 'current_mode'
        '当前任务' = 'current_task'
    }

    return ('{0}：<{1}>' -f $SlotName, $slotTokenMap[$SlotName])
}

function Get-PanelResponseStatusLines([object]$VersionInfo, [object]$TaskStartState, [string]$ScriptRootPath, [string]$ResolvedTargetCodexHome, [string]$ResolvedRepoRootPath, [hashtable]$BaseTokens, [string]$ExplicitLastCheck, [string]$ExplicitAutoRepair, [string]$ExplicitKeyFileConsistency, [string]$ExplicitCurrentMode, [string]$ExplicitCurrentTask) {
    $statusTemplateLines = if (($null -ne $VersionInfo.standard_response_templates) -and ($null -ne $VersionInfo.standard_response_templates.status)) {
        Get-PanelResponseArrayOrDefault -Value $VersionInfo.standard_response_templates.status -Fallback @()
    }
    else {
        @()
    }
    $statusSlots = Get-PanelResponseArrayOrDefault -Value $VersionInfo.status_bar_slots -Fallback @('版本', '上次检查', '自动修复', '关键文件一致性', '当前模式', '当前任务')
    $statusTemplateMap = Get-PanelResponseTemplateMapByLabel -TemplateLines $statusTemplateLines
    $statusTokens = Get-PanelResponseStatusTokenMap -VersionInfo $VersionInfo -TaskStartState $TaskStartState -ScriptRootPath $ScriptRootPath -ResolvedTargetCodexHome $ResolvedTargetCodexHome -ResolvedRepoRootPath $ResolvedRepoRootPath -ExplicitLastCheck $ExplicitLastCheck -ExplicitAutoRepair $ExplicitAutoRepair -ExplicitKeyFileConsistency $ExplicitKeyFileConsistency -ExplicitCurrentMode $ExplicitCurrentMode -ExplicitCurrentTask $ExplicitCurrentTask
    $resolvedTokens = @{}
    foreach ($tokenName in $BaseTokens.Keys) {
        $resolvedTokens[$tokenName] = $BaseTokens[$tokenName]
    }
    foreach ($tokenName in $statusTokens.Keys) {
        $resolvedTokens[$tokenName] = $statusTokens[$tokenName]
    }

    $renderedLines = @()
    foreach ($statusSlot in $statusSlots) {
        $templateLine = if ($statusTemplateMap.ContainsKey([string]$statusSlot)) { $statusTemplateMap[[string]$statusSlot] } else { Get-PanelResponseStatusFallbackTemplateLine -SlotName ([string]$statusSlot) }
        $renderedLines += Resolve-PanelResponseTemplateLine -Template $templateLine -TokenMap $resolvedTokens
    }

    return $renderedLines
}

function Get-PanelResponseProcessQuoteText([object]$VersionInfo, [string]$PhaseName) {
    $defaultQuoteMap = @{
        task_entry = '军令已明，亮先接手。'
        analysis = '亮先看清症结，再动手。'
        breakdown = '此事可拆，亮按最短路径推进。'
        dispatch = '所需动作已排定，开始推进。'
        wrap_up = '主干已稳，亮正在收束余项。'
        closeout = '此事已交卷，现呈结果。'
    }
    $quoteText = ''
    if (($null -ne $VersionInfo.process_quotes_minimal) -and ($VersionInfo.process_quotes_minimal.PSObject.Properties.Name -contains $PhaseName)) {
        $quoteText = [string]$VersionInfo.process_quotes_minimal.$PhaseName
    }

    return Get-PanelResponseStringOrDefault -Value $quoteText -Fallback $defaultQuoteMap[$PhaseName]
}

function Get-PanelResponseCloseoutLines([object]$VersionInfo, [string]$ExplicitCompletedText, [string]$ExplicitResultText, [string]$ExplicitNextStepText) {
    $defaultSections = @('已完成', '结果', '下一步')
    $sections = if (($null -ne $VersionInfo.standard_response_templates) -and ($null -ne $VersionInfo.standard_response_templates.closeout_sections)) {
        Get-PanelResponseArrayOrDefault -Value $VersionInfo.standard_response_templates.closeout_sections -Fallback $defaultSections
    }
    else {
        $defaultSections
    }
    if ($sections.Count -lt 3) {
        $sections = $defaultSections
    }

    $leadLine = Get-PanelResponseProcessQuoteText -VersionInfo $VersionInfo -PhaseName 'closeout'
    $completedValue = Get-PanelResponseStringOrDefault -Value $ExplicitCompletedText -Fallback '已完成本次收口。'
    $resultValue = Get-PanelResponseStringOrDefault -Value $ExplicitResultText -Fallback '结果已汇总。'
    $nextStepValue = Get-PanelResponseStringOrDefault -Value $ExplicitNextStepText -Fallback '可继续下一步。'

    return @(
        $leadLine
        ('{0}：{1}' -f $sections[0], $completedValue)
        ('{0}：{1}' -f $sections[1], $resultValue)
        ('{0}：{1}' -f $sections[2], $nextStepValue)
    )
}

if (-not (Test-Path $resolvedVersionPath)) {
    Stop-FriendlyPanelRender `
        -Summary '渲染口径缺少真源版本文件，当前没法继续。' `
        -Detail ("缺少文件：{0}" -f $resolvedVersionPath)
}

$versionInfo = Read-PanelResponseJsonFile -Path $resolvedVersionPath
$taskStartState = Read-PanelResponseJsonFile -Path $taskStartStatePath
$baseTokens = Get-PanelResponseBaseTokenMap -VersionInfo $versionInfo -ExplicitCxVersion $CxVersion
$sourceRootPath = Get-PanelResponseStateSourceRoot -TaskStartState $taskStartState -ScriptRootPath $scriptRootPath
$targetCodexHomePath = Get-PanelResponseStateTargetCodexHome -TaskStartState $taskStartState -ResolvedTargetCodexHome $resolvedTargetCodexHome
$needsLightCheck = -not (Test-PanelResponseTaskStartStateLightCheckSatisfied -TaskStartState $taskStartState -SourceRootPath $sourceRootPath -TargetCodexHomePath $targetCodexHomePath)

switch ($Kind) {
    'hint' {
        Write-Output (Get-PanelResponseHintLines -VersionInfo $versionInfo -BaseTokens $baseTokens)
    }
    'task-entry' {
        Write-Output (Get-PanelResponseTaskEntryLines -VersionInfo $versionInfo -BaseTokens $baseTokens -NeedsCheck $needsLightCheck)
    }
    'version' {
        Write-Output (Get-PanelResponseVersionLines -VersionInfo $versionInfo -BaseTokens $baseTokens)
    }
    'status' {
        Write-Output (Get-PanelResponseStatusLines -VersionInfo $versionInfo -TaskStartState $taskStartState -ScriptRootPath $scriptRootPath -ResolvedTargetCodexHome $resolvedTargetCodexHome -ResolvedRepoRootPath $resolvedRepoRootPath -BaseTokens $baseTokens -ExplicitLastCheck $LastCheck -ExplicitAutoRepair $AutoRepair -ExplicitKeyFileConsistency $KeyFileConsistency -ExplicitCurrentMode $CurrentMode -ExplicitCurrentTask $CurrentTask)
    }
    'upgrade' {
        Write-Output (Get-PanelResponseUpgradeLines -VersionInfo $versionInfo -BaseTokens $baseTokens)
    }
    'process-quote' {
        if ([string]::IsNullOrWhiteSpace($Phase)) {
            Stop-FriendlyPanelRender `
                -Summary '渲染最小过程提示时缺少阶段参数，当前没法继续。' `
                -Detail 'Kind=process-quote 时必须提供 Phase。'
        }

        Write-Output (Get-PanelResponseProcessQuoteText -VersionInfo $versionInfo -PhaseName $Phase)
    }
    'closeout' {
        Write-Output (Get-PanelResponseCloseoutLines -VersionInfo $versionInfo -ExplicitCompletedText $CompletedText -ExplicitResultText $ResultText -ExplicitNextStepText $NextStepText)
    }
}
