param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$SkipVerify,
    [switch]$SkipSmoke
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath((Join-Path $scriptRootPath '..'))
$installScriptPath = Join-Path $scriptRootPath 'install-to-home.ps1'
$verifyScriptPath = Join-Path $scriptRootPath 'verify-cutover.ps1'
$smokeScriptPath = Join-Path $scriptRootPath 'verify-panel-command-smoke.ps1'
$runtimeScriptsRootPath = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode'
$authPath = Join-Path $resolvedTargetCodexHome 'auth.json'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

foreach ($requiredPath in @($installScriptPath, $verifyScriptPath, $smokeScriptPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少安装入口所需文件：$requiredPath"
    }
}

Write-Info "RepoRoot=$resolvedRepoRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info '开始执行用户安装入口：同步 → 冒烟 → 可选完整验真。'

& $installScriptPath -TargetCodexHome $resolvedTargetCodexHome

if (-not $SkipSmoke) {
    & $smokeScriptPath `
        -TargetCodexHome $resolvedTargetCodexHome `
        -ScriptsRootPath $runtimeScriptsRootPath `
        -RepoRootPath $resolvedRepoRootPath
}
else {
    Write-WarnLine '已按参数跳过面板传令冒烟验证。'
}

if ($SkipVerify) {
    Write-WarnLine '已按参数跳过完整验真。'
}
elseif (Test-Path $authPath) {
    & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome -RequireBackupRoot
}
else {
    Write-WarnLine '未检测到 auth.json，已跳过完整验真。请先完成 Codex 登录，再执行 self-check.cmd。'
}

Write-Host ''
Write-Ok '安装入口已完成。'
Write-Info '新对话验证示例：`传令：版本`、`传令：状态`、`传令：我要做 XX`。'
Write-Info ("升级入口：{0}" -f (Join-Path $resolvedTargetCodexHome 'upgrade.cmd'))
Write-Info ("自检入口：{0}" -f (Join-Path $resolvedTargetCodexHome 'self-check.cmd'))
Write-Info ("回滚入口：{0}" -f (Join-Path $resolvedTargetCodexHome 'rollback.cmd'))
