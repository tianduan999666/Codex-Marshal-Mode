param(
    [Parameter(Mandatory = $true)]
    [string]$ResultPath,
    [string]$TaskId = 'v4-trial-035-panel-acceptance-closeout',
    [string]$TasksRootPath = '',
    [string]$ActiveTaskFilePath = '',
    [string]$AuditReferenceTimeText = '',
    [switch]$SkipReview,
    [switch]$NormalizeTrial034ToDone
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$defaultTasksRootPath = Join-Path $scriptRootPath 'tasks'
$defaultActiveTaskFilePath = Join-Path $scriptRootPath 'active-task.txt'
$reviewScriptPath = Join-Path $scriptRootPath 'review-panel-acceptance-closeout.ps1'
$resolveScriptPath = Join-Path $scriptRootPath 'resolve-panel-acceptance-closeout.ps1'
$resolvedResultPath = [System.IO.Path]::GetFullPath($ResultPath)
$timestampText = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlyFinalizeCloseout {
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

function Get-BulletValue {
    param(
        [string]$Content,
        [string]$Label
    )

    $pattern = '(?m)^- ' + [regex]::Escape($Label) + '：[ \t]*(.*)$'
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        Stop-FriendlyFinalizeCloseout `
            -Summary '结果稿还没写完整，当前不能继续一键收口。' `
            -Detail ("结果稿缺少字段：{0}" -f $Label) `
            -NextSteps @(
                '先补齐结果稿里的固定字段。',
                '补完后再重新执行一键收口。'
            )
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

function Write-Utf8NoBomFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parentPath = Split-Path -Parent $Path
    if ($parentPath) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

if ([string]::IsNullOrWhiteSpace($TasksRootPath)) {
    $TasksRootPath = $defaultTasksRootPath
}
if ([string]::IsNullOrWhiteSpace($ActiveTaskFilePath)) {
    $ActiveTaskFilePath = $defaultActiveTaskFilePath
}
$tasksRootPath = [System.IO.Path]::GetFullPath($TasksRootPath)
$activeTaskFilePath = [System.IO.Path]::GetFullPath($ActiveTaskFilePath)

foreach ($requiredPath in @($reviewScriptPath, $resolveScriptPath, $resolvedResultPath)) {
    if (-not (Test-Path $requiredPath)) {
        Stop-FriendlyFinalizeCloseout `
            -Summary '一键收口所需文件不齐，当前不能继续。' `
            -Detail ("缺少一键收口所需文件：{0}" -f $requiredPath) `
            -NextSteps @(
                '先确认结果稿和维护脚本都在。',
                '补齐后再重新执行一键收口。'
            )
    }
}

$reviewParameters = @{
    ResultPath = $resolvedResultPath
}
if (-not [string]::IsNullOrWhiteSpace($TasksRootPath)) {
    $reviewParameters['TasksRootPath'] = $tasksRootPath
}
if (-not [string]::IsNullOrWhiteSpace($ActiveTaskFilePath)) {
    $reviewParameters['ActiveTaskFilePath'] = $ActiveTaskFilePath
}
if (-not [string]::IsNullOrWhiteSpace($AuditReferenceTimeText)) {
    $reviewParameters['AuditReferenceTimeText'] = $AuditReferenceTimeText
}
try {
    & $reviewScriptPath @reviewParameters
}
catch {
    Stop-FriendlyFinalizeCloseout `
        -Summary '结果稿复核没有通过，本次一键收口先停在这里。' `
        -Detail $_.Exception.Message `
        -NextSteps @(
            '先按上面的复核提示补齐结果稿或任务状态。',
            '确认复核通过后再重新执行一键收口。'
        )
}

$resolveParameters = @{
    ResultPath = $resolvedResultPath
    TaskId = $TaskId
}
if (-not [string]::IsNullOrWhiteSpace($TasksRootPath)) {
    $resolveParameters['TasksRootPath'] = $tasksRootPath
}
if (-not [string]::IsNullOrWhiteSpace($ActiveTaskFilePath)) {
    $resolveParameters['ActiveTaskFilePath'] = $ActiveTaskFilePath
}
if (-not [string]::IsNullOrWhiteSpace($AuditReferenceTimeText)) {
    $resolveParameters['AuditReferenceTimeText'] = $AuditReferenceTimeText
}
if ($SkipReview) {
    $resolveParameters['SkipReview'] = $true
}
try {
    & $resolveScriptPath @resolveParameters
}
catch {
    Stop-FriendlyFinalizeCloseout `
        -Summary '结果回写没有完成，本次一键收口先停在这里。' `
        -Detail $_.Exception.Message `
        -NextSteps @(
            '先按上面的提示处理回写阻塞项。',
            '处理完成后再重新执行一键收口。'
        )
}

$resultContent = [System.IO.File]::ReadAllText($resolvedResultPath)
$finalResult = Get-BulletValue -Content $resultContent -Label '人工验板最终结果'
$nextAction = Get-BulletValue -Content $resultContent -Label '下一步'

if ($NormalizeTrial034ToDone) {
    if ($finalResult -ne '通过') {
        Stop-FriendlyFinalizeCloseout `
            -Summary '当前还不能归一化 v4-trial-034。' `
            -Detail '只有人工验板结果为“通过”时，才可归一化 v4-trial-034 为 done。' `
            -NextSteps @(
                '先确认真实人工验板最终结果已经写成“通过”。',
                '确认通过后再带上 -NormalizeTrial034ToDone 重试。'
            )
    }

    $trial034TaskId = 'v4-trial-034-public-rule-order-gate'
    $trial034TaskDirectoryPath = Join-Path $tasksRootPath $trial034TaskId
    $trial034StateFilePath = Join-Path $trial034TaskDirectoryPath 'state.yaml'
    $trial034ResultFilePath = Join-Path $trial034TaskDirectoryPath 'result.md'
    $trial034DecisionLogFilePath = Join-Path $trial034TaskDirectoryPath 'decision-log.md'

    foreach ($requiredPath in @($trial034TaskDirectoryPath, $trial034StateFilePath, $trial034ResultFilePath, $trial034DecisionLogFilePath)) {
        if (-not (Test-Path $requiredPath)) {
            Stop-FriendlyFinalizeCloseout `
                -Summary 'v4-trial-034 的归一化资料不齐，当前不能继续。' `
                -Detail ("缺少归一化 v4-trial-034 所需文件：{0}" -f $requiredPath) `
                -NextSteps @(
                    '先补齐 v4-trial-034 对应的任务文件。',
                    '补齐后再重新执行归一化。'
                )
        }
    }

    $trial034StateText = Get-Content -Raw $trial034StateFilePath
    $trial034CurrentStatusMatch = [regex]::Match($trial034StateText, '(?m)^status:\s*(.+)$')
    if (-not $trial034CurrentStatusMatch.Success) {
        Stop-FriendlyFinalizeCloseout `
            -Summary 'v4-trial-034 的状态文件不完整，当前不能归一化。' `
            -Detail 'v4-trial-034 缺少 status 字段。' `
            -NextSteps @(
                '先补齐 state.yaml 里的 status 字段。',
                '补完后再重新执行归一化。'
            )
    }

    $trial034CurrentStatus = $trial034CurrentStatusMatch.Groups[1].Value.Trim()
    if ($trial034CurrentStatus -eq 'completed') {
        $trial034StateText = Set-YamlField -YamlText $trial034StateText -Key 'status' -ValueLiteral 'done'
        $trial034StateText = Set-YamlField -YamlText $trial034StateText -Key 'next_action' -ValueLiteral (ConvertTo-YamlSingleQuotedText -Text '已按主公拍板将 completed 统一归一为 done，后续进入最终总收口。')
        $trial034StateText = Set-YamlField -YamlText $trial034StateText -Key 'updated_at' -ValueLiteral (ConvertTo-YamlSingleQuotedText -Text $timestampText)
        $trial034StateText = Set-YamlField -YamlText $trial034StateText -Key 'plan_step' -ValueLiteral (ConvertTo-YamlSingleQuotedText -Text '主公已拍板将 v4-trial-034 的 completed 统一归一为 done。')
        $trial034StateText = Set-YamlField -YamlText $trial034StateText -Key 'verify_signal' -ValueLiteral (ConvertTo-YamlSingleQuotedText -Text '原验证信号保持有效，状态口径已按主公拍板统一为 done。')
        Set-Content -Path $trial034StateFilePath -Value $trial034StateText -Encoding UTF8

        $trial034ResultAppendText = @"

## 状态归一化回写（$timestampText）

- 决策：按主公拍板，将 `completed` 统一归一为 `done`
- 原因：避免最终总收口时继续保留非规范终态口径
- 影响：`v4-trial-034` 当前统一按已完成任务参与后续总收口
"@
        Add-Content -Path $trial034ResultFilePath -Value $trial034ResultAppendText -Encoding UTF8

        $trial034DecisionAppendText = @"

## $timestampText

- 决策：将 v4-trial-034 的状态从 completed 归一为 done
- 原因：主公已拍板统一终态口径，减少最终总收口时的重复解释
- 证据：真实人工验板已通过，且当前唯一剩余拍板项为 v4-trial-034 的终态口径
- 影响：v4-trial-034 后续按 done 参与总收口
"@
        Add-Content -Path $trial034DecisionLogFilePath -Value $trial034DecisionAppendText -Encoding UTF8

        Write-Ok '已按主公拍板归一化 v4-trial-034：completed -> done'
    }
    elseif ($trial034CurrentStatus -eq 'done') {
        Write-Info 'v4-trial-034 当前已是 done，无需重复归一化。'
    }
    else {
        Stop-FriendlyFinalizeCloseout `
            -Summary 'v4-trial-034 的当前状态不适合自动归一化。' `
            -Detail ("v4-trial-034 当前状态不是 completed/done，无法自动归一化：{0}" -f $trial034CurrentStatus) `
            -NextSteps @(
                '先人工确认 v4-trial-034 的真实状态。',
                '确认后再决定是手动修正还是重新执行归一化。'
            )
    }
}

$currentActiveTaskId = ''
if (Test-Path $activeTaskFilePath) {
    $currentActiveTaskId = ((Get-Content $activeTaskFilePath | Select-Object -First 1) | ForEach-Object { $_.Trim() })
}

if ($finalResult -eq '通过' -and $currentActiveTaskId -eq $TaskId) {
    Write-Utf8NoBomFile -Path $activeTaskFilePath -Content ''
    Write-Ok '已清空 active-task.txt，避免继续指向已完成任务。'
}

Write-Info "ResultPath=$resolvedResultPath"
Write-Info "TaskId=$TaskId"
Write-Info "FinalResult=$finalResult"
if ($finalResult -eq '通过') {
    Write-Ok '一键收口已完成：真实人工验板结果已复核并回写到本地任务包。'
    if ($NormalizeTrial034ToDone) {
        Write-Info '下一步：v4-trial-035 与 v4-trial-034 已准备就绪，可继续推进最终总收口。'
    }
    else {
        Write-Info '下一步：若主公已拍板 v4-trial-034，可继续推进最终总收口。'
    }
}
else {
    Write-Ok '一键收口已完成：结果稿已复核并回写到本地任务包当前状态。'
    Write-Info ('下一步：按结果稿继续处理 -> {0}' -f $nextAction)
}
