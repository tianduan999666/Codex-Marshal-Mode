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

function Reset-TestRuntime {
    param(
        [string]$InstallScriptPath,
        [string]$TargetCodexHomePath,
        [string]$AuthPath
    )

    if (Test-Path $TargetCodexHomePath) {
        Remove-Item -LiteralPath $TargetCodexHomePath -Recurse -Force
    }

    $installResult = Invoke-TestScript -ScriptPath $InstallScriptPath -Arguments @{
        TargetCodexHome = $TargetCodexHomePath
    }
    Assert-ExitCode -Actual $installResult.ExitCode -Expected 0 -Message '测试前置安装应成功'

    Write-TestUtf8BomJson -Path $AuthPath -Payload ([ordered]@{
        OPENAI_API_KEY = 'test-key'
    })
}

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifyScriptPath = Join-Path $scriptRootPath 'verify-cutover.ps1'
$installScriptPath = Join-Path $scriptRootPath 'install-to-home.ps1'
$versionPath = Join-Path $scriptRootPath 'VERSION.json'
$tempRootPath = Join-Path ([System.IO.Path]::GetTempPath()) ('verify-cutover-test-' + [System.Guid]::NewGuid().ToString('N'))
$targetCodexHomePath = Join-Path $tempRootPath 'codex-home'
$runtimeVersionPath = Join-Path $targetCodexHomePath 'config\cx-version.json'
$runtimeManifestPath = Join-Path $targetCodexHomePath 'config\chancellor-mode\manifest.json'
$runtimeInstallRecordPath = Join-Path $targetCodexHomePath 'config\chancellor-mode\install-record.json'
$runtimeRenderScriptPath = Join-Path $targetCodexHomePath 'config\chancellor-mode\render-panel-response.ps1'
$authPath = Join-Path $targetCodexHomePath 'auth.json'
$versionInfo = Get-Content -Raw -Encoding UTF8 -Path $versionPath | ConvertFrom-Json

try {
    New-Item -ItemType Directory -Force -Path $tempRootPath | Out-Null

    Reset-TestRuntime -InstallScriptPath $installScriptPath -TargetCodexHomePath $targetCodexHomePath -AuthPath $authPath

    Remove-Item -LiteralPath $authPath -Force
    $missingAuthResult = Invoke-TestScript -ScriptPath $verifyScriptPath -Arguments @{
        TargetCodexHome = $targetCodexHomePath
    }
    Assert-ExitCode -Actual $missingAuthResult.ExitCode -Expected 1 -Message '缺少 auth.json 时应失败'
    Assert-OutputContains -Lines $missingAuthResult.Lines -ExpectedText '此局可破，但还缺一份关键信报。' -Message '缺少 auth.json 时应先给丞相式补位句'
    Assert-OutputContains -Lines $missingAuthResult.Lines -ExpectedText '当前还没完成 Codex 登录，所以这次不能算验真通过。' -Message '缺少 auth.json 时应说明登录未完成'

    Reset-TestRuntime -InstallScriptPath $installScriptPath -TargetCodexHomePath $targetCodexHomePath -AuthPath $authPath

    $runtimeVersionInfo = Get-Content -Raw -Encoding UTF8 -Path $runtimeVersionPath | ConvertFrom-Json
    $runtimeVersionInfo.cx_version = 'CX-TEST-OLD'
    Write-TestUtf8BomJson -Path $runtimeVersionPath -Payload $runtimeVersionInfo
    $versionMismatchResult = Invoke-TestScript -ScriptPath $verifyScriptPath -Arguments @{
        TargetCodexHome = $targetCodexHomePath
    }
    Assert-ExitCode -Actual $versionMismatchResult.ExitCode -Expected 1 -Message '运行态版本不一致时应失败'
    Assert-OutputContains -Lines $versionMismatchResult.Lines -ExpectedText '若强行动手，快是快，未必稳；请主公补一项关键前提。' -Message '版本不一致时应先给稳态提示'
    Assert-OutputContains -Lines $versionMismatchResult.Lines -ExpectedText ("运行态版本值不对（期望：{0}，实际：CX-TEST-OLD）。" -f $versionInfo.cx_version) -Message '版本不一致时应说清期望值和实际值'

    Reset-TestRuntime -InstallScriptPath $installScriptPath -TargetCodexHomePath $targetCodexHomePath -AuthPath $authPath

    Remove-Item -LiteralPath $runtimeManifestPath -Force
    $missingFileResult = Invoke-TestScript -ScriptPath $verifyScriptPath -Arguments @{
        TargetCodexHome = $targetCodexHomePath
    }
    Assert-ExitCode -Actual $missingFileResult.ExitCode -Expected 1 -Message '缺少验真必要文件时应失败'
    Assert-OutputContains -Lines $missingFileResult.Lines -ExpectedText '此局可破，但还缺一份关键信报。' -Message '缺少必要文件时应先给丞相式补位句'
    Assert-OutputContains -Lines $missingFileResult.Lines -ExpectedText '验真缺少必要文件，说明当前安装还没完整落地。' -Message '缺少必要文件时应说清安装未完整落地'

    Reset-TestRuntime -InstallScriptPath $installScriptPath -TargetCodexHomePath $targetCodexHomePath -AuthPath $authPath

    $installRecordInfo = Get-Content -Raw -Encoding UTF8 -Path $runtimeInstallRecordPath | ConvertFrom-Json
    $installRecordInfo.managed_files = @(
        @($installRecordInfo.managed_files) | Where-Object { $_ -ne 'config/chancellor-mode/install-record.json' }
    )
    Write-TestUtf8BomJson -Path $runtimeInstallRecordPath -Payload $installRecordInfo
    $managedFilesMismatchResult = Invoke-TestScript -ScriptPath $verifyScriptPath -Arguments @{
        TargetCodexHome = $targetCodexHomePath
    }
    Assert-ExitCode -Actual $managedFilesMismatchResult.ExitCode -Expected 1 -Message '安装记录缺少 managed_files 项时应失败'
    Assert-OutputContains -Lines $managedFilesMismatchResult.Lines -ExpectedText '此局可破，但还缺一份关键信报。' -Message 'managed_files 缺项时应先给补位句'
    Assert-OutputContains -Lines $managedFilesMismatchResult.Lines -ExpectedText '安装记录不完整，当前没法确认受管文件都已落地。' -Message 'managed_files 缺项时应说明安装记录不完整'

    Reset-TestRuntime -InstallScriptPath $installScriptPath -TargetCodexHomePath $targetCodexHomePath -AuthPath $authPath

    $runtimeRenderScriptContent = Get-Content -Raw -Encoding UTF8 -Path $runtimeRenderScriptPath
    [System.IO.File]::WriteAllText($runtimeRenderScriptPath, ($runtimeRenderScriptContent + "`r`n# runtime drift"), (New-Object System.Text.UTF8Encoding($true)))
    $runtimeDriftResult = Invoke-TestScript -ScriptPath $verifyScriptPath -Arguments @{
        TargetCodexHome = $targetCodexHomePath
    }
    Assert-ExitCode -Actual $runtimeDriftResult.ExitCode -Expected 1 -Message '运行态受管文件漂移时应失败'
    Assert-OutputContains -Lines $runtimeDriftResult.Lines -ExpectedText '若强行动手，快是快，未必稳；请主公补一项关键前提。' -Message '运行态漂移时应先给稳态提示'
    Assert-OutputContains -Lines $runtimeDriftResult.Lines -ExpectedText '运行态文件和源仓不同步。' -Message '运行态漂移时应说明文件不同步'

    Reset-TestRuntime -InstallScriptPath $installScriptPath -TargetCodexHomePath $targetCodexHomePath -AuthPath $authPath

    $installRecordInfo = Get-Content -Raw -Encoding UTF8 -Path $runtimeInstallRecordPath | ConvertFrom-Json
    $installRecordInfo.backup_root = ''
    Write-TestUtf8BomJson -Path $runtimeInstallRecordPath -Payload $installRecordInfo
    $missingBackupResult = Invoke-TestScript -ScriptPath $verifyScriptPath -Arguments @{
        TargetCodexHome = $targetCodexHomePath
        RequireBackupRoot = $true
    }
    Assert-ExitCode -Actual $missingBackupResult.ExitCode -Expected 1 -Message '缺少 backup_root 且要求备份时应失败'
    Assert-OutputContains -Lines $missingBackupResult.Lines -ExpectedText '此局可破，但还缺一份关键信报。' -Message '缺少 backup_root 时应先给补位句'
    Assert-OutputContains -Lines $missingBackupResult.Lines -ExpectedText '当前没有可回滚备份，所以这次不能算完整验真通过。' -Message '缺少 backup_root 时应说明不可回滚'

    Reset-TestRuntime -InstallScriptPath $installScriptPath -TargetCodexHomePath $targetCodexHomePath -AuthPath $authPath

    $runtimeRenderScriptContent = Get-Content -Raw -Encoding UTF8 -Path $runtimeRenderScriptPath
    [System.IO.File]::WriteAllText($runtimeRenderScriptPath, ($runtimeRenderScriptContent + "`r`n# maintainer drift"), (New-Object System.Text.UTF8Encoding($true)))

    $installRecordInfo = Get-Content -Raw -Encoding UTF8 -Path $runtimeInstallRecordPath | ConvertFrom-Json
    $installRecordInfo.synced_hashes = @(
        @($installRecordInfo.synced_hashes) |
            Where-Object { $_.path -ne 'config/chancellor-mode/start-panel-task.ps1' }
    )
    foreach ($hashItem in @($installRecordInfo.synced_hashes)) {
        if ($hashItem.path -eq 'config/chancellor-mode/invoke-panel-command.ps1') {
            $hashItem.sha256 = 'deadbeef'
        }
    }
    Write-TestUtf8BomJson -Path $runtimeInstallRecordPath -Payload $installRecordInfo
    $maintainerModeResult = Invoke-TestScript -ScriptPath $verifyScriptPath -Arguments @{
        TargetCodexHome = $targetCodexHomePath
        MaintainerMode = $true
    }
    Assert-ExitCode -Actual $maintainerModeResult.ExitCode -Expected 1 -Message 'MaintainerMode 遇到多类漂移时应失败并汇总'
    Assert-OutputContains -Lines $maintainerModeResult.Lines -ExpectedText '若强行动手，快是快，未必稳；请主公补一项关键前提。' -Message 'MaintainerMode 汇总漂移时应先给稳态提示'
    Assert-OutputContains -Lines $maintainerModeResult.Lines -ExpectedText '运行态受管文件存在漂移。' -Message 'MaintainerMode 应输出统一汇总标题'
    Assert-OutputContains -Lines $maintainerModeResult.Lines -ExpectedText '运行态文件内容没对齐：config/chancellor-mode/render-panel-response.ps1' -Message 'MaintainerMode 应列出运行态漂移文件'
    Assert-OutputContains -Lines $maintainerModeResult.Lines -ExpectedText '安装记录缺少同步哈希记录（字段：synced_hashes）：config/chancellor-mode/start-panel-task.ps1' -Message 'MaintainerMode 应列出缺失同步哈希文件'
    Assert-OutputContains -Lines $maintainerModeResult.Lines -ExpectedText '安装记录里的同步哈希值不对（字段：synced_hashes）：config/chancellor-mode/invoke-panel-command.ps1' -Message 'MaintainerMode 应列出错误同步哈希文件'
}
finally {
    if (Test-Path $tempRootPath) {
        Remove-Item -LiteralPath $tempRootPath -Recurse -Force
    }
}

Write-Host 'PASS: verify-cutover.test.ps1'
