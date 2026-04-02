param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Title,
    [string]$Goal = '',
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [ValidateSet('trial', 'target')]
    [string]$TaskNamespace = 'target',
    [ValidateSet('low', 'medium', 'high', 'critical')]
    [string]$RiskLevel = 'low',
    [switch]$SkipAutoRepair
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..'
}
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$verifyScriptPath = Join-Path $scriptRootPath 'verify-cutover.ps1'
$installScriptPath = Join-Path $scriptRootPath 'install-to-home.ps1'
$newTaskScriptPath = Join-Path $scriptRootPath 'new-task.ps1'
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

function Get-ActiveTaskId([string]$Path) {
    if (-not (Test-Path $Path)) {
        return ''
    }

    return ((Get-Content $Path | Select-Object -First 1) | ForEach-Object { $_.Trim() })
}

foreach ($requiredPath in @($verifyScriptPath, $installScriptPath, $newTaskScriptPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少一句话开工所需脚本：$requiredPath"
    }
}

Write-Info "RepoRoot=$resolvedRepoRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info ("TaskTitle={0}" -f $Title)

$repairUsed = $false
$verifyErrorMessage = ''
try {
    & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome
}
catch {
    $verifyErrorMessage = $_.Exception.Message.Trim()
}

if (-not [string]::IsNullOrWhiteSpace($verifyErrorMessage)) {
    if ($verifyErrorMessage -like 'auth.json 不存在*') {
        throw '当前还没登录官方 Codex，不能自动开工。请先完成登录，再回面板重试“丞相：我要做 XX”。'
    }
}

if (-not [string]::IsNullOrWhiteSpace($verifyErrorMessage)) {
    if ($SkipAutoRepair) {
        throw ("自动验真未通过：{0}" -f $verifyErrorMessage)
    }

    Write-WarnLine ("自动验真未通过，开始尝试一次安全修复：{0}" -f $verifyErrorMessage)
    & $installScriptPath -TargetCodexHome $resolvedTargetCodexHome
    & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome
    $repairUsed = $true
}

$newTaskArguments = @{
    Title = $Title
    RepoRootPath = $resolvedRepoRootPath
    TaskNamespace = $TaskNamespace
    RiskLevel = $RiskLevel
    PanelMode = $true
}
if (-not [string]::IsNullOrWhiteSpace($Goal)) {
    $newTaskArguments['Goal'] = $Goal
}

& $newTaskScriptPath @newTaskArguments

$activeTaskId = Get-ActiveTaskId -Path $activeTaskFilePath

Write-Host ''
Write-Ok '一句话开工已完成。'
if ($repairUsed) {
    Write-Output '- 自动验真：先发现漂移，已安全修复并复查通过。'
}
else {
    Write-Output '- 自动验真：通过。'
}
Write-Output ('- 自动建任务：{0}' -f $Title)
if (-not [string]::IsNullOrWhiteSpace($activeTaskId)) {
    Write-Output ('- 当前激活任务：{0}' -f $activeTaskId)
}
Write-Output '- 下一步：留在当前会话，直接判断瓶颈并开始，不用切到 PowerShell。'
