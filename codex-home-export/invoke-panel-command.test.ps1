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

function Assert-PanelCommandExitCode([int]$Actual, [int]$Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw ('{0}；期望退出码：{1}；实际退出码：{2}' -f $Message, $Expected, $Actual)
    }
}

function Write-TestUtf8BomFile([string]$Path, [string]$Content) {
    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8Bom)
}

function Invoke-PanelCommandExternal([hashtable]$Arguments) {
    return Invoke-PanelCommandExternalAtPath -ScriptPath $invokeScriptPath -Arguments $Arguments
}

function Invoke-PanelCommandExternalAtPath([string]$ScriptPath, [hashtable]$Arguments) {
    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $invokeScriptPath)
    if (-not [string]::IsNullOrWhiteSpace($ScriptPath)) {
        $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    }
    foreach ($key in $Arguments.Keys) {
        $argumentList += ('-{0}' -f $key)
        $argumentList += [string]$Arguments[$key]
    }

    $lines = @(& powershell.exe @argumentList *>&1 | ForEach-Object { [string]$_ })
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Lines = $lines
        Text = ($lines -join "`n")
    }
}

function New-InvokePanelFailureWorkspace {
    param(
        [string]$RootPath
    )

    $sourceRootPath = Join-Path $RootPath 'source'
    $repoRootPath = Join-Path $RootPath 'repo'
    $homePath = Join-Path $RootPath 'home'

    foreach ($path in @($sourceRootPath, $repoRootPath, (Join-Path $homePath 'config\chancellor-mode'))) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }

    Copy-Item -Path $invokeScriptPath -Destination (Join-Path $sourceRootPath 'invoke-panel-command.ps1') -Force
    Copy-Item -Path $versionPath -Destination (Join-Path $sourceRootPath 'VERSION.json') -Force

    Write-TestUtf8BomFile -Path (Join-Path $sourceRootPath 'render-panel-response.ps1') -Content @'
param(
    [string]$Kind = '',
    [string]$TaskEntryMode = 'unchecked',
    [string]$CurrentTask = '',
    [string]$CompletedText = '',
    [string]$ResultText = '',
    [string]$NextStepText = ''
)

switch ($Kind) {
    'task-entry' {
        Write-Output '🪶 军令入帐。亮，即刻接管全局。'
        Write-Output '军令已明，亮先接手。'
    }
    'status' {
        Write-Output '版本：VX'
        Write-Output '上次检查：LC'
        Write-Output '自动修复：AR'
        Write-Output '关键文件一致性：KC'
        Write-Output '当前模式：CM'
        Write-Output ('当前任务：{0}' -f $CurrentTask)
    }
    'closeout' {
        Write-Output '此事已交卷，现呈结果。'
        Write-Output ('已完成：{0}' -f $CompletedText)
        Write-Output ('结果：{0}' -f $ResultText)
        Write-Output ('下一步：{0}' -f $NextStepText)
    }
    'support-quote' {
        Write-Output '亮已看见主线，还需主公补一段范围。'
    }
}
exit 0
'@
    Write-TestUtf8BomFile -Path (Join-Path $sourceRootPath 'start-panel-task.ps1') -Content "param(); Write-Output 'STUB: start ok'; exit 0"
    Write-TestUtf8BomFile -Path (Join-Path $sourceRootPath 'sync-task-context.ps1') -Content "param(); Write-Output 'STUB: sync ok'; exit 0"

    return [pscustomobject]@{
        SourceRootPath = $sourceRootPath
        RepoRootPath = $repoRootPath
        HomePath = $homePath
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

$missingTaskRoot = Join-Path $env:TEMP ('cx-missing-task-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $missingTaskRoot | Out-Null
    $missingTaskResult = Invoke-PanelCommandExternal -Arguments @{
        CommandText = '传令：继续'
        RepoRootPath = $missingTaskRoot
    }
    Assert-PanelCommandEqual -Actual ([string]$missingTaskResult.ExitCode) -Expected '1' -Message '无激活任务时传令：继续 应返回失败退出码'
    if ($missingTaskResult.Text -notlike '*亮已看见主线，还需主公补一段范围。*') {
        throw ('无激活任务时传令：继续 应先给出丞相补范围提示；实际：{0}' -f $missingTaskResult.Text)
    }
    if ($missingTaskResult.Text -notlike '*当前没有激活任务，不能直接继续。*') {
        throw ('无激活任务时传令：继续 应说明当前没有激活任务；实际：{0}' -f $missingTaskResult.Text)
    }
}
finally {
    if (Test-Path $missingTaskRoot) {
        Remove-Item -Recurse -Force -LiteralPath $missingTaskRoot
    }
}

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
    Set-Content -Path (Join-Path $continueTaskRoot 'state.yaml') -Value @(
        ('task_id: {0}' -f $continueTaskId)
        'status: running'
        'risk_level: low'
        'next_action: 继续补入口主链'
        'blocked_by: []'
        "updated_at: '2026-04-05 18:40:00'"
        'phase_hint: continue'
        'plan_step: 先读当前任务，再续做'
        'verify_signal: 继续命令不新建任务'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $continueTaskRoot 'decision-log.md') -Value @(
        '# 决策记录'
        ''
        '## 2026-04-05 18:41:00'
        ''
        '- 决策：继续沿用当前任务'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $continueTaskRoot 'result.md') -Value @(
        '# 结果摘要'
        ''
        '## 已完成'
        ''
        '- 已建立继续任务入口'
        ''
        '## 验证证据'
        ''
        '- 任务包存在'
        ''
        '## 遗留事项'
        ''
        '- 尚未刷新任务快照'
        ''
        '## 下一步建议'
        ''
        '- 直接继续当前任务'
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
    if (-not (Test-Path (Join-Path $continueTaskRoot 'progress-snapshot.md'))) {
        throw "传令：继续当前任务 后未刷新任务快照：$(Join-Path $continueTaskRoot 'progress-snapshot.md')"
    }
}
finally {
    if (Test-Path $continueTestRoot) {
        Remove-Item -Recurse -Force -LiteralPath $continueTestRoot
    }
}

$handoffTestRoot = Join-Path $env:TEMP ('cx-handoff-' + [guid]::NewGuid().ToString('N'))
try {
    $handoffTaskId = 'v4-target-998-panel-handoff'
    $handoffTaskRoot = Join-Path $handoffTestRoot ('.codex\chancellor\tasks\' + $handoffTaskId)
    $handoffActiveTaskPath = Join-Path $handoffTestRoot '.codex\chancellor\active-task.txt'
    $handoffHomePath = Join-Path $handoffTestRoot 'home'

    foreach ($path in @($handoffTaskRoot, (Join-Path $handoffHomePath 'config\chancellor-mode'))) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }

    Set-Content -Path $handoffActiveTaskPath -Value $handoffTaskId -Encoding UTF8
    Set-Content -Path (Join-Path $handoffTaskRoot 'contract.yaml') -Value @(
        ('task_id: {0}' -f $handoffTaskId)
        'title: 接上跨聊天连续性'
        'goal: >-'
        '  让交班与接班链路直接可用。'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $handoffTaskRoot 'state.yaml') -Value @(
        ('task_id: {0}' -f $handoffTaskId)
        'status: ready_to_resume'
        'risk_level: low'
        'next_action: 先读取 handoff.md 再继续'
        'blocked_by: []'
        "updated_at: '2026-04-05 18:48:00'"
        'phase_hint: handoff'
        'plan_step: 先补交班，再验证接班'
        'verify_signal: 新聊天只输入传令：接班也能续上'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $handoffTaskRoot 'decision-log.md') -Value @(
        '# 决策记录'
        ''
        '## 2026-04-05 18:49:00'
        ''
        '- 决策：把交班材料落在当前任务目录'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $handoffTaskRoot 'gates.yaml') -Value @(
        ('task_id: {0}' -f $handoffTaskId)
        'items: []'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $handoffTaskRoot 'result.md') -Value @(
        '# 结果摘要'
        ''
        '## 已完成'
        ''
        '- 已明确交班文件落点'
        ''
        '## 验证证据'
        ''
        '- 任务包完整'
        ''
        '## 遗留事项'
        ''
        '- 还未补入口路由'
        ''
        '## 下一步建议'
        ''
        '- 先接通公开命令'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $handoffHomePath 'config\cx-version.json') -Value @'
{
  "cx_version": "CX-TEST-HANDOFF"
}
'@ -Encoding UTF8
    Set-Content -Path (Join-Path $handoffHomePath 'config\chancellor-mode\task-start-state.json') -Value @'
{
  "verified_at": "2026-04-05 18:50:00",
  "verify_status": "passed",
  "repair_used": false
}
'@ -Encoding UTF8

    $handoffLines = @(& $invokeScriptPath '传令：交班' -RepoRootPath $handoffTestRoot -TargetCodexHome $handoffHomePath)
    Assert-PanelCommandEqual -Actual $handoffLines[0] -Expected $versionInfo.opening_line -Message '传令：交班 第 1 行应返回开场白'
    Assert-PanelCommandEqual -Actual $handoffLines[2] -Expected '已完成：已为当前任务生成交班材料。' -Message '传令：交班 应明确已生成交班材料'
    Assert-PanelCommandEqual -Actual $handoffLines[3] -Expected ('任务编号：{0}（接上跨聊天连续性）' -f $handoffTaskId) -Message '传令：交班 应返回当前任务'
    Assert-PanelCommandEqual -Actual $handoffLines[7] -Expected '下一步：新聊天只需输入 `传令：接班`。' -Message '传令：交班 应提示新聊天直接接班'

    $handoffSnapshotPath = Join-Path $handoffTaskRoot 'progress-snapshot.md'
    $handoffFilePath = Join-Path $handoffTaskRoot 'handoff.md'
    if (-not (Test-Path $handoffSnapshotPath)) {
        throw "传令：交班 后未生成任务快照：$handoffSnapshotPath"
    }
    if (-not (Test-Path $handoffFilePath)) {
        throw "传令：交班 后未生成交班文件：$handoffFilePath"
    }

    $resumeLines = @(& $invokeScriptPath '传令：接班' -RepoRootPath $handoffTestRoot -TargetCodexHome $handoffHomePath)
    Assert-PanelCommandEqual -Actual $resumeLines[0] -Expected $versionInfo.opening_line -Message '传令：接班 第 1 行应返回开场白'
    Assert-PanelCommandEqual -Actual $resumeLines[2] -Expected ('当前任务：{0}（接上跨聊天连续性）' -f $handoffTaskId) -Message '传令：接班 应返回当前任务'
    Assert-PanelCommandEqual -Actual $resumeLines[7] -Expected '下一步：先读取 handoff.md 再继续' -Message '传令：接班 应返回下一步'
}
finally {
    if (Test-Path $handoffTestRoot) {
        Remove-Item -Recurse -Force -LiteralPath $handoffTestRoot
    }
}

$taskFailureRoot = Join-Path $env:TEMP ('cx-task-failure-' + [guid]::NewGuid().ToString('N'))
try {
    $taskFailureWorkspace = New-InvokePanelFailureWorkspace -RootPath $taskFailureRoot
    Write-TestUtf8BomFile -Path (Join-Path $taskFailureWorkspace.SourceRootPath 'start-panel-task.ps1') -Content @'
param()
Write-Output 'STUB: task-start failed detail'
exit 1
'@

    $taskFailureResult = Invoke-PanelCommandExternalAtPath -ScriptPath (Join-Path $taskFailureWorkspace.SourceRootPath 'invoke-panel-command.ps1') -Arguments @{
        CommandText = '传令：修一下登录页'
        RepoRootPath = $taskFailureWorkspace.RepoRootPath
        TargetCodexHome = $taskFailureWorkspace.HomePath
    }

    Assert-PanelCommandExitCode -Actual $taskFailureResult.ExitCode -Expected 1 -Message '任务开工子脚本失败时入口应停止'
    if ($taskFailureResult.Text -notlike '*丞相已接到任务，但真正开工这一步没走完。*') {
        throw ('任务开工子脚本失败时应返回人话总结；实际：{0}' -f $taskFailureResult.Text)
    }
    if ($taskFailureResult.Text -notlike '*STUB: task-start failed detail*') {
        throw ('任务开工子脚本失败时应保留子脚本明细；实际：{0}' -f $taskFailureResult.Text)
    }
    if ($taskFailureResult.Text -notlike '*self-check.cmd*') {
        throw ('任务开工子脚本失败时应提示后续动作；实际：{0}' -f $taskFailureResult.Text)
    }
}
finally {
    if (Test-Path $taskFailureRoot) {
        Remove-Item -Recurse -Force -LiteralPath $taskFailureRoot
    }
}

$handoffFailureRoot = Join-Path $env:TEMP ('cx-handoff-failure-' + [guid]::NewGuid().ToString('N'))
try {
    $handoffFailureWorkspace = New-InvokePanelFailureWorkspace -RootPath $handoffFailureRoot
    $handoffTaskId = 'v4-target-996-handoff-failure'
    $handoffTaskRoot = Join-Path $handoffFailureWorkspace.RepoRootPath ('.codex\chancellor\tasks\' + $handoffTaskId)
    New-Item -ItemType Directory -Force -Path $handoffTaskRoot | Out-Null
    Set-Content -Path (Join-Path $handoffFailureWorkspace.RepoRootPath '.codex\chancellor\active-task.txt') -Value $handoffTaskId -Encoding UTF8
    Set-Content -Path (Join-Path $handoffTaskRoot 'contract.yaml') -Value @(
        ('task_id: {0}' -f $handoffTaskId)
        'title: 交班失败分流'
    ) -Encoding UTF8

    Write-TestUtf8BomFile -Path (Join-Path $handoffFailureWorkspace.SourceRootPath 'sync-task-context.ps1') -Content @'
param(
    [string]$Mode = ''
)
Write-Output ("STUB: sync failed mode={0}" -f $Mode)
exit 1
'@

    $handoffFailureResult = Invoke-PanelCommandExternalAtPath -ScriptPath (Join-Path $handoffFailureWorkspace.SourceRootPath 'invoke-panel-command.ps1') -Arguments @{
        CommandText = '传令：交班'
        RepoRootPath = $handoffFailureWorkspace.RepoRootPath
        TargetCodexHome = $handoffFailureWorkspace.HomePath
    }

    Assert-PanelCommandExitCode -Actual $handoffFailureResult.ExitCode -Expected 1 -Message '交班子脚本失败时入口应停止'
    if ($handoffFailureResult.Text -notlike '*🪶 军令入帐。亮，即刻接管全局。*') {
        throw ('交班子脚本失败时仍应先输出开工骨架；实际：{0}' -f $handoffFailureResult.Text)
    }
    if ($handoffFailureResult.Text -notlike '*丞相已经接到交班传令，但交班材料落盘失败了。*') {
        throw ('交班子脚本失败时应返回人话总结；实际：{0}' -f $handoffFailureResult.Text)
    }
    if ($handoffFailureResult.Text -notlike '*STUB: sync failed mode=write*') {
        throw ('交班子脚本失败时应保留子脚本明细；实际：{0}' -f $handoffFailureResult.Text)
    }
    if ($handoffFailureResult.Text -notlike '*任务包 5 件套*') {
        throw ('交班子脚本失败时应提示核对任务包；实际：{0}' -f $handoffFailureResult.Text)
    }
}
finally {
    if (Test-Path $handoffFailureRoot) {
        Remove-Item -Recurse -Force -LiteralPath $handoffFailureRoot
    }
}

Write-Host 'PASS: invoke-panel-command.test.ps1'
