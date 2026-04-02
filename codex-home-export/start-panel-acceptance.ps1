param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'logs'),
    [switch]$RequireBackupRoot
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifyScriptPath = Join-Path $sourceRoot 'verify-cutover.ps1'
$resultDraftScriptPath = Join-Path $sourceRoot 'new-panel-acceptance-result.ps1'
$threeStepCardPath = Join-Path $sourceRoot 'panel-acceptance-three-step-card.md'
$passFailSheetPath = Join-Path $sourceRoot 'panel-acceptance-pass-fail-sheet.md'
$resultTemplatePath = Join-Path $sourceRoot 'panel-acceptance-result-template.md'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

foreach ($requiredPath in @($verifyScriptPath, $resultDraftScriptPath, $threeStepCardPath, $passFailSheetPath, $resultTemplatePath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少验板准备文件：$requiredPath"
    }
}

Write-Info '开始准备人工验板：先做自动验板，再生成结果稿。'
& $verifyScriptPath -TargetCodexHome $TargetCodexHome -RequireBackupRoot:$RequireBackupRoot
$resultDraftPath = & $resultDraftScriptPath -OutputDirectory $OutputDirectory

Write-Ok '人工验板准备完成。'
Write-Info "三步入口：$threeStepCardPath"
Write-Info "打勾单：$passFailSheetPath"
Write-Info "结果模板：$resultTemplatePath"
Write-Info "结果稿：$resultDraftPath"
Write-Info "结果复核：填完结果稿后，执行 `verify-panel-acceptance-result.ps1 -ResultPath \"$resultDraftPath\"`。"
Write-Info '现在进入官方 Codex 面板，新开会话后先输入：`传令：测试入口是否稳态`，再按顺序输入：`传令 版本` → `传令 检查` → 必要时 `传令 状态`。'
Write-Output $resultDraftPath
