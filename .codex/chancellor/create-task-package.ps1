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
    [ValidateSet('drafting', 'planning', 'running')]
    [string]$InitialStatus = 'drafting',
    [ValidateSet('low', 'medium', 'high', 'critical')]
    [string]$RiskLevel = 'low',
    [bool]$SetActiveTask = $true,
    [bool]$PlanningRequired = $false,
    [int]$EstimatedHours = 0
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

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlyCreateTaskPackage {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string[]]$NextSteps = @()
    )

    Write-Host ''
    Write-Host "[ERROR] $Summary" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原因：{0}" -f $Detail)
    }

    foreach ($nextStep in $NextSteps) {
        Write-Info $nextStep
    }

    exit 1
}

if ($TaskId -notmatch '^v4-(trial|target)-\d{3}-.+$') {
    Stop-FriendlyCreateTaskPackage `
        -Summary '任务包编号格式不对，当前没法起包。' `
        -Detail 'TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 或 v4-target-<三位序号>-<语义名> 格式。' `
        -NextSteps @(
            '先把任务编号改成例如 `v4-target-001-语义名` 或 `v4-trial-001-语义名`。',
            '确认编号不重复后再重新起包。'
        )
}

if (Test-Path $taskDirectoryPath) {
    Stop-FriendlyCreateTaskPackage `
        -Summary '任务包目录已经存在，本次没有继续覆盖。' `
        -Detail ("任务目录已存在：{0}" -f $taskDirectoryPath) `
        -NextSteps @(
            '先确认是不是重复起包。',
            '如果要新开任务，请换一个新的任务编号后再重试。'
        )
}

New-Item -ItemType Directory -Path $taskDirectoryPath | Out-Null

# 自动判断是否需要技术方案
if ($EstimatedHours -gt 4) {
    $PlanningRequired = $true
}

$planningStatusText = if ($PlanningRequired) { 'pending' } else { 'not_required' }

$contractYamlText = @"
task_id: $TaskId
title: $Title
goal: >-
  $Goal

  【VibeCoding 要求】必须写清楚具体目标，不能模糊。
  错误示例：优化性能
  正确示例：把登录接口响应时间从 2 秒降到 500 毫秒

user_scenario: >-
  【VibeCoding 要求】用户场景必须包含以下 4 要素：
  - 谁：[具体用户角色]
  - 在什么情况下：[具体场景]
  - 要做什么：[具体操作]
  - 期望什么结果：[可验证的结果]

technical_approach: >-
  【VibeCoding 要求】技术方案概要必须包含：
  - 改动哪些文件
  - 核心逻辑是什么
  - 有什么风险点

constraints:
  - 不新增未批准目录
  - 保持当前目录内自含
  - 运行态继续只留本地，不推公开仓
acceptance:
  - 【VibeCoding 要求】验收标准必须可验证、可量化，不能写"功能正常"
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
  - docs/30-方案/10-VibeCoding融合要点提取.md
planning_hint: >-
  $PlanningHint
planning_required: $PlanningRequired
planning_status: $planningStatusText
estimated_hours: $EstimatedHours
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

# 如果需要技术方案，生成 tech-spec.md 骨架
if ($PlanningRequired) {
    $techSpecMarkdownText = @"
# 技术方案

## 1. 用户场景

[从 contract.yaml 的 user_scenario 字段复制]

## 改动文件清单

| 文件路径 | 改动类型 | 改动原因 | 风险等级 |
|---------|---------|---------|---------|
| [待补充] | 新增/修改/删除 | [待补充] | 低/中/高 |

## 执行流程

``````mermaid
graph TD
    A[开始] --> B[步骤1]
    B --> C[步骤2]
    C --> D[结束]
``````

## 核心代码逻辑

``````typescript
// 待补充核心逻辑伪代码
function mainLogic() {
  // TODO
}
``````

## 风险评估

- 风险1：[描述]
  - 应对：[方案]
- 风险2：[描述]
  - 应对：[方案]

## 验收标准

- [ ] [可验证的验收标准1]
- [ ] [可验证的验收标准2]
- [ ] 单元测试覆盖率 ≥ 80%

## 依赖与前置条件

- 依赖项：[列出外部依赖]
- 前置条件：[列出必须满足的条件]

## 实施步骤

1. [步骤1]
2. [步骤2]
3. [步骤3]
"@
    Set-Content -Path (Join-Path $taskDirectoryPath 'tech-spec.md') -Value $techSpecMarkdownText -Encoding UTF8
    Write-Output "已生成 tech-spec.md 骨架（复杂任务）"
}

if ($SetActiveTask) {
    Set-Content -Path (Join-Path $scriptRootPath 'active-task.txt') -Value $TaskId -Encoding UTF8
}

Write-Output "任务包已创建：$taskDirectoryPath"
Write-Output "收口参考：$closeoutGuideRelativePath"
if ($PlanningRequired) {
    Write-Output "⚠️ 复杂任务：请先完成 tech-spec.md，将 planning_status 改为 'approved'，再将 status 改为 'running'"
}
