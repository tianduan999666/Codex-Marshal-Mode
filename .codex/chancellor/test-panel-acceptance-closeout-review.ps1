$ErrorActionPreference = 'Stop'

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRootPath = Split-Path -Parent (Split-Path -Parent $scriptRootPath)
$auditScriptPath = Join-Path $scriptRootPath 'audit-local-task-status.ps1'
$reviewScriptPath = Join-Path $scriptRootPath 'review-panel-acceptance-closeout.ps1'
$resolveScriptPath = Join-Path $scriptRootPath 'resolve-panel-acceptance-closeout.ps1'
$finalizeScriptPath = Join-Path $scriptRootPath 'finalize-panel-acceptance-closeout.ps1'
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

function Invoke-PowerShellScriptForTest {
    param(
        [string]$ScriptPath,
        [string[]]$ArgumentList = @()
    )

    $outputText = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ArgumentList *>&1 | Out-String)
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $outputText
    }
}

function New-MaintenanceScriptSandbox {
    param(
        [string]$SandboxName,
        [string[]]$ScriptNames
    )

    $sandboxRootPath = Join-Path (Join-Path $repoRootPath 'temp/generated') $SandboxName
    $tasksSandboxPath = Join-Path $sandboxRootPath 'tasks'
    New-Item -ItemType Directory -Force -Path $tasksSandboxPath | Out-Null

    foreach ($scriptName in $ScriptNames) {
        Copy-Item -LiteralPath (Join-Path $scriptRootPath $scriptName) -Destination (Join-Path $sandboxRootPath $scriptName) -Force
    }

    return [pscustomobject]@{
        RootPath = $sandboxRootPath
        TasksPath = $tasksSandboxPath
    }
}

function New-MaintenanceTaskStateContent {
    param(
        [string]$TaskId,
        [string]$Status = 'running',
        [string]$NextAction = '继续推进维护层样例'
    )

    return @"
task_id: $TaskId
status: $Status
risk_level: low
next_action: $NextAction
blocked_by: []
updated_at: '2026-04-04 07:00:00'
phase_hint: maintenance_test
"@
}

function New-MaintenanceTaskPackage {
    param(
        [string]$TasksRootPath,
        [string]$TaskId,
        [string]$StateContent,
        [string]$ResultContent,
        [string]$DecisionLogContent,
        [string]$GatesContent = ''
    )

    $taskDirectoryPath = Join-Path $TasksRootPath $TaskId
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'state.yaml') -Content $StateContent
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'result.md') -Content $ResultContent
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'decision-log.md') -Content $DecisionLogContent

    if (-not [string]::IsNullOrWhiteSpace($GatesContent)) {
        Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'gates.yaml') -Content $GatesContent
    }

    return $taskDirectoryPath
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
    $taskDirectoryPath = Join-Path $tasksRootPath $taskId
    $stateFilePath = Join-Path $taskDirectoryPath 'state.yaml'
    $resultFilePath = Join-Path $taskDirectoryPath 'result.md'
    $decisionLogFilePath = Join-Path $taskDirectoryPath 'decision-log.md'

    Write-Utf8NoBomFile -Path $stateFilePath -Content $taskStateMap[$taskId]
    Write-Utf8NoBomFile -Path $resultFilePath -Content @'
# 结果摘要

## 已完成

- 已创建任务包骨架。

## 验证证据

- 目录：样例任务包

## 遗留事项

- 尚未获得官方面板真实人工验板结果。

## 下一步建议

- 等待真实人工验板结果。
'@
    Write-Utf8NoBomFile -Path $decisionLogFilePath -Content @'
# 决策记录

## 2026-03-31 20:00:00

- 决策：创建样例任务包
- 原因：用于定向回归测试
'@
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

### `传令：版本`

- 是否正常响应：是
- 版本号是否正确：是
- 版本来源是否正确：是
- 真源路径是否正确：是
- 备注：

### `传令：状态`

- 是否正常响应：是
- 固定 6 行是否完整：是
- 当前模式是否清楚：是
- 当前任务是否清楚：是
- 备注：

### `传令：升级`（如有执行）

- 是否正常响应：未执行
- 是否明确用户主动提出才处理：未执行
- 是否明确不会擅自升级项目：未执行
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

$missingResolveTasksRootPath = Join-Path (Join-Path $repoRootPath 'temp/generated') ("panel-acceptance-closeout-resolve-missing-$testRunId")
$missingResolveOutput = ''
try {
    & $resolveScriptPath -ResultPath $passResultPath -TaskId 'v4-trial-035-panel-acceptance-closeout' -TasksRootPath $missingResolveTasksRootPath -SkipReview
}
catch {
    $missingResolveOutput = $_.Exception.Message
}
Assert-Contains -Content $missingResolveOutput -ExpectedText '回写所需文件不齐，当前不能继续。' -Message '回写缺文件提示校验失败'
Assert-Contains -Content $missingResolveOutput -ExpectedText '缺少回写所需文件' -Message '回写缺文件原因提示校验失败'

$passResolveTaskRootPath = Join-Path (Join-Path $repoRootPath 'temp/generated') ("panel-acceptance-closeout-resolve-pass-$testRunId")
$passResolveTasksRootPath = Join-Path $passResolveTaskRootPath 'tasks'
$passResolveActiveTaskFilePath = Join-Path $passResolveTaskRootPath 'active-task.txt'
Write-Utf8NoBomFile -Path $passResolveActiveTaskFilePath -Content "v4-trial-035-panel-acceptance-closeout`n"
foreach ($taskId in $taskStateMap.Keys) {
    $taskDirectoryPath = Join-Path $passResolveTasksRootPath $taskId
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'state.yaml') -Content $taskStateMap[$taskId]
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'result.md') -Content (Get-Content (Join-Path (Join-Path $tasksRootPath $taskId) 'result.md') -Raw)
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'decision-log.md') -Content (Get-Content (Join-Path (Join-Path $tasksRootPath $taskId) 'decision-log.md') -Raw)
}
& $resolveScriptPath -ResultPath $passResultPath -TaskId 'v4-trial-035-panel-acceptance-closeout' -TasksRootPath $passResolveTasksRootPath -ActiveTaskFilePath $passResolveActiveTaskFilePath -SkipReview
$passResolvedState = Get-Content (Join-Path $passResolveTasksRootPath 'v4-trial-035-panel-acceptance-closeout/state.yaml') -Raw
$passResolvedResult = Get-Content (Join-Path $passResolveTasksRootPath 'v4-trial-035-panel-acceptance-closeout/result.md') -Raw
$passResolvedDecision = Get-Content (Join-Path $passResolveTasksRootPath 'v4-trial-035-panel-acceptance-closeout/decision-log.md') -Raw
Assert-Contains -Content $passResolvedState -ExpectedText 'status: done' -Message '通过态回写后状态应为 done'
Assert-Contains -Content $passResolvedResult -ExpectedText '人工验板最终结果：通过' -Message '通过态回写结果摘要缺少最终结论'
Assert-Contains -Content $passResolvedDecision -ExpectedText '决策：回写真实人工验板结果到任务包' -Message '通过态回写决策日志缺少回写记录'

$failResolveTaskRootPath = Join-Path (Join-Path $repoRootPath 'temp/generated') ("panel-acceptance-closeout-resolve-fail-$testRunId")
$failResolveTasksRootPath = Join-Path $failResolveTaskRootPath 'tasks'
$failResolveActiveTaskFilePath = Join-Path $failResolveTaskRootPath 'active-task.txt'
Write-Utf8NoBomFile -Path $failResolveActiveTaskFilePath -Content "v4-trial-035-panel-acceptance-closeout`n"
foreach ($taskId in $taskStateMap.Keys) {
    $taskDirectoryPath = Join-Path $failResolveTasksRootPath $taskId
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'state.yaml') -Content $taskStateMap[$taskId]
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'result.md') -Content (Get-Content (Join-Path (Join-Path $tasksRootPath $taskId) 'result.md') -Raw)
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'decision-log.md') -Content (Get-Content (Join-Path (Join-Path $tasksRootPath $taskId) 'decision-log.md') -Raw)
}
& $resolveScriptPath -ResultPath $failResultPath -TaskId 'v4-trial-035-panel-acceptance-closeout' -TasksRootPath $failResolveTasksRootPath -ActiveTaskFilePath $failResolveActiveTaskFilePath -SkipReview
$failResolvedState = Get-Content (Join-Path $failResolveTasksRootPath 'v4-trial-035-panel-acceptance-closeout/state.yaml') -Raw
$failResolvedResult = Get-Content (Join-Path $failResolveTasksRootPath 'v4-trial-035-panel-acceptance-closeout/result.md') -Raw
Assert-Contains -Content $failResolvedState -ExpectedText 'status: ready_to_resume' -Message '不通过态回写后状态应为 ready_to_resume'
Assert-Contains -Content $failResolvedResult -ExpectedText '人工验板最终结果：不通过' -Message '不通过态回写结果摘要缺少最终结论'
Assert-Contains -Content $failResolvedResult -ExpectedText '最小缺口：面板回复中仍有一处口径不稳' -Message '不通过态回写结果摘要缺少最小缺口'

$finalizeTaskRootPath = Join-Path (Join-Path $repoRootPath 'temp/generated') ("panel-acceptance-closeout-finalize-$testRunId")
$finalizeTasksRootPath = Join-Path $finalizeTaskRootPath 'tasks'
$finalizeActiveTaskFilePath = Join-Path $finalizeTaskRootPath 'active-task.txt'
Write-Utf8NoBomFile -Path $finalizeActiveTaskFilePath -Content "v4-trial-035-panel-acceptance-closeout`n"
foreach ($taskId in $taskStateMap.Keys) {
    $taskDirectoryPath = Join-Path $finalizeTasksRootPath $taskId
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'state.yaml') -Content $taskStateMap[$taskId]
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'result.md') -Content (Get-Content (Join-Path (Join-Path $tasksRootPath $taskId) 'result.md') -Raw)
    Write-Utf8NoBomFile -Path (Join-Path $taskDirectoryPath 'decision-log.md') -Content (Get-Content (Join-Path (Join-Path $tasksRootPath $taskId) 'decision-log.md') -Raw)
}
$finalizeOutput = (& $finalizeScriptPath -ResultPath $passResultPath -TaskId 'v4-trial-035-panel-acceptance-closeout' -TasksRootPath $finalizeTasksRootPath -ActiveTaskFilePath $finalizeActiveTaskFilePath -AuditReferenceTimeText $auditReferenceTimeText -NormalizeTrial034ToDone *>&1 | Out-String)
$finalizeResolvedState = Get-Content (Join-Path $finalizeTasksRootPath 'v4-trial-035-panel-acceptance-closeout/state.yaml') -Raw
$finalizeTrial034State = Get-Content (Join-Path $finalizeTasksRootPath 'v4-trial-034-public-rule-order-gate/state.yaml') -Raw
$finalizeActiveTaskContent = Get-Content $finalizeActiveTaskFilePath -Raw
if ($null -eq $finalizeActiveTaskContent) {
    $finalizeActiveTaskContent = ''
}
Assert-Contains -Content $finalizeOutput -ExpectedText '一键收口已完成：真实人工验板结果已复核并回写到本地任务包。' -Message '一键收口提示校验失败'
Assert-Contains -Content $finalizeOutput -ExpectedText '已按主公拍板归一化 v4-trial-034：completed -> done' -Message '一键收口未输出 034 归一化提示'
Assert-Contains -Content $finalizeOutput -ExpectedText '已清空 active-task.txt，避免继续指向已完成任务。' -Message '一键收口未清空 active-task.txt'
Assert-Contains -Content $finalizeResolvedState -ExpectedText 'status: done' -Message '一键收口后状态应为 done'
Assert-Contains -Content $finalizeTrial034State -ExpectedText 'status: done' -Message '一键收口后 034 应归一化为 done'
Assert-Equal -Actual ($finalizeActiveTaskContent.Trim()) -Expected '' -Message '一键收口后 active-task.txt 应清空'

$maintenanceSandbox = New-MaintenanceScriptSandbox -SandboxName ("maintenance-script-friendly-test-$testRunId") -ScriptNames @(
    'record-exception-state.ps1',
    'resolve-gate-package.ps1'
)
$recordExceptionScriptForTestPath = Join-Path $maintenanceSandbox.RootPath 'record-exception-state.ps1'
$resolveGatePackageScriptForTestPath = Join-Path $maintenanceSandbox.RootPath 'resolve-gate-package.ps1'
$maintenanceBaseResultContent = @'
# 结果摘要

- 当前为维护层样例任务包。
'@
$maintenanceBaseDecisionLogContent = @'
# 决策记录

- 当前为维护层样例任务包。
'@

$invalidTaskIdRecordResult = Invoke-PowerShellScriptForTest -ScriptPath $recordExceptionScriptForTestPath -ArgumentList @(
    '-TaskId', 'bad-task-id',
    '-Summary', '样例异常摘要',
    '-RollbackScope', '只回退样例文件',
    '-ResumeHint', '补证据后继续'
)
Assert-Equal -Actual $invalidTaskIdRecordResult.ExitCode -Expected 1 -Message '异常记录脚本非法 TaskId 应退出 1'
Assert-Contains -Content $invalidTaskIdRecordResult.Output -ExpectedText '[ERROR] 任务包编号格式不对，当前没法记录异常路径。' -Message '异常记录脚本非法 TaskId 缺少人话错误'
Assert-Contains -Content $invalidTaskIdRecordResult.Output -ExpectedText '[WARN] 原因：TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 格式。' -Message '异常记录脚本非法 TaskId 缺少原因说明'

$recordMissingFileTaskId = 'v4-trial-401-record-exception-missing-file'
$recordMissingFileTaskPath = New-MaintenanceTaskPackage `
    -TasksRootPath $maintenanceSandbox.TasksPath `
    -TaskId $recordMissingFileTaskId `
    -StateContent (New-MaintenanceTaskStateContent -TaskId $recordMissingFileTaskId) `
    -ResultContent $maintenanceBaseResultContent `
    -DecisionLogContent $maintenanceBaseDecisionLogContent
Remove-Item -LiteralPath (Join-Path $recordMissingFileTaskPath 'decision-log.md') -Force
$missingFileRecordResult = Invoke-PowerShellScriptForTest -ScriptPath $recordExceptionScriptForTestPath -ArgumentList @(
    '-TaskId', $recordMissingFileTaskId,
    '-Summary', '样例异常摘要',
    '-RollbackScope', '只回退样例文件',
    '-ResumeHint', '补证据后继续'
)
Assert-Equal -Actual $missingFileRecordResult.ExitCode -Expected 1 -Message '异常记录脚本缺文件时应退出 1'
Assert-Contains -Content $missingFileRecordResult.Output -ExpectedText '[ERROR] 任务包资料还没补齐，当前不能记录异常路径。' -Message '异常记录脚本缺文件缺少人话错误'
Assert-Contains -Content $missingFileRecordResult.Output -ExpectedText 'decision-log.md' -Message '异常记录脚本缺文件缺少具体文件名'

$recordSuccessTaskId = 'v4-trial-402-record-exception-success'
$recordSuccessTaskPath = New-MaintenanceTaskPackage `
    -TasksRootPath $maintenanceSandbox.TasksPath `
    -TaskId $recordSuccessTaskId `
    -StateContent (New-MaintenanceTaskStateContent -TaskId $recordSuccessTaskId) `
    -ResultContent $maintenanceBaseResultContent `
    -DecisionLogContent $maintenanceBaseDecisionLogContent
$recordSuccessResult = Invoke-PowerShellScriptForTest -ScriptPath $recordExceptionScriptForTestPath -ArgumentList @(
    '-TaskId', $recordSuccessTaskId,
    '-ExceptionType', 'blocked',
    '-Summary', '外部依赖暂未返回结果',
    '-RollbackScope', '仅回退维护层样例记录',
    '-ResumeHint', '等待依赖恢复后继续',
    '-NextStatus', 'ready_to_resume',
    '-NextAction', '补齐依赖结果后继续推进'
)
Assert-Equal -Actual $recordSuccessResult.ExitCode -Expected 0 -Message '异常记录脚本成功态应退出 0'
Assert-Contains -Content $recordSuccessResult.Output -ExpectedText '[INFO] 异常路径已记录：' -Message '异常记录脚本成功态缺少完成提示'
$recordSuccessState = Get-Content (Join-Path $recordSuccessTaskPath 'state.yaml') -Raw
$recordSuccessResultContent = Get-Content (Join-Path $recordSuccessTaskPath 'result.md') -Raw
$recordSuccessDecisionLog = Get-Content (Join-Path $recordSuccessTaskPath 'decision-log.md') -Raw
Assert-Contains -Content $recordSuccessState -ExpectedText 'status: ready_to_resume' -Message '异常记录脚本成功态未更新状态'
Assert-Contains -Content $recordSuccessState -ExpectedText 'next_action: 补齐依赖结果后继续推进' -Message '异常记录脚本成功态未更新下一步'
Assert-Contains -Content $recordSuccessResultContent -ExpectedText '## 异常路径记录（blocked）' -Message '异常记录脚本成功态结果稿缺少异常章节'
Assert-Contains -Content $recordSuccessDecisionLog -ExpectedText '回退范围：仅回退维护层样例记录' -Message '异常记录脚本成功态决策日志缺少回退范围'

$invalidGateResolveResult = Invoke-PowerShellScriptForTest -ScriptPath $resolveGatePackageScriptForTestPath -ArgumentList @(
    '-TaskId', 'v4-trial-403-resolve-invalid-gate',
    '-GateId', 'bad_gate_id',
    '-DecisionSummary', '样例拍板结论'
)
Assert-Equal -Actual $invalidGateResolveResult.ExitCode -Expected 1 -Message '拍板回写脚本非法 GateId 应退出 1'
Assert-Contains -Content $invalidGateResolveResult.Output -ExpectedText '[ERROR] 拍板编号格式不对，当前没法回写拍板结果。' -Message '拍板回写脚本非法 GateId 缺少人话错误'
Assert-Contains -Content $invalidGateResolveResult.Output -ExpectedText '[INFO] 先把拍板编号改成例如 gate-confirm-scope。' -Message '拍板回写脚本非法 GateId 缺少下一步提示'

$resolveNonPendingTaskId = 'v4-trial-404-resolve-gate-non-pending'
$resolveNonPendingTaskPath = New-MaintenanceTaskPackage `
    -TasksRootPath $maintenanceSandbox.TasksPath `
    -TaskId $resolveNonPendingTaskId `
    -StateContent (New-MaintenanceTaskStateContent -TaskId $resolveNonPendingTaskId -Status 'waiting_gate' -NextAction '等待拍板回写') `
    -ResultContent $maintenanceBaseResultContent `
    -DecisionLogContent $maintenanceBaseDecisionLogContent `
    -GatesContent @'
- gate_id: gate-confirm-scope
  status: decided
  decision_summary: 已有结论
'@
$nonPendingResolveResult = Invoke-PowerShellScriptForTest -ScriptPath $resolveGatePackageScriptForTestPath -ArgumentList @(
    '-TaskId', $resolveNonPendingTaskId,
    '-GateId', 'gate-confirm-scope',
    '-DecisionSummary', '重复回写样例'
)
Assert-Equal -Actual $nonPendingResolveResult.ExitCode -Expected 1 -Message '拍板回写脚本非 pending 态应退出 1'
Assert-Contains -Content $nonPendingResolveResult.Output -ExpectedText '[ERROR] 这个拍板项已经不是待处理状态，本次没有重复回写。' -Message '拍板回写脚本非 pending 态缺少人话错误'
Assert-Contains -Content $nonPendingResolveResult.Output -ExpectedText 'gate 当前不是 pending 状态，不能重复回写：gate-confirm-scope' -Message '拍板回写脚本非 pending 态缺少原因说明'

$resolveSuccessTaskId = 'v4-trial-405-resolve-gate-success'
$resolveSuccessTaskPath = New-MaintenanceTaskPackage `
    -TasksRootPath $maintenanceSandbox.TasksPath `
    -TaskId $resolveSuccessTaskId `
    -StateContent (New-MaintenanceTaskStateContent -TaskId $resolveSuccessTaskId -Status 'waiting_gate' -NextAction '等待拍板回写') `
    -ResultContent $maintenanceBaseResultContent `
    -DecisionLogContent $maintenanceBaseDecisionLogContent `
    -GatesContent @'
- gate_id: gate-confirm-scope
  status: pending
  owner: 主公
  question: 是否继续按当前边界推进
'@
$resolveSuccessResult = Invoke-PowerShellScriptForTest -ScriptPath $resolveGatePackageScriptForTestPath -ArgumentList @(
    '-TaskId', $resolveSuccessTaskId,
    '-GateId', 'gate-confirm-scope',
    '-DecisionSummary', '确认只推进维护层测试',
    '-ChosenOption', 'keep-current-scope',
    '-NextStatus', 'running',
    '-NextAction', '按拍板结论继续推进'
)
Assert-Equal -Actual $resolveSuccessResult.ExitCode -Expected 0 -Message '拍板回写脚本成功态应退出 0'
Assert-Contains -Content $resolveSuccessResult.Output -ExpectedText '[INFO] 拍板结果已回写：' -Message '拍板回写脚本成功态缺少完成提示'
$resolveSuccessState = Get-Content (Join-Path $resolveSuccessTaskPath 'state.yaml') -Raw
$resolveSuccessResultContent = Get-Content (Join-Path $resolveSuccessTaskPath 'result.md') -Raw
$resolveSuccessDecisionLog = Get-Content (Join-Path $resolveSuccessTaskPath 'decision-log.md') -Raw
$resolveSuccessGates = Get-Content (Join-Path $resolveSuccessTaskPath 'gates.yaml') -Raw
Assert-Contains -Content $resolveSuccessState -ExpectedText 'status: running' -Message '拍板回写脚本成功态未更新状态'
Assert-Contains -Content $resolveSuccessState -ExpectedText 'next_action: 按拍板结论继续推进' -Message '拍板回写脚本成功态未更新下一步'
Assert-Contains -Content $resolveSuccessResultContent -ExpectedText '## 拍板结果回写（gate-confirm-scope）' -Message '拍板回写脚本成功态结果稿缺少拍板章节'
Assert-Contains -Content $resolveSuccessDecisionLog -ExpectedText '决策：回写拍板结果 gate-confirm-scope' -Message '拍板回写脚本成功态决策日志缺少回写记录'
Assert-Contains -Content $resolveSuccessGates -ExpectedText 'status: decided' -Message '拍板回写脚本成功态未更新 gate 状态'
Assert-Contains -Content $resolveSuccessGates -ExpectedText 'chosen_option: keep-current-scope' -Message '拍板回写脚本成功态未写入选定项'

Write-Host 'PASS: test-panel-acceptance-closeout-review.ps1' -ForegroundColor Green
