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

function Get-PanelCommandPayload([string]$RawCommandText) {
    $trimmedCommandText = $RawCommandText.Trim()
    if ($trimmedCommandText -match '^传令[：:]\s*(.+?)\s*$') {
        return $matches[1].Trim()
    }

    throw '当前只接受 `传令：XXXX` 或 `传令:XXXX` 格式。'
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
        throw "缺少入口路由所需文件：$requiredPath"
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
        Write-PanelCommandLines @{
            Kind = 'process-quote'
            Phase = 'task_entry'
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
