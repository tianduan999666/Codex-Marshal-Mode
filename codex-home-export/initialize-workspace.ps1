param(
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$FirstTaskTitle = '第一个示例任务',
    [string]$FirstTaskGoal = '',
    [switch]$InstallGovernanceHook,
    [switch]$CreateExampleTask,
    [switch]$SkipExampleTask,
    [switch]$ForceExampleTask,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..'
}
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$installScriptPath = Join-Path $scriptRootPath 'install-to-home.ps1'
$verifyScriptPath = Join-Path $scriptRootPath 'verify-cutover.ps1'
$newTaskScriptPath = Join-Path $scriptRootPath 'new-task.ps1'
$hookInstallScriptPath = Join-Path $resolvedRepoRootPath '.codex\chancellor\install-public-commit-governance-hook.ps1'
$tasksRootPath = Join-Path $resolvedRepoRootPath '.codex\chancellor\tasks'
$activeTaskFilePath = Join-Path $resolvedRepoRootPath '.codex\chancellor\active-task.txt'
$gitHookDirectoryPath = Join-Path $resolvedRepoRootPath '.git\hooks'
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

function Get-ActiveTaskId([string]$Path) {
    if (-not (Test-Path $Path)) {
        return ''
    }

    return ((Get-Content $Path | Select-Object -First 1) | ForEach-Object { $_.Trim() })
}

function Test-HasAnyTask([string]$Path) {
    if (-not (Test-Path $Path)) {
        return $false
    }

    return (@(Get-ChildItem -Path $Path -Directory).Count -gt 0)
}

foreach ($requiredPath in @($installScriptPath, $newTaskScriptPath, $verifyScriptPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少初始化所需文件：$requiredPath"
    }
}

Write-Info "RepoRoot=$resolvedRepoRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info '开始执行初始化：同步最小主链 → 可选补建任务 → 可选验真。'

& $installScriptPath -TargetCodexHome $resolvedTargetCodexHome

if ($InstallGovernanceHook) {
    if (Test-Path $gitHookDirectoryPath) {
        if (-not (Test-Path $hookInstallScriptPath)) {
            throw "缺少 hook 安装脚本：$hookInstallScriptPath"
        }

        & $hookInstallScriptPath -RepoRootPath $resolvedRepoRootPath
    }
    else {
        Write-WarnLine '未检测到 .git/hooks，已跳过治理门禁安装；如当前是 ZIP 包，请改用 git clone 后重跑。'
    }
}
else {
    Write-Info '默认未安装治理门禁；如需维护层 hook，请显式加 `-InstallGovernanceHook`。'
}

$createdExampleTask = $false
$activeTaskId = Get-ActiveTaskId -Path $activeTaskFilePath
$hasAnyTask = Test-HasAnyTask -Path $tasksRootPath
$shouldAttemptExampleTask = $CreateExampleTask -or $ForceExampleTask
if ($shouldAttemptExampleTask) {
    if ($ForceExampleTask -or ((-not $hasAnyTask) -and [string]::IsNullOrWhiteSpace($activeTaskId))) {
        $newTaskParameters = @{
            Title = $FirstTaskTitle
            RepoRootPath = $resolvedRepoRootPath
        }
        if (-not [string]::IsNullOrWhiteSpace($FirstTaskGoal)) {
            $newTaskParameters['Goal'] = $FirstTaskGoal
        }

        & $newTaskScriptPath @newTaskParameters
        $createdExampleTask = $true
    }
    else {
        Write-WarnLine '检测到当前仓已存在任务包或 active-task.txt 非空，已跳过自动创建示例任务。'
        Write-Info '如需强制补一个示例任务，可重跑并加 `-ForceExampleTask`。'
    }
}
elseif (-not $SkipExampleTask) {
    Write-Info '默认未创建示例任务；如需补一个引导任务，请显式加 `-CreateExampleTask`。'
}

if (-not $SkipVerify) {
    if (Test-Path $authPath) {
        & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome
    }
    else {
        Write-WarnLine '未检测到 `auth.json`，已跳过自动验板。请先完成 Codex 登录后，再执行 `verify-cutover.ps1`。'
    }
}

Write-Host ''
Write-Ok '初始化已完成。'
Write-Output '当前只保留 3 条主链：'
Write-Output '1. 复查安装状态：`verify-cutover.ps1`'
if ($createdExampleTask) {
    Write-Output '2. 继续刚才脚本输出的任务话术。'
}
else {
    Write-Output '2. 新建任务：`new-task.ps1 -Title "你的任务标题"`'
}
Write-Output '3. 回官方 Codex 面板继续。'
