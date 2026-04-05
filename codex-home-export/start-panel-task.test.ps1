param()

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$startPanelTaskScriptPath = Join-Path $scriptRootPath 'start-panel-task.ps1'
$versionPath = Join-Path $scriptRootPath 'VERSION.json'
$versionInfo = Get-Content -Raw -Encoding UTF8 -Path $versionPath | ConvertFrom-Json

function Assert-TestEqual([object]$Actual, [object]$Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw ('{0}；期望：{1}；实际：{2}' -f $Message, $Expected, $Actual)
    }
}

function Assert-TestTrue([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Get-TestSha256Text([string]$Path) {
    $fileStream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha256.ComputeHash($fileStream)
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $fileStream.Dispose()
    }

    return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
}

function Write-TestUtf8BomJson([string]$Path, [object]$Payload) {
    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $jsonText = ($Payload | ConvertTo-Json -Depth 6)
    [System.IO.File]::WriteAllText($Path, $jsonText, $utf8Bom)
}

function Invoke-TestScript([string]$ScriptPath, [hashtable]$Arguments) {
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

function New-TestWorkspace() {
    $tempRootPath = Join-Path $env:TEMP ('cx-start-panel-task-' + [guid]::NewGuid().ToString('N'))
    $sourceRootPath = Join-Path $tempRootPath 'source'
    $repoRootPath = Join-Path $tempRootPath 'repo'
    $homePath = Join-Path $tempRootPath 'home'
    $runtimeScriptRootPath = Join-Path $homePath 'config\chancellor-mode'
    $runtimeConfigPath = Join-Path $homePath 'config'

    foreach ($path in @($sourceRootPath, $repoRootPath, $runtimeScriptRootPath)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }

    Copy-Item -Path $startPanelTaskScriptPath -Destination (Join-Path $sourceRootPath 'start-panel-task.ps1') -Force
    Copy-Item -Path $versionPath -Destination (Join-Path $sourceRootPath 'VERSION.json') -Force
    Copy-Item -Path (Join-Path $scriptRootPath 'AGENTS.md') -Destination (Join-Path $sourceRootPath 'AGENTS.md') -Force
    Copy-Item -Path (Join-Path $scriptRootPath 'AGENTS.md') -Destination (Join-Path $homePath 'AGENTS.md') -Force
    Copy-Item -Path $versionPath -Destination (Join-Path $runtimeConfigPath 'cx-version.json') -Force
    Copy-Item -Path (Join-Path $sourceRootPath 'start-panel-task.ps1') -Destination (Join-Path $runtimeScriptRootPath 'start-panel-task.ps1') -Force

    $invokeStub = @'
param()
Write-Output 'invoke-stub'
'@
    $verifyStub = @'
param(
    [string]$TargetCodexHome = ''
)
$logPath = Join-Path $PSScriptRoot 'verify-calls.log'
Add-Content -Path $logPath -Value 'verify' -Encoding UTF8
exit 0
'@
    $installStub = @'
param(
    [string]$TargetCodexHome = ''
)
$logPath = Join-Path $PSScriptRoot 'install-calls.log'
Add-Content -Path $logPath -Value 'install' -Encoding UTF8
exit 0
'@
    $newTaskStub = @'
param(
    [string]$Title,
    [string]$RepoRootPath,
    [string]$TaskNamespace = 'target',
    [string]$RiskLevel = 'low',
    [switch]$PanelMode,
    [string]$Goal = ''
)
$logPath = Join-Path $PSScriptRoot 'new-task-calls.log'
Add-Content -Path $logPath -Value ("Title={0}" -f $Title) -Encoding UTF8
$activeTaskPath = Join-Path $RepoRootPath '.codex\chancellor\active-task.txt'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $activeTaskPath) | Out-Null
Set-Content -Path $activeTaskPath -Value 'test-task-001' -Encoding UTF8
exit 0
'@
    $syncStub = @'
param(
    [string]$Mode,
    [string]$RepoRootPath,
    [string]$TargetCodexHome,
    [switch]$Quiet
)
$logPath = Join-Path $PSScriptRoot 'sync-calls.log'
Add-Content -Path $logPath -Value ("Mode={0}" -f $Mode) -Encoding UTF8
exit 0
'@
    $renderStub = @'
param(
    [string]$Kind,
    [string]$Phase = '',
    [string]$TaskEntryMode = 'auto',
    [string]$VersionPath = '',
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = '',
    [string]$CxVersion = '',
    [string]$LastCheck = '',
    [string]$AutoRepair = '',
    [string]$KeyFileConsistency = '',
    [string]$CurrentMode = '',
    [string]$CurrentTask = '',
    [string]$CompletedText = '',
    [string]$ResultText = '',
    [string]$NextStepText = ''
)
$logPath = Join-Path $PSScriptRoot 'render-calls.log'
Add-Content -Path $logPath -Value ("Kind={0};Phase={1};TaskEntryMode={2}" -f $Kind, $Phase, $TaskEntryMode) -Encoding UTF8
switch ($Kind) {
    'task-entry' {
        if ($TaskEntryMode -eq 'checked') {
            Write-Output 'OPEN'
            Write-Output 'BOUNDARY'
            Write-Output 'TASK'
        }
        else {
            Write-Output 'OPEN'
            Write-Output 'TASK'
        }
    }
    'process-quote' {
        Write-Output ("QUOTE:{0}" -f $Phase)
    }
    'status' {
        Write-Output 'STATUS:1'
        Write-Output 'STATUS:2'
        Write-Output 'STATUS:3'
        Write-Output 'STATUS:4'
        Write-Output 'STATUS:5'
        Write-Output 'STATUS:6'
    }
    'closeout' {
        Write-Output 'CLOSEOUT:1'
        Write-Output 'CLOSEOUT:2'
        Write-Output 'CLOSEOUT:3'
        Write-Output 'CLOSEOUT:4'
    }
}
exit 0
'@

    $stubMap = [ordered]@{
        'invoke-panel-command.ps1' = $invokeStub
        'verify-cutover.ps1' = $verifyStub
        'install-to-home.ps1' = $installStub
        'new-task.ps1' = $newTaskStub
        'sync-task-context.ps1' = $syncStub
        'render-panel-response.ps1' = $renderStub
    }

    foreach ($entry in $stubMap.GetEnumerator()) {
        $sourcePath = Join-Path $sourceRootPath $entry.Key
        Set-Content -Path $sourcePath -Value $entry.Value -Encoding UTF8
    }

    Copy-Item -Path (Join-Path $sourceRootPath 'invoke-panel-command.ps1') -Destination (Join-Path $runtimeScriptRootPath 'invoke-panel-command.ps1') -Force
    Copy-Item -Path (Join-Path $sourceRootPath 'render-panel-response.ps1') -Destination (Join-Path $runtimeScriptRootPath 'render-panel-response.ps1') -Force

    return [pscustomobject]@{
        TempRootPath = $tempRootPath
        SourceRootPath = $sourceRootPath
        RepoRootPath = $repoRootPath
        HomePath = $homePath
        StartScriptPath = (Join-Path $sourceRootPath 'start-panel-task.ps1')
        RenderLogPath = (Join-Path $sourceRootPath 'render-calls.log')
        VerifyLogPath = (Join-Path $sourceRootPath 'verify-calls.log')
        InstallLogPath = (Join-Path $sourceRootPath 'install-calls.log')
        TaskStatePath = (Join-Path $runtimeScriptRootPath 'task-start-state.json')
        AuthPath = (Join-Path $homePath 'auth.json')
    }
}

function Write-PassedTaskStartState([object]$Workspace) {
    $resolvedSourceRootPath = [System.IO.Path]::GetFullPath($Workspace.SourceRootPath)
    $resolvedHomePath = [System.IO.Path]::GetFullPath($Workspace.HomePath)
    $lightCheckHashes = @(
        @($versionInfo.light_check_targets) | ForEach-Object {
            $sourceRelativePath = [string]$_.source_path
            $runtimeRelativePath = [string]$_.runtime_path
            $sourcePath = Join-Path $resolvedSourceRootPath ($sourceRelativePath -replace '/', '\')
            $runtimePath = Join-Path $resolvedHomePath ($runtimeRelativePath -replace '/', '\')
            [ordered]@{
                name = [string]$_.name
                source_path = $sourceRelativePath
                runtime_path = $runtimeRelativePath
                source_sha256 = Get-TestSha256Text -Path $sourcePath
                runtime_sha256 = Get-TestSha256Text -Path $runtimePath
            }
        }
    )

    Write-TestUtf8BomJson -Path $Workspace.TaskStatePath -Payload ([ordered]@{
        verified_at = '2026-04-05 22:20:00'
        verify_status = 'passed'
        cx_version = $versionInfo.cx_version
        runtime_version = $versionInfo.cx_version
        source_root = $resolvedSourceRootPath
        target_codex_home = $resolvedHomePath
        source_agents_hash = Get-TestSha256Text -Path (Join-Path $resolvedSourceRootPath 'AGENTS.md')
        runtime_agents_hash = Get-TestSha256Text -Path (Join-Path $resolvedHomePath 'AGENTS.md')
        repair_used = $false
        light_check_hashes = $lightCheckHashes
    })
}

$testWorkspaces = @()
try {
    $skipVerifyWorkspace = New-TestWorkspace
    $testWorkspaces += $skipVerifyWorkspace
    Write-PassedTaskStartState -Workspace $skipVerifyWorkspace
    $skipVerifyResult = Invoke-TestScript -ScriptPath $skipVerifyWorkspace.StartScriptPath -Arguments @{
        Title = '沿用已通过状态'
        RepoRootPath = $skipVerifyWorkspace.RepoRootPath
        TargetCodexHome = $skipVerifyWorkspace.HomePath
    }

    Assert-TestEqual -Actual $skipVerifyResult.ExitCode -Expected 0 -Message '沿用已通过状态时 start-panel-task 应成功'
    Assert-TestTrue -Condition ($skipVerifyResult.Text -notlike '*BOUNDARY*') -Message '沿用已通过状态时不应输出边界提示'
    Assert-TestTrue -Condition ((Get-Content -Path $skipVerifyWorkspace.RenderLogPath | Select-Object -First 1) -like '*TaskEntryMode=unchecked*') -Message '沿用已通过状态时 task-entry 应明确走 unchecked'
    Assert-TestTrue -Condition (-not (Test-Path $skipVerifyWorkspace.VerifyLogPath)) -Message '沿用已通过状态时不应调用 verify-cutover.ps1'

    $checkedVerifyWorkspace = New-TestWorkspace
    $testWorkspaces += $checkedVerifyWorkspace
    Set-Content -Path $checkedVerifyWorkspace.AuthPath -Value '{"token":"ok"}' -Encoding UTF8
    $checkedVerifyResult = Invoke-TestScript -ScriptPath $checkedVerifyWorkspace.StartScriptPath -Arguments @{
        Title = '需要执行自检'
        RepoRootPath = $checkedVerifyWorkspace.RepoRootPath
        TargetCodexHome = $checkedVerifyWorkspace.HomePath
    }

    Assert-TestEqual -Actual $checkedVerifyResult.ExitCode -Expected 0 -Message '需要执行自检时 start-panel-task 应成功'
    Assert-TestTrue -Condition ($checkedVerifyResult.Text -like '*BOUNDARY*') -Message '实际执行自检前应输出边界提示'
    Assert-TestTrue -Condition ((Get-Content -Path $checkedVerifyWorkspace.RenderLogPath | Select-Object -First 1) -like '*TaskEntryMode=checked*') -Message '实际执行自检前 task-entry 应明确走 checked'
    Assert-TestTrue -Condition (Test-Path $checkedVerifyWorkspace.VerifyLogPath) -Message '需要执行自检时应调用 verify-cutover.ps1'

    $missingAuthWorkspace = New-TestWorkspace
    $testWorkspaces += $missingAuthWorkspace
    $missingAuthResult = Invoke-TestScript -ScriptPath $missingAuthWorkspace.StartScriptPath -Arguments @{
        Title = '未登录不应显示边界提示'
        RepoRootPath = $missingAuthWorkspace.RepoRootPath
        TargetCodexHome = $missingAuthWorkspace.HomePath
    }

    Assert-TestEqual -Actual $missingAuthResult.ExitCode -Expected 1 -Message '缺少 auth.json 时 start-panel-task 应停止'
    Assert-TestTrue -Condition ($missingAuthResult.Text -notlike '*BOUNDARY*') -Message '未实际执行自检时不应提前输出边界提示'
    Assert-TestTrue -Condition ((Get-Content -Path $missingAuthWorkspace.RenderLogPath | Select-Object -First 1) -like '*TaskEntryMode=unchecked*') -Message '缺少 auth.json 时 task-entry 应保持 unchecked'
    Assert-TestTrue -Condition (-not (Test-Path $missingAuthWorkspace.VerifyLogPath)) -Message '缺少 auth.json 时不应调用 verify-cutover.ps1'
    Assert-TestTrue -Condition ($missingAuthResult.Text -like '*此局可破，但还缺一份关键信报。*') -Message '缺少 auth.json 时应先给出丞相式补信息提示'

    $skipRepairWorkspace = New-TestWorkspace
    $testWorkspaces += $skipRepairWorkspace
    Set-Content -Path $skipRepairWorkspace.AuthPath -Value '{"token":"ok"}' -Encoding UTF8
    Set-Content -Path (Join-Path $skipRepairWorkspace.SourceRootPath 'verify-cutover.ps1') -Value @'
param(
    [string]$TargetCodexHome = ''
)
exit 1
'@ -Encoding UTF8
    $skipRepairResult = Invoke-TestScript -ScriptPath $skipRepairWorkspace.StartScriptPath -Arguments @{
        Title = '失败后不自动修整'
        RepoRootPath = $skipRepairWorkspace.RepoRootPath
        TargetCodexHome = $skipRepairWorkspace.HomePath
        SkipAutoRepair = $true
    }

    Assert-TestEqual -Actual $skipRepairResult.ExitCode -Expected 1 -Message 'SkipAutoRepair 且自检失败时 start-panel-task 应停止'
    Assert-TestTrue -Condition ($skipRepairResult.Text -like '*自动验真未通过，本次已按要求停止，不做自动修整。*') -Message 'SkipAutoRepair 且自检失败时应明确停止自动修整'
    Assert-TestTrue -Condition ($skipRepairResult.Text -notlike '*自动验真未通过，开始尝试一次安全修复。*') -Message 'SkipAutoRepair 且自检失败时不应继续进入自动修复'
    Assert-TestTrue -Condition (-not (Test-Path $skipRepairWorkspace.InstallLogPath)) -Message 'SkipAutoRepair 且自检失败时不应调用 install-to-home.ps1'
}
finally {
    foreach ($workspace in $testWorkspaces) {
        if (($null -ne $workspace) -and (Test-Path $workspace.TempRootPath)) {
            Remove-Item -Recurse -Force -LiteralPath $workspace.TempRootPath
        }
    }
}

Write-Host 'PASS: start-panel-task.test.ps1'
