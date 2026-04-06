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
    if (-not $joinedOutput.Contains($ExpectedText)) {
        throw ("{0}：未找到 `{1}`。" -f $Message, $ExpectedText)
    }
}

function Assert-TextContains {
    param(
        [string]$ActualText,
        [string]$ExpectedText,
        [string]$Message
    )

    if (-not $ActualText.Contains($ExpectedText)) {
        throw ("{0}：未找到 `{1}`。" -f $Message, $ExpectedText)
    }
}

function Assert-TextNotContains {
    param(
        [string]$ActualText,
        [string]$UnexpectedText,
        [string]$Message
    )

    if ($ActualText.Contains($UnexpectedText)) {
        throw ("{0}：意外包含 `{1}`。" -f $Message, $UnexpectedText)
    }
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
$draftScriptPath = Join-Path $scriptRootPath 'new-panel-acceptance-result.ps1'
$templatePath = Join-Path $scriptRootPath 'panel-acceptance-result-template.md'
$tempRootPath = Join-Path ([System.IO.Path]::GetTempPath()) ('new-panel-acceptance-result-test-' + [System.Guid]::NewGuid().ToString('N'))

try {
    $missingTemplateRoot = Join-Path $tempRootPath 'missing-template'
    $missingTemplateSourceRoot = Join-Path $missingTemplateRoot 'source'
    $missingTemplateOutputRoot = Join-Path $missingTemplateRoot 'logs'
    New-Item -ItemType Directory -Force -Path $missingTemplateSourceRoot | Out-Null
    Copy-Item -Path $draftScriptPath -Destination (Join-Path $missingTemplateSourceRoot 'new-panel-acceptance-result.ps1') -Force

    $missingTemplateResult = Invoke-TestScript -ScriptPath (Join-Path $missingTemplateSourceRoot 'new-panel-acceptance-result.ps1') -Arguments @{
        OutputDirectory = $missingTemplateOutputRoot
    }

    Assert-ExitCode -Actual $missingTemplateResult.ExitCode -Expected 1 -Message '缺少结果模板时 new-panel-acceptance-result 应失败'
    Assert-OutputContains -Lines $missingTemplateResult.Lines -ExpectedText '人工验板结果稿模板不见了，当前没法直接生成结果稿。' -Message '缺少结果模板时应返回人话总结'
    Assert-OutputContains -Lines $missingTemplateResult.Lines -ExpectedText 'panel-acceptance-result-template.md' -Message '缺少结果模板时应指出缺失模板'

    $successRoot = Join-Path $tempRootPath 'success'
    $successSourceRoot = Join-Path $successRoot 'source'
    $successOutputRoot = Join-Path $successRoot 'logs'
    New-Item -ItemType Directory -Force -Path $successSourceRoot | Out-Null
    Copy-Item -Path $draftScriptPath -Destination (Join-Path $successSourceRoot 'new-panel-acceptance-result.ps1') -Force
    Copy-Item -Path $templatePath -Destination (Join-Path $successSourceRoot 'panel-acceptance-result-template.md') -Force

    $successResult = Invoke-TestScript -ScriptPath (Join-Path $successSourceRoot 'new-panel-acceptance-result.ps1') -Arguments @{
        OutputDirectory = $successOutputRoot
        FileNamePrefix = 'panel-acceptance-result-test'
    }

    Assert-ExitCode -Actual $successResult.ExitCode -Expected 0 -Message '模板齐全时 new-panel-acceptance-result 应成功'
    Assert-OutputContains -Lines $successResult.Lines -ExpectedText '已生成人工验板结果稿' -Message '生成成功时应提示结果稿已生成'

    $generatedResultPath = $successResult.Lines | Select-Object -Last 1
    if (-not (Test-Path $generatedResultPath)) {
        throw ("生成成功后结果稿不存在：{0}" -f $generatedResultPath)
    }

    $generatedContent = Get-Content -Raw -Encoding UTF8 -Path $generatedResultPath
    Assert-TextContains -ActualText $generatedContent -ExpectedText '自动验板结果：`verify-cutover.ps1` 已通过' -Message '生成结果稿时应把自动验板结果默认置为已通过'
    Assert-TextNotContains -ActualText $generatedContent -UnexpectedText '自动验板结果：`verify-cutover.ps1` 已通过 / 未通过' -Message '生成结果稿时不应保留自动验板结果占位文案'
    Assert-TextNotContains -ActualText $generatedContent -UnexpectedText 'YYYY-MM-DD HH:mm:ss' -Message '生成结果稿时应替换时间占位符'
}
finally {
    if (Test-Path $tempRootPath) {
        Remove-Item -LiteralPath $tempRootPath -Recurse -Force
    }
}

Write-Host 'PASS: new-panel-acceptance-result.test.ps1'
