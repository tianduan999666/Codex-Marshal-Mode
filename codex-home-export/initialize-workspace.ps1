param(
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$FirstTaskTitle = '第一个示例任务',
    [string]$FirstTaskGoal = '',
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
Write-Info '开始执行一键初始化：安装最小骨架 → 安装门禁 → 准备首个任务 → 自动验板。'

& $installScriptPath -TargetCodexHome $resolvedTargetCodexHome

if (Test-Path $gitHookDirectoryPath) {
    if (-not (Test-Path $hookInstallScriptPath)) {
        throw "缺少 hook 安装脚本：$hookInstallScriptPath"
    }

    & $hookInstallScriptPath -RepoRootPath $resolvedRepoRootPath
}
else {
    Write-WarnLine '未检测到 .git/hooks，已跳过治理门禁安装；如当前是 ZIP 包，请改用 git clone 后重跑。'
}

$createdExampleTask = $false
$activeTaskId = Get-ActiveTaskId -Path $activeTaskFilePath
$hasAnyTask = Test-HasAnyTask -Path $tasksRootPath
if (-not $SkipExampleTask) {
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

if (-not $SkipVerify) {
    if (Test-Path $authPath) {
        & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome
    }
    else {
        Write-WarnLine '未检测到 `auth.json`，已跳过自动验板。请先完成 Codex 登录后，再执行 `verify-cutover.ps1`。'
    }
}

Write-Host ''
Write-Ok '一键初始化已完成。'
Write-Output '你现在可以这样继续：'
Write-Output '1. 打开官方 Codex 面板。'
Write-Output '2. 新开一个会话。'
if ($createdExampleTask) {
    Write-Output '3. 直接使用刚才脚本输出的那段任务继续话术开工。'
}
else {
    Write-Output '3. 如需新任务，执行 `new-task.ps1 -Title "你的任务标题"` 后再回到面板。'
}
Write-Output '4. 若想复查本机安装状态，可执行 `verify-cutover.ps1`。'
