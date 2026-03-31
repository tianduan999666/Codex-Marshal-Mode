$ErrorActionPreference = 'Stop'

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRootPath = Split-Path -Parent (Split-Path -Parent $scriptRootPath)
$auditScriptPath = Join-Path $scriptRootPath 'audit-local-task-status.ps1'
$reviewScriptPath = Join-Path $scriptRootPath 'review-panel-acceptance-closeout.ps1'
$testRunId = Get-Date -Format 'yyyyMMdd-HHmmss'
$testRootPath = Join-Path (Join-Path $repoRootPath 'temp/generated') ("panel-acceptance-closeout-review-test-$testRunId")
$tasksRootPath = Join-Path $testRootPath 'tasks'
$activeTaskFilePath = Join-Path $testRootPath 'active-task.txt'
$auditReferenceTimeText = '2026-03-31 21:00:00'

function Write-Utf8NoBomFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parentPath = Split-Path -Parent $Path
    if ($parentPath) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw ("{0}：期望 {1}，实际 {2}" -f $Message, $Expected, $Actual)
    }
}

function Assert-Contains {
    param(
        [string]$Content,
        [string]$ExpectedText,
        [string]$Message
    )

    if (-not $Content.Contains($ExpectedText)) {
        throw ("{0}：未找到 {1}" -f $Message, $ExpectedText)
    }
}

Write-Utf8NoBomFile -Path $activeTaskFilePath -Content "v4-trial-035-panel-acceptance-closeout`n"

$taskStateMap = @{
    'v4-trial-017-gate-package-smoke' = @'
task_id: v4-trial-017-gate-package-smoke
status: running
risk_level: low
next_action: 按允许调整方案继续推进目录调整评估
blocked_by: []
updated_at: '2026-03-29 03:25:53'
phase_hint: gate_package
'@
    'v4-trial-019-exception-path-smoke' = @'
task_id: v4-trial-019-exception-path-smoke
status: ready_to_resume
risk_level: low
next_action: 整理失败原因并准备下一轮恢复
blocked_by: []
updated_at: '2026-03-29 03:46:47'
phase_hint: exception_path
'@
    'v4-trial-034-public-rule-order-gate' = @'
task_id: v4-trial-034-public-rule-order-gate
status: completed
risk_level: low
next_action: 等待下一刀，继续把更多公开口径一致性下沉到自动门禁
blocked_by: []
updated_at: '2026-03-29 15:00:55'
phase_hint: governance_gate_hardening
'@
    'v4-trial-035-panel-acceptance-closeout' = @'
task_id: v4-trial-035-panel-acceptance-closeout
status: waiting_assist
risk_level: low
next_action: 主公进入官方 Codex 面板执行真实人工验板，并补齐结果稿后做结果复核。
blocked_by: [主公在官方面板执行人工验板]
updated_at: '2026-03-31 20:26:59'
phase_hint: panel_acceptance_closeout
'@
}

foreach ($taskId in $taskStateMap.Keys) {
    $stateFilePath = Join-Path (Join-Path $tasksRootPath $taskId) 'state.yaml'
    Write-Utf8NoBomFile -Path $stateFilePath -Content $taskStateMap[$taskId]
}

$passResultPath = Join-Path $testRootPath 'panel-acceptance-result-pass.md'
$failResultPath = Join-Path $testRootPath 'panel-acceptance-result-fail.md'

$passResultContent = @'
# 面板人工验板结果模板

## 基本信息

- 时间：2026-03-31 20:09:35
- 执行人：主公
- 面板入口：官方 `Codex` 面板
- 自动验板结果：`verify-cutover.ps1` 已通过

## 命令结果

### `丞相版本`

- 是否正常响应：是
- 版本号是否正确：是
- 版本来源是否正确：是
- 真源路径是否正确：是
- 备注：

### `丞相检查`

- 是否正常响应：是
- 检查范围是否清楚：是
- 检查结论是否人话清楚：是
- 建议动作是否清楚：是
- 备注：

### `丞相状态`（如有执行）

- 是否正常响应：未执行
- 当前模式是否清楚：未执行
- 稳态判断是否清楚：未执行
- 下一步是否清楚：未执行
- 备注：

## 最终判定

- 人工验板最终结果：通过
- 是否需要回退：否
- 是否需要补刀：否
- 若不通过，最小缺口是：
- 下一步：进入真实任务使用
'@
Write-Utf8NoBomFile -Path $passResultPath -Content $passResultContent
Write-Utf8NoBomFile -Path $failResultPath -Content ($passResultContent.Replace('人工验板最终结果：通过','人工验板最终结果：不通过').Replace('是否需要回退：否','是否需要回退：是').Replace('是否需要补刀：否','是否需要补刀：是').Replace('若不通过，最小缺口是：','若不通过，最小缺口是：面板回复中仍有一处口径不稳').Replace('下一步：进入真实任务使用','下一步：先补口径，再重新打开官方面板复验'))

$auditSummary = & $auditScriptPath -AsJson -TasksRootPath $tasksRootPath -ActiveTaskFilePath $activeTaskFilePath -AuditReferenceTimeText $auditReferenceTimeText | ConvertFrom-Json
Assert-Equal -Actual ([int]$auditSummary.TaskCount) -Expected 4 -Message '任务总数校验失败'
Assert-Equal -Actual ([int]$auditSummary.StaleTasks.Count) -Expected 3 -Message '陈旧任务数校验失败'
Assert-Equal -Actual ([int]$auditSummary.RulerDecisionTasks.Count) -Expected 2 -Message '主公拍板项数校验失败'

$passOutput = (& $reviewScriptPath -ResultPath $passResultPath -TasksRootPath $tasksRootPath -ActiveTaskFilePath $activeTaskFilePath -AuditReferenceTimeText $auditReferenceTimeText *>&1 | Out-String)
Assert-Contains -Content $passOutput -ExpectedText '人工验板真实阻塞已解除，可进入维护层统一收口阶段。' -Message '通过态收口提示校验失败'
Assert-Contains -Content $passOutput -ExpectedText '建议主公拍板项数：1' -Message '通过态主公拍板计数校验失败'
Assert-Contains -Content $passOutput -ExpectedText 'v4-trial-034-public-rule-order-gate' -Message '通过态应保留 034 拍板项'

$failOutput = (& $reviewScriptPath -ResultPath $failResultPath -TasksRootPath $tasksRootPath -ActiveTaskFilePath $activeTaskFilePath -AuditReferenceTimeText $auditReferenceTimeText *>&1 | Out-String)
Assert-Contains -Content $failOutput -ExpectedText '人工验板尚未通过，当前不能按通过态收口。' -Message '不通过态收口提示校验失败'
Assert-Contains -Content $failOutput -ExpectedText '建议主公拍板项数：2' -Message '不通过态主公拍板计数校验失败'
Assert-Contains -Content $failOutput -ExpectedText 'v4-trial-035-panel-acceptance-closeout' -Message '不通过态应保留 035 拍板项'

Write-Host 'PASS: test-panel-acceptance-closeout-review.ps1' -ForegroundColor Green
