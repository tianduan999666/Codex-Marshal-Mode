$ErrorActionPreference = 'Stop'

function Assert-ExitCode {
    param(
        [int]$Actual,
        [int]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw ("{0}：期望退出码 {1}，实际 {2}。" -f $Message, $Expected, $Actual)
    }
}

function Assert-OutputContains {
    param(
        [string[]]$Lines,
        [string]$ExpectedText,
        [string]$Message
    )

    $joinedOutput = ($Lines -join [Environment]::NewLine)
    if ($joinedOutput -notlike ('*' + $ExpectedText + '*')) {
        throw ("{0}：未找到 `{1}`。" -f $Message, $ExpectedText)
    }
}

function Write-Utf8BomFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8Bom)
}

function Invoke-TestScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments
    )

    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    foreach ($key in $Arguments.Keys) {
        $argumentList += ('-{0}' -f $key)
        $argumentList += [string]$Arguments[$key]
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& powershell.exe @argumentList 2>&1 | ForEach-Object { [string]$_ })
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Lines = $lines
        Text = ($lines -join "`n")
    }
}

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$smokeScriptPath = Join-Path $scriptRootPath 'verify-panel-command-smoke.ps1'
$tempRootPath = Join-Path ([System.IO.Path]::GetTempPath()) ('verify-panel-command-smoke-test-' + [System.Guid]::NewGuid().ToString('N'))

try {
    $routeFailureScriptsRootPath = Join-Path $tempRootPath 'route-failure\scripts'
    $routeFailureHomePath = Join-Path $tempRootPath 'route-failure\home'
    $routeFailureRepoPath = Join-Path $tempRootPath 'route-failure\repo'
    Write-Utf8BomFile -Path (Join-Path $routeFailureScriptsRootPath 'VERSION.json') -Content @'
{
  "cx_version": "CX-TEST",
  "opening_line": "🪶 军令入帐。亮，即刻接管全局。"
}
'@
    Write-Utf8BomFile -Path (Join-Path $routeFailureScriptsRootPath 'invoke-panel-command.ps1') -Content @'
param([string]$CommandText = '')
Write-Host 'STUB: invoke-route-failure'
exit 1
'@
    Write-Utf8BomFile -Path (Join-Path $routeFailureScriptsRootPath 'render-panel-response.ps1') -Content @'
param([string]$Kind = '')
Write-Output 'unused-render'
'@

    $routeFailureResult = Invoke-TestScript -ScriptPath $smokeScriptPath -Arguments @{
        TargetCodexHome = $routeFailureHomePath
        ScriptsRootPath = $routeFailureScriptsRootPath
        RepoRootPath = $routeFailureRepoPath
    }

    Assert-ExitCode -Actual $routeFailureResult.ExitCode -Expected 1 -Message '入口路由非零退出时冒烟应失败'
    Assert-OutputContains -Lines $routeFailureResult.Lines -ExpectedText '面板冒烟没通过：传令：版本 的入口路由提前停住了。' -Message '入口路由失败时应返回人话总结'
    Assert-OutputContains -Lines $routeFailureResult.Lines -ExpectedText 'STUB: invoke-route-failure' -Message '入口路由失败时应保留子脚本输出'
    Assert-OutputContains -Lines $routeFailureResult.Lines -ExpectedText 'self-check.cmd' -Message '入口路由失败时应提示后续动作'

    $renderFailureScriptsRootPath = Join-Path $tempRootPath 'render-failure\scripts'
    $renderFailureHomePath = Join-Path $tempRootPath 'render-failure\home'
    $renderFailureRepoPath = Join-Path $tempRootPath 'render-failure\repo'
    Write-Utf8BomFile -Path (Join-Path $renderFailureScriptsRootPath 'VERSION.json') -Content @'
{
  "cx_version": "CX-TEST",
  "opening_line": "🪶 军令入帐。亮，即刻接管全局。"
}
'@
    Write-Utf8BomFile -Path (Join-Path $renderFailureScriptsRootPath 'invoke-panel-command.ps1') -Content @'
param([string]$CommandText = '')
Write-Output '版本号：CX-TEST'
Write-Output '版本来源：codex-home-export'
Write-Output '真源路径：codex-home-export/VERSION.json'
'@
    Write-Utf8BomFile -Path (Join-Path $renderFailureScriptsRootPath 'render-panel-response.ps1') -Content @'
param([string]$Kind = '')
Write-Host 'STUB: render-failure'
exit 1
'@

    $renderFailureResult = Invoke-TestScript -ScriptPath $smokeScriptPath -Arguments @{
        TargetCodexHome = $renderFailureHomePath
        ScriptsRootPath = $renderFailureScriptsRootPath
        RepoRootPath = $renderFailureRepoPath
    }

    Assert-ExitCode -Actual $renderFailureResult.ExitCode -Expected 1 -Message '真源渲染非零退出时冒烟应失败'
    Assert-OutputContains -Lines $renderFailureResult.Lines -ExpectedText '面板冒烟没通过：传令：版本 的真源渲染提前停住了。' -Message '真源渲染失败时应返回人话总结'
    Assert-OutputContains -Lines $renderFailureResult.Lines -ExpectedText 'STUB: render-failure' -Message '真源渲染失败时应保留子脚本输出'
    Assert-OutputContains -Lines $renderFailureResult.Lines -ExpectedText 'rollback.cmd' -Message '真源渲染失败时应提示回退动作'
}
finally {
    if (Test-Path $tempRootPath) {
        Remove-Item -LiteralPath $tempRootPath -Recurse -Force
    }
}

Write-Host 'PASS: verify-panel-command-smoke.test.ps1'
