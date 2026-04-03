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

function Stop-FriendlyInitialize {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string]$NextStep = ''
    )

    Write-Host ("[ERROR] {0}" -f $Summary) -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原因：{0}" -f $Detail)
    }
    if (-not [string]::IsNullOrWhiteSpace($NextStep)) {
        Write-Info ("下一步：{0}" -f $NextStep)
    }

    exit 1
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
        Stop-FriendlyInitialize `
            -Summary '初始化缺少必要脚本，当前没法继续。' `
            -Detail ("缺少初始化所需文件：{0}" -f $requiredPath) `
            -NextStep '先补齐仓库文件，再重新执行 initialize-workspace.ps1。'
    }
}

Write-Info "RepoRoot=$resolvedRepoRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info '本次只初始化丞相自身维护环境，不会改你的项目。'
Write-Info '开始执行初始化：同步最小主链 → 可选补建任务 → 可选验真。'

try {
    & $installScriptPath -TargetCodexHome $resolvedTargetCodexHome
}
catch {
    Stop-FriendlyInitialize `
        -Summary '初始化卡在“同步丞相文件”这一步。' `
        -Detail $_.Exception.Message.Trim() `
        -NextStep '先把 install-to-home.ps1 提示的问题处理掉，再重新执行 initialize-workspace.ps1。'
}

if ($InstallGovernanceHook) {
    if (Test-Path $gitHookDirectoryPath) {
        if (-not (Test-Path $hookInstallScriptPath)) {
            Stop-FriendlyInitialize `
                -Summary '你要求安装治理门禁，但 hook 安装脚本不见了。' `
                -Detail ("缺少 hook 安装脚本：{0}" -f $hookInstallScriptPath) `
                -NextStep '先补齐 hook 脚本，再重试 `-InstallGovernanceHook`。'
        }

        try {
            & $hookInstallScriptPath -RepoRootPath $resolvedRepoRootPath
        }
        catch {
            Stop-FriendlyInitialize `
                -Summary '治理门禁安装失败。' `
                -Detail $_.Exception.Message.Trim() `
                -NextStep '先处理 hook 安装问题，再重新执行 initialize-workspace.ps1。'
        }
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

        try {
            & $newTaskScriptPath @newTaskParameters
        }
        catch {
            Stop-FriendlyInitialize `
                -Summary '示例任务创建失败。' `
                -Detail $_.Exception.Message.Trim() `
                -NextStep '先处理起包问题，再决定是否重试示例任务。'
        }
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
        try {
            & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome
        }
        catch {
            Stop-FriendlyInitialize `
                -Summary '初始化最后一步验真没通过。' `
                -Detail $_.Exception.Message.Trim() `
                -NextStep '先处理 verify-cutover.ps1 提示的问题，再重新初始化；如果已经装坏，再考虑 rollback-from-backup.ps1。'
        }
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
