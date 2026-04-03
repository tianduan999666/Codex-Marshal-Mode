param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Title,
    [string]$Goal = '',
    [string]$Slug = '',
    [string]$RepoRootPath = '',
    [string]$PhaseHint = 'user_task',
    [ValidateSet('trial', 'target')]
    [string]$TaskNamespace = 'target',
    [ValidateSet('low', 'medium', 'high', 'critical')]
    [string]$RiskLevel = 'low',
    [switch]$NoSetActiveTask,
    [switch]$PanelMode
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..'
}
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
$createTaskScriptPath = Join-Path $resolvedRepoRootPath '.codex\chancellor\create-task-package.ps1'
$tasksRootPath = Join-Path $resolvedRepoRootPath '.codex\chancellor\tasks'
$activeTaskFilePath = Join-Path $resolvedRepoRootPath '.codex\chancellor\active-task.txt'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlyNewTask {
    param(
        [string]$Summary,
        [string]$Detail,
        [string[]]$NextSteps = @()
    )

    Write-Host ''
    Write-Host "[ERROR] $Summary" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原始错误：{0}" -f $Detail)
    }

    foreach ($nextStep in $NextSteps) {
        Write-Info $nextStep
    }

    exit 1
}

function Invoke-NewTaskStep {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments = @{},
        [string]$Summary,
        [string[]]$NextSteps = @()
    )

    $global:LASTEXITCODE = 0
    try {
        & $ScriptPath @Arguments
    }
    catch {
        Stop-FriendlyNewTask `
            -Summary $Summary `
            -Detail $_.Exception.Message.Trim() `
            -NextSteps $NextSteps
    }

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function ConvertTo-TaskSlug {
    param([string]$Text)

    $value = ($Text | ForEach-Object { $_.Trim() })
    if ([string]::IsNullOrWhiteSpace($value)) {
        return ''
    }

    $value = $value.ToLowerInvariant()
    $value = [regex]::Replace($value, '[<>:"/\\|?*]+', ' ')
    $value = [regex]::Replace($value, '[\p{P}\p{S}]+', ' ')
    $value = [regex]::Replace($value, '\s+', '-')
    $value = [regex]::Replace($value, '-{2,}', '-')
    $value = $value.Trim('-')

    if ([string]::IsNullOrWhiteSpace($value)) {
        return 'task-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    }

    return $value
}

function Get-NextTaskNumber {
    param(
        [string]$TasksRoot,
        [string]$TaskNamespace
    )

    if (-not (Test-Path $TasksRoot)) {
        return 1
    }

    $taskPattern = '^v4-{0}-(\d{{3}})-.+$' -f [regex]::Escape($TaskNamespace)
    $numbers = @(
        Get-ChildItem -Path $TasksRoot -Directory |
            ForEach-Object {
                if ($_.Name -match $taskPattern) {
                    [int]$Matches[1]
                }
            }
    )

    if ($numbers.Count -eq 0) {
        return 1
    }

    return (($numbers | Measure-Object -Maximum).Maximum + 1)
}

if (-not (Test-Path $createTaskScriptPath)) {
    Stop-FriendlyNewTask `
        -Summary '当前无法创建任务包，因为起包脚手架不在仓里。' `
        -Detail ("缺少起包脚手架：{0}" -f $createTaskScriptPath) `
        -NextSteps @(
            '先确认你是在完整仓库根目录发起当前动作。',
            '如果刚做过清理、切分支或拷文件，先把 `.codex\chancellor\create-task-package.ps1` 补齐后再重试。'
        )
}

$resolvedSlug = ConvertTo-TaskSlug -Text $(if ([string]::IsNullOrWhiteSpace($Slug)) { $Title } else { $Slug })
$taskNumber = Get-NextTaskNumber -TasksRoot $tasksRootPath -TaskNamespace $TaskNamespace
$taskId = 'v4-{0}-{1:000}-{2}' -f $TaskNamespace, $taskNumber, $resolvedSlug
$resolvedGoal = $Goal
if ([string]::IsNullOrWhiteSpace($resolvedGoal)) {
    $resolvedGoal = ('围绕“{0}”完成当前轮最小闭环推进' -f $Title)
}

$planningHint = ('先围绕“{0}”收敛最小可验证闭环，再决定是否扩步。' -f $Title)
$planStep = ('先确认“{0}”的直接瓶颈，并完成第一刀最小验证。' -f $Title)
$verifySignal = '已落盘当前任务的首轮结果、下一步与关键决策。'
$setActiveTask = -not $NoSetActiveTask.IsPresent

Write-Info "RepoRoot=$resolvedRepoRootPath"
Write-Info "TaskNamespace=$TaskNamespace"
Write-Info "TaskId=$taskId"

Invoke-NewTaskStep `
    -ScriptPath $createTaskScriptPath `
    -Arguments @{
        TaskId = $taskId
        Title = $Title
        Goal = $resolvedGoal
        PhaseHint = $PhaseHint
        PlanningHint = $planningHint
        PlanStep = $planStep
        VerifySignal = $verifySignal
        InitialStatus = 'running'
        RiskLevel = $RiskLevel
        SetActiveTask = $setActiveTask
    } `
    -Summary '任务包创建到一半停住了。' `
    -NextSteps @(
        '先不要继续新开任务。',
        '先核对任务目录和 `active-task.txt` 有没有留下半截结果，确认后再重试当前入口。',
        '如果问题来自模板或字段校验，先修正脚手架再重新创建。'
    )

$taskDirectoryPath = Join-Path $tasksRootPath $taskId

Write-Host ''
Write-Ok '新任务已创建。'
Write-Output ('- 任务命名空间：{0}' -f $TaskNamespace)
Write-Output ('- 任务编号：{0}' -f $taskId)
Write-Output ('- 任务目录：{0}' -f $taskDirectoryPath)
Write-Output ('- 当前标题：{0}' -f $Title)
if ($setActiveTask) {
    Write-Output ('- 激活任务：已写入 {0}' -f $activeTaskFilePath)
}
else {
    Write-Output '- 激活任务：未切换（已按要求保留原 active-task.txt）'
}
Write-Host ''
if ($PanelMode) {
    Write-Output '下一步（无需切到 PowerShell）：'
    Write-Output '1. 留在当前官方 Codex 面板会话。'
    Write-Output '2. 直接判断瓶颈，给出最小可验证推进点，然后开始。'
}
else {
    Write-Output '下一步（维护层动作已完成后，回到官方 Codex 面板即可）：'
    Write-Output '1. 打开官方 Codex 面板，新开一个会话。'
    Write-Output '2. 直接粘贴下面这段话：'
    Write-Host ''
    Write-Host '传令：当前任务已创建。' -ForegroundColor Yellow
    Write-Host ('任务编号：{0}' -f $taskId) -ForegroundColor Yellow
    Write-Host ('任务标题：{0}' -f $Title) -ForegroundColor Yellow
    Write-Host '请先判断瓶颈，给出最小可验证推进点，然后直接开始。' -ForegroundColor Yellow
}
