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
        $value = $Arguments[$key]
        if ($value -is [bool]) {
            if ($value) {
                $argumentList += ('-{0}' -f $key)
            }
            continue
        }

        $argumentList += ('-{0}' -f $key)
        $argumentList += [string]$value
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

function New-TestWorkspace {
    param(
        [string]$TempRootPath,
        [string]$Mode,
        [string]$TemplateScriptPath
    )

    $sourceRootPath = Join-Path $TempRootPath $Mode
    $targetCodexHomePath = Join-Path $sourceRootPath 'home'
    $runtimeScriptsRootPath = Join-Path $targetCodexHomePath 'config\chancellor-mode'
    $runManagedInstallPath = Join-Path $sourceRootPath 'run-managed-install.ps1'
    $authPath = Join-Path $targetCodexHomePath 'auth.json'

    foreach ($path in @($sourceRootPath, $runtimeScriptsRootPath)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }

    Copy-Item -Path $TemplateScriptPath -Destination $runManagedInstallPath -Force

    $installStub = @'
param(
    [string]$TargetCodexHome = '',
    [switch]$ApplyTemplateConfig
)
Write-Host 'STUB: install-to-home ok'
exit 0
'@
    $verifyStub = @'
param(
    [string]$TargetCodexHome = '',
    [switch]$RequireBackupRoot
)
Write-Host 'STUB: verify-cutover ok'
exit 0
'@
    $smokeSuccessStub = @'
param(
    [string]$TargetCodexHome = '',
    [string]$ScriptsRootPath = '',
    [string]$RepoRootPath = ''
)
Write-Host 'STUB: smoke ok'
exit 0
'@
    $providerSuccessStub = @'
param(
    [string]$TargetCodexHome = ''
)
Write-Host 'STUB: provider-auth ok'
exit 0
'@

    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'install-to-home.ps1') -Content $installStub
    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'verify-cutover.ps1') -Content $verifyStub
    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'verify-panel-command-smoke.ps1') -Content $smokeSuccessStub
    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'verify-provider-auth.ps1') -Content $providerSuccessStub
    Write-Utf8BomFile -Path $authPath -Content '{ "OPENAI_API_KEY": "test-key" }'

    return [pscustomobject]@{
        SourceRootPath = $sourceRootPath
        RunManagedInstallPath = $runManagedInstallPath
        TargetCodexHomePath = $targetCodexHomePath
        AuthPath = $authPath
    }
}

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRootPath = Join-Path ([System.IO.Path]::GetTempPath()) ('run-managed-install-test-' + [System.Guid]::NewGuid().ToString('N'))

try {
    $smokeFailureWorkspace = New-TestWorkspace -TempRootPath $tempRootPath -Mode 'smoke-failure' -TemplateScriptPath (Join-Path $scriptRootPath 'run-managed-install.ps1')
    Write-Utf8BomFile -Path (Join-Path $smokeFailureWorkspace.SourceRootPath 'verify-panel-command-smoke.ps1') -Content @'
param(
    [string]$TargetCodexHome = '',
    [string]$ScriptsRootPath = '',
    [string]$RepoRootPath = ''
)
Write-Host 'STUB: smoke failed'
exit 1
'@

    $smokeFailureResult = Invoke-TestScript -ScriptPath $smokeFailureWorkspace.RunManagedInstallPath -Arguments @{
        TargetCodexHome = $smokeFailureWorkspace.TargetCodexHomePath
    }

    Assert-ExitCode -Actual $smokeFailureResult.ExitCode -Expected 1 -Message '面板冒烟非零退出时安装入口应失败'
    Assert-OutputContains -Lines $smokeFailureResult.Lines -ExpectedText '安装已经完成同步，但面板入口冒烟没通过。' -Message '面板冒烟失败时应有人话总结'
    Assert-OutputContains -Lines $smokeFailureResult.Lines -ExpectedText 'STUB: smoke failed' -Message '面板冒烟失败时应保留子脚本输出'
    Assert-OutputContains -Lines $smokeFailureResult.Lines -ExpectedText 'self-check.cmd' -Message '面板冒烟失败时应提示后续动作'

    $providerFailureWorkspace = New-TestWorkspace -TempRootPath $tempRootPath -Mode 'provider-failure' -TemplateScriptPath (Join-Path $scriptRootPath 'run-managed-install.ps1')
    Write-Utf8BomFile -Path (Join-Path $providerFailureWorkspace.SourceRootPath 'verify-provider-auth.ps1') -Content @'
param(
    [string]$TargetCodexHome = ''
)
Write-Host 'STUB: provider-auth failed'
exit 1
'@

    $providerFailureResult = Invoke-TestScript -ScriptPath $providerFailureWorkspace.RunManagedInstallPath -Arguments @{
        TargetCodexHome = $providerFailureWorkspace.TargetCodexHomePath
    }

    Assert-ExitCode -Actual $providerFailureResult.ExitCode -Expected 1 -Message '真实鉴权非零退出时安装入口应失败'
    Assert-OutputContains -Lines $providerFailureResult.Lines -ExpectedText '安装已经完成，但真实 provider/auth 鉴权没通过。' -Message '真实鉴权失败时应有人话总结'
    Assert-OutputContains -Lines $providerFailureResult.Lines -ExpectedText 'STUB: provider-auth failed' -Message '真实鉴权失败时应保留子脚本输出'
    Assert-OutputContains -Lines $providerFailureResult.Lines -ExpectedText '官方 Codex 面板' -Message '真实鉴权失败时应提示真人验证'
}
finally {
    if (Test-Path $tempRootPath) {
        Remove-Item -LiteralPath $tempRootPath -Recurse -Force
    }
}

Write-Host 'PASS: run-managed-install.test.ps1'
