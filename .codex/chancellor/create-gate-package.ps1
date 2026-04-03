param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [Parameter(Mandatory = $true)]
    [string]$GateId,
    [Parameter(Mandatory = $true)]
    [string]$Question,
    [Parameter(Mandatory = $true)]
    [string]$Recommendation,
    [Parameter(Mandatory = $true)]
    [string]$OptionAName,
    [Parameter(Mandatory = $true)]
    [string]$OptionAImpact,
    [Parameter(Mandatory = $true)]
    [string]$OptionBName,
    [Parameter(Mandatory = $true)]
    [string]$OptionBImpact,
    [string]$OptionCName = '',
    [string]$OptionCImpact = '',
    [string]$NeededBy = '',
    [string]$BlockingReason = '未拍板前不能继续下一步'
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

function Stop-FriendlyCreateGatePackage {
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
    Stop-FriendlyCreateGatePackage `
        -Summary '任务包编号格式不对，当前没法生成拍板包。' `
        -Detail 'TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 格式。' `
        -NextSteps @(
            '先把任务编号改成例如 v4-trial-001-语义名。',
            '确认任务编号无误后再重试。'
        )
}

if ($GateId -notmatch '^gate-[a-z0-9-]+$') {
    Stop-FriendlyCreateGatePackage `
        -Summary '拍板编号格式不对，当前没法生成拍板包。' `
        -Detail 'GateId 必须匹配 gate-<语义名> 格式。' `
        -NextSteps @(
            '先把拍板编号改成例如 gate-confirm-tech-spec。',
            '只用小写字母、数字和中划线。'
        )
}

if (-not (Test-Path $taskDirectoryPath)) {
    Stop-FriendlyCreateGatePackage `
        -Summary '任务目录不存在，当前没法往里写拍板包。' `
        -Detail ("任务目录不存在：{0}" -f $taskDirectoryPath) `
        -NextSteps @(
            '先确认 TaskId 是否写对了。',
            '确认对应任务包已经创建后再重试。'
        )
}

$gatesFilePath = Join-Path $taskDirectoryPath 'gates.yaml'
$stateFilePath = Join-Path $taskDirectoryPath 'state.yaml'
$resultFilePath = Join-Path $taskDirectoryPath 'result.md'
$decisionLogFilePath = Join-Path $taskDirectoryPath 'decision-log.md'

foreach ($requiredFilePath in @($gatesFilePath, $stateFilePath, $resultFilePath, $decisionLogFilePath)) {
    if (-not (Test-Path $requiredFilePath)) {
        Stop-FriendlyCreateGatePackage `
            -Summary '任务包资料还没补齐，当前不能直接生成拍板包。' `
            -Detail ("缺少必需文件：{0}" -f $requiredFilePath) `
            -NextSteps @(
                '先把任务包基础文件补齐。',
                '至少确认 gates.yaml、state.yaml、result.md、decision-log.md 都存在。'
            )
    }
}

if (($OptionCName -eq '') -xor ($OptionCImpact -eq '')) {
    Stop-FriendlyCreateGatePackage `
        -Summary '方案 C 的信息没填完整，当前没法继续。' `
        -Detail 'OptionCName 与 OptionCImpact 要么同时提供，要么同时留空。' `
        -NextSteps @(
            '如果要提供方案 C，就把名称和影响一起填上。',
            '如果暂时不需要方案 C，就两项都留空。'
        )
}

$gatesYamlText = Get-Content -Raw $gatesFilePath
if ($gatesYamlText -notmatch '(?m)^items:\s*\[\]\s*$') {
    Stop-FriendlyCreateGatePackage `
        -Summary 'gates.yaml 里已经有内容，本次没有继续自动追加。' `
        -Detail '当前脚本只支持从空的 gates.yaml 起包。' `
        -NextSteps @(
            '先人工整理现有待拍板项。',
            '确认 gates.yaml 回到空白起包状态后再重试。'
        )
}

$gateYamlLines = @(
    'items:',
    "  - gate_id: $GateId",
    '    status: pending',
    "    question: $Question",
    "    recommendation: $Recommendation",
    '    options:',
    "      - name: $OptionAName",
    "        impact: $OptionAImpact",
    "      - name: $OptionBName",
    "        impact: $OptionBImpact"
)

if ($OptionCName -ne '') {
    $gateYamlLines += "      - name: $OptionCName"
    $gateYamlLines += "        impact: $OptionCImpact"
}
if ($NeededBy -ne '') {
    $gateYamlLines += "    needed_by: '$NeededBy'"
}

$gateYamlLines += "    blocking_reason: $BlockingReason"
$gateYamlText = $gateYamlLines -join [Environment]::NewLine
$updatedGatesYamlText = [regex]::Replace($gatesYamlText, '(?m)^items:\s*\[\]\s*$', $gateYamlText)
Set-Content -Path $gatesFilePath -Value $updatedGatesYamlText -Encoding UTF8

$stateYamlText = Get-Content -Raw $stateFilePath
$updatedStateYamlText = $stateYamlText
$updatedStateYamlText = [regex]::Replace($updatedStateYamlText, '(?m)^status:\s*.*$', 'status: waiting_gate')
$updatedStateYamlText = [regex]::Replace($updatedStateYamlText, '(?m)^next_action:\s*.*$', "next_action: 等待主公拍板：$GateId")
$updatedStateYamlText = [regex]::Replace($updatedStateYamlText, "(?m)^updated_at:\s*'.*'$", "updated_at: '$timestampText'")
Set-Content -Path $stateFilePath -Value $updatedStateYamlText -Encoding UTF8

$decisionLogAppendText = @"

## $timestampText

- 决策：准备拍板包 $GateId
- 原因：当前任务进入待拍板状态，需要形成标准拍板输入
- 证据：依据 $gateGuideRelativePath 与 $governanceGuideRelativePath 生成待拍板结构
- 影响：任务状态切换为 waiting_gate，待主公拍板后再继续
- 治理提示：拍板汇报与提交前，应追加治理审计复核
"@
Add-Content -Path $decisionLogFilePath -Value $decisionLogAppendText -Encoding UTF8
$resultAppendText = @"

## 待拍板事项（$GateId）

- 问题：$Question
- 推荐：$Recommendation
- 阻塞原因：$BlockingReason
- 拍板规范：$gateGuideRelativePath
- 治理复核：$governanceGuideRelativePath
- 收口参考：$closeoutGuideRelativePath

## 治理提示（$GateId）

- 当前关键口径来源是否已说明：待补说明
- 当前拍板输出是否可追溯：待补说明
- 当前是否发现口径漂移：待复核
- 提交前是否已完成治理审计复核：待确认
"@
Add-Content -Path $resultFilePath -Value $resultAppendText -Encoding UTF8

Write-Output "拍板包已写入：$taskDirectoryPath"
Write-Output "待拍板编号：$GateId"
Write-Output "拍板规范：$gateGuideRelativePath"
Write-Output "收口参考：$closeoutGuideRelativePath"
