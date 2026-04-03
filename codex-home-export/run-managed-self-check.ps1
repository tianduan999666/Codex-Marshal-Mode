param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex')
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$runtimeMetaRootPath = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode'
$runtimeInstallRecordPath = Join-Path $runtimeMetaRootPath 'install-record.json'
$runtimeScriptsRootPath = $runtimeMetaRootPath

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json)
}

if (-not (Test-Path $runtimeInstallRecordPath)) {
    throw "缺少安装记录：$runtimeInstallRecordPath"
}

$installRecord = Read-JsonFile -Path $runtimeInstallRecordPath
$sourceRootPath = [string]$installRecord.source_root
if ([string]::IsNullOrWhiteSpace($sourceRootPath)) {
    throw "安装记录缺少 source_root：$runtimeInstallRecordPath"
}

$resolvedSourceRootPath = [System.IO.Path]::GetFullPath($sourceRootPath)
$verifyScriptPath = Join-Path $resolvedSourceRootPath 'verify-cutover.ps1'
$smokeScriptPath = Join-Path $resolvedSourceRootPath 'verify-panel-command-smoke.ps1'
$providerAuthCheckScriptPath = Join-Path $resolvedSourceRootPath 'verify-provider-auth.ps1'
foreach ($requiredPath in @($resolvedSourceRootPath, $verifyScriptPath, $smokeScriptPath, $providerAuthCheckScriptPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "完整自检缺少源文件：$requiredPath"
    }
}

Write-Info "SourceRoot=$resolvedSourceRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info '开始执行用户自检入口：源仓验真 → 运行态冒烟 → 真实鉴权。'

& $verifyScriptPath `
    -TargetCodexHome $resolvedTargetCodexHome `
    -ExpectedSourceRoot $resolvedSourceRootPath `
    -RequireBackupRoot
& $smokeScriptPath `
    -TargetCodexHome $resolvedTargetCodexHome `
    -ScriptsRootPath $runtimeScriptsRootPath
& $providerAuthCheckScriptPath -TargetCodexHome $resolvedTargetCodexHome

Write-Host ''
Write-Ok '自检完成。'
Write-Info '可回官方 Codex 面板测试：`传令：版本`、`传令：状态`。'
