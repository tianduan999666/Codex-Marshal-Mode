param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$MaintainerMode
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

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json)
}

function Stop-FriendlySelfCheck {
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

function Invoke-ManagedSelfCheckStep {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments = @{},
        [string]$Summary,
        [string[]]$NextSteps = @()
    )

    $global:LASTEXITCODE = 0
    try {
        & $ScriptPath @Arguments
    }
    catch {
        Stop-FriendlySelfCheck `
            -Summary $Summary `
            -Detail $_.Exception.Message.Trim() `
            -NextSteps $NextSteps
    }

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path $runtimeInstallRecordPath)) {
    Stop-FriendlySelfCheck `
        -Summary '这台机器还没装好丞相，现在没法直接自检。' `
        -Detail ("缺少安装记录：{0}" -f $runtimeInstallRecordPath) `
        -NextSteps @(
            '先执行 `install.cmd` 完成安装。',
            '安装完成后，再执行 `self-check.cmd`。'
        )
}

$installRecord = Read-JsonFile -Path $runtimeInstallRecordPath
$sourceRootPath = [string]$installRecord.source_root
if ([string]::IsNullOrWhiteSpace($sourceRootPath)) {
    Stop-FriendlySelfCheck `
        -Summary '安装记录不完整，当前自检不能继续。' `
        -Detail ("安装记录缺少 source_root：{0}" -f $runtimeInstallRecordPath) `
        -NextSteps @(
            '先重新执行 `install.cmd` 修复安装记录。',
            '如果仍不通过，再考虑 `rollback.cmd`。'
        )
}

$resolvedSourceRootPath = [System.IO.Path]::GetFullPath($sourceRootPath)
$verifyScriptPath = Join-Path $resolvedSourceRootPath 'verify-cutover.ps1'
$smokeScriptPath = Join-Path $resolvedSourceRootPath 'verify-panel-command-smoke.ps1'
$providerAuthCheckScriptPath = Join-Path $resolvedSourceRootPath 'verify-provider-auth.ps1'
foreach ($requiredPath in @($resolvedSourceRootPath, $verifyScriptPath, $smokeScriptPath, $providerAuthCheckScriptPath)) {
    if (-not (Test-Path $requiredPath)) {
        Stop-FriendlySelfCheck `
            -Summary '自检要用的源文件不全，当前这份仓库不能直接验真。' `
            -Detail ("完整自检缺少源文件：{0}" -f $requiredPath) `
            -NextSteps @(
                '先确认当前仓库是完整的。',
                '必要时重新拉一份仓库，再执行 `install.cmd`。'
            )
    }
}

Write-Info "SourceRoot=$resolvedSourceRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info '本次只检查丞相自身状态，不改你的项目。'
Write-Info '开始执行用户自检入口：源仓验真 → 运行态冒烟 → 真实鉴权。'

Invoke-ManagedSelfCheckStep `
    -ScriptPath $verifyScriptPath `
    -Arguments @{
        TargetCodexHome = $resolvedTargetCodexHome
        ExpectedSourceRoot = $resolvedSourceRootPath
        RequireBackupRoot = $true
        MaintainerMode = $MaintainerMode
    } `
    -Summary '自检卡在“运行态验真”这一步，说明当前安装状态还没完全对齐。' `
    -NextSteps @(
        '先重新执行一次 `install.cmd` 或 `upgrade.cmd`。',
        '如果你刚换过文件或版本，先别直接开工。',
        '仍不通过再执行 `rollback.cmd`。'
    )

Invoke-ManagedSelfCheckStep `
    -ScriptPath $smokeScriptPath `
    -Arguments @{
        TargetCodexHome = $resolvedTargetCodexHome
        ScriptsRootPath = $runtimeScriptsRootPath
    } `
    -Summary '自检卡在“面板入口冒烟”这一步，说明入口链路还不稳。' `
    -NextSteps @(
        '先不要直接开始真实任务。',
        '先重跑一次 `self-check.cmd` 确认是不是偶发问题。',
        '如果连续失败，再执行 `rollback.cmd`。'
    )

Invoke-ManagedSelfCheckStep `
    -ScriptPath $providerAuthCheckScriptPath `
    -Arguments @{ TargetCodexHome = $resolvedTargetCodexHome } `
    -Summary '自检卡在“真实 provider/auth 鉴权”这一步，说明官方入口大概率也会受影响。' `
    -NextSteps @(
        '先确认 `config.toml` 的 provider 和 `auth.json` 的 key 是否匹配。',
        '必要时回官方 Codex 面板做一次真人验证。',
        '确认前先不要直接开始真实开发任务。'
    )

Write-Host ''
Write-Ok '自检完成。'
Write-Info '可回官方 Codex 面板测试：`传令：版本`、`传令：状态`。'
