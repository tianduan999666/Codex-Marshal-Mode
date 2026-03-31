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

if (-not (Test-Path $resolvedResultPath)) {
    throw "结果稿不存在：$resolvedResultPath"
}

$content = [System.IO.File]::ReadAllText($resolvedResultPath)

function Get-BulletValue([string]$Label) {
    $pattern = '(?m)^- ' + [regex]::Escape($Label) + '：\s*(.*)$'
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
Write-Ok "人工验板结果复核通过：$finalResult"
