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

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$selfCheckScriptPath = Join-Path $scriptRootPath 'run-managed-self-check.ps1'
$tempRootPath = Join-Path ([System.IO.Path]::GetTempPath()) ('run-managed-self-check-test-' + [System.Guid]::NewGuid().ToString('N'))

try {
    $missingInstallHomePath = Join-Path $tempRootPath 'missing-install-home'
    New-Item -ItemType Directory -Force -Path $missingInstallHomePath | Out-Null

    $missingInstallOutput = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfCheckScriptPath -TargetCodexHome $missingInstallHomePath 2>&1
    )
    $missingInstallExitCode = $LASTEXITCODE

    Assert-ExitCode -Actual $missingInstallExitCode -Expected 1 -Message '缺少安装记录时自检应停止'
    Assert-OutputContains -Lines $missingInstallOutput -ExpectedText '这台机器还没装好丞相，现在没法直接自检。' -Message '缺少安装记录时应返回人话'
    Assert-OutputContains -Lines $missingInstallOutput -ExpectedText 'install.cmd' -Message '缺少安装记录时应提示先安装'

    $happySourceRootPath = Join-Path $tempRootPath 'source'
    $happyTargetCodexHomePath = Join-Path $tempRootPath 'happy-home'
    $happyInstallRecordPath = Join-Path $happyTargetCodexHomePath 'config\chancellor-mode\install-record.json'
    $verifyStubPath = Join-Path $happySourceRootPath 'verify-cutover.ps1'
    $smokeStubPath = Join-Path $happySourceRootPath 'verify-panel-command-smoke.ps1'
    $providerStubPath = Join-Path $happySourceRootPath 'verify-provider-auth.ps1'

    $verifyStubContent = @'
param(
    [string]$TargetCodexHome = '',
    [string]$ExpectedSourceRoot = '',
    [switch]$RequireBackupRoot,
    [switch]$MaintainerMode
)

Write-Host 'STUB: verify-cutover'
if ($MaintainerMode) {
    Write-Host 'STUB: verify-cutover maintainer-mode'
}
'@
    $smokeStubContent = @'
param(
    [string]$TargetCodexHome = '',
    [string]$ScriptsRootPath = ''
)

Write-Host 'STUB: verify-panel-command-smoke'
'@
    $providerStubContent = @'
param(
    [string]$TargetCodexHome = ''
)

Write-Host 'STUB: verify-provider-auth'
'@

    Write-Utf8BomFile -Path $verifyStubPath -Content $verifyStubContent
    Write-Utf8BomFile -Path $smokeStubPath -Content $smokeStubContent
    Write-Utf8BomFile -Path $providerStubPath -Content $providerStubContent
    Write-Utf8BomFile -Path $happyInstallRecordPath -Content (@{
        source_root = $happySourceRootPath
    } | ConvertTo-Json -Depth 3)

    $happyOutput = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfCheckScriptPath -TargetCodexHome $happyTargetCodexHomePath 2>&1
    )
    $happyExitCode = $LASTEXITCODE

    Assert-ExitCode -Actual $happyExitCode -Expected 0 -Message '自检主链在三段都通过时应成功'
    Assert-OutputContains -Lines $happyOutput -ExpectedText 'STUB: verify-cutover' -Message '应执行运行态验真脚本'
    Assert-OutputContains -Lines $happyOutput -ExpectedText 'STUB: verify-panel-command-smoke' -Message '应执行面板冒烟脚本'
    Assert-OutputContains -Lines $happyOutput -ExpectedText 'STUB: verify-provider-auth' -Message '应执行真实鉴权脚本'
    Assert-OutputContains -Lines $happyOutput -ExpectedText '自检完成。' -Message '三段通过后应返回完成提示'

    $maintainerOutput = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfCheckScriptPath -TargetCodexHome $happyTargetCodexHomePath -MaintainerMode 2>&1
    )
    $maintainerExitCode = $LASTEXITCODE

    Assert-ExitCode -Actual $maintainerExitCode -Expected 0 -Message '维护者模式自检在三段都通过时也应成功'
    Assert-OutputContains -Lines $maintainerOutput -ExpectedText 'STUB: verify-cutover maintainer-mode' -Message '维护者模式应把参数传给 verify-cutover'

    $verifyFailureStubContent = @'
param(
    [string]$TargetCodexHome = '',
    [string]$ExpectedSourceRoot = '',
    [switch]$RequireBackupRoot,
    [switch]$MaintainerMode
)

Write-Host '若强行动手，快是快，未必稳；请主公补一项关键前提。'
Write-Host '[ERROR] 运行态受管文件存在漂移。'
Write-Host '[WARN] 原因：运行态文件内容没对齐：config/chancellor-mode/render-panel-response.ps1；安装记录缺少同步哈希记录（字段：synced_hashes）：config/chancellor-mode/start-panel-task.ps1'
exit 1
'@
    Write-Utf8BomFile -Path $verifyStubPath -Content $verifyFailureStubContent

    $maintainerFailureOutput = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfCheckScriptPath -TargetCodexHome $happyTargetCodexHomePath -MaintainerMode 2>&1
    )
    $maintainerFailureExitCode = $LASTEXITCODE

    Assert-ExitCode -Actual $maintainerFailureExitCode -Expected 1 -Message '维护者模式下 verify-cutover 失败时自检应停止'
    Assert-OutputContains -Lines $maintainerFailureOutput -ExpectedText '若强行动手，快是快，未必稳；请主公补一项关键前提。' -Message '维护者模式失败时应保留漂移补位句'
    Assert-OutputContains -Lines $maintainerFailureOutput -ExpectedText '运行态受管文件存在漂移。' -Message '维护者模式失败时应保留汇总标题'
    Assert-OutputContains -Lines $maintainerFailureOutput -ExpectedText 'config/chancellor-mode/render-panel-response.ps1' -Message '维护者模式失败时应保留运行态漂移明细'
    Assert-OutputContains -Lines $maintainerFailureOutput -ExpectedText 'config/chancellor-mode/start-panel-task.ps1' -Message '维护者模式失败时应保留同步哈希缺失明细'
}
finally {
    if (Test-Path $tempRootPath) {
        Remove-Item -LiteralPath $tempRootPath -Recurse -Force
    }
}

Write-Host 'PASS: run-managed-self-check.test.ps1'
