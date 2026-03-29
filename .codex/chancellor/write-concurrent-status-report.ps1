param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [ValidateSet('drafting', 'ready', 'running', 'waiting_gate', 'waiting_assist', 'verifying', 'done', 'paused', 'ready_to_resume')]
    [string]$PrimaryStatus = 'waiting_gate',
    [Parameter(Mandatory = $true)]
    [string]$PrimaryBlocker,
    [Parameter(Mandatory = $true)]
    [string]$PrimaryReason,
    [string[]]$SecondaryItems = @(),
    [string[]]$RecoverySteps = @(),
    [Parameter(Mandatory = $true)]
    [string]$NextAction,
    [string[]]$DecisionBasis = @(),
    [string[]]$RejectedCandidates = @(),
    [switch]$SyncState
)

function ConvertTo-BulletLines {
    param(
        [string[]]$Items,
        [string]$DefaultText
    )

    $normalizedItems = @($Items | Where-Object { $_ -and $_.Trim() -ne '' })

    if ($normalizedItems.Count -eq 0) {
        return @("- $DefaultText")
    }

    return @($normalizedItems | ForEach-Object { "- $_" })
}

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskDirectoryPath = Join-Path (Join-Path $scriptRootPath 'tasks') $TaskId
$timestampText = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$ruleGuideRelativePath = 'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
$templateGuideRelativePath = 'docs/40-执行/20-复杂并存汇报骨架模板.md'
$governanceGuideRelativePath = 'docs/30-方案/08-V4-治理审计候选规范.md'
$closeoutGuideRelativePath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'

if ($TaskId -notmatch '^v4-trial-\d{3}-.+$') {
    throw 'TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 格式。'
}

if (-not (Test-Path $taskDirectoryPath)) {
    throw "任务目录不存在：$taskDirectoryPath"
}

$resultFilePath = Join-Path $taskDirectoryPath 'result.md'
$decisionLogFilePath = Join-Path $taskDirectoryPath 'decision-log.md'
$stateFilePath = Join-Path $taskDirectoryPath 'state.yaml'

foreach ($requiredFilePath in @($resultFilePath, $decisionLogFilePath, $stateFilePath)) {
    if (-not (Test-Path $requiredFilePath)) {
        throw "缺少必需文件：$requiredFilePath"
    }
}

$secondaryItemLines = ConvertTo-BulletLines -Items $SecondaryItems -DefaultText '当前无次要待处理项'
$recoveryStepLines = ConvertTo-BulletLines -Items $RecoverySteps -DefaultText "主阻塞解除后，按“$NextAction”恢复"
$decisionBasisLines = ConvertTo-BulletLines -Items $DecisionBasis -DefaultText "按 $ruleGuideRelativePath 的主阻塞优先级规则裁决"
$rejectedCandidateLines = ConvertTo-BulletLines -Items $RejectedCandidates -DefaultText '本轮无其他更高优先级候选状态'

$resultAppendLines = @(
    '',
    '',
    "## 复杂并存汇报（$timestampText）",
    '',
    "- 主状态：$PrimaryStatus",
    "- 主阻塞：$PrimaryBlocker",
    "- 主阻塞原因：$PrimaryReason",
    "- 主规则：$ruleGuideRelativePath",
    "- 骨架模板：$templateGuideRelativePath",
    "- 治理复核：$governanceGuideRelativePath",
    '',
    '### 次要待处理项',
    ''
)
$resultAppendLines += $secondaryItemLines
$resultAppendLines += @(
    '',
    '### 恢复顺序',
    ''
)
$resultAppendLines += $recoveryStepLines
$resultAppendLines += @(
    '',
    '### 下一步',
    '',
    "- $NextAction",
    '',
    '### 治理复核',
    '',
    '- 当前主状态依据是否可追溯：待补说明',
    '- 当前次要待处理项是否完整保留：待补说明',
    '- 当前是否发现口径漂移：待复核',
    '- 提交前是否已完成治理审计复核：待确认',
    '',
    '### 收口参考',
    '',
    "- $closeoutGuideRelativePath"
)

$decisionLogAppendLines = @(
    '',
    '',
    "## $timestampText",
    '',
    "- 决策：记录复杂并存场景主状态为 $PrimaryStatus",
    "- 主阻塞：$PrimaryBlocker",
    "- 原因：$PrimaryReason",
    "- 证据：依据 $ruleGuideRelativePath、$templateGuideRelativePath 与 $governanceGuideRelativePath 形成统一汇报骨架",
    '- 未选状态：'
)
$decisionLogAppendLines += $rejectedCandidateLines
$decisionLogAppendLines += @(
    '',
    '- 裁决依据：'
)
$decisionLogAppendLines += $decisionBasisLines
$decisionLogAppendLines += @(
    '',
    '- 治理提示：复杂裁决结果与提交前，应确认主状态依据、次要待处理项与公开边界已完成治理审计复核',
    "- 影响：result.md 已生成复杂并存汇报骨架，下一步为 $NextAction"
)

Add-Content -Path $resultFilePath -Value ($resultAppendLines -join [Environment]::NewLine) -Encoding UTF8
Add-Content -Path $decisionLogFilePath -Value ($decisionLogAppendLines -join [Environment]::NewLine) -Encoding UTF8

if ($SyncState) {
    $stateYamlText = Get-Content -Raw $stateFilePath
    $updatedStateYamlText = $stateYamlText
    $updatedStateYamlText = [regex]::Replace($updatedStateYamlText, '(?m)^status:\s*.*$', "status: $PrimaryStatus")
    $updatedStateYamlText = [regex]::Replace($updatedStateYamlText, '(?m)^next_action:\s*.*$', "next_action: $NextAction")
    $updatedStateYamlText = [regex]::Replace($updatedStateYamlText, "(?m)^updated_at:\s*'.*'$", "updated_at: '$timestampText'")
    Set-Content -Path $stateFilePath -Value $updatedStateYamlText -Encoding UTF8
}

Write-Output "复杂并存汇报骨架已写入：$taskDirectoryPath"
Write-Output "主状态：$PrimaryStatus"
Write-Output "下一步：$NextAction"
Write-Output "规则入口：$ruleGuideRelativePath"
Write-Output "骨架模板：$templateGuideRelativePath"
Write-Output "治理复核：$governanceGuideRelativePath"
