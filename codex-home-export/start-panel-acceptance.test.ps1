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

function New-AcceptanceWorkspace {
    param(
        [string]$TempRootPath,
        [string]$VerifyScriptContent,
        [string]$ResultDraftScriptContent
    )

    $sourceRootPath = Join-Path $TempRootPath 'source'
    $homePath = Join-Path $TempRootPath 'home'
    $outputDirectory = Join-Path $TempRootPath 'logs'

    foreach ($path in @($sourceRootPath, $homePath, $outputDirectory)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }

    Copy-Item -Path $startAcceptanceScriptPath -Destination (Join-Path $sourceRootPath 'start-panel-acceptance.ps1') -Force
    Copy-Item -Path $versionPath -Destination (Join-Path $sourceRootPath 'VERSION.json') -Force

    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'invoke-panel-command.ps1') -Content @'
param(
    [switch]$ShowHint,
    [switch]$PreviewTaskEntry,
    [string]$CommandText = '',
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = ''
)

if ($ShowHint) {
    Write-Output '例如：传令：计算1+1=?'
    exit 0
}

if ($PreviewTaskEntry) {
    Write-Output '🪶 军令入帐。亮，即刻接管全局。'
    Write-Output '军令已明，亮先接手。'
    exit 0
}

switch -Regex ($CommandText) {
    '版本$' {
        Write-Output '版本号：CX-TEST'
        Write-Output '版本来源：codex-home-export'
        Write-Output '真源路径：codex-home-export/VERSION.json'
        exit 0
    }
    '状态$' {
        Write-Output '版本：CX-TEST'
        Write-Output '上次检查：刚刚'
        Write-Output '自动修复：未触发'
        Write-Output '关键文件一致性：一致'
        Write-Output '当前模式：丞相'
        Write-Output '当前任务：无'
        exit 0
    }
    '升级$' {
        Write-Output '触发方式：只在用户主动输入 `传令：升级` 时触发'
        Write-Output '处理边界：只处理丞相自身升级或同步，不擅自升级用户项目'
        Write-Output '默认策略：未收到明确升级传令时，不自动升级'
        exit 0
    }
}

Write-Output '未命中测试命令'
exit 0
'@
    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'verify-cutover.ps1') -Content $VerifyScriptContent
    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'new-panel-acceptance-result.ps1') -Content $ResultDraftScriptContent
    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'panel-acceptance-three-step-card.md') -Content '# 三步入口'
    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'panel-acceptance-pass-fail-sheet.md') -Content '# 打勾单'
    Write-Utf8BomFile -Path (Join-Path $sourceRootPath 'panel-acceptance-result-template.md') -Content '# 结果模板'

    return [pscustomobject]@{
        TempRootPath = $TempRootPath
        StartScriptPath = (Join-Path $sourceRootPath 'start-panel-acceptance.ps1')
        HomePath = $homePath
        OutputDirectory = $outputDirectory
    }
}

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$startAcceptanceScriptPath = Join-Path $scriptRootPath 'start-panel-acceptance.ps1'
$versionPath = Join-Path $scriptRootPath 'VERSION.json'
$testWorkspaces = @()

try {
    $verifyFailureWorkspace = New-AcceptanceWorkspace `
        -TempRootPath (Join-Path $env:TEMP ('cx-start-panel-acceptance-verify-failure-' + [guid]::NewGuid().ToString('N'))) `
        -VerifyScriptContent @'
param(
    [string]$TargetCodexHome = ''
)
Write-Output 'STUB: verify failed detail'
exit 1
'@ `
        -ResultDraftScriptContent @'
param(
    [string]$OutputDirectory = ''
)
Write-Output 'unused result draft'
exit 0
'@
    $testWorkspaces += $verifyFailureWorkspace

    $verifyFailureResult = Invoke-TestScript -ScriptPath $verifyFailureWorkspace.StartScriptPath -Arguments @{
        TargetCodexHome = $verifyFailureWorkspace.HomePath
        OutputDirectory = $verifyFailureWorkspace.OutputDirectory
    }

    Assert-ExitCode -Actual $verifyFailureResult.ExitCode -Expected 1 -Message '自动验真失败时 start-panel-acceptance 应停止'
    Assert-OutputContains -Lines $verifyFailureResult.Lines -ExpectedText '人工验板准备在“自动验真”这一步停住了。' -Message '自动验真失败时应返回人话总结'
    Assert-OutputContains -Lines $verifyFailureResult.Lines -ExpectedText 'STUB: verify failed detail' -Message '自动验真失败时应保留子脚本明细'
    Assert-OutputContains -Lines $verifyFailureResult.Lines -ExpectedText 'self-check.cmd' -Message '自动验真失败时应提示先做自检'

    $resultDraftFailureWorkspace = New-AcceptanceWorkspace `
        -TempRootPath (Join-Path $env:TEMP ('cx-start-panel-acceptance-result-failure-' + [guid]::NewGuid().ToString('N'))) `
        -VerifyScriptContent @'
param(
    [string]$TargetCodexHome = ''
)
Write-Output 'STUB: verify passed'
exit 0
'@ `
        -ResultDraftScriptContent @'
param(
    [string]$OutputDirectory = ''
)
Write-Output 'STUB: result draft failed detail'
exit 1
'@
    $testWorkspaces += $resultDraftFailureWorkspace

    $resultDraftFailureResult = Invoke-TestScript -ScriptPath $resultDraftFailureWorkspace.StartScriptPath -Arguments @{
        TargetCodexHome = $resultDraftFailureWorkspace.HomePath
        OutputDirectory = $resultDraftFailureWorkspace.OutputDirectory
    }

    Assert-ExitCode -Actual $resultDraftFailureResult.ExitCode -Expected 1 -Message '结果稿生成失败时 start-panel-acceptance 应停止'
    Assert-OutputContains -Lines $resultDraftFailureResult.Lines -ExpectedText '自动验真通过了，但结果稿没有生成出来。' -Message '结果稿生成失败时应返回人话总结'
    Assert-OutputContains -Lines $resultDraftFailureResult.Lines -ExpectedText 'STUB: result draft failed detail' -Message '结果稿生成失败时应保留子脚本明细'
    Assert-OutputContains -Lines $resultDraftFailureResult.Lines -ExpectedText '输出目录可写' -Message '结果稿生成失败时应提示检查输出目录'
}
finally {
    foreach ($workspace in $testWorkspaces) {
        if (($null -ne $workspace) -and (Test-Path $workspace.TempRootPath)) {
            Remove-Item -LiteralPath $workspace.TempRootPath -Recurse -Force
        }
    }
}

Write-Host 'PASS: start-panel-acceptance.test.ps1'
