param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [Parameter(Mandatory = $true)]
    [string]$GateId,
    [ValidateSet('decided', 'dropped')]
    [string]$DecisionStatus = 'decided',
    [Parameter(Mandatory = $true)]
    [string]$DecisionSummary,
    [string]$ChosenOption = '',
    [ValidateSet('drafting', 'ready', 'running', 'waiting_gate', 'waiting_assist', 'verifying', 'done', 'paused', 'ready_to_resume')]
    [string]$NextStatus = 'running',
    [string]$NextAction = '按拍板结果继续推进'
)

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskDirectoryPath = Join-Path (Join-Path $scriptRootPath 'tasks') $TaskId
$timestampText = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$gateGuideRelativePath = 'docs/40-执行/15-拍板包准备与收口规范.md'
$governanceGuideRelativePath = 'docs/30-方案/08-V4-治理审计候选规范.md'
$closeoutGuideRelativePath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'

if ($TaskId -notmatch '^v4-trial-\d{3}-.+$') {
    throw 'TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 格式。'
}

if ($GateId -notmatch '^gate-[a-z0-9-]+$') {
    throw 'GateId 必须匹配 gate-<语义名> 格式。'
}
if (-not (Test-Path $taskDirectoryPath)) {
    throw "任务目录不存在：$taskDirectoryPath"
}

$gatesFilePath = Join-Path $taskDirectoryPath 'gates.yaml'
$stateFilePath = Join-Path $taskDirectoryPath 'state.yaml'
$resultFilePath = Join-Path $taskDirectoryPath 'result.md'
$decisionLogFilePath = Join-Path $taskDirectoryPath 'decision-log.md'

foreach ($requiredFilePath in @($gatesFilePath, $stateFilePath, $resultFilePath, $decisionLogFilePath)) {
    if (-not (Test-Path $requiredFilePath)) {
        throw "缺少必需文件：$requiredFilePath"
    }
}

$gateLines = Get-Content $gatesFilePath
$gateStartIndex = -1
for ($lineIndex = 0; $lineIndex -lt $gateLines.Count; $lineIndex++) {
    if ($gateLines[$lineIndex] -match "^\s*-\s*gate_id:\s*$GateId\s*$") {
        $gateStartIndex = $lineIndex
        break
    }
}

if ($gateStartIndex -lt 0) {
    throw "未找到待处理 gate：$GateId"
}

$gateEndIndex = $gateLines.Count - 1
for ($lineIndex = $gateStartIndex + 1; $lineIndex -lt $gateLines.Count; $lineIndex++) {
    if ($gateLines[$lineIndex] -match '^\s*-\s*gate_id:\s*.+$') {
        $gateEndIndex = $lineIndex - 1
        break
    }
}

$statusLineIndex = -1
for ($lineIndex = $gateStartIndex; $lineIndex -le $gateEndIndex; $lineIndex++) {
    if ($gateLines[$lineIndex] -match '^\s*status:\s*(pending|decided|dropped)\s*$') {
        $statusLineIndex = $lineIndex
        break
    }
}

if ($statusLineIndex -lt 0) {
    throw "gate 缺少 status 字段：$GateId"
}

if ($gateLines[$statusLineIndex] -notmatch '^\s*status:\s*pending\s*$') {
    throw "gate 当前不是 pending 状态，不能重复回写：$GateId"
}

$statusIndent = ([regex]::Match($gateLines[$statusLineIndex], '^\s*')).Value
$detailIndent = $statusIndent
$updatedGateBlockLines = @()
for ($lineIndex = $gateStartIndex; $lineIndex -le $gateEndIndex; $lineIndex++) {
    if ($lineIndex -eq $statusLineIndex) {
        $updatedGateBlockLines += ($statusIndent + "status: $DecisionStatus")
        $updatedGateBlockLines += ($detailIndent + "decided_at: '$timestampText'")
        $updatedGateBlockLines += ($detailIndent + "decision_summary: $DecisionSummary")
        if ($ChosenOption -ne '') {
            $updatedGateBlockLines += ($detailIndent + "chosen_option: $ChosenOption")
        }
        continue
    }

    if ($gateLines[$lineIndex] -match '^\s*(decided_at|decision_summary|chosen_option):\s*.*$') {
        continue
    }

    $updatedGateBlockLines += $gateLines[$lineIndex]
}

$updatedGateLines = @()
if ($gateStartIndex -gt 0) {
    $updatedGateLines += $gateLines[0..($gateStartIndex - 1)]
}
$updatedGateLines += $updatedGateBlockLines
if ($gateEndIndex -lt ($gateLines.Count - 1)) {
    $updatedGateLines += $gateLines[($gateEndIndex + 1)..($gateLines.Count - 1)]
}
Set-Content -Path $gatesFilePath -Value $updatedGateLines -Encoding UTF8

$stateYamlText = Get-Content -Raw $stateFilePath
$updatedStateYamlText = $stateYamlText
$updatedStateYamlText = [regex]::Replace($updatedStateYamlText, '(?m)^status:\s*.*$', "status: $NextStatus")
$updatedStateYamlText = [regex]::Replace($updatedStateYamlText, '(?m)^next_action:\s*.*$', "next_action: $NextAction")
$updatedStateYamlText = [regex]::Replace($updatedStateYamlText, "(?m)^updated_at:\s*'.*'$", "updated_at: '$timestampText'")
Set-Content -Path $stateFilePath -Value $updatedStateYamlText -Encoding UTF8
$decisionLogAppendText = @"

## $timestampText

- 决策：回写拍板结果 $GateId
- 结果：$DecisionStatus
- 结论：$DecisionSummary
- 证据：依据 $gateGuideRelativePath 与 $governanceGuideRelativePath 完成拍板结果回写
- 影响：任务状态切换为 $NextStatus，下一步为 $NextAction
- 治理提示：提交前应确认回写后的关键口径、后续动作与公开边界已完成治理审计复核
"@
Add-Content -Path $decisionLogFilePath -Value $decisionLogAppendText -Encoding UTF8

$resultAppendText = @"

## 拍板结果回写（$GateId）

- 结果：$DecisionStatus
- 结论：$DecisionSummary
- 选定项：$ChosenOption
- 下一状态：$NextStatus
- 下一步：$NextAction
- 治理复核：$governanceGuideRelativePath
- 收口参考：$closeoutGuideRelativePath

## 治理复核（$GateId）

- 回写后的关键口径来源是否已说明：待补说明
- 回写后的后续动作是否可追溯：待补说明
- 当前是否发现口径漂移：待复核
- 提交前是否已完成治理审计复核：待确认
"@
Add-Content -Path $resultFilePath -Value $resultAppendText -Encoding UTF8

Write-Output "拍板结果已回写：$taskDirectoryPath"
Write-Output "待拍板编号：$GateId"
Write-Output "结果状态：$DecisionStatus"
Write-Output "收口参考：$closeoutGuideRelativePath"
