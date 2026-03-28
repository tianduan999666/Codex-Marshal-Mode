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

if (($OptionCName -eq '') -xor ($OptionCImpact -eq '')) {
    throw 'OptionCName 与 OptionCImpact 要么同时提供，要么同时留空。'
}

$gatesYamlText = Get-Content -Raw $gatesFilePath
if ($gatesYamlText -notmatch '(?m)^items:\s*\[\]\s*$') {
    throw '当前脚本仅支持从空的 gates.yaml 起包；如已有待拍板项，请手动整理后再继续。'
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
- 证据：依据 $gateGuideRelativePath 生成待拍板结构
- 影响：任务状态切换为 waiting_gate，待主公拍板后再继续
"@
Add-Content -Path $decisionLogFilePath -Value $decisionLogAppendText -Encoding UTF8
$resultAppendText = @"

## 待拍板事项（$GateId）

- 问题：$Question
- 推荐：$Recommendation
- 阻塞原因：$BlockingReason
- 拍板规范：$gateGuideRelativePath
- 收口参考：$closeoutGuideRelativePath
"@
Add-Content -Path $resultFilePath -Value $resultAppendText -Encoding UTF8

Write-Output "拍板包已写入：$taskDirectoryPath"
Write-Output "待拍板编号：$GateId"
Write-Output "拍板规范：$gateGuideRelativePath"
Write-Output "收口参考：$closeoutGuideRelativePath"
