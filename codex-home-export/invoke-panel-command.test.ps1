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

$previewHomePath = Join-Path $env:TEMP ('cx-preview-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $previewHomePath 'config\chancellor-mode') | Out-Null

    $taskPreviewLines = @(& $invokeScriptPath -PreviewTaskEntry -TargetCodexHome $previewHomePath)
    Assert-PanelCommandLineCount -ActualLines $taskPreviewLines -ExpectedCount 2 -Message 'PreviewTaskEntry 在预览模式下应返回 2 行'
    Assert-PanelCommandEqual -Actual $taskPreviewLines[0] -Expected $versionInfo.opening_line -Message 'PreviewTaskEntry 第 1 行应返回开场白'
    Assert-PanelCommandEqual -Actual $taskPreviewLines[1] -Expected $versionInfo.process_quotes_minimal.task_entry -Message 'PreviewTaskEntry 第 2 行应返回接令句'
}
finally {
    if (Test-Path $previewHomePath) {
        Remove-Item -Recurse -Force -LiteralPath $previewHomePath
    }
}

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

$continueTestRoot = Join-Path $env:TEMP ('cx-continue-' + [guid]::NewGuid().ToString('N'))
try {
    $continueTaskId = 'v4-target-999-continue-smoke'
    $continueTaskRoot = Join-Path $continueTestRoot ('.codex\chancellor\tasks\' + $continueTaskId)
    $continueTaskContractPath = Join-Path $continueTaskRoot 'contract.yaml'
    $continueActiveTaskPath = Join-Path $continueTestRoot '.codex\chancellor\active-task.txt'
    $continueHomePath = Join-Path $continueTestRoot 'home'

    foreach ($path in @($continueTaskRoot, $continueHomePath)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }

    Set-Content -Path $continueActiveTaskPath -Value $continueTaskId -Encoding UTF8
    Set-Content -Path $continueTaskContractPath -Value @(
        ('task_id: {0}' -f $continueTaskId)
        'title: 继续修入口'
    ) -Encoding UTF8

    $continueDryRunLines = @(& $invokeScriptPath '传令：继续' -DryRunTaskStart -RepoRootPath $continueTestRoot)
    Assert-PanelCommandLineCount -ActualLines $continueDryRunLines -ExpectedCount 2 -Message '传令：继续 DryRunTaskStart 应返回 2 行'
    Assert-PanelCommandEqual -Actual $continueDryRunLines[0] -Expected '路由结果：continue-active-task' -Message '传令：继续 DryRunTaskStart 应走 continue-active-task'
    Assert-PanelCommandEqual -Actual $continueDryRunLines[1] -Expected ('当前任务：{0}（继续修入口）' -f $continueTaskId) -Message '传令：继续 DryRunTaskStart 应返回当前激活任务'

    $continueLines = @(& $invokeScriptPath '传令：继续当前任务' -RepoRootPath $continueTestRoot -TargetCodexHome $continueHomePath)
    Assert-PanelCommandLineCount -ActualLines $continueLines -ExpectedCount 12 -Message '传令：继续当前任务 应返回骨架 + 状态 + 收口'
    Assert-PanelCommandEqual -Actual $continueLines[0] -Expected $versionInfo.opening_line -Message '传令：继续当前任务 第 1 行应返回开场白'
    Assert-PanelCommandEqual -Actual $continueLines[7] -Expected ('当前任务：{0}（继续修入口）' -f $continueTaskId) -Message '传令：继续当前任务 状态栏应返回激活任务'
    Assert-PanelCommandEqual -Actual $continueLines[10] -Expected ('结果：继续沿用 {0}（继续修入口），不新建任务。' -f $continueTaskId) -Message '传令：继续当前任务 应明确不新建任务'
}
finally {
    if (Test-Path $continueTestRoot) {
        Remove-Item -Recurse -Force -LiteralPath $continueTestRoot
    }
}

Write-Host 'PASS: invoke-panel-command.test.ps1'
