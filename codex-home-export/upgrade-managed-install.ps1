param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$ApplyTemplateConfig
)

$ErrorActionPreference = 'Stop'
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$runtimeMetaRootPath = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode'
$runtimeInstallRecordPath = Join-Path $runtimeMetaRootPath 'install-record.json'
$authPath = Join-Path $resolvedTargetCodexHome 'auth.json'
$runtimeScriptsRootPath = $runtimeMetaRootPath

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json)
}

function Invoke-GitAndRequireSuccess([string[]]$Arguments, [string]$ErrorMessage) {
    $output = @(& git @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw ($ErrorMessage + '：' + (($output -join [Environment]::NewLine).Trim()))
    }

    return $output
}

if (-not (Test-Path $runtimeInstallRecordPath)) {
    throw "缺少安装记录：$runtimeInstallRecordPath。请先执行 install.cmd。"
}

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) {
    throw '未检测到 git，无法执行升级。请先安装 git，再重试 upgrade.cmd。'
}

$installRecord = Read-JsonFile -Path $runtimeInstallRecordPath
$sourceRootPath = [string]$installRecord.source_root
if ([string]::IsNullOrWhiteSpace($sourceRootPath)) {
    throw "安装记录缺少 source_root：$runtimeInstallRecordPath"
}

$resolvedSourceRootPath = [System.IO.Path]::GetFullPath($sourceRootPath)
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedSourceRootPath '..'))
$installScriptPath = Join-Path $resolvedSourceRootPath 'install-to-home.ps1'
$verifyScriptPath = Join-Path $resolvedSourceRootPath 'verify-cutover.ps1'
$smokeScriptPath = Join-Path $resolvedSourceRootPath 'verify-panel-command-smoke.ps1'
$providerAuthCheckScriptPath = Join-Path $resolvedSourceRootPath 'verify-provider-auth.ps1'

foreach ($requiredPath in @($resolvedSourceRootPath, $resolvedRepoRootPath, $installScriptPath, $verifyScriptPath, $smokeScriptPath, $providerAuthCheckScriptPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "升级入口缺少源文件：$requiredPath"
    }
}

if (-not (Test-Path (Join-Path $resolvedRepoRootPath '.git'))) {
    throw "未检测到 Git 仓库：$resolvedRepoRootPath。请确认 install-record.json 指向的是 git clone 后的仓库。"
}

$dirtyWorkingTreeLines = @(& git -C $resolvedRepoRootPath status --short)
if ($LASTEXITCODE -ne 0) {
    throw "无法读取源仓状态：$resolvedRepoRootPath"
}

$autoStashName = ''
if ($dirtyWorkingTreeLines.Count -gt 0) {
    $autoStashName = 'cx-upgrade-auto-stash-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    Write-WarnLine ("检测到源仓有未提交改动，开始执行最安全方案：先自动暂存，再升级。")
    Write-Info ("DirtyFiles={0}" -f ($dirtyWorkingTreeLines -join ' | '))
    [void](Invoke-GitAndRequireSuccess -Arguments @('-C', $resolvedRepoRootPath, 'stash', 'push', '--include-untracked', '--message', $autoStashName) -ErrorMessage '自动暂存失败')
    $dirtyWorkingTreeLines = @(& git -C $resolvedRepoRootPath status --short)
    if ($LASTEXITCODE -ne 0) {
        throw "自动暂存后无法重新读取源仓状态：$resolvedRepoRootPath"
    }
    if ($dirtyWorkingTreeLines.Count -gt 0) {
        throw "自动暂存后源仓仍不干净，已停止升级：$resolvedRepoRootPath"
    }
}

Write-Info "RepoRoot=$resolvedRepoRootPath"
Write-Info "SourceRoot=$resolvedSourceRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info '开始执行升级入口：git pull --ff-only → 重新安装 → 本地冒烟 → 真实鉴权 → 可选完整验真。'

& git -C $resolvedRepoRootPath pull --ff-only
if ($LASTEXITCODE -ne 0) {
    throw "git pull --ff-only 失败：$resolvedRepoRootPath"
}

& $installScriptPath -TargetCodexHome $resolvedTargetCodexHome -ApplyTemplateConfig:$ApplyTemplateConfig
& $smokeScriptPath `
    -TargetCodexHome $resolvedTargetCodexHome `
    -ScriptsRootPath $runtimeScriptsRootPath `
    -RepoRootPath $resolvedRepoRootPath

if (Test-Path $authPath) {
    & $providerAuthCheckScriptPath -TargetCodexHome $resolvedTargetCodexHome
    & $verifyScriptPath `
        -TargetCodexHome $resolvedTargetCodexHome `
        -ExpectedSourceRoot $resolvedSourceRootPath `
        -RequireBackupRoot
}
else {
    Write-WarnLine '未检测到 auth.json，已跳过完整验真。请先完成 Codex 登录，再执行 self-check.cmd。'
}

Write-Host ''
Write-Ok '升级完成。'
if ($ApplyTemplateConfig) {
    Write-WarnLine '本次升级已按显式参数套用仓内 config 模板。'
}
else {
    Write-Info '本次升级默认保留你现有的全局 config.toml。'
}
if (-not [string]::IsNullOrWhiteSpace($autoStashName)) {
    Write-WarnLine ("升级前改动已安全暂存：{0}" -f $autoStashName)
    Write-Info ("如需恢复旧改动：git -C {0} stash list" -f $resolvedRepoRootPath)
}
Write-Info '建议回官方 Codex 面板复核：`传令：版本`、`传令：状态`。'
