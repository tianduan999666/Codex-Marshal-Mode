param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'command')]
    [string]$CommandText,
    [Parameter(Mandatory = $true, ParameterSetName = 'hint')]
    [switch]$ShowHint,
    [Parameter(Mandatory = $true, ParameterSetName = 'task-preview')]
    [switch]$PreviewTaskEntry,
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$DryRunTaskStart
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..'
}
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$renderPanelResponseScriptPath = Join-Path $scriptRootPath 'render-panel-response.ps1'
$startPanelTaskScriptPath = Join-Path $scriptRootPath 'start-panel-task.ps1'
$syncTaskContextScriptPath = Join-Path $scriptRootPath 'sync-task-context.ps1'
$sourceVersionPath = Join-Path $scriptRootPath 'VERSION.json'
$runtimeVersionPath = Join-Path (Split-Path -Parent $scriptRootPath) 'cx-version.json'
$versionSourcePath = if (Test-Path $sourceVersionPath) { $sourceVersionPath } else { $runtimeVersionPath }

function Stop-FriendlyPanelEntry {
    param(
        [string]$Summary,
        [string]$LeadLine = '',
        [string]$NextStep = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($LeadLine)) {
        Write-Host $LeadLine
    }

    if ([string]::IsNullOrWhiteSpace($NextStep)) {
        Write-Host "[ERROR] $Summary" -ForegroundColor Red
        exit 1
    }

    Write-Host ("[ERROR] {0}" -f $Summary) -ForegroundColor Red
    Write-Host ("[INFO] 下一步：{0}" -f $NextStep) -ForegroundColor Cyan
    exit 1
}

function Write-PanelCommandLinesSafe {
    param(
        [hashtable]$Arguments,
        [string]$Summary,
        [string]$NextStep
    )

    $global:LASTEXITCODE = 0
    try {
        foreach ($outputLine in @(& $renderPanelResponseScriptPath @Arguments)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$outputLine)) {
                Write-Output $outputLine
            }
        }
    }
    catch {
        Stop-FriendlyPanelEntry `
            -Summary ("{0} 原始错误：{1}" -f $Summary, $_.Exception.Message.Trim()) `
            -NextStep $NextStep
    }

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Get-PanelSupportQuoteLine([string]$QuoteKey) {
    if ([string]::IsNullOrWhiteSpace($QuoteKey)) {
        return ''
    }

    $fallbackMap = @{
        missing_info = '此局可破，但还缺一份关键信报。'
        need_scope = '亮已看见主线，还需主公补一段范围。'
        need_decision = '此处有两路都能走，请主公拍板哪一路更重。'
        high_risk = '若强行动手，快是快，未必稳；请主公补一项关键前提。'
    }

    $global:LASTEXITCODE = 0
    try {
        $quoteLines = @(
            & $renderPanelResponseScriptPath `
                -Kind 'support-quote' `
                -QuoteKey $QuoteKey `
                -VersionPath $versionSourcePath `
                -RepoRootPath $resolvedRepoRootPath `
                -TargetCodexHome $resolvedTargetCodexHome
        )
    }
    catch {
        return $fallbackMap[$QuoteKey]
    }

    if ($LASTEXITCODE -ne 0) {
        return $fallbackMap[$QuoteKey]
    }

    $matchedLine = @(
        $quoteLines |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -First 1
    )
    if ($matchedLine.Count -gt 0) {
        return [string]$matchedLine[0]
    }

    return $fallbackMap[$QuoteKey]
}

function Get-PanelCommandPayload([string]$RawCommandText) {
    $trimmedCommandText = $RawCommandText.Trim()
    if ($trimmedCommandText -match '^传令[：:]\s*(.+?)\s*$') {
        return $matches[1].Trim()
    }

    Stop-FriendlyPanelEntry `
        -Summary '这句话还不是丞相的公开入口格式，所以当前没法直接接令。' `
        -NextStep '请直接输入 `传令：你的需求`，例如：`传令：修一下登录页`。'
}

function Get-ActiveTaskContext([string]$ResolvedRepoRootPath) {
    $activeTaskPath = Join-Path $ResolvedRepoRootPath '.codex\chancellor\active-task.txt'
    if (-not (Test-Path $activeTaskPath)) {
        return $null
    }

    $activeTaskId = ((Get-Content -Path $activeTaskPath | Select-Object -First 1) | ForEach-Object { $_.Trim() })
    if ([string]::IsNullOrWhiteSpace($activeTaskId)) {
        return $null
    }

    $activeTaskTitle = ''
    $taskContractPath = Join-Path $ResolvedRepoRootPath ('.codex\chancellor\tasks\{0}\contract.yaml' -f $activeTaskId)
    if (Test-Path $taskContractPath) {
        $taskContractContent = Get-Content -Raw -Path $taskContractPath
        if ($taskContractContent -match 'title:\s*(.+?)(?:\r?\n|$)') {
            $activeTaskTitle = $matches[1].Trim()
        }
    }

    return [pscustomobject]@{
        TaskId = $activeTaskId
        TaskTitle = $activeTaskTitle
    }
}

function Format-ActiveTaskDisplayText([object]$ActiveTaskContext) {
    if ($null -eq $ActiveTaskContext) {
        return ''
    }

    if ([string]::IsNullOrWhiteSpace([string]$ActiveTaskContext.TaskTitle)) {
        return [string]$ActiveTaskContext.TaskId
    }

    return ('{0}（{1}）' -f $ActiveTaskContext.TaskId, $ActiveTaskContext.TaskTitle)
}

function Write-ContinueActiveTaskLines {
    param(
        [object]$ActiveTaskContext
    )

    $currentTaskText = Format-ActiveTaskDisplayText -ActiveTaskContext $ActiveTaskContext
    Write-PanelCommandLinesSafe -Arguments @{
        Kind = 'task-entry'
        TaskEntryMode = 'unchecked'
        VersionPath = $versionSourcePath
        RepoRootPath = $resolvedRepoRootPath
        TargetCodexHome = $resolvedTargetCodexHome
    } -Summary '丞相已经接到继续当前任务的传令，但开工骨架渲染失败了。' -NextStep '先执行 `self-check.cmd` 检查渲染链路，再回面板重试。'
    Write-PanelCommandLinesSafe -Arguments @{
        Kind = 'status'
        VersionPath = $versionSourcePath
        RepoRootPath = $resolvedRepoRootPath
        TargetCodexHome = $resolvedTargetCodexHome
        CurrentTask = $currentTaskText
    } -Summary '丞相已经接到继续当前任务的传令，但状态栏渲染失败了。' -NextStep '先执行 `self-check.cmd` 检查渲染链路，再回面板重试。'
    Write-PanelCommandLinesSafe -Arguments @{
        Kind = 'closeout'
        VersionPath = $versionSourcePath
        CompletedText = '已接上当前激活任务。'
        ResultText = ('继续沿用 {0}，不新建任务。' -f $currentTaskText)
        NextStepText = '留在当前会话，直接基于当前任务继续推进。'
    } -Summary '丞相已经接上当前任务，但收口文案渲染失败了。' -NextStep '先执行 `self-check.cmd` 检查渲染链路，再回面板重试。'
}

function Invoke-PanelTaskStart {
    param(
        [string]$TaskTitle
    )

    $global:LASTEXITCODE = 0
    try {
        & $startPanelTaskScriptPath -Title $TaskTitle -RepoRootPath $resolvedRepoRootPath -TargetCodexHome $resolvedTargetCodexHome
    }
    catch {
        Stop-FriendlyPanelEntry `
            -Summary ("丞相已接到任务，但开工入口自己报错了。原始错误：{0}" -f $_.Exception.Message.Trim()) `
            -NextStep '先执行 `self-check.cmd` 看入口链路是否完整，确认后再回面板重试。'
    }

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Invoke-TaskContextStep {
    param(
        [ValidateSet('snapshot', 'write', 'read')]
        [string]$Mode
    )

    $global:LASTEXITCODE = 0
    try {
        return @(
            & $syncTaskContextScriptPath `
                -Mode $Mode `
                -RepoRootPath $resolvedRepoRootPath `
                -TargetCodexHome $resolvedTargetCodexHome
        )
    }
    catch {
        $messageByMode = @{
            snapshot = '当前任务存在，但任务级进度快照刷新失败了。'
            write = '丞相已经接到交班传令，但交班材料落盘失败了。'
            read = '丞相已经接到接班传令，但读取交班材料失败了。'
        }
        Stop-FriendlyPanelEntry `
            -Summary ("{0} 原始错误：{1}" -f $messageByMode[$Mode], $_.Exception.Message.Trim()) `
            -NextStep '先核对当前任务包 5 件套是否完整，再重试当前传令。'
    }

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    return @()
}

function Write-TaskContextCommandLines {
    param(
        [ValidateSet('write', 'read')]
        [string]$Mode
    )

    Write-PanelCommandLinesSafe -Arguments @{
        Kind = 'task-entry'
        TaskEntryMode = 'unchecked'
        VersionPath = $versionSourcePath
        RepoRootPath = $resolvedRepoRootPath
        TargetCodexHome = $resolvedTargetCodexHome
    } -Summary '丞相已经接到传令，但开工骨架渲染失败了。' -NextStep '先执行 `self-check.cmd` 检查渲染链路，再回面板重试。'

    foreach ($line in @(Invoke-TaskContextStep -Mode $Mode)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-Output $line
        }
    }
}

foreach ($requiredPath in @($renderPanelResponseScriptPath, $startPanelTaskScriptPath, $syncTaskContextScriptPath, $versionSourcePath)) {
    if (-not (Test-Path $requiredPath)) {
        Stop-FriendlyPanelEntry `
            -Summary '丞相入口缺少必要脚本，当前没法正常接令。' `
            -NextStep '先执行 `install.cmd` 或 `self-check.cmd` 修复入口文件，再回面板重试。'
    }
}

switch ($PSCmdlet.ParameterSetName) {
    'hint' {
        Write-PanelCommandLinesSafe -Arguments @{
            Kind = 'hint'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        } -Summary '丞相入口已经接通，但示例提示渲染失败了。' -NextStep '先执行 `self-check.cmd` 看入口文件是否完整，再回面板重试。'
        exit 0
    }
    'task-preview' {
        Write-PanelCommandLinesSafe -Arguments @{
            Kind = 'task-entry'
            TaskEntryMode = 'unchecked'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        } -Summary '丞相入口已经接通，但开工骨架预览失败了。' -NextStep '先执行 `self-check.cmd` 检查渲染链路，再回面板重试。'
        exit 0
    }
}

$commandPayload = Get-PanelCommandPayload -RawCommandText $CommandText
$activeTaskContext = Get-ActiveTaskContext -ResolvedRepoRootPath $resolvedRepoRootPath

switch ($commandPayload) {
    '状态' {
        Write-PanelCommandLinesSafe -Arguments @{
            Kind = 'status'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        } -Summary '丞相入口已经接通，但状态栏渲染失败了。' -NextStep '先执行 `self-check.cmd` 检查渲染链路，再回面板重试。'
        break
    }
    '版本' {
        Write-PanelCommandLinesSafe -Arguments @{
            Kind = 'version'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        } -Summary '丞相入口已经接通，但版本口径渲染失败了。' -NextStep '先执行 `self-check.cmd` 检查入口文件，再回面板重试。'
        break
    }
    '升级' {
        Write-PanelCommandLinesSafe -Arguments @{
            Kind = 'upgrade'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        } -Summary '丞相入口已经接通，但升级说明渲染失败了。' -NextStep '先执行 `self-check.cmd` 检查渲染链路，再回面板重试。'
        break
    }
    { $_ -in @('继续', '继续当前任务') } {
        if ($null -eq $activeTaskContext) {
            Stop-FriendlyPanelEntry `
                -LeadLine (Get-PanelSupportQuoteLine -QuoteKey 'need_scope') `
                -Summary '当前没有激活任务，不能直接继续。' `
                -NextStep '请直接输入 `传令：你的需求`，例如：`传令：修一下登录页`。'
        }

        if ($DryRunTaskStart) {
            Write-Output '路由结果：continue-active-task'
            Write-Output ('当前任务：{0}' -f (Format-ActiveTaskDisplayText -ActiveTaskContext $activeTaskContext))
            break
        }

        Invoke-TaskContextStep -Mode 'snapshot' | Out-Null

        Write-ContinueActiveTaskLines -ActiveTaskContext $activeTaskContext
        break
    }
    '交班' {
        if ($null -eq $activeTaskContext) {
            Stop-FriendlyPanelEntry `
                -LeadLine (Get-PanelSupportQuoteLine -QuoteKey 'need_scope') `
                -Summary '当前没有激活任务，不能直接交班。' `
                -NextStep '请先输入 `传令：你的需求` 建立任务，或用 `传令：继续当前任务` 接上现有任务。'
        }

        Write-TaskContextCommandLines -Mode 'write'
        break
    }
    '接班' {
        if ($null -eq $activeTaskContext) {
            Stop-FriendlyPanelEntry `
                -LeadLine (Get-PanelSupportQuoteLine -QuoteKey 'need_scope') `
                -Summary '当前没有激活任务，不能直接接班。' `
                -NextStep '请先输入 `传令：你的需求` 建立任务，或用 `传令：继续当前任务` 接上现有任务。'
        }

        Write-TaskContextCommandLines -Mode 'read'
        break
    }
    default {
        if ($DryRunTaskStart) {
            Write-Output '路由结果：task-start'
            Write-Output ('任务标题：{0}' -f $commandPayload)
            break
        }

        Invoke-PanelTaskStart -TaskTitle $commandPayload
        break
    }
}
