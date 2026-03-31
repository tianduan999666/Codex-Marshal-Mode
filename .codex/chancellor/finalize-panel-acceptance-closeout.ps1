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
$reviewScriptPath = Join-Path $scriptRootPath 'review-panel-acceptance-closeout.ps1'
$resolveScriptPath = Join-Path $scriptRootPath 'resolve-panel-acceptance-closeout.ps1'
$resolvedResultPath = [System.IO.Path]::GetFullPath($ResultPath)

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

foreach ($requiredPath in @($reviewScriptPath, $resolveScriptPath, $resolvedResultPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少一键收口所需文件：$requiredPath"
    }
}

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

$resolveParameters = @{
    ResultPath = $resolvedResultPath
    TaskId = $TaskId
}
if (-not [string]::IsNullOrWhiteSpace($TasksRootPath)) {
    $resolveParameters['TasksRootPath'] = $TasksRootPath
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

& $resolveScriptPath @resolveParameters

$resultContent = [System.IO.File]::ReadAllText($resolvedResultPath)
$finalResult = Get-BulletValue -Content $resultContent -Label '人工验板最终结果'
$nextAction = Get-BulletValue -Content $resultContent -Label '下一步'

Write-Info "ResultPath=$resolvedResultPath"
Write-Info "TaskId=$TaskId"
Write-Info "FinalResult=$finalResult"
if ($finalResult -eq '通过') {
    Write-Ok '一键收口已完成：真实人工验板结果已复核并回写到本地任务包。'
    Write-Info '下一步：若主公已拍板 v4-trial-034，可继续推进最终总收口。'
}
else {
    Write-Ok '一键收口已完成：结果稿已复核并回写到本地任务包当前状态。'
    Write-Info ('下一步：按结果稿继续处理 -> {0}' -f $nextAction)
}
