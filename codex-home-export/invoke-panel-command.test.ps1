param()

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$invokeScriptPath = Join-Path $scriptRootPath 'invoke-panel-command.ps1'
$versionPath = Join-Path $scriptRootPath 'VERSION.json'
$versionInfo = Get-Content -Raw -Encoding UTF8 -Path $versionPath | ConvertFrom-Json

function Assert-PanelCommandEqual([string]$Actual, [string]$Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw ('{0}；期望：{1}；实际：{2}' -f $Message, $Expected, $Actual)
    }
}

function Assert-PanelCommandLineCount([string[]]$ActualLines, [int]$ExpectedCount, [string]$Message) {
    if (@($ActualLines).Count -ne $ExpectedCount) {
        throw ('{0}；期望行数：{1}；实际行数：{2}' -f $Message, $ExpectedCount, @($ActualLines).Count)
    }
}

if (-not (Test-Path $invokeScriptPath)) {
    throw "缺少入口路由脚本：$invokeScriptPath"
}

$hintLines = @(& $invokeScriptPath -ShowHint)
Assert-PanelCommandLineCount -ActualLines $hintLines -ExpectedCount 1 -Message 'ShowHint 应返回 1 行'
Assert-PanelCommandEqual -Actual $hintLines[0] -Expected $versionInfo.new_chat_hint -Message 'ShowHint 应返回真源示例句'

$taskPreviewLines = @(& $invokeScriptPath -PreviewTaskEntry)
Assert-PanelCommandLineCount -ActualLines $taskPreviewLines -ExpectedCount 3 -Message 'PreviewTaskEntry 应返回 3 行'
Assert-PanelCommandEqual -Actual $taskPreviewLines[0] -Expected $versionInfo.opening_line -Message 'PreviewTaskEntry 第 1 行应返回开场白'
Assert-PanelCommandEqual -Actual $taskPreviewLines[2] -Expected $versionInfo.process_quotes_minimal.task_entry -Message 'PreviewTaskEntry 第 3 行应返回接令句'

$statusLines = @(& $invokeScriptPath '传令：状态')
Assert-PanelCommandLineCount -ActualLines $statusLines -ExpectedCount 6 -Message '传令：状态 应返回 6 行'
Assert-PanelCommandEqual -Actual $statusLines[0] -Expected ('版本：{0}' -f $versionInfo.cx_version) -Message '传令：状态 第 1 行应返回版本'

$versionLines = @(& $invokeScriptPath '传令：版本')
Assert-PanelCommandLineCount -ActualLines $versionLines -ExpectedCount 3 -Message '传令：版本 应返回 3 行'
Assert-PanelCommandEqual -Actual $versionLines[0] -Expected ('版本号：{0}' -f $versionInfo.cx_version) -Message '传令：版本 第 1 行应返回版本号'

$upgradeLines = @(& $invokeScriptPath '传令：升级')
Assert-PanelCommandLineCount -ActualLines $upgradeLines -ExpectedCount 3 -Message '传令：升级 应返回 3 行'
Assert-PanelCommandEqual -Actual $upgradeLines[2] -Expected '默认策略：未收到明确升级传令时，不自动升级' -Message '传令：升级 第 3 行应返回默认策略'

$taskPreviewLines = @(& $invokeScriptPath '传令：修一下登录页' -DryRunTaskStart)
Assert-PanelCommandLineCount -ActualLines $taskPreviewLines -ExpectedCount 2 -Message 'DryRunTaskStart 应返回 2 行'
Assert-PanelCommandEqual -Actual $taskPreviewLines[0] -Expected '路由结果：task-start' -Message 'DryRunTaskStart 应返回 task-start 路由结果'
Assert-PanelCommandEqual -Actual $taskPreviewLines[1] -Expected '任务标题：修一下登录页' -Message 'DryRunTaskStart 应返回任务标题'

Write-Host 'PASS: invoke-panel-command.test.ps1'
