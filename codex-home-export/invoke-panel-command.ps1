param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'command')]
    [string]$CommandText,
    [Parameter(Mandatory = $true, ParameterSetName = 'hint')]
    [switch]$ShowHint,
    [Parameter(Mandatory = $true, ParameterSetName = 'task-preview')]
    [switch]$PreviewTaskEntry,
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$DryRunTaskStart
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..'
}
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$renderPanelResponseScriptPath = Join-Path $scriptRootPath 'render-panel-response.ps1'
$startPanelTaskScriptPath = Join-Path $scriptRootPath 'start-panel-task.ps1'
$sourceVersionPath = Join-Path $scriptRootPath 'VERSION.json'
$runtimeVersionPath = Join-Path (Split-Path -Parent $scriptRootPath) 'cx-version.json'
$versionSourcePath = if (Test-Path $sourceVersionPath) { $sourceVersionPath } else { $runtimeVersionPath }

function Stop-FriendlyPanelEntry {
    param(
        [string]$Summary,
        [string]$NextStep = ''
    )

    if ([string]::IsNullOrWhiteSpace($NextStep)) {
        Write-Host "[ERROR] $Summary" -ForegroundColor Red
        exit 1
    }

    Write-Host ("[ERROR] {0}" -f $Summary) -ForegroundColor Red
    Write-Host ("[INFO] 下一步：{0}" -f $NextStep) -ForegroundColor Cyan
    exit 1
}

function Write-PanelCommandLinesSafe {
    param(
        [hashtable]$Arguments,
        [string]$Summary,
        [string]$NextStep
    )

    $global:LASTEXITCODE = 0
    try {
        foreach ($outputLine in @(& $renderPanelResponseScriptPath @Arguments)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$outputLine)) {
                Write-Output $outputLine
            }
        }
    }
    catch {
        Stop-FriendlyPanelEntry `
            -Summary ("{0} 原始错误：{1}" -f $Summary, $_.Exception.Message.Trim()) `
            -NextStep $NextStep
    }

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Get-PanelCommandPayload([string]$RawCommandText) {
    $trimmedCommandText = $RawCommandText.Trim()
    if ($trimmedCommandText -match '^传令[：:]\s*(.+?)\s*$') {
        return $matches[1].Trim()
    }

    Stop-FriendlyPanelEntry `
        -Summary '这句话还不是丞相的公开入口格式，所以当前没法直接接令。' `
        -NextStep '请直接输入 `传令：你的需求`，例如：`传令：修一下登录页`。'
}

function Invoke-PanelTaskStart {
    param(
        [string]$TaskTitle
    )

    $global:LASTEXITCODE = 0
    try {
        & $startPanelTaskScriptPath -Title $TaskTitle -RepoRootPath $resolvedRepoRootPath -TargetCodexHome $resolvedTargetCodexHome
    }
    catch {
        Stop-FriendlyPanelEntry `
            -Summary ("丞相已接到任务，但开工入口自己报错了。原始错误：{0}" -f $_.Exception.Message.Trim()) `
            -NextStep '先执行 `self-check.cmd` 看入口链路是否完整，确认后再回面板重试。'
    }

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

foreach ($requiredPath in @($renderPanelResponseScriptPath, $startPanelTaskScriptPath, $versionSourcePath)) {
    if (-not (Test-Path $requiredPath)) {
        Stop-FriendlyPanelEntry `
            -Summary '丞相入口缺少必要脚本，当前没法正常接令。' `
            -NextStep '先执行 `install.cmd` 或 `self-check.cmd` 修复入口文件，再回面板重试。'
    }
}

switch ($PSCmdlet.ParameterSetName) {
    'hint' {
        Write-PanelCommandLinesSafe -Arguments @{
            Kind = 'hint'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        } -Summary '丞相入口已经接通，但示例提示渲染失败了。' -NextStep '先执行 `self-check.cmd` 看入口文件是否完整，再回面板重试。'
        exit 0
    }
    'task-preview' {
        Write-PanelCommandLinesSafe -Arguments @{
            Kind = 'task-entry'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        } -Summary '丞相入口已经接通，但开工骨架预览失败了。' -NextStep '先执行 `self-check.cmd` 检查渲染链路，再回面板重试。'
        exit 0
    }
}

$commandPayload = Get-PanelCommandPayload -RawCommandText $CommandText

switch ($commandPayload) {
    '状态' {
        Write-PanelCommandLinesSafe -Arguments @{
            Kind = 'status'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        } -Summary '丞相入口已经接通，但状态栏渲染失败了。' -NextStep '先执行 `self-check.cmd` 检查渲染链路，再回面板重试。'
        break
    }
    '版本' {
        Write-PanelCommandLinesSafe -Arguments @{
            Kind = 'version'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        } -Summary '丞相入口已经接通，但版本口径渲染失败了。' -NextStep '先执行 `self-check.cmd` 检查入口文件，再回面板重试。'
        break
    }
    '升级' {
        Write-PanelCommandLinesSafe -Arguments @{
            Kind = 'upgrade'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        } -Summary '丞相入口已经接通，但升级说明渲染失败了。' -NextStep '先执行 `self-check.cmd` 检查渲染链路，再回面板重试。'
        break
    }
    default {
        if ($DryRunTaskStart) {
            Write-Output '路由结果：task-start'
            Write-Output ('任务标题：{0}' -f $commandPayload)
            break
        }

        Invoke-PanelTaskStart -TaskTitle $commandPayload
        break
    }
}
