param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [Parameter(Mandatory = $true)]
    [string]$Goal,
    [string]$PhaseHint = 'optional_phase',
    [string]$PlanningHint = 'optional',
    [string]$PlanStep = '按真实情况填写当前最小推进步',
    [string]$VerifySignal = '按真实情况填写当前验证信号',
    [ValidateSet('drafting', 'running')]
    [string]$InitialStatus = 'drafting',
    [ValidateSet('low', 'medium', 'high', 'critical')]
    [string]$RiskLevel = 'low',
    [bool]$SetActiveTask = $true
)

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$tasksRootPath = Join-Path $scriptRootPath 'tasks'
$taskDirectoryPath = Join-Path $tasksRootPath $TaskId
$timestampText = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$taskSpecRelativePath = 'docs/40-执行/01-任务包规范.md'
$taskTemplateRelativePath = 'docs/40-执行/02-任务包模板.md'
$planningGuideRelativePath = 'docs/30-方案/07-V4-规划策略候选规范.md'
$governanceGuideRelativePath = 'docs/30-方案/08-V4-治理审计候选规范.md'
$closeoutGuideRelativePath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'

if ($TaskId -notmatch '^v4-(trial|target)-\d{3}-.+$') {
    throw 'TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 或 v4-target-<三位序号>-<语义名> 格式。'
}

if (Test-Path $taskDirectoryPath) {
    throw "任务目录已存在：$taskDirectoryPath"
}

New-Item -ItemType Directory -Path $taskDirectoryPath | Out-Null

$contractYamlText = @"
task_id: $TaskId
title: $Title
goal: >-
  $Goal
constraints:
  - 不新增未批准目录
  - 保持当前目录内自含
  - 运行态继续只留本地，不推公开仓
acceptance:
  - 已创建任务包 5 件套基础文件
  - 已写入最小目标、状态与结果骨架
must_gate: []
default_auto:
  - 低风险起包动作可直接执行
source_refs:
  - $taskSpecRelativePath
  - $taskTemplateRelativePath
  - $planningGuideRelativePath
  - $governanceGuideRelativePath
  - $closeoutGuideRelativePath
planning_hint: >-
  $PlanningHint
"@
$stateYamlText = @"
task_id: $TaskId
status: $InitialStatus
risk_level: $RiskLevel
next_action: $PlanStep
blocked_by: []
updated_at: '$timestampText'
phase_hint: $PhaseHint
plan_step: $PlanStep
verify_signal: $VerifySignal
"@

$decisionLogMarkdownText = @"
# 决策记录

## $timestampText

- 决策：创建任务包骨架
- 原因：减少重复手工起包成本
- 证据：依据当前仓任务包规范、模板、规划策略候选规范与治理审计候选规范
- 影响：后续可在此基础上继续补全任务细节
- 路线修正：若验证失败，按真实情况改写下一轮推进路径
- 治理提示：公开口径变更或提交前，应追加治理审计复核
"@

$gatesYamlText = @"
task_id: $TaskId
items: []
"@

$resultMarkdownText = @"
# 结果摘要

## 已完成

- 已创建任务包骨架

## 验证证据

- 目录：.codex/chancellor/tasks/$TaskId/
- 收口参考：$closeoutGuideRelativePath

## 遗留事项

- 尚未补齐任务特定细节

## 下一步建议

- 回看 `contract.yaml`，补齐任务边界、验收与主假设。
- 回看 `state.yaml`，改成真实下一步、最小推进步与验证信号。
- 按 $planningGuideRelativePath 决定是否需要改路。
- 提交前按 $governanceGuideRelativePath 追加治理审计复核。
- 如当前轮涉及入口、现行标准件或公开口径，按 docs/40-执行/21-关键配置来源与漂移复核模板.md 追加配置来源与漂移复核。
- 按 $closeoutGuideRelativePath 完成本轮收口。

## 规划复核

- 当前主假设是否成立：待补证据
- 当前最小推进步是否完成：否
- 下一轮是否需要改路：待当前验证结果决定

## 治理复核

- 当前关键口径来源是否已说明：待补说明
- 当前关键输出是否可追溯：待补说明
- 当前是否发现口径漂移：待复核
- 公开仓边界是否已复核：待提交前确认
"@

Set-Content -Path (Join-Path $taskDirectoryPath 'contract.yaml') -Value $contractYamlText -Encoding UTF8
Set-Content -Path (Join-Path $taskDirectoryPath 'state.yaml') -Value $stateYamlText -Encoding UTF8
Set-Content -Path (Join-Path $taskDirectoryPath 'decision-log.md') -Value $decisionLogMarkdownText -Encoding UTF8
Set-Content -Path (Join-Path $taskDirectoryPath 'gates.yaml') -Value $gatesYamlText -Encoding UTF8
Set-Content -Path (Join-Path $taskDirectoryPath 'result.md') -Value $resultMarkdownText -Encoding UTF8

if ($SetActiveTask) {
    Set-Content -Path (Join-Path $scriptRootPath 'active-task.txt') -Value $TaskId -Encoding UTF8
}

Write-Output "任务包已创建：$taskDirectoryPath"
Write-Output "收口参考：$closeoutGuideRelativePath"
