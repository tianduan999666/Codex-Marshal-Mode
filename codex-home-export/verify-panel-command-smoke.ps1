param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$ScriptsRootPath = '',
    [string]$RepoRootPath = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ScriptsRootPath)) {
    $ScriptsRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $ScriptsRootPath '..'
}

$resolvedScriptsRootPath = [System.IO.Path]::GetFullPath($ScriptsRootPath)
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$invokePanelCommandScriptPath = Join-Path $resolvedScriptsRootPath 'invoke-panel-command.ps1'
$renderPanelResponseScriptPath = Join-Path $resolvedScriptsRootPath 'render-panel-response.ps1'
$sourceVersionPath = Join-Path $resolvedScriptsRootPath 'VERSION.json'
$runtimeVersionPath = Join-Path $resolvedTargetCodexHome 'config\cx-version.json'
$resolvedVersionPath = if (Test-Path $sourceVersionPath) { $sourceVersionPath } else { $runtimeVersionPath }

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlySmokeCheck {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string]$NextStep = ''
    )

    Write-Host ''
    Write-Host "[ERROR] $Summary" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原因：{0}" -f $Detail)
    }

    if (-not [string]::IsNullOrWhiteSpace($NextStep)) {
        Write-Info ("下一步：{0}" -f $NextStep)
    }

    exit 1
}

function Get-NonEmptyLines([object[]]$Lines) {
    return @(
        $Lines |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Assert-LinesEqual([string]$Label, [string[]]$ActualLines, [string[]]$ExpectedLines) {
    if ($ActualLines.Count -ne $ExpectedLines.Count) {
        Stop-FriendlySmokeCheck `
            -Summary ("面板冒烟没通过：{0} 的返回行数不对。" -f $Label) `
            -Detail ("期望 {0} 行，实际 {1} 行" -f $ExpectedLines.Count, $ActualLines.Count) `
            -NextStep '先执行 self-check.cmd；如果仍不通过，再执行 rollback.cmd。'
    }

    for ($index = 0; $index -lt $ExpectedLines.Count; $index++) {
        if ($ActualLines[$index] -ne $ExpectedLines[$index]) {
            Stop-FriendlySmokeCheck `
                -Summary ("面板冒烟没通过：{0} 的返回内容和真源不一致。" -f $Label) `
                -Detail ("第 {0} 行期望 '{1}'，实际 '{2}'" -f ($index + 1), $ExpectedLines[$index], $ActualLines[$index]) `
                -NextStep '先执行 self-check.cmd；如果仍不通过，再执行 rollback.cmd。'
        }
    }
}

foreach ($requiredPath in @($invokePanelCommandScriptPath, $renderPanelResponseScriptPath, $resolvedVersionPath)) {
    if (-not (Test-Path $requiredPath)) {
        Stop-FriendlySmokeCheck `
            -Summary '面板冒烟缺少必要脚本，当前没法继续验证入口。' `
            -Detail ("缺少文件：{0}" -f $requiredPath) `
            -NextStep '先执行 install.cmd 或 upgrade.cmd，把入口文件补齐后再重试。'
    }
}

Write-Info "ScriptsRoot=$resolvedScriptsRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info '本次只检查丞相入口返回是否稳定，不会改你的项目。'

$commandMatrix = @(
    [ordered]@{ command = '传令：版本'; kind = 'version' }
    [ordered]@{ command = '传令：状态'; kind = 'status' }
    [ordered]@{ command = '传令：升级'; kind = 'upgrade' }
)

foreach ($commandItem in $commandMatrix) {
    $actualLines = Get-NonEmptyLines -Lines @(
        & $invokePanelCommandScriptPath $commandItem.command `
            -RepoRootPath $resolvedRepoRootPath `
            -TargetCodexHome $resolvedTargetCodexHome
    )
    $expectedLines = Get-NonEmptyLines -Lines @(
        & $renderPanelResponseScriptPath -Kind $commandItem.kind `
            -RepoRootPath $resolvedRepoRootPath `
            -TargetCodexHome $resolvedTargetCodexHome `
            -VersionPath $resolvedVersionPath
    )

    Assert-LinesEqual -Label $commandItem.command -ActualLines $actualLines -ExpectedLines $expectedLines
    Write-Ok ("{0} 冒烟通过。" -f $commandItem.command)
}

$taskProbeCommand = '传令：修一下登录页'
$taskProbeLines = Get-NonEmptyLines -Lines @(
    & $invokePanelCommandScriptPath $taskProbeCommand `
        -RepoRootPath $resolvedRepoRootPath `
        -TargetCodexHome $resolvedTargetCodexHome `
        -DryRunTaskStart
)
$expectedTaskProbeLines = @(
    '路由结果：task-start'
    '任务标题：修一下登录页'
)

Assert-LinesEqual -Label $taskProbeCommand -ActualLines $taskProbeLines -ExpectedLines $expectedTaskProbeLines
Write-Ok ("{0} 干跑冒烟通过。" -f $taskProbeCommand)

Write-Ok '面板传令冒烟验证通过。'
Write-WarnLine '注意：本脚本只验证本地路由与真源渲染，不验证官方面板真实 provider/auth 鉴权。'
