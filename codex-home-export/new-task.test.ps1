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

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$newTaskScriptPath = Join-Path $scriptRootPath 'new-task.ps1'
$tempRootPath = Join-Path ([System.IO.Path]::GetTempPath()) ('new-task-test-' + [System.Guid]::NewGuid().ToString('N'))

try {
    $missingScaffoldRoot = Join-Path $tempRootPath 'missing-scaffold'
    $missingScaffoldSourceRoot = Join-Path $missingScaffoldRoot 'source'
    $missingScaffoldRepoRoot = Join-Path $missingScaffoldRoot 'repo'
    New-Item -ItemType Directory -Force -Path $missingScaffoldSourceRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $missingScaffoldRepoRoot | Out-Null
    Copy-Item -Path $newTaskScriptPath -Destination (Join-Path $missingScaffoldSourceRoot 'new-task.ps1') -Force

    $missingScaffoldResult = Invoke-TestScript -ScriptPath (Join-Path $missingScaffoldSourceRoot 'new-task.ps1') -Arguments @{
        Title = '修一下登录页'
        RepoRootPath = $missingScaffoldRepoRoot
    }

    Assert-ExitCode -Actual $missingScaffoldResult.ExitCode -Expected 1 -Message '缺少起包脚手架时 new-task 应失败'
    Assert-OutputContains -Lines $missingScaffoldResult.Lines -ExpectedText '当前无法创建任务包，因为起包脚手架不在仓里。' -Message '缺少起包脚手架时应返回人话总结'
    Assert-OutputContains -Lines $missingScaffoldResult.Lines -ExpectedText '.codex\chancellor\create-task-package.ps1' -Message '缺少起包脚手架时应指出缺失文件'

    $childFailureRoot = Join-Path $tempRootPath 'child-failure'
    $childFailureSourceRoot = Join-Path $childFailureRoot 'source'
    $childFailureRepoRoot = Join-Path $childFailureRoot 'repo'
    New-Item -ItemType Directory -Force -Path $childFailureSourceRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $childFailureRepoRoot | Out-Null
    Copy-Item -Path $newTaskScriptPath -Destination (Join-Path $childFailureSourceRoot 'new-task.ps1') -Force
    Write-Utf8BomFile -Path (Join-Path $childFailureRepoRoot '.codex\chancellor\create-task-package.ps1') -Content @'
param()
Write-Output 'STUB: create-task-package failed detail'
exit 1
'@

    $childFailureResult = Invoke-TestScript -ScriptPath (Join-Path $childFailureSourceRoot 'new-task.ps1') -Arguments @{
        Title = '修一下登录页'
        RepoRootPath = $childFailureRepoRoot
    }

    Assert-ExitCode -Actual $childFailureResult.ExitCode -Expected 1 -Message '起包脚手架非零退出时 new-task 应失败'
    Assert-OutputContains -Lines $childFailureResult.Lines -ExpectedText '任务包创建到一半停住了。' -Message '起包脚手架失败时应返回人话总结'
    Assert-OutputContains -Lines $childFailureResult.Lines -ExpectedText 'STUB: create-task-package failed detail' -Message '起包脚手架失败时应保留子脚本明细'
    Assert-OutputContains -Lines $childFailureResult.Lines -ExpectedText 'active-task.txt' -Message '起包脚手架失败时应提示检查半截结果'
}
finally {
    if (Test-Path $tempRootPath) {
        Remove-Item -LiteralPath $tempRootPath -Recurse -Force
    }
}

Write-Host 'PASS: new-task.test.ps1'
