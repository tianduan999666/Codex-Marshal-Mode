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

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlyResolveGatePackage {
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

if ($TaskId -notmatch '^v4-trial-\d{3}-.+$') {
    Stop-FriendlyResolveGatePackage `
        -Summary '任务包编号格式不对，当前没法回写拍板结果。' `
        -Detail 'TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 格式。' `
        -NextSteps @(
            '先把任务编号改成例如 v4-trial-001-语义名。',
            '确认任务编号无误后再重新回写。'
        )
}

if ($GateId -notmatch '^gate-[a-z0-9-]+$') {
    Stop-FriendlyResolveGatePackage `
        -Summary '拍板编号格式不对，当前没法回写拍板结果。' `
        -Detail 'GateId 必须匹配 gate-<语义名> 格式。' `
        -NextSteps @(
            '先把拍板编号改成例如 gate-confirm-scope。',
            '只用小写字母、数字和中划线。'
        )
}
if (-not (Test-Path $taskDirectoryPath)) {
    Stop-FriendlyResolveGatePackage `
        -Summary '任务目录不存在，当前没法回写拍板结果。' `
        -Detail ("任务目录不存在：{0}" -f $taskDirectoryPath) `
        -NextSteps @(
            '先确认 TaskId 是否写对了。',
            '确认对应任务包已经创建后再重新回写。'
        )
}

$gatesFilePath = Join-Path $taskDirectoryPath 'gates.yaml'
$stateFilePath = Join-Path $taskDirectoryPath 'state.yaml'
$resultFilePath = Join-Path $taskDirectoryPath 'result.md'
$decisionLogFilePath = Join-Path $taskDirectoryPath 'decision-log.md'

foreach ($requiredFilePath in @($gatesFilePath, $stateFilePath, $resultFilePath, $decisionLogFilePath)) {
    if (-not (Test-Path $requiredFilePath)) {
        Stop-FriendlyResolveGatePackage `
            -Summary '任务包资料还没补齐，当前不能回写拍板结果。' `
            -Detail ("缺少必需文件：{0}" -f $requiredFilePath) `
            -NextSteps @(
                '先补齐 gates.yaml、state.yaml、result.md、decision-log.md。',
                '补齐后再重新回写拍板结果。'
            )
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
    Stop-FriendlyResolveGatePackage `
        -Summary '当前任务里没找到这个待拍板项，不能继续回写。' `
        -Detail ("未找到待处理 gate：{0}" -f $GateId) `
        -NextSteps @(
            '先确认 GateId 是否写对了。',
            '确认 gates.yaml 里确实存在这个待拍板项后再重试。'
        )
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
    Stop-FriendlyResolveGatePackage `
        -Summary '这个拍板项资料不完整，当前不能回写。' `
        -Detail ("gate 缺少 status 字段：{0}" -f $GateId) `
        -NextSteps @(
            '先补齐该拍板项的 status 字段。',
            '补完后再重新回写拍板结果。'
        )
}

if ($gateLines[$statusLineIndex] -notmatch '^\s*status:\s*pending\s*$') {
    Stop-FriendlyResolveGatePackage `
        -Summary '这个拍板项已经不是待处理状态，本次没有重复回写。' `
        -Detail ("gate 当前不是 pending 状态，不能重复回写：{0}" -f $GateId) `
        -NextSteps @(
            '先确认是不是已经回写过拍板结果。',
            '如果要改结论，请先人工核对现有记录后再处理。'
        )
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

Write-Info ("拍板结果已回写：{0}" -f $taskDirectoryPath)
Write-Info ("待拍板编号：{0}" -f $GateId)
Write-Info ("结果状态：{0}" -f $DecisionStatus)
Write-Info ("收口参考：{0}" -f $closeoutGuideRelativePath)
