param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$ApplyTemplateConfig,
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
$providerAuthCheckScriptPath = Join-Path $scriptRootPath 'verify-provider-auth.ps1'
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

function Stop-FriendlyInstall {
    param(
        [string]$Summary,
        [string]$Detail,
        [string[]]$NextSteps = @()
    )

    Write-Host ''
    Write-Host "[ERROR] $Summary" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原始错误：{0}" -f $Detail)
    }

    foreach ($nextStep in $NextSteps) {
        Write-Info $nextStep
    }

    exit 1
}

foreach ($requiredPath in @($installScriptPath, $verifyScriptPath, $smokeScriptPath, $providerAuthCheckScriptPath)) {
    if (-not (Test-Path $requiredPath)) {
        Stop-FriendlyInstall `
            -Summary '安装入口缺少必要文件，当前这份仓库还不能直接安装。' `
            -Detail ("缺少安装入口所需文件：{0}" -f $requiredPath) `
            -NextSteps @(
                '先确认你是在完整仓库根目录执行 `.\install.cmd`。',
                '如果刚拉仓或刚拷贝文件，先补齐缺失文件后再重试。'
            )
    }
}

Write-Info "RepoRoot=$resolvedRepoRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info '本次只同步丞相自身文件；不会改你的项目，默认也不会覆盖全局 config.toml。'
Write-Info '开始执行用户安装入口：同步 → 本地冒烟 → 真实鉴权 → 可选完整验真。'

try {
    & $installScriptPath -TargetCodexHome $resolvedTargetCodexHome -ApplyTemplateConfig:$ApplyTemplateConfig
}
catch {
    Stop-FriendlyInstall `
        -Summary '安装在“同步丞相文件”这一步停住了。' `
        -Detail $_.Exception.Message.Trim() `
        -NextSteps @(
            '先不要继续开工。',
            '先检查仓库文件是否完整，再重新执行 `.\install.cmd`。',
            '如果之前装过旧版本，也可以先执行 `rollback.cmd` 再重试。'
        )
}

if (-not $SkipSmoke) {
    try {
        & $smokeScriptPath `
            -TargetCodexHome $resolvedTargetCodexHome `
            -ScriptsRootPath $runtimeScriptsRootPath `
            -RepoRootPath $resolvedRepoRootPath
    }
    catch {
        Stop-FriendlyInstall `
            -Summary '安装已经完成同步，但面板入口冒烟没通过。' `
            -Detail $_.Exception.Message.Trim() `
            -NextSteps @(
                '先不要直接进入真实任务。',
                '先执行 `self-check.cmd` 看完整结果。',
                '如果仍不通过，再执行 `rollback.cmd` 回到上一个可用版本。'
            )
    }
}
else {
    Write-WarnLine '已按参数跳过面板传令冒烟验证。'
}

if ($SkipVerify) {
    Write-WarnLine '已按参数跳过完整验真。'
}
elseif (Test-Path $authPath) {
    try {
        & $providerAuthCheckScriptPath -TargetCodexHome $resolvedTargetCodexHome
    }
    catch {
        Stop-FriendlyInstall `
            -Summary '安装已经完成，但真实 provider/auth 鉴权没通过。' `
            -Detail $_.Exception.Message.Trim() `
            -NextSteps @(
                '先确认 `config.toml` 里的 provider 和 `auth.json` 里的 key 是不是当前要用的那套。',
                '如果你刚切过 provider，先回官方 Codex 面板做一次真人验证。',
                '确认前不要直接开始真实开发任务。'
            )
    }

    try {
        & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome -RequireBackupRoot
    }
    catch {
        Stop-FriendlyInstall `
            -Summary '安装已经完成，但最终验真没通过。' `
            -Detail $_.Exception.Message.Trim() `
            -NextSteps @(
                '先执行 `self-check.cmd` 复看详细结果。',
                '如果只是同步不一致，重新执行一次 `.\install.cmd`。',
                '如果仍不通过，再执行 `rollback.cmd` 回退。'
            )
    }
}
else {
    Write-WarnLine '未检测到 auth.json，已跳过完整验真。请先完成 Codex 登录，再执行 self-check.cmd。'
}

Write-Host ''
Write-Ok '安装入口已完成。'
if ($ApplyTemplateConfig) {
    Write-WarnLine '本次已按显式参数套用仓内 config 模板；后续新会话会使用模板里的 provider / auth 设定。'
}
else {
    Write-Info '本次默认保留你现有的全局 config.toml；不会静默切换 provider / key。'
}
Write-WarnLine '本地传令冒烟只验证丞相脚本链路；真实面板可用性已额外通过当前 provider/auth 做过一轮探针检查。'
Write-Info '新对话验证示例：`传令：版本`、`传令：状态`、`传令：修一下登录页`。'
Write-Info ("升级入口：{0}" -f (Join-Path $resolvedTargetCodexHome 'upgrade.cmd'))
Write-Info ("自检入口：{0}" -f (Join-Path $resolvedTargetCodexHome 'self-check.cmd'))
Write-Info ("回滚入口：{0}" -f (Join-Path $resolvedTargetCodexHome 'rollback.cmd'))
