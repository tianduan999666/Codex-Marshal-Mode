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

function Invoke-SmokeOutputStep {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments = @{},
        [string]$Summary,
        [string]$NextStep = ''
    )

    $global:LASTEXITCODE = 0
    try {
        $stepOutput = @(& $ScriptPath @Arguments)
    }
    catch {
        Stop-FriendlySmokeCheck `
            -Summary $Summary `
            -Detail $_.Exception.Message.Trim() `
            -NextStep $NextStep
    }

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    return $stepOutput
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

function Assert-LineEqual([string]$Label, [string]$ActualLine, [string]$ExpectedLine) {
    if ($ActualLine -ne $ExpectedLine) {
        Stop-FriendlySmokeCheck `
            -Summary ("面板冒烟没通过：{0} 的返回内容和预期不一致。" -f $Label) `
            -Detail ("期望 '{0}'，实际 '{1}'" -f $ExpectedLine, $ActualLine) `
            -NextStep '先执行 self-check.cmd；如果仍不通过，再执行 rollback.cmd。'
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

$versionInfo = Get-Content -Raw -Encoding UTF8 -Path $resolvedVersionPath | ConvertFrom-Json

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
        Invoke-SmokeOutputStep `
            -ScriptPath $invokePanelCommandScriptPath `
            -Arguments @{
                CommandText = $commandItem.command
                RepoRootPath = $resolvedRepoRootPath
                TargetCodexHome = $resolvedTargetCodexHome
            } `
            -Summary ("面板冒烟没通过：{0} 的入口路由提前停住了。" -f $commandItem.command) `
            -NextStep '先执行 self-check.cmd；如果仍不通过，再执行 rollback.cmd。'
    )
    $expectedLines = Get-NonEmptyLines -Lines @(
        Invoke-SmokeOutputStep `
            -ScriptPath $renderPanelResponseScriptPath `
            -Arguments @{
                Kind = $commandItem.kind
                RepoRootPath = $resolvedRepoRootPath
                TargetCodexHome = $resolvedTargetCodexHome
                VersionPath = $resolvedVersionPath
            } `
            -Summary ("面板冒烟没通过：{0} 的真源渲染提前停住了。" -f $commandItem.command) `
            -NextStep '先执行 self-check.cmd；如果仍不通过，再执行 rollback.cmd。'
    )

    Assert-LinesEqual -Label $commandItem.command -ActualLines $actualLines -ExpectedLines $expectedLines
    Write-Ok ("{0} 冒烟通过。" -f $commandItem.command)
}

$taskProbeCommand = '传令：修一下登录页'
$taskProbeLines = Get-NonEmptyLines -Lines @(
    Invoke-SmokeOutputStep `
        -ScriptPath $invokePanelCommandScriptPath `
        -Arguments @{
            CommandText = $taskProbeCommand
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
            DryRunTaskStart = $true
        } `
        -Summary ("面板冒烟没通过：{0} 的任务干跑提前停住了。" -f $taskProbeCommand) `
        -NextStep '先执行 self-check.cmd；如果仍不通过，再执行 rollback.cmd。'
)
$expectedTaskProbeLines = @(
    '路由结果：task-start'
    '任务标题：修一下登录页'
)

Assert-LinesEqual -Label $taskProbeCommand -ActualLines $taskProbeLines -ExpectedLines $expectedTaskProbeLines
Write-Ok ("{0} 干跑冒烟通过。" -f $taskProbeCommand)

$handoffTestRoot = Join-Path $env:TEMP ('cx-smoke-handoff-' + [guid]::NewGuid().ToString('N'))
try {
    $handoffTaskId = 'v4-target-997-smoke-handoff'
    $handoffTaskRoot = Join-Path $handoffTestRoot ('.codex\chancellor\tasks\' + $handoffTaskId)
    $handoffHomePath = Join-Path $handoffTestRoot 'home'
    foreach ($path in @($handoffTaskRoot, (Join-Path $handoffHomePath 'config\chancellor-mode'))) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }

    Set-Content -Path (Join-Path $handoffTestRoot '.codex\chancellor\active-task.txt') -Value $handoffTaskId -Encoding UTF8
    Set-Content -Path (Join-Path $handoffTaskRoot 'contract.yaml') -Value @(
        ('task_id: {0}' -f $handoffTaskId)
        'title: 冒烟验证交班接班'
        'goal: >-'
        '  让交班与接班在公开入口上直接可用。'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $handoffTaskRoot 'state.yaml') -Value @(
        ('task_id: {0}' -f $handoffTaskId)
        'status: ready_to_resume'
        'risk_level: low'
        'next_action: 先读取 handoff.md 再继续'
        'blocked_by: []'
        "updated_at: '2026-04-05 20:20:00'"
        'phase_hint: smoke'
        'plan_step: 先补交班，再验证接班'
        'verify_signal: 新聊天只输入传令：接班也能续上'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $handoffTaskRoot 'decision-log.md') -Value @(
        '# 决策记录'
        ''
        '## 2026-04-05 20:21:00'
        ''
        '- 决策：交班单落在当前任务目录'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $handoffTaskRoot 'result.md') -Value @(
        '# 结果摘要'
        ''
        '## 已完成'
        ''
        '- 已明确交班单落点'
        ''
        '## 验证证据'
        ''
        '- 任务包完整'
        ''
        '## 遗留事项'
        ''
        '- 还未读回交班单'
        ''
        '## 下一步建议'
        ''
        '- 先读取 handoff.md 再继续'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $handoffHomePath 'config\cx-version.json') -Value @"
{
  "cx_version": "$($versionInfo.cx_version)"
}
"@ -Encoding UTF8
    Set-Content -Path (Join-Path $handoffHomePath 'config\chancellor-mode\task-start-state.json') -Value @'
{
  "verified_at": "2026-04-05 20:22:00",
  "verify_status": "passed",
  "repair_used": false
}
'@ -Encoding UTF8

    $handoffLines = Get-NonEmptyLines -Lines @(
        Invoke-SmokeOutputStep `
            -ScriptPath $invokePanelCommandScriptPath `
            -Arguments @{
                CommandText = '传令：交班'
                RepoRootPath = $handoffTestRoot
                TargetCodexHome = $handoffHomePath
            } `
            -Summary '面板冒烟没通过：传令：交班 的入口路由提前停住了。' `
            -NextStep '先执行 self-check.cmd；如果仍不通过，再执行 rollback.cmd。'
    )
    Assert-LineEqual -Label '传令：交班 第 1 行' -ActualLine $handoffLines[0] -ExpectedLine $versionInfo.opening_line
    Assert-LineEqual -Label '传令：交班 结果行' -ActualLine $handoffLines[2] -ExpectedLine '已完成：已为当前任务生成交班材料。'
    Assert-LineEqual -Label '传令：交班 下一步行' -ActualLine $handoffLines[7] -ExpectedLine '下一步：新聊天只需输入 `传令：接班`。'
    if (-not (Test-Path (Join-Path $handoffTaskRoot 'progress-snapshot.md'))) {
        Stop-FriendlySmokeCheck -Summary '面板冒烟没通过：传令：交班 未生成 progress-snapshot.md。' -NextStep '先执行 self-check.cmd；如果仍不通过，再执行 rollback.cmd。'
    }
    if (-not (Test-Path (Join-Path $handoffTaskRoot 'handoff.md'))) {
        Stop-FriendlySmokeCheck -Summary '面板冒烟没通过：传令：交班 未生成 handoff.md。' -NextStep '先执行 self-check.cmd；如果仍不通过，再执行 rollback.cmd。'
    }
    Write-Ok '传令：交班 冒烟通过。'

    $resumeLines = Get-NonEmptyLines -Lines @(
        Invoke-SmokeOutputStep `
            -ScriptPath $invokePanelCommandScriptPath `
            -Arguments @{
                CommandText = '传令：接班'
                RepoRootPath = $handoffTestRoot
                TargetCodexHome = $handoffHomePath
            } `
            -Summary '面板冒烟没通过：传令：接班 的入口路由提前停住了。' `
            -NextStep '先执行 self-check.cmd；如果仍不通过，再执行 rollback.cmd。'
    )
    Assert-LineEqual -Label '传令：接班 第 1 行' -ActualLine $resumeLines[0] -ExpectedLine $versionInfo.opening_line
    Assert-LineEqual -Label '传令：接班 当前任务行' -ActualLine $resumeLines[2] -ExpectedLine ('当前任务：{0}（冒烟验证交班接班）' -f $handoffTaskId)
    Assert-LineEqual -Label '传令：接班 下一步行' -ActualLine $resumeLines[7] -ExpectedLine '下一步：先读取 handoff.md 再继续'
    Write-Ok '传令：接班 冒烟通过。'
}
finally {
    if (Test-Path $handoffTestRoot) {
        Remove-Item -Recurse -Force -LiteralPath $handoffTestRoot
    }
}

Write-Ok '面板传令冒烟验证通过。'
Write-WarnLine '注意：本脚本只验证本地路由与真源渲染，不验证官方面板真实 provider/auth 鉴权。'
