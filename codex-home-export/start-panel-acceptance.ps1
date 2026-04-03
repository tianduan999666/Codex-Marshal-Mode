param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'logs'),
    [switch]$RequireBackupRoot
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifyScriptPath = Join-Path $sourceRoot 'verify-cutover.ps1'
$resultDraftScriptPath = Join-Path $sourceRoot 'new-panel-acceptance-result.ps1'
$invokePanelCommandScriptPath = Join-Path $sourceRoot 'invoke-panel-command.ps1'
$threeStepCardPath = Join-Path $sourceRoot 'panel-acceptance-three-step-card.md'
$passFailSheetPath = Join-Path $sourceRoot 'panel-acceptance-pass-fail-sheet.md'
$resultTemplatePath = Join-Path $sourceRoot 'panel-acceptance-result-template.md'
$versionSourcePath = Join-Path $sourceRoot 'VERSION.json'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlyAcceptance {
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

function Invoke-AcceptanceStep {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments = @{},
        [string]$Summary,
        [string[]]$NextSteps = @(),
        [switch]$ReturnOutput
    )

    $global:LASTEXITCODE = 0
    try {
        $stepOutput = @(& $ScriptPath @Arguments)
    }
    catch {
        Stop-FriendlyAcceptance `
            -Summary $Summary `
            -Detail $_.Exception.Message.Trim() `
            -NextSteps $NextSteps
    }

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    if ($ReturnOutput) {
        return $stepOutput
    }

    return @()
}

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json)
}

function Get-RoutedPanelLines([hashtable]$Arguments) {
    return @(Invoke-AcceptanceStep `
        -ScriptPath $invokePanelCommandScriptPath `
        -Arguments $Arguments `
        -Summary '人工验板还没开始，面板入口预览这一步提前停住了。' `
        -NextSteps @(
            '先执行 `self-check.cmd` 看入口链路是否完整。',
            '如果刚改过面板入口，先修好入口后再回来继续验板。'
        ) `
        -ReturnOutput)
}

foreach ($requiredPath in @($verifyScriptPath, $resultDraftScriptPath, $invokePanelCommandScriptPath, $threeStepCardPath, $passFailSheetPath, $resultTemplatePath, $versionSourcePath)) {
    if (-not (Test-Path $requiredPath)) {
        Stop-FriendlyAcceptance `
            -Summary '人工验板还没开始，因为准备文件不完整。' `
            -Detail ("缺少验板准备文件：{0}" -f $requiredPath) `
            -NextSteps @(
                '先确认你是在完整仓库根目录执行当前脚本。',
                '如果刚切分支、清文件或做过升级，先把缺失文件补齐后再重试。'
            )
    }
}

try {
    $versionInfo = Read-JsonFile -Path $versionSourcePath
    $taskEntryPrefix = if ([string]::IsNullOrWhiteSpace($versionInfo.task_entry_prefix)) { '传令：' } else { [string]$versionInfo.task_entry_prefix }
    $hintLines = @(Get-RoutedPanelLines @{
        ShowHint = $true
        RepoRootPath = (Join-Path $sourceRoot '..')
        TargetCodexHome = $TargetCodexHome
    })
    $taskEntryLines = @(Get-RoutedPanelLines @{
        PreviewTaskEntry = $true
        RepoRootPath = (Join-Path $sourceRoot '..')
        TargetCodexHome = $TargetCodexHome
    })
    $versionPreviewLines = @(Get-RoutedPanelLines @{
        CommandText = '{0}版本' -f $taskEntryPrefix
        RepoRootPath = (Join-Path $sourceRoot '..')
        TargetCodexHome = $TargetCodexHome
    })
    $statusPreviewLines = @(Get-RoutedPanelLines @{
        CommandText = '{0}状态' -f $taskEntryPrefix
        RepoRootPath = (Join-Path $sourceRoot '..')
        TargetCodexHome = $TargetCodexHome
    })
    $upgradePreviewLines = @(Get-RoutedPanelLines @{
        CommandText = '{0}升级' -f $taskEntryPrefix
        RepoRootPath = (Join-Path $sourceRoot '..')
        TargetCodexHome = $TargetCodexHome
    })
    $statusLabelOrder = @(
        $statusPreviewLines |
            ForEach-Object {
                if ($_ -match '^\s*([^：:]+)') {
                    $matches[1].Trim()
                }
            }
    )
    $versionCommand = @($versionInfo.panel_commands | Where-Object { $_ -match '版本$' } | Select-Object -First 1)
    $statusCommand = @($versionInfo.panel_commands | Where-Object { $_ -match '状态$' } | Select-Object -First 1)
    $upgradeCommand = @($versionInfo.panel_commands | Where-Object { $_ -match '升级$' } | Select-Object -First 1)
    if ($versionCommand.Count -eq 0) { $versionCommand = @('{0}版本' -f $taskEntryPrefix) }
    if ($statusCommand.Count -eq 0) { $statusCommand = @('{0}状态' -f $taskEntryPrefix) }
    if ($upgradeCommand.Count -eq 0) { $upgradeCommand = @('{0}升级' -f $taskEntryPrefix) }
    $taskProbeCommand = '{0}测试入口是否稳态' -f $taskEntryPrefix
}
catch {
    Stop-FriendlyAcceptance `
        -Summary '人工验板还没开始，面板口径预览这一步没跑通。' `
        -Detail $_.Exception.Message.Trim() `
        -NextSteps @(
            '先确认 `VERSION.json` 和 `invoke-panel-command.ps1` 是同一批版本。',
            '如果刚改过面板入口，先把入口脚本修到可预览，再回来继续验板。'
        )
}

Write-Info '开始准备人工验板：先做自动验板，再生成结果稿。'
Invoke-AcceptanceStep `
    -ScriptPath $verifyScriptPath `
    -Arguments @{
        TargetCodexHome = $TargetCodexHome
        RequireBackupRoot = $RequireBackupRoot
    } `
    -Summary '人工验板准备在“自动验真”这一步停住了。' `
    -NextSteps @(
        '先不要直接开始人工验板。',
        '先执行 `self-check.cmd` 或 `verify-cutover.ps1` 看详细原因，修好后再重跑当前脚本。'
    )

$resultDraftPath = @(
    Invoke-AcceptanceStep `
        -ScriptPath $resultDraftScriptPath `
        -Arguments @{ OutputDirectory = $OutputDirectory } `
        -Summary '自动验真通过了，但结果稿没有生成出来。' `
        -NextSteps @(
            '先确认输出目录可写，并检查结果模板文件是否完整。',
            '修好后重新执行当前脚本，让验板材料重新生成。'
        ) `
        -ReturnOutput
) | Select-Object -Last 1

Write-Ok '人工验板准备完成。'
Write-Info "三步入口：$threeStepCardPath"
Write-Info "打勾单：$passFailSheetPath"
Write-Info "结果模板：$resultTemplatePath"
Write-Info "结果稿：$resultDraftPath"
Write-Info ("结果复核：填完结果稿后，执行 verify-panel-acceptance-result.ps1 -ResultPath ""{0}""。" -f $resultDraftPath)
Write-Info ("当前官句：{0}" -f $taskEntryLines[0])
Write-Info ("当前开工骨架：{0} → {1} → {2}" -f $taskEntryLines[0], $taskEntryLines[1], $taskEntryLines[2])
Write-Info ("当前版本口径：{0}" -f ($versionPreviewLines -join ' | '))
Write-Info ("当前状态栏顺序：{0}" -f ($statusLabelOrder -join ' / '))
Write-Info ("当前升级口径：{0}" -f ($upgradePreviewLines -join ' | '))
Write-Info ("现在进入官方 Codex 面板，新开会话后先看是否出现示例：{0}" -f $hintLines[0])
Write-Info ("然后按顺序输入：{0} → {1} → {2}；如需确认升级口径，再输入 {3}" -f $taskProbeCommand, $versionCommand[0], $statusCommand[0], $upgradeCommand[0])
Write-Output $resultDraftPath
