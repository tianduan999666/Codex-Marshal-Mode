param(
    [Parameter(Mandatory = $true)]
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
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

if (-not (Test-Path $resolvedResultPath)) {
    throw "结果稿不存在：$resolvedResultPath"
}

$content = [System.IO.File]::ReadAllText($resolvedResultPath)

function Get-BulletValue([string]$Label) {
    $pattern = '(?m)^- ' + [regex]::Escape($Label) + '：[ \t]*(.*)$'
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) {
        throw "结果稿缺少字段：$Label"
    }

    return $match.Groups[1].Value.Trim()
}

$placeholderTokens = @(
    '是 / 否 / 未执行',
    '是 / 否',
    '通过 / 不通过',
    '`verify-cutover.ps1` 已通过 / 未通过'
)

$remainingPlaceholders = @(
    $placeholderTokens | Where-Object { $content.Contains($_) }
)
if ($remainingPlaceholders.Count -gt 0) {
    throw "结果稿仍存在未填写占位项：$($remainingPlaceholders -join '、')"
}

$finalResult = Get-BulletValue -Label '人工验板最终结果'
$needRollback = Get-BulletValue -Label '是否需要回退'
$needFollowup = Get-BulletValue -Label '是否需要补刀'
$nextAction = Get-BulletValue -Label '下一步'
$executor = Get-BulletValue -Label '执行人'
$autoVerifyResult = Get-BulletValue -Label '自动验板结果'
$minimumGap = Get-BulletValue -Label '若不通过，最小缺口是'

if ([string]::IsNullOrWhiteSpace($executor)) {
    throw '结果稿缺少执行人。'
}

if ($finalResult -notin @('通过', '不通过')) {
    throw ('人工验板最终结果只能是“通过”或“不通过”，实际为：{0}' -f $finalResult)
}

if ($needRollback -notin @('是', '否')) {
    throw ('是否需要回退只能是“是”或“否”，实际为：{0}' -f $needRollback)
}

if ($needFollowup -notin @('是', '否')) {
    throw ('是否需要补刀只能是“是”或“否”，实际为：{0}' -f $needFollowup)
}

if ([string]::IsNullOrWhiteSpace($nextAction)) {
    throw '结果稿缺少下一步。'
}

if ($autoVerifyResult -notmatch '已通过|未通过') {
    throw "自动验板结果格式不正确：$autoVerifyResult"
}

$blankBulletMatches = [regex]::Matches($content, '(?m)^- ([^：]+)：\s*$')
$allowedBlankLabels = @('备注')
if ($finalResult -eq '通过') {
    $allowedBlankLabels += '若不通过，最小缺口是'
}

$unexpectedBlankLabels = @(
    $blankBulletMatches | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ -notin $allowedBlankLabels }
)
if ($unexpectedBlankLabels.Count -gt 0) {
    throw "结果稿仍存在未填写字段：$($unexpectedBlankLabels -join '、')"
}

if ($finalResult -eq '通过' -and $needRollback -ne '否') {
    throw '人工验板已通过时，“是否需要回退”必须为“否”。'
}

if ($finalResult -eq '通过' -and $needFollowup -ne '否') {
    throw '人工验板已通过时，“是否需要补刀”必须为“否”。'
}

if ($finalResult -eq '不通过' -and [string]::IsNullOrWhiteSpace($minimumGap)) {
    throw '人工验板不通过时，必须填写“若不通过，最小缺口是”。'
}

Write-Info "ResultPath=$resolvedResultPath"
Write-Info "Executor=$executor"
Write-Info "AutoVerify=$autoVerifyResult"
Write-Info "FinalResult=$finalResult"
Write-Info "NeedRollback=$needRollback"
Write-Info "NeedFollowup=$needFollowup"
if (-not [string]::IsNullOrWhiteSpace($minimumGap)) {
    Write-Info "MinimumGap=$minimumGap"
}
Write-Info "NextAction=$nextAction"

if ($finalResult -eq '通过') {
    Write-Ok '结果稿格式复核通过，人工验板结论为：通过'
    Write-Ok '收口提示：本结果稿已可作为人工验板证据之一。'
    Write-Info '建议下一步：进入维护层，运行 `audit-local-task-status.ps1`，再统一收口剩余非终态任务。'
}
else {
    Write-Ok '结果稿格式复核通过，人工验板结论为：不通过'
    Write-WarnLine '收口提示：当前不能按通过态收口，请先按结果稿里的最小缺口补刀。'

    if ($needRollback -eq '是') {
        Write-WarnLine '建议动作：先执行 `verify-cutover.ps1`，仍异常再执行 `rollback-from-backup.ps1`。'
    }
    else {
        Write-Info '建议动作：先补最小缺口，再重新执行一次人工验板。'
    }
}
