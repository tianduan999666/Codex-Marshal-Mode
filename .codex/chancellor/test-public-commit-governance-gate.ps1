$ErrorActionPreference = 'Stop'

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$gateScriptPath = Join-Path $scriptRootPath 'invoke-public-commit-governance-gate.ps1'

if (-not (Test-Path $gateScriptPath)) {
    throw "缺少门禁脚本：$gateScriptPath"
}

function Invoke-GateForTestCase {
    param(
        [string[]]$Paths,
        [int]$ExpectedExitCode,
        [string]$TestName
    )

    $quotedPaths = @(
        $Paths | ForEach-Object { "'{0}'" -f $_ }
    )
    $commandText = "& '{0}' -ChangedPaths @({1})" -f $gateScriptPath, ($quotedPaths -join ', ')

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $commandText | Out-Host
    $actualExitCode = $LASTEXITCODE

    if ($actualExitCode -ne $ExpectedExitCode) {
        throw "测试失败：$TestName 期望退出码 $ExpectedExitCode，实际为 $actualExitCode。"
    }
}

$testCases = @(
    @{
        Name = 'allow-public-docs'
        Paths = @('README.md', 'docs/40-执行/10-本地安全提交流程.md')
        ExpectedExitCode = 0
    },
    @{
        Name = 'block-runtime-task-state'
        Paths = @('.codex/chancellor/tasks/example-task/state.yaml')
        ExpectedExitCode = 1
    },
    @{
        Name = 'block-ide-state'
        Paths = @('.vscode/settings.json')
        ExpectedExitCode = 1
    }
)

foreach ($testCase in $testCases) {
    Invoke-GateForTestCase -Paths $testCase.Paths -ExpectedExitCode $testCase.ExpectedExitCode -TestName $testCase.Name
}

$repoRootPath = (Resolve-Path (Join-Path $scriptRootPath '..\..')).Path
$execReadmePath = Join-Path $repoRootPath 'docs/40-执行/README.md'
$originalExecReadmeBytes = [System.IO.File]::ReadAllBytes($execReadmePath)
$execReadmeLines = Get-Content $execReadmePath
$removedLineText = '- `21-关键配置来源与漂移复核模板.md`'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if ($execReadmeLines -notcontains $removedLineText) {
    throw "测试前置条件不满足：$execReadmePath 中缺少 $removedLineText"
}

try {
    $driftedExecReadmeLines = @(
        $execReadmeLines | Where-Object { $_ -ne $removedLineText }
    )
    $driftedExecReadmeContent = ($driftedExecReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($execReadmePath, $driftedExecReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/README.md') -ExpectedExitCode 1 -TestName 'block-public-entry-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execReadmePath, $originalExecReadmeBytes)
}

$docsReadmePath = Join-Path $repoRootPath 'docs/README.md'
$originalDocsReadmeBytes = [System.IO.File]::ReadAllBytes($docsReadmePath)
$docsReadmeLines = Get-Content $docsReadmePath
$removedRuleEntryLineText = '- `reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md`'

if ($docsReadmeLines -notcontains $removedRuleEntryLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $removedRuleEntryLineText"
}

try {
    $driftedDocsReadmeLines = @(
        $docsReadmeLines | Where-Object { $_ -ne $removedRuleEntryLineText }
    )
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-public-rule-entry-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

Write-Host 'PASS: test-public-commit-governance-gate.ps1'
