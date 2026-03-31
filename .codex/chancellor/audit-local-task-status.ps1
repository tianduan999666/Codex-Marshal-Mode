param(
    [switch]$AsJson,
    [int]$StaleAfterDays = 2
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

function ConvertTo-NullableDateTime {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $parsedDateTime = [datetime]::MinValue
    if ([datetime]::TryParseExact(
        $Text,
        'yyyy-MM-dd HH:mm:ss',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsedDateTime
    )) {
        return $parsedDateTime
    }

    if ([datetime]::TryParse($Text, [ref]$parsedDateTime)) {
        return $parsedDateTime
    }

    return $null
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

    $updatedAtText = Get-YamlScalarValue -Lines $lines -Key 'updated_at'
    $updatedAtDateTime = ConvertTo-NullableDateTime -Text $updatedAtText

    return [pscustomobject]@{
        TaskId       = $taskId
        Status       = Get-YamlScalarValue -Lines $lines -Key 'status'
        UpdatedAt    = $updatedAtText
        UpdatedAtDateTime = $updatedAtDateTime
        IdleDays     = if ($updatedAtDateTime) { [math]::Floor(($script:auditReferenceTime - $updatedAtDateTime).TotalDays) } else { $null }
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

$script:auditReferenceTime = Get-Date

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
$staleTasks = @(
    $nonTerminalTasks |
        Where-Object { $_.IdleDays -ne $null -and $_.IdleDays -ge $StaleAfterDays } |
        Sort-Object -Property @(
            @{ Expression = 'IdleDays'; Descending = $true },
            @{ Expression = 'TaskId'; Descending = $false }
        )
)
$attentionTasks = @($taskStates | Where-Object {
    $_.TaskId -eq $activeTaskId -or
    $_.Status -in $attentionStatuses -or
    $_.Status -in $legacyStatuses
} | Sort-Object TaskId -Unique)
$rulerDecisionTasks = @(
    $taskStates |
        Where-Object {
            $_.Status -eq 'waiting_assist' -or
            $_.Status -in $legacyStatuses
        } |
        Sort-Object TaskId |
        Select-Object -Property @(
            'TaskId',
            'Status',
            'UpdatedAt',
            'IdleDays',
            @{ Name = 'Reason'; Expression = {
                if ($_.Status -eq 'waiting_assist') {
                    '需要主公在官方面板执行真实人工验板'
                }
                elseif ($_.Status -in $legacyStatuses) {
                    '需要主公拍板是否统一把 legacy 状态收为 done'
                }
                else {
                    '需要主公确认下一步'
                }
            } },
            'NextAction'
        )
)
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
    StaleAfterDays   = $StaleAfterDays
    StatusCounts     = $statusCounts
    NonTerminalTasks = $nonTerminalTasks
    NonStandardTasks = $nonStandardTasks
    StaleTasks       = $staleTasks
    AttentionTasks   = $attentionTasks
    RulerDecisionTasks = $rulerDecisionTasks
}

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 6
    return
}

Write-Output '=== 本地任务状态审计 ==='
Write-Output ('审计时间：{0}' -f $summary.AuditedAt)
Write-Output ('任务根目录：{0}' -f $summary.TaskRootPath)
Write-Output ('任务总数：{0}' -f $summary.TaskCount)
Write-Output ('陈旧阈值：非终态任务 >= {0} 天未更新' -f $summary.StaleAfterDays)
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
Write-TaskSection -Title '非终态任务' -Rows $nonTerminalTasks -PropertyNames @('TaskId', 'Status', 'UpdatedAt', 'IdleDays', 'NextAction')
Write-Output ''
Write-TaskSection -Title '非规范状态任务' -Rows $nonStandardTasks -PropertyNames @('TaskId', 'Status', 'UpdatedAt', 'NextAction')
Write-Output ''
Write-TaskSection -Title '陈旧非终态任务' -Rows $staleTasks -PropertyNames @('TaskId', 'Status', 'UpdatedAt', 'IdleDays', 'NextAction')
Write-Output ''
Write-TaskSection -Title '建议优先人工关注' -Rows $attentionTasks -PropertyNames @('TaskId', 'Status', 'UpdatedAt', 'NextAction')
Write-Output ''
Write-TaskSection -Title '建议主公拍板' -Rows $rulerDecisionTasks -PropertyNames @('TaskId', 'Status', 'UpdatedAt', 'IdleDays', 'Reason', 'NextAction')

if ($nonStandardTasks.Count -gt 0) {
    Write-Output ''
    Write-Output '提示：存在未纳入现行标准集的状态，建议人工统一终态口径后再做最终收口。'
}

if ($staleTasks.Count -gt 0) {
    Write-Output ''
    Write-Output '提示：存在长时间未更新的非终态任务，建议先确认它们是否仍应保持运行态。'
}

if ($activeTaskId -and -not $activeTaskState) {
    Write-Output ''
    Write-Output '提示：active-task.txt 指向的任务目录不存在，建议立即修正。'
}
