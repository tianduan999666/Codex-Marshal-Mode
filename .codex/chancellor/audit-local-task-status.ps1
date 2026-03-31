param(
    [switch]$AsJson
)

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$tasksRootPath = Join-Path $scriptRootPath 'tasks'
$activeTaskFilePath = Join-Path $scriptRootPath 'active-task.txt'
$canonicalStatuses = @(
    'drafting',
    'ready',
    'running',
    'waiting_gate',
    'waiting_assist',
    'verifying',
    'done',
    'paused',
    'ready_to_resume'
)
$terminalStatuses = @('done')
$attentionStatuses = @('waiting_assist', 'ready_to_resume')
$legacyStatuses = @('completed')

function Get-YamlScalarValue {
    param(
        [string[]]$Lines,
        [string]$Key
    )

    $pattern = '^{0}:\s*(.+)$' -f [regex]::Escape($Key)
    $match = $Lines | Select-String -Pattern $pattern | Select-Object -First 1
    if (-not $match) {
        return $null
    }

    $value = $match.Matches[0].Groups[1].Value.Trim()
    if ($value -match "^'(.*)'$") {
        return $Matches[1]
    }

    if ($value -match '^"(.*)"$') {
        return $Matches[1]
    }

    return $value
}

function Get-TaskState {
    param(
        [System.IO.DirectoryInfo]$TaskDirectory
    )

    $stateFilePath = Join-Path $TaskDirectory.FullName 'state.yaml'
    if (-not (Test-Path $stateFilePath)) {
        return [pscustomobject]@{
            TaskId       = $TaskDirectory.Name
            Status       = '<missing-state-file>'
            UpdatedAt    = $null
            RiskLevel    = $null
            NextAction   = '缺少 state.yaml，请人工补齐'
            BlockedBy    = $null
            PhaseHint    = $null
            StateFilePath = $stateFilePath
        }
    }

    $lines = Get-Content $stateFilePath
    $taskId = Get-YamlScalarValue -Lines $lines -Key 'task_id'
    if (-not $taskId) {
        $taskId = $TaskDirectory.Name
    }

    return [pscustomobject]@{
        TaskId       = $taskId
        Status       = Get-YamlScalarValue -Lines $lines -Key 'status'
        UpdatedAt    = Get-YamlScalarValue -Lines $lines -Key 'updated_at'
        RiskLevel    = Get-YamlScalarValue -Lines $lines -Key 'risk_level'
        NextAction   = Get-YamlScalarValue -Lines $lines -Key 'next_action'
        BlockedBy    = Get-YamlScalarValue -Lines $lines -Key 'blocked_by'
        PhaseHint    = Get-YamlScalarValue -Lines $lines -Key 'phase_hint'
        StateFilePath = $stateFilePath
    }
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

if (-not (Test-Path $tasksRootPath)) {
    throw "任务目录不存在：$tasksRootPath"
}

$activeTaskId = ''
if (Test-Path $activeTaskFilePath) {
    $activeTaskId = ((Get-Content $activeTaskFilePath | Select-Object -First 1) | ForEach-Object { $_.Trim() })
}

$taskStates = Get-ChildItem $tasksRootPath -Directory | Sort-Object Name | ForEach-Object { Get-TaskState -TaskDirectory $_ }
$statusCounts = @(
    $taskStates |
        Group-Object Status |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                Status = $_.Name
                Count  = $_.Count
            }
        }
)
$nonTerminalTasks = @($taskStates | Where-Object { $_.Status -notin $terminalStatuses } | Sort-Object TaskId)
$nonStandardTasks = @($taskStates | Where-Object { $_.Status -and $_.Status -notin $canonicalStatuses } | Sort-Object TaskId)
$attentionTasks = @($taskStates | Where-Object {
    $_.TaskId -eq $activeTaskId -or
    $_.Status -in $attentionStatuses -or
    $_.Status -in $legacyStatuses
} | Sort-Object TaskId -Unique)
$activeTaskState = $null
if ($activeTaskId) {
    $activeTaskState = $taskStates | Where-Object { $_.TaskId -eq $activeTaskId } | Select-Object -First 1
}

$summary = [pscustomobject]@{
    AuditedAt        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    TaskRootPath     = $tasksRootPath
    ActiveTaskId     = $activeTaskId
    ActiveTaskStatus = if ($activeTaskState) { $activeTaskState.Status } else { '<missing-task>' }
    TaskCount        = $taskStates.Count
    StatusCounts     = $statusCounts
    NonTerminalTasks = $nonTerminalTasks
    NonStandardTasks = $nonStandardTasks
    AttentionTasks   = $attentionTasks
}

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 6
    return
}

Write-Output '=== 本地任务状态审计 ==='
Write-Output ('审计时间：{0}' -f $summary.AuditedAt)
Write-Output ('任务根目录：{0}' -f $summary.TaskRootPath)
Write-Output ('任务总数：{0}' -f $summary.TaskCount)
if ($activeTaskId) {
    Write-Output ('当前激活任务：{0}' -f $activeTaskId)
    Write-Output ('激活任务状态：{0}' -f $summary.ActiveTaskStatus)
}
else {
    Write-Output '当前激活任务：<empty>'
}

Write-Output ''
Write-Output '状态计数：'
foreach ($statusCount in $statusCounts) {
    Write-Output ('- {0}: {1}' -f $statusCount.Status, $statusCount.Count)
}

Write-Output ''
Write-TaskSection -Title '非终态任务' -Rows $nonTerminalTasks -PropertyNames @('TaskId', 'Status', 'UpdatedAt', 'NextAction')
Write-Output ''
Write-TaskSection -Title '非规范状态任务' -Rows $nonStandardTasks -PropertyNames @('TaskId', 'Status', 'UpdatedAt', 'NextAction')
Write-Output ''
Write-TaskSection -Title '建议优先人工关注' -Rows $attentionTasks -PropertyNames @('TaskId', 'Status', 'UpdatedAt', 'NextAction')

if ($nonStandardTasks.Count -gt 0) {
    Write-Output ''
    Write-Output '提示：存在未纳入现行标准集的状态，建议人工统一终态口径后再做最终收口。'
}

if ($activeTaskId -and -not $activeTaskState) {
    Write-Output ''
    Write-Output '提示：active-task.txt 指向的任务目录不存在，建议立即修正。'
}
