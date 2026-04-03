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

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Path $Path | ConvertFrom-Json)
}

function Get-RoutedPanelLines([hashtable]$Arguments) {
    return @(& $invokePanelCommandScriptPath @Arguments)
}

foreach ($requiredPath in @($verifyScriptPath, $resultDraftScriptPath, $invokePanelCommandScriptPath, $threeStepCardPath, $passFailSheetPath, $resultTemplatePath, $versionSourcePath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少验板准备文件：$requiredPath"
    }
}

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

Write-Info '开始准备人工验板：先做自动验板，再生成结果稿。'
& $verifyScriptPath -TargetCodexHome $TargetCodexHome -RequireBackupRoot:$RequireBackupRoot
$resultDraftPath = & $resultDraftScriptPath -OutputDirectory $OutputDirectory

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
