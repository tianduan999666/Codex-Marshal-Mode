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

function Stop-FriendlyAcceptanceResultCheck {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string]$NextStep = ''
    )

    Write-Host ''
    Write-Host "[ERROR] $Summary" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原因：{0}" -f $Detail)
    }

    if (-not [string]::IsNullOrWhiteSpace($NextStep)) {
        Write-Info ("下一步：{0}" -f $NextStep)
    }

    exit 1
}

if (-not (Test-Path $resolvedResultPath)) {
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '人工验板结果稿还不存在，当前没法做结果复核。' `
        -Detail ("结果稿不存在：{0}" -f $resolvedResultPath) `
        -NextStep '先生成或填写结果稿，再重新执行 verify-panel-acceptance-result.ps1。'
}

$content = [System.IO.File]::ReadAllText($resolvedResultPath)

function Get-BulletValue([string]$Label) {
    $pattern = '(?m)^- ' + [regex]::Escape($Label) + '：[ \t]*(.*)$'
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success) {
        Stop-FriendlyAcceptanceResultCheck `
            -Summary '人工验板结果稿还没填完整。' `
            -Detail ("缺少字段：{0}" -f $Label) `
            -NextStep '先把缺的字段补上，再重新复核。'
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
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '人工验板结果稿里还有占位项没改成真实结论。' `
        -Detail ("未填写占位项：{0}" -f ($remainingPlaceholders -join '、')) `
        -NextStep '先把占位项改成真实结果，再重新复核。'
}

$finalResult = Get-BulletValue -Label '人工验板最终结果'
$needRollback = Get-BulletValue -Label '是否需要回退'
$needFollowup = Get-BulletValue -Label '是否需要补刀'
$nextAction = Get-BulletValue -Label '下一步'
$executor = Get-BulletValue -Label '执行人'
$autoVerifyResult = Get-BulletValue -Label '自动验板结果'
$minimumGap = Get-BulletValue -Label '若不通过，最小缺口是'

if ([string]::IsNullOrWhiteSpace($executor)) {
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '人工验板结果稿还没写执行人。' `
        -NextStep '先补上执行人，再重新复核。'
}

if ($finalResult -notin @('通过', '不通过')) {
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '人工验板最终结果只能填“通过”或“不通过”。' `
        -Detail ("实际填写：{0}" -f $finalResult) `
        -NextStep '先把最终结果改成“通过”或“不通过”，再重新复核。'
}

if ($needRollback -notin @('是', '否')) {
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '“是否需要回退”只能填“是”或“否”。' `
        -Detail ("实际填写：{0}" -f $needRollback) `
        -NextStep '先改成“是”或“否”，再重新复核。'
}

if ($needFollowup -notin @('是', '否')) {
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '“是否需要补刀”只能填“是”或“否”。' `
        -Detail ("实际填写：{0}" -f $needFollowup) `
        -NextStep '先改成“是”或“否”，再重新复核。'
}

if ([string]::IsNullOrWhiteSpace($nextAction)) {
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '人工验板结果稿还没写下一步。' `
        -NextStep '先把下一步补上，再重新复核。'
}

if ($autoVerifyResult -notmatch '已通过|未通过') {
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '自动验板结果格式不对。' `
        -Detail ("实际填写：{0}" -f $autoVerifyResult) `
        -NextStep '先改成“已通过”或“未通过”的表达，再重新复核。'
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
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '人工验板结果稿还有空字段没填。' `
        -Detail ("未填写字段：{0}" -f ($unexpectedBlankLabels -join '、')) `
        -NextStep '先把空字段补齐，再重新复核。'
}

if ($finalResult -eq '通过' -and $needRollback -ne '否') {
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '既然人工验板已通过，“是否需要回退”就不能填“是”。' `
        -NextStep '先把“是否需要回退”改成“否”，再重新复核。'
}

if ($finalResult -eq '通过' -and $needFollowup -ne '否') {
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '既然人工验板已通过，“是否需要补刀”就不能填“是”。' `
        -NextStep '先把“是否需要补刀”改成“否”，再重新复核。'
}

if ($finalResult -eq '不通过' -and [string]::IsNullOrWhiteSpace($minimumGap)) {
    Stop-FriendlyAcceptanceResultCheck `
        -Summary '人工验板既然不通过，就必须写清最小缺口。' `
        -NextStep '先补上“若不通过，最小缺口是”，再重新复核。'
}

Write-Info "ResultPath=$resolvedResultPath"
Write-Info '本次只检查结果稿是否填完整，不会改你的项目。'
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
