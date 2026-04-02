param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Title,
    [string]$Goal = '',
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [ValidateSet('trial', 'target')]
    [string]$TaskNamespace = 'target',
    [ValidateSet('low', 'medium', 'high', 'critical')]
    [string]$RiskLevel = 'low',
    [switch]$SkipAutoRepair,
    [switch]$ForceVerify
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..'
}
$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$verifyScriptPath = Join-Path $scriptRootPath 'verify-cutover.ps1'
$installScriptPath = Join-Path $scriptRootPath 'install-to-home.ps1'
$newTaskScriptPath = Join-Path $scriptRootPath 'new-task.ps1'
$versionSourcePath = Join-Path $scriptRootPath 'VERSION.json'
$agentsSourcePath = Join-Path $scriptRootPath 'AGENTS.md'
$configSourcePath = Join-Path $scriptRootPath 'config.toml'
$runtimeVersionPath = Join-Path $resolvedTargetCodexHome 'config\cx-version.json'
$runtimeAgentsPath = Join-Path $resolvedTargetCodexHome 'AGENTS.md'
$runtimeConfigPath = Join-Path $resolvedTargetCodexHome 'config.toml'
$runtimeMetaRootPath = Join-Path $resolvedTargetCodexHome 'config\marshal-mode'
$taskStartStatePath = Join-Path $runtimeMetaRootPath 'task-start-state.json'
$activeTaskFilePath = Join-Path $resolvedRepoRootPath '.codex\chancellor\active-task.txt'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Get-ActiveTaskId([string]$Path) {
    if (-not (Test-Path $Path)) {
        return ''
    }

    return ((Get-Content $Path | Select-Object -First 1) | ForEach-Object { $_.Trim() })
}

function Read-JsonFileOrNull([string]$Path) {
    if (-not (Test-Path $Path)) {
        return $null
    }

    return (Get-Content -Raw -Path $Path | ConvertFrom-Json)
}

function Write-Utf8NoBomJson([string]$Path, [object]$Payload) {
    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $jsonText = ($Payload | ConvertTo-Json -Depth 6)
    [System.IO.File]::WriteAllText($Path, $jsonText, $utf8NoBom)
}

function Get-Sha256TextOrEmpty([string]$Path) {
    if (-not (Test-Path $Path)) {
        return ''
    }

    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

foreach ($requiredPath in @($verifyScriptPath, $installScriptPath, $newTaskScriptPath, $versionSourcePath, $agentsSourcePath, $configSourcePath, $runtimeAgentsPath, $runtimeConfigPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少一句话开工所需脚本：$requiredPath"
    }
}

Write-Info "RepoRoot=$resolvedRepoRootPath"
Write-Info "TargetCodexHome=$resolvedTargetCodexHome"
Write-Info ("TaskTitle={0}" -f $Title)

$sourceVersionInfo = Read-JsonFileOrNull -Path $versionSourcePath
$runtimeVersionInfo = Read-JsonFileOrNull -Path $runtimeVersionPath
$taskStartState = Read-JsonFileOrNull -Path $taskStartStatePath
$currentSourceVersion = if ($null -ne $sourceVersionInfo) { $sourceVersionInfo.cx_version } else { '' }
$currentRuntimeVersion = if ($null -ne $runtimeVersionInfo) { $runtimeVersionInfo.cx_version } else { '' }
$currentSourceRoot = $scriptRootPath
$currentSourceAgentsHash = Get-Sha256TextOrEmpty -Path $agentsSourcePath
$currentSourceConfigHash = Get-Sha256TextOrEmpty -Path $configSourcePath
$currentRuntimeAgentsHash = Get-Sha256TextOrEmpty -Path $runtimeAgentsPath
$currentRuntimeConfigHash = Get-Sha256TextOrEmpty -Path $runtimeConfigPath
$canSkipVerify = $false
if (-not $ForceVerify) {
    if (($null -ne $taskStartState) -and ($taskStartState.verify_status -eq 'passed') -and ($taskStartState.cx_version -eq $currentSourceVersion) -and ($taskStartState.runtime_version -eq $currentRuntimeVersion) -and ($taskStartState.source_root -eq $currentSourceRoot) -and ($currentSourceVersion -eq $currentRuntimeVersion) -and ($currentSourceAgentsHash -eq $currentRuntimeAgentsHash) -and ($currentSourceConfigHash -eq $currentRuntimeConfigHash)) {
        $canSkipVerify = $true
    }
}

$repairUsed = $false
$verifySkipped = $false
$verifyErrorMessage = ''
if ($canSkipVerify) {
    $verifySkipped = $true
    Write-Info ("检测到当前版本 {0} 已在本机通过首轮验真，本次直接建任务。" -f $currentSourceVersion)
}
else {
    try {
        & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome
    }
    catch {
        $verifyErrorMessage = $_.Exception.Message.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($verifyErrorMessage)) {
        if ($verifyErrorMessage -like 'auth.json 不存在*') {
            throw '当前还没登录官方 Codex，不能自动开工。请先完成登录，再回面板重试“丞相：我要做 XX”。'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($verifyErrorMessage)) {
        if ($SkipAutoRepair) {
            throw ("自动验真未通过：{0}" -f $verifyErrorMessage)
        }

        Write-WarnLine ("自动验真未通过，开始尝试一次安全修复：{0}" -f $verifyErrorMessage)
        & $installScriptPath -TargetCodexHome $resolvedTargetCodexHome
        & $verifyScriptPath -TargetCodexHome $resolvedTargetCodexHome
        $repairUsed = $true
        $runtimeVersionInfo = Read-JsonFileOrNull -Path $runtimeVersionPath
        $currentRuntimeVersion = if ($null -ne $runtimeVersionInfo) { $runtimeVersionInfo.cx_version } else { '' }
        $currentRuntimeAgentsHash = Get-Sha256TextOrEmpty -Path $runtimeAgentsPath
        $currentRuntimeConfigHash = Get-Sha256TextOrEmpty -Path $runtimeConfigPath
    }

    $taskStartStatePayload = [ordered]@{
        verified_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        verify_status = 'passed'
        cx_version = $currentSourceVersion
        runtime_version = $currentRuntimeVersion
        source_root = $currentSourceRoot
        target_codex_home = $resolvedTargetCodexHome
        source_agents_hash = $currentSourceAgentsHash
        source_config_hash = $currentSourceConfigHash
        runtime_agents_hash = $currentRuntimeAgentsHash
        runtime_config_hash = $currentRuntimeConfigHash
        repair_used = $repairUsed
    }
    Write-Utf8NoBomJson -Path $taskStartStatePath -Payload $taskStartStatePayload
}

$newTaskArguments = @{
    Title = $Title
    RepoRootPath = $resolvedRepoRootPath
    TaskNamespace = $TaskNamespace
    RiskLevel = $RiskLevel
    PanelMode = $true
}
if (-not [string]::IsNullOrWhiteSpace($Goal)) {
    $newTaskArguments['Goal'] = $Goal
}

& $newTaskScriptPath @newTaskArguments

$activeTaskId = Get-ActiveTaskId -Path $activeTaskFilePath

Write-Host ''
Write-Ok '一句话开工已完成。'
if ($verifySkipped) {
    Write-Output '- 自动验真：已跳过（当前版本本机已验过）。'
}
elseif ($repairUsed) {
    Write-Output '- 自动验真：先发现漂移，已安全修复并复查通过。'
}
else {
    Write-Output '- 自动验真：通过。'
}
Write-Output ('- 自动建任务：{0}' -f $Title)
if (-not [string]::IsNullOrWhiteSpace($activeTaskId)) {
    Write-Output ('- 当前激活任务：{0}' -f $activeTaskId)
}
Write-Output '- 下一步：留在当前会话，直接判断瓶颈并开始，不用切到 PowerShell。'
