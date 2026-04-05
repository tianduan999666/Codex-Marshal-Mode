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

function Stop-FriendlyUpgrade {
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

function Get-FriendlyUpgradeFailureDetail([object[]]$ChildOutput, [int]$ExitCode) {
    $detailLines = @(
        $ChildOutput |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($detailLines.Count -gt 0) {
        return ($detailLines -join '；')
    }

    return ("子脚本退出码：{0}" -f $ExitCode)
}

function Invoke-ManagedUpgradeStep {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments = @{},
        [string]$Summary,
        [string[]]$NextSteps = @()
    )

    $global:LASTEXITCODE = 0
    try {
        $stepOutput = @(& $ScriptPath @Arguments)
    }
    catch {
        Stop-FriendlyUpgrade `
            -Summary $Summary `
            -Detail $_.Exception.Message.Trim() `
            -NextSteps $NextSteps
    }

    if ($LASTEXITCODE -ne 0) {
        Stop-FriendlyUpgrade `
            -Summary $Summary `
            -Detail (Get-FriendlyUpgradeFailureDetail -ChildOutput $stepOutput -ExitCode $LASTEXITCODE) `
            -NextSteps $NextSteps
    }

    foreach ($line in $stepOutput) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-Output $line
        }
    }
}

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json)
}

function ConvertTo-NormalizedRepoPath([string]$PathText) {
    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return ''
    }

    return ($PathText.Trim().Trim('"') -replace '\\', '/')
}

function Get-DirtyWorkingTreePath([string]$StatusLine) {
    if ([string]::IsNullOrWhiteSpace($StatusLine)) {
        return ''
    }

    if ($StatusLine.Length -lt 4) {
        return ''
    }

    $repoPath = $StatusLine.Substring(3).Trim()
    if ($repoPath -match '^.+ -> (.+)$') {
        $repoPath = $Matches[1].Trim()
    }

    return ConvertTo-NormalizedRepoPath -PathText $repoPath
}

function Get-DirtyWorkingTreeGroup([string]$RepoPath) {
    if ([string]::IsNullOrWhiteSpace($RepoPath)) {
        return '其他待人工判断'
    }

    switch -Regex ($RepoPath) {
        '^\.gitignore$' { return '公开入口/生产母体' }
        '^codex-home-export/' { return '公开入口/生产母体' }
        '^\.codex/chancellor/(active-task\.txt|tasks/)' { return '本地任务/运行态' }
        '^\.codex/chancellor/' { return '维护层在研' }
        '^docs/' { return '文档/方案' }
        default { return '其他待人工判断' }
    }
}

function Write-DirtyWorkingTreeGroups([string[]]$DirtyWorkingTreeLines) {
    $groupOrder = @(
        '公开入口/生产母体',
        '维护层在研',
        '本地任务/运行态',
        '文档/方案',
        '其他待人工判断'
    )
    $groupedPaths = @{}

    foreach ($groupName in $groupOrder) {
        $groupedPaths[$groupName] = New-Object System.Collections.Generic.List[string]
    }

    foreach ($dirtyWorkingTreeLine in $DirtyWorkingTreeLines) {
        $repoPath = Get-DirtyWorkingTreePath -StatusLine $dirtyWorkingTreeLine
        if ([string]::IsNullOrWhiteSpace($repoPath)) {
            continue
        }

        $groupName = Get-DirtyWorkingTreeGroup -RepoPath $repoPath
        if ($groupedPaths[$groupName] -notcontains $repoPath) {
            [void]$groupedPaths[$groupName].Add($repoPath)
        }
    }

    Write-Info '改动分组：'
    foreach ($groupName in $groupOrder) {
        $groupPaths = @($groupedPaths[$groupName])
        if ($groupPaths.Count -eq 0) {
            continue
        }

        Write-Info ("- {0}({1})：{2}" -f $groupName, $groupPaths.Count, ($groupPaths -join ' | '))
    }
}

function Write-DirtyWorkingTreeGuidance {
    param(
        [string]$RepoRootPath,
        [string[]]$DirtyWorkingTreeLines
    )

    Write-WarnLine '检测到源仓有未提交改动，本次升级已停止。'
    if ($DirtyWorkingTreeLines.Count -gt 0) {
        Write-DirtyWorkingTreeGroups -DirtyWorkingTreeLines $DirtyWorkingTreeLines
    }

    Write-Info '研判：公开入口/生产母体改动先单独核对并收口；其余在研或草稿改动先收起，再做升级。'
    Write-Info ("先查看改动：git -C {0} status --short --untracked-files=all" -f $RepoRootPath)
    Write-Info ("如需临时收起改动：git -C {0} stash push --include-untracked -m ""cx-upgrade-manual-stash""" -f $RepoRootPath)
    Write-Info ("如需丢弃已跟踪改动：git -C {0} restore ." -f $RepoRootPath)
    Write-Info '如需彻底回到干净状态：请在仓库上级目录重新 git clone 当前仓。'
}

if (-not (Test-Path $runtimeInstallRecordPath)) {
    Stop-FriendlyUpgrade `
        -Summary '这台机器还没有可升级的丞相安装记录。' `
        -Detail ("缺少安装记录：{0}" -f $runtimeInstallRecordPath) `
        -NextSteps @(
            '先执行 `install.cmd` 完成首次安装。',
            '安装完成后，再执行 `upgrade.cmd`。'
        )
}

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) {
    Stop-FriendlyUpgrade `
        -Summary '当前机器没装 git，升级现在走不下去。' `
        -Detail '未检测到 git，无法执行升级。' `
        -NextSteps @(
            '先安装 git。',
            '安装完成后，再重试 `upgrade.cmd`。'
        )
}

$installRecord = Read-JsonFile -Path $runtimeInstallRecordPath
$sourceRootPath = [string]$installRecord.source_root
if ([string]::IsNullOrWhiteSpace($sourceRootPath)) {
    Stop-FriendlyUpgrade `
        -Summary '安装记录不完整，升级现在没法继续。' `
        -Detail ("安装记录里少了源仓路径（字段：source_root，记录文件：{0}）。" -f $runtimeInstallRecordPath) `
        -NextSteps @(
            '先重新执行 `install.cmd` 修复安装记录。',
            '确认安装正常后，再执行 `upgrade.cmd`。'
        )
}

$resolvedSourceRootPath = [System.IO.Path]::GetFullPath($sourceRootPath)
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedSourceRootPath '..'))
$installScriptPath = Join-Path $resolvedSourceRootPath 'install-to-home.ps1'
$verifyScriptPath = Join-Path $resolvedSourceRootPath 'verify-cutover.ps1'
$smokeScriptPath = Join-Path $resolvedSourceRootPath 'verify-panel-command-smoke.ps1'
$providerAuthCheckScriptPath = Join-Path $resolvedSourceRootPath 'verify-provider-auth.ps1'

foreach ($requiredPath in @($resolvedSourceRootPath, $resolvedRepoRootPath, $installScriptPath, $verifyScriptPath, $smokeScriptPath, $providerAuthCheckScriptPath)) {
    if (-not (Test-Path $requiredPath)) {
        Stop-FriendlyUpgrade `
            -Summary '升级要用的源文件不全，当前不能继续升级。' `
            -Detail ("升级入口缺少源文件：{0}" -f $requiredPath) `
            -NextSteps @(
                '先确认当前仓库是完整的 git clone。',
                '如果仓库残缺，先重新拉仓，再重试升级。'
            )
    }
}

if (-not (Test-Path (Join-Path $resolvedRepoRootPath '.git'))) {
    Stop-FriendlyUpgrade `
        -Summary '安装记录指向的源目录不是一个正常的 Git 仓库。' `
        -Detail ("未检测到 Git 仓库：{0}" -f $resolvedRepoRootPath) `
        -NextSteps @(
            '先确认 install-record.json 指向的是 git clone 下来的仓库。',
            '必要时重新 clone 仓库，再重新安装。'
        )
}

$dirtyWorkingTreeLines = @(& git -c core.quotepath=false -C $resolvedRepoRootPath status --short --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    Stop-FriendlyUpgrade `
        -Summary '升级前没法读出源仓状态，所以本次先停住。' `
        -Detail ("无法读取源仓状态：{0}" -f $resolvedRepoRootPath) `
        -NextSteps @(
            '先在仓库目录手动执行 `git status` 看是不是仓库本身有问题。',
            '确认 git 正常后，再重试 `upgrade.cmd`。'
        )
}

if ($dirtyWorkingTreeLines.Count -gt 0) {
    Write-DirtyWorkingTreeGuidance -RepoRootPath $resolvedRepoRootPath -DirtyWorkingTreeLines $dirtyWorkingTreeLines
    exit 1
}

Write-Info "RepoRoot=$resolvedRepoRootPath"
Write-Info "SourceRoot=$resolvedSourceRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info '本次只升级丞相自身；如源仓有未提交改动，会先停下，不会硬拉更新。'
Write-Info '开始执行升级入口：git pull --ff-only → 重新安装 → 本地冒烟 → 真实鉴权 → 可选完整验真。'

& git -C $resolvedRepoRootPath pull --ff-only
if ($LASTEXITCODE -ne 0) {
    Stop-FriendlyUpgrade `
        -Summary '拉取远端更新失败，本次升级没有继续往下走。' `
        -Detail ("git pull --ff-only 失败：{0}" -f $resolvedRepoRootPath) `
        -NextSteps @(
            '先确认网络和远端仓库状态。',
            '如果本地分支落后较多，先手动看一眼 `git status` 和 `git log --oneline --decorate -5`。',
            '确认没问题后，再重试 `upgrade.cmd`。'
        )
}

Invoke-ManagedUpgradeStep `
    -ScriptPath $installScriptPath `
    -Arguments @{
        TargetCodexHome = $resolvedTargetCodexHome
        ApplyTemplateConfig = $ApplyTemplateConfig
    } `
    -Summary '远端更新已经拉下来，但重新安装这一步没走完。' `
    -NextSteps @(
        '先不要继续开工。',
        '先执行 `self-check.cmd` 看当前状态。',
        '如果连续失败，再执行 `rollback.cmd`。'
    )

Invoke-ManagedUpgradeStep `
    -ScriptPath $smokeScriptPath `
    -Arguments @{
        TargetCodexHome = $resolvedTargetCodexHome
        ScriptsRootPath = $runtimeScriptsRootPath
        RepoRootPath = $resolvedRepoRootPath
    } `
    -Summary '升级后的面板入口冒烟没通过。' `
    -NextSteps @(
        '先不要直接开始真实任务。',
        '先执行 `self-check.cmd` 复看详细结果。',
        '如果仍不通过，再执行 `rollback.cmd`。'
    )

if (Test-Path $authPath) {
    Invoke-ManagedUpgradeStep `
        -ScriptPath $providerAuthCheckScriptPath `
        -Arguments @{ TargetCodexHome = $resolvedTargetCodexHome } `
        -Summary '升级后的真实 provider/auth 鉴权没通过。' `
        -NextSteps @(
            '先确认 `config.toml` 的 provider 和 `auth.json` 的 key 还是当前要用的。',
            '必要时先回官方 Codex 面板做一次真人验证。',
            '确认前先不要直接开始真实开发任务。'
        )

    Invoke-ManagedUpgradeStep `
        -ScriptPath $verifyScriptPath `
        -Arguments @{
            TargetCodexHome = $resolvedTargetCodexHome
            ExpectedSourceRoot = $resolvedSourceRootPath
            RequireBackupRoot = $true
        } `
        -Summary '升级已经完成，但最终验真没通过。' `
        -NextSteps @(
            '先执行 `self-check.cmd` 再看一遍完整结果。',
            '如果只是同步没对齐，重试一次 `upgrade.cmd`。',
            '如果仍不通过，再执行 `rollback.cmd`。'
        )
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
Write-Info '建议回官方 Codex 面板复核：`传令：版本`、`传令：状态`。'
