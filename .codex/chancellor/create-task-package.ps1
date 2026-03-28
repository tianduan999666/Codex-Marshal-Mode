param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [Parameter(Mandatory = $true)]
    [string]$Goal,
    [string]$PhaseHint = 'optional_phase',
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
$closeoutGuideRelativePath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'

if ($TaskId -notmatch '^v4-trial-\d{3}-.+$') {
    throw 'TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 格式。'
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
  - $closeoutGuideRelativePath
"@
$stateYamlText = @"
task_id: $TaskId
status: drafting
risk_level: $RiskLevel
next_action: 按收口检查表补充任务细节并开始推进
blocked_by: []
updated_at: '$timestampText'
phase_hint: $PhaseHint
"@

$decisionLogMarkdownText = @"
# 决策记录

## $timestampText

- 决策：创建任务包骨架
- 原因：减少重复手工起包成本
- 证据：依据当前仓任务包规范与模板
- 影响：后续可在此基础上继续补全任务细节
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

- 回看 `contract.yaml`，补齐任务边界与验收。
- 回看 `state.yaml`，改成真实下一步。
- 按 $closeoutGuideRelativePath 完成本轮收口。
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
