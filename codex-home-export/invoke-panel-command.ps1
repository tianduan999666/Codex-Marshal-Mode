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

function Get-PanelCommandPayload([string]$RawCommandText) {
    $trimmedCommandText = $RawCommandText.Trim()
    if ($trimmedCommandText -match '^传令[：:]\s*(.+?)\s*$') {
        return $matches[1].Trim()
    }

    Stop-FriendlyPanelEntry `
        -Summary '这句话还不是丞相的公开入口格式，所以当前没法直接接令。' `
        -NextStep '请直接输入 `传令：你的需求`，例如：`传令：修一下登录页`。'
}

function Write-PanelCommandLines([hashtable]$Arguments) {
    foreach ($outputLine in @(& $renderPanelResponseScriptPath @Arguments)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$outputLine)) {
            Write-Output $outputLine
        }
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
        Write-PanelCommandLines @{
            Kind = 'hint'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        }
        exit 0
    }
    'task-preview' {
        Write-PanelCommandLines @{
            Kind = 'task-entry'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        }
        exit 0
    }
}

$commandPayload = Get-PanelCommandPayload -RawCommandText $CommandText

switch ($commandPayload) {
    '状态' {
        Write-PanelCommandLines @{
            Kind = 'status'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        }
        break
    }
    '版本' {
        Write-PanelCommandLines @{
            Kind = 'version'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        }
        break
    }
    '升级' {
        Write-PanelCommandLines @{
            Kind = 'upgrade'
            VersionPath = $versionSourcePath
            RepoRootPath = $resolvedRepoRootPath
            TargetCodexHome = $resolvedTargetCodexHome
        }
        break
    }
    default {
        if ($DryRunTaskStart) {
            Write-Output '路由结果：task-start'
            Write-Output ('任务标题：{0}' -f $commandPayload)
            break
        }

        & $startPanelTaskScriptPath -Title $commandPayload -RepoRootPath $resolvedRepoRootPath -TargetCodexHome $resolvedTargetCodexHome
        break
    }
}
