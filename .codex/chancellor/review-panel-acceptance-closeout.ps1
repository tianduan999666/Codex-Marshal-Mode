param(
    [Parameter(Mandatory = $true)]
    [string]$ResultPath,
    [string]$TasksRootPath = '',
    [string]$ActiveTaskFilePath = '',
    [string]$AuditReferenceTimeText = ''
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRootPath = Split-Path -Parent (Split-Path -Parent $scriptRootPath)
$verifyScriptPath = Join-Path (Join-Path $repoRootPath 'codex-home-export') 'verify-panel-acceptance-result.ps1'
$auditScriptPath = Join-Path $scriptRootPath 'audit-local-task-status.ps1'
$resolvedResultPath = [System.IO.Path]::GetFullPath($ResultPath)

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
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

function Write-TaskSection {
    param(
        [string]$Title,
        [object[]]$Rows,
        [string[]]$PropertyNames
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        Write-Output ('{0}：无' -f $Title)
        return
    }

    Write-Output ('{0}：' -f $Title)
    ($Rows | Select-Object -Property $PropertyNames | Format-Table -AutoSize | Out-String).TrimEnd() | Write-Output
}

foreach ($requiredPath in @($verifyScriptPath, $auditScriptPath, $resolvedResultPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少收口联动所需文件：$requiredPath"
    }
}

& $verifyScriptPath -ResultPath $resolvedResultPath

$resultContent = [System.IO.File]::ReadAllText($resolvedResultPath)
$finalResult = Get-BulletValue -Content $resultContent -Label '人工验板最终结果'
$needRollback = Get-BulletValue -Content $resultContent -Label '是否需要回退'
$needFollowup = Get-BulletValue -Content $resultContent -Label '是否需要补刀'
$nextAction = Get-BulletValue -Content $resultContent -Label '下一步'
$minimumGap = Get-BulletValue -Content $resultContent -Label '若不通过，最小缺口是'

$auditParameters = @{
    AsJson = $true
}
if (-not [string]::IsNullOrWhiteSpace($TasksRootPath)) {
    $auditParameters['TasksRootPath'] = $TasksRootPath
}
if (-not [string]::IsNullOrWhiteSpace($ActiveTaskFilePath)) {
    $auditParameters['ActiveTaskFilePath'] = $ActiveTaskFilePath
}
if (-not [string]::IsNullOrWhiteSpace($AuditReferenceTimeText)) {
    $auditParameters['AuditReferenceTimeText'] = $AuditReferenceTimeText
}

$auditSummary = & $auditScriptPath @auditParameters | ConvertFrom-Json
$nonTerminalTasks = @($auditSummary.NonTerminalTasks)
$nonStandardTasks = @($auditSummary.NonStandardTasks)
$staleTasks = @($auditSummary.StaleTasks)
$rulerDecisionTasks = @($auditSummary.RulerDecisionTasks)
$activeTaskId = [string]$auditSummary.ActiveTaskId
$activeTaskStatus = [string]$auditSummary.ActiveTaskStatus
$effectiveRulerDecisionTasks = @($rulerDecisionTasks)
if ($finalResult -eq '通过' -and $activeTaskId -eq 'v4-trial-035-panel-acceptance-closeout') {
    $effectiveRulerDecisionTasks = @(
        $rulerDecisionTasks | Where-Object { $_.TaskId -ne 'v4-trial-035-panel-acceptance-closeout' }
    )
}

Write-Output ''
Write-Output '=== 面板人工验板收口联动复盘 ==='
Write-Output ('结果稿：{0}' -f $resolvedResultPath)
Write-Output ('人工验板结论：{0}' -f $finalResult)
Write-Output ('当前激活任务：{0}' -f $activeTaskId)
Write-Output ('激活任务状态：{0}' -f $activeTaskStatus)
Write-Output ('剩余非终态任务数：{0}' -f $nonTerminalTasks.Count)
Write-Output ('建议主公拍板项数：{0}' -f $effectiveRulerDecisionTasks.Count)

Write-Output ''
Write-TaskSection -Title '建议主公拍板' -Rows $effectiveRulerDecisionTasks -PropertyNames @('TaskId', 'Status', 'Reason', 'NextAction')
Write-Output ''
Write-TaskSection -Title '陈旧非终态任务' -Rows $staleTasks -PropertyNames @('TaskId', 'Status', 'IdleDays', 'NextAction')
Write-Output ''
Write-TaskSection -Title '非规范状态任务' -Rows $nonStandardTasks -PropertyNames @('TaskId', 'Status', 'UpdatedAt', 'NextAction')
Write-Output ''

if ($finalResult -eq '通过') {
    Write-Ok '人工验板真实阻塞已解除，可进入维护层统一收口阶段。'
    if ($activeTaskId -eq 'v4-trial-035-panel-acceptance-closeout' -and $activeTaskStatus -eq 'waiting_assist') {
        Write-Info '建议动作：先回写 v4-trial-035 的真实验板证据，再推进最终状态收口。'
    }

    if ($effectiveRulerDecisionTasks.Count -gt 0) {
        Write-WarnLine '当前仍有主公拍板项未清空，最终收口前请先定口径。'
    }
    else {
        Write-Ok '当前未发现额外主公拍板项，可直接进入剩余非终态任务收口。'
    }

    Write-Info ('建议下一步：依据结果稿与审计清单，优先处理 {0} 个剩余非终态任务。' -f $nonTerminalTasks.Count)
}
else {
    Write-WarnLine '人工验板尚未通过，当前不能按通过态收口。'
    if (-not [string]::IsNullOrWhiteSpace($minimumGap)) {
        Write-WarnLine ('最小缺口：{0}' -f $minimumGap)
    }

    if ($needRollback -eq '是') {
        Write-WarnLine '建议动作：先执行 verify-cutover.ps1，仍异常再执行 rollback-from-backup.ps1。'
    }
    elseif ($needFollowup -eq '是') {
        Write-Info '建议动作：先补最小缺口，再重新执行一次人工验板。'
    }

    Write-Info ('结果稿下一步：{0}' -f $nextAction)
}
