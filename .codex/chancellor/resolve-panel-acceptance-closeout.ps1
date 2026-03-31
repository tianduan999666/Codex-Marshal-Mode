param(
    [Parameter(Mandatory = $true)]
    [string]$ResultPath,
    [string]$TaskId = 'v4-trial-035-panel-acceptance-closeout',
    [string]$TasksRootPath = '',
    [string]$ActiveTaskFilePath = '',
    [string]$AuditReferenceTimeText = '',
    [switch]$SkipReview
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRootPath = Split-Path -Parent (Split-Path -Parent $scriptRootPath)
$defaultTasksRootPath = Join-Path $scriptRootPath 'tasks'
$defaultActiveTaskFilePath = Join-Path $scriptRootPath 'active-task.txt'
$reviewScriptPath = Join-Path $scriptRootPath 'review-panel-acceptance-closeout.ps1'
$verifyScriptPath = Join-Path (Join-Path $repoRootPath 'codex-home-export') 'verify-panel-acceptance-result.ps1'
$resolvedResultPath = [System.IO.Path]::GetFullPath($ResultPath)
$timestampText = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$closeoutGuideRelativePath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'

if ([string]::IsNullOrWhiteSpace($TasksRootPath)) {
    $TasksRootPath = $defaultTasksRootPath
}
if ([string]::IsNullOrWhiteSpace($ActiveTaskFilePath)) {
    $ActiveTaskFilePath = $defaultActiveTaskFilePath
}

$tasksRootPath = [System.IO.Path]::GetFullPath($TasksRootPath)
$activeTaskFilePath = [System.IO.Path]::GetFullPath($ActiveTaskFilePath)
$taskDirectoryPath = Join-Path $tasksRootPath $TaskId
$stateFilePath = Join-Path $taskDirectoryPath 'state.yaml'
$resultFilePath = Join-Path $taskDirectoryPath 'result.md'
$decisionLogFilePath = Join-Path $taskDirectoryPath 'decision-log.md'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Get-BulletValue {
    param(
        [string]$Content,
        [string]$Label
    )

    $pattern = '(?m)^- ' + [regex]::Escape($Label) + '：[ \t]*(.*)$'
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        throw "结果稿缺少字段：$Label"
    }

    return $match.Groups[1].Value.Trim()
}

function ConvertTo-YamlSingleQuotedText {
    param([string]$Text)

    if ($null -eq $Text) {
        $Text = ''
    }

    return "'" + ($Text -replace "'", "''") + "'"
}

function Set-YamlField {
    param(
        [string]$YamlText,
        [string]$Key,
        [string]$ValueLiteral
    )

    $pattern = '(?m)^' + [regex]::Escape($Key) + ':\s*.*$'
    if ([regex]::IsMatch($YamlText, $pattern)) {
        return [regex]::Replace($YamlText, $pattern, ("{0}: {1}" -f $Key, $ValueLiteral), 1)
    }

    return ($YamlText.TrimEnd() + [Environment]::NewLine + ("{0}: {1}" -f $Key, $ValueLiteral) + [Environment]::NewLine)
}

foreach ($requiredPath in @($taskDirectoryPath, $stateFilePath, $resultFilePath, $decisionLogFilePath, $resolvedResultPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少回写所需文件：$requiredPath"
    }
}

if ($SkipReview) {
    & $verifyScriptPath -ResultPath $resolvedResultPath
}
else {
    $reviewParameters = @{
        ResultPath = $resolvedResultPath
    }
    if (-not [string]::IsNullOrWhiteSpace($TasksRootPath)) {
        $reviewParameters['TasksRootPath'] = $TasksRootPath
    }
    if (-not [string]::IsNullOrWhiteSpace($ActiveTaskFilePath)) {
        $reviewParameters['ActiveTaskFilePath'] = $ActiveTaskFilePath
    }
    if (-not [string]::IsNullOrWhiteSpace($AuditReferenceTimeText)) {
        $reviewParameters['AuditReferenceTimeText'] = $AuditReferenceTimeText
    }

    & $reviewScriptPath @reviewParameters
}

$resultContent = [System.IO.File]::ReadAllText($resolvedResultPath)
$executor = Get-BulletValue -Content $resultContent -Label '执行人'
$autoVerifyResult = Get-BulletValue -Content $resultContent -Label '自动验板结果'
$finalResult = Get-BulletValue -Content $resultContent -Label '人工验板最终结果'
$needRollback = Get-BulletValue -Content $resultContent -Label '是否需要回退'
$needFollowup = Get-BulletValue -Content $resultContent -Label '是否需要补刀'
$minimumGap = Get-BulletValue -Content $resultContent -Label '若不通过，最小缺口是'
$nextActionFromResult = Get-BulletValue -Content $resultContent -Label '下一步'

if ($finalResult -eq '通过') {
    $nextStatus = 'done'
    $nextAction = '基于真实人工验板结果，推进剩余非终态任务最终收口。'
    $legacyText = '- 无'
    $planStep = '真实人工验板已通过并回写到本地任务包。'
    $verifySignal = '结果稿已通过 verify-panel-acceptance-result.ps1 与 review-panel-acceptance-closeout.ps1，人工验板结论为通过。'
    $nextStepLines = @(
        '- 若主公已拍板 `v4-trial-034`，可继续统一收口剩余非终态任务。'
        '- 若 `active-task.txt` 仍指向当前任务，收口后按新主线更新。'
    )
    $planningStatusLine = '- 当前最小推进步是否完成：是；真实人工验板结果已回写。'
    $routeLine = '- 下一轮是否需要改路：否；进入最终总收口阶段。'
    $driftLine = '- 当前是否发现口径漂移：当前未发现新的公开口径漂移。'
}
else {
    $nextStatus = 'ready_to_resume'
    $nextAction = $nextActionFromResult
    $legacyText = @(
        '- 已获得真实人工验板结果，但当前仍需按最小缺口补刀后重新验板。'
        ('- 最小缺口：{0}' -f $minimumGap)
    ) -join [Environment]::NewLine
    $planStep = '真实人工验板结果已回写，当前按最小缺口补刀后重新验板。'
    $verifySignal = '结果稿已通过 verify-panel-acceptance-result.ps1 与 review-panel-acceptance-closeout.ps1，但人工验板结论为不通过。'
    $nextStepLines = @(
        ('- 先按结果稿下一步处理：{0}' -f $nextActionFromResult)
        '- 补齐最小缺口后，重新执行一次人工验板。'
    )
    $planningStatusLine = '- 当前最小推进步是否完成：否；仍需按最小缺口补刀后重新验板。'
    $routeLine = '- 下一轮是否需要改路：否；先按最小缺口回归。'
    $driftLine = '- 当前是否发现口径漂移：已发现人工验板最小缺口，待补齐后回归。'
}

$stateYamlText = Get-Content -Raw $stateFilePath
$stateYamlText = Set-YamlField -YamlText $stateYamlText -Key 'status' -ValueLiteral $nextStatus
$stateYamlText = Set-YamlField -YamlText $stateYamlText -Key 'next_action' -ValueLiteral (ConvertTo-YamlSingleQuotedText -Text $nextAction)
$stateYamlText = Set-YamlField -YamlText $stateYamlText -Key 'blocked_by' -ValueLiteral '[]'
$stateYamlText = Set-YamlField -YamlText $stateYamlText -Key 'updated_at' -ValueLiteral (ConvertTo-YamlSingleQuotedText -Text $timestampText)
$stateYamlText = Set-YamlField -YamlText $stateYamlText -Key 'plan_step' -ValueLiteral (ConvertTo-YamlSingleQuotedText -Text $planStep)
$stateYamlText = Set-YamlField -YamlText $stateYamlText -Key 'verify_signal' -ValueLiteral (ConvertTo-YamlSingleQuotedText -Text $verifySignal)
Set-Content -Path $stateFilePath -Value $stateYamlText -Encoding UTF8

$nextStepText = $nextStepLines -join [Environment]::NewLine
$resultSummaryText = @"
# 结果摘要

## 已完成

- 已创建任务包骨架。
- 已把人工验板公开准备链收敛为一键准备、三步入口、打勾判断、结果留痕、结果复核与完整清单。
- 已完成真实人工验板结果稿复核与维护层收口联动复盘。
- 已将真实人工验板结果回写到当前任务包。

## 验证证据

- 目录：.codex/chancellor/tasks/$TaskId/
- 结果稿：$resolvedResultPath
- 结果复核入口：codex-home-export/verify-panel-acceptance-result.ps1
- 收口联动入口：.codex/chancellor/review-panel-acceptance-closeout.ps1
"@

$resultSummaryText += @"
- 自动验板结果：$autoVerifyResult
- 人工验板最终结果：$finalResult
- 是否需要回退：$needRollback
- 是否需要补刀：$needFollowup
- 收口参考：$closeoutGuideRelativePath

## 遗留事项

$legacyText

## 下一步建议

$nextStepText

## 规划复核

- 当前主假设是否成立：成立；当前公开侧准备件已拿到真实人工验板结果。
$planningStatusLine
$routeLine

## 治理复核

- 当前关键口径来源是否已说明：已说明。
- 当前关键输出是否可追溯：可追溯。
$driftLine
- 公开仓边界是否已复核：已复核，运行态继续只留本地。
"@
Set-Content -Path $resultFilePath -Value $resultSummaryText -Encoding UTF8

$decisionLogAppendText = @"

## $timestampText

- 决策：回写真实人工验板结果到任务包
- 结果：$finalResult
- 证据：结果稿 $resolvedResultPath 已通过 verify-panel-acceptance-result.ps1 与 review-panel-acceptance-closeout.ps1
"@
$decisionLogAppendText += @"
- 影响：任务状态切换为 $nextStatus，下一步为 $nextAction
- 执行人：$executor
- 治理提示：提交前应确认本地任务状态、结果稿结论与后续动作已经统一。
"@
Add-Content -Path $decisionLogFilePath -Value $decisionLogAppendText -Encoding UTF8

Write-Info "ResultPath=$resolvedResultPath"
Write-Info "TaskDirectory=$taskDirectoryPath"
Write-Info "FinalResult=$finalResult"
Write-Ok "已完成本地任务包回写：$TaskId -> $nextStatus"
if (Test-Path $activeTaskFilePath) {
    $activeTaskId = ((Get-Content $activeTaskFilePath | Select-Object -First 1) | ForEach-Object { $_.Trim() })
    if ($activeTaskId -eq $TaskId -and $nextStatus -eq 'done') {
        Write-Info '提示：active-task.txt 仍指向已完成任务，后续可按新主线更新。'
    }
}
