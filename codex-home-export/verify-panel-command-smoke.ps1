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

function Get-NonEmptyLines([object[]]$Lines) {
    return @(
        $Lines |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Assert-LinesEqual([string]$Label, [string[]]$ActualLines, [string[]]$ExpectedLines) {
    if ($ActualLines.Count -ne $ExpectedLines.Count) {
        throw ("{0} 行数不匹配：期望 {1} 行，实际 {2} 行。" -f $Label, $ExpectedLines.Count, $ActualLines.Count)
    }

    for ($index = 0; $index -lt $ExpectedLines.Count; $index++) {
        if ($ActualLines[$index] -ne $ExpectedLines[$index]) {
            throw ("{0} 第 {1} 行不匹配：期望 '{2}'，实际 '{3}'。" -f $Label, ($index + 1), $ExpectedLines[$index], $ActualLines[$index])
        }
    }
}

foreach ($requiredPath in @($invokePanelCommandScriptPath, $renderPanelResponseScriptPath, $resolvedVersionPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少冒烟验证所需文件：$requiredPath"
    }
}

Write-Info "ScriptsRoot=$resolvedScriptsRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"

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

Write-Ok '面板传令冒烟验证通过。'
