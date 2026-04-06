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

    $commandOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $commandText *>&1 | Out-String)
    $actualExitCode = $LASTEXITCODE

    if ($actualExitCode -ne $ExpectedExitCode) {
        if (-not [string]::IsNullOrWhiteSpace($commandOutput)) {
            Write-Host $commandOutput.TrimEnd()
        }
        throw "测试失败：$TestName 期望退出码 $ExpectedExitCode，实际为 $actualExitCode。"
    }

    $caseResultText = if ($ExpectedExitCode -eq 0) {
        '已按预期放行'
    }
    else {
        '已按预期拦截'
    }
    Write-Host ("PASS CASE: {0} -> {1}" -f $TestName, $caseResultText) -ForegroundColor DarkGray
}

function Find-LineMatch {
    param(
        [string[]]$Lines,
        [string]$Pattern
    )

    $lineIndex = [Array]::FindIndex(
        $Lines,
        [Predicate[string]]{
            param($line)
            return $line -match $Pattern
        }
    )

    if ($lineIndex -lt 0) {
        return $null
    }

    return [pscustomobject]@{
        Index = $lineIndex
        LineText = $Lines[$lineIndex]
    }
}

$testCases = @(
    @{
        Name = 'allow-public-docs'
        Paths = @('README.md', 'docs/40-执行/10-本地安全提交流程.md')
        ExpectedExitCode = 0
    },
    @{
        Name = 'allow-root-install-wrapper'
        Paths = @('install.cmd', 'docs/30-方案/02-V4-目录锁定清单.md')
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
    },
    @{
        Name = 'allow-codex-home-export-consistency'
        Paths = @('codex-home-export/README.md', 'codex-home-export/manifest.json', 'codex-home-export/VERSION.json')
        ExpectedExitCode = 0
    },
    @{
        Name = 'block-codex-home-export-managed-change-without-version'
        Paths = @('codex-home-export/README.md')
        ExpectedExitCode = 1
    },
    @{
        Name = 'allow-panel-command-consistency'
        Paths = @('AGENTS.md', 'codex-home-export/VERSION.json', 'codex-home-export/panel-acceptance-checklist.md', 'docs/40-执行/03-面板入口验收.md')
        ExpectedExitCode = 0
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

 $unapprovedCodexProbeRelativePath = '.codex/chancellor/__gate-unapproved-probe.ps1'
$unapprovedCodexProbePath = Join-Path $repoRootPath ($unapprovedCodexProbeRelativePath -replace '/', '\')
try {
    [System.IO.File]::WriteAllText($unapprovedCodexProbePath, "Write-Host 'probe'" + [Environment]::NewLine, $utf8NoBom)
    git -C $repoRootPath add -- $unapprovedCodexProbeRelativePath | Out-Null
    Invoke-GateForTestCase -Paths @($unapprovedCodexProbeRelativePath) -ExpectedExitCode 1 -TestName 'block-unapproved-codex-tracked-file'
}
finally {
    git -C $repoRootPath reset HEAD -- $unapprovedCodexProbeRelativePath 2>$null | Out-Null
    if (Test-Path $unapprovedCodexProbePath) {
        Remove-Item -LiteralPath $unapprovedCodexProbePath -Force
    }
}

$secretEnvProbeRelativePath = '.env.local'
$secretEnvProbePath = Join-Path $repoRootPath $secretEnvProbeRelativePath
try {
    [System.IO.File]::WriteAllText($secretEnvProbePath, "OPENAI_API_KEY=test-key" + [Environment]::NewLine, $utf8NoBom)
    Invoke-GateForTestCase -Paths @($secretEnvProbeRelativePath) -ExpectedExitCode 1 -TestName 'block-sensitive-file-name'
}
finally {
    if (Test-Path $secretEnvProbePath) {
        Remove-Item -LiteralPath $secretEnvProbePath -Force
    }
}

$safePlaceholderProbeRelativePath = 'safe-placeholder-probe.md'
$safePlaceholderProbePath = Join-Path $repoRootPath $safePlaceholderProbeRelativePath
try {
    [System.IO.File]::WriteAllText($safePlaceholderProbePath, "OPENAI_API_KEY=test-key" + [Environment]::NewLine, $utf8NoBom)
    Invoke-GateForTestCase -Paths @($safePlaceholderProbeRelativePath) -ExpectedExitCode 0 -TestName 'allow-safe-placeholder-content'
}
finally {
    if (Test-Path $safePlaceholderProbePath) {
        Remove-Item -LiteralPath $safePlaceholderProbePath -Force
    }
}

$secretContentProbeRelativePath = 'secret-content-probe.md'
$secretContentProbePath = Join-Path $repoRootPath $secretContentProbeRelativePath
try {
    $fakeOpenAiToken = ('sk' + '-' + ('a' * 32))
    [System.IO.File]::WriteAllText($secretContentProbePath, ("token={0}" -f $fakeOpenAiToken) + [Environment]::NewLine, $utf8NoBom)
    Invoke-GateForTestCase -Paths @($secretContentProbeRelativePath) -ExpectedExitCode 1 -TestName 'block-sensitive-content-pattern'
}
finally {
    if (Test-Path $secretContentProbePath) {
        Remove-Item -LiteralPath $secretContentProbePath -Force
    }
}

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
$docsReadmeStartupEntrySourceLineText = '- `00-导航/01-V4-重启导读.md` 是启动阶段唯一对外总入口。'
$docsReadmeStartupCoreSourceLineText = '- 启动阶段核心入口以 `00-导航/01-V4-重启导读.md` 的 `先看什么` 为准，`docs/README.md` 不再重复抄整套入口清单。'
$docsReadmeStartupPhaseSourceLineText = '- 启动阶段顺序以 `00-导航/01-V4-重启导读.md` 的 `启动阶段真源` 为准；需要细项时直接查看该文档。'
$docsReadmeTargetEntrySourceLineText = '- `40-执行/12-V4-Target-实施计划.md` 是 Target 主线唯一对外总入口。'
$docsReadmeTargetMainlineSourceLineText = '- Target 主线入口以 `40-执行/12-V4-Target-实施计划.md` 的 `Target 主线真源` 为准，`docs/README.md` 不再重复抄整套主线清单。'
$docsReadmeTargetOrderSourceLineText = '- Target 推进顺序以 `40-执行/12-V4-Target-实施计划.md` 的 `推荐推进顺序` 为准；需要细项时直接查看该文档。'
$docsReadmeMaintenanceEntrySourceLineText = '- `40-执行/13-维护层总入口.md` 是维护层唯一对外总入口。'
$docsReadmeMaintenanceMainlineSourceLineText = '- 维护层主线顺序以 `40-执行/13-维护层总入口.md` 的 `维护层主线真源` 为准，`docs/README.md` 不再重复抄整套主线清单。'
$docsReadmeMaintenanceCapabilitySourceLineText = '- 维护层补充能力以 `40-执行/13-维护层总入口.md` 的 `当前维护层能力` 为准；需要细项时直接查看该文档。'
$docsReadmeGovernanceSummaryLineText = '- 核心治理与公开边界以 `reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md`、`reference/02-仓库卫生与命名规范.md`、`30-方案/02-V4-目录锁定清单.md`、`30-方案/08-V4-治理审计候选规范.md`、`40-执行/10-本地安全提交流程.md`、`40-执行/14-维护层动作矩阵与收口检查表.md`、`40-执行/21-关键配置来源与漂移复核模板.md` 为准。'

if ($docsReadmeLines -notcontains $docsReadmeGovernanceSummaryLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $docsReadmeGovernanceSummaryLineText"
}

try {
    $driftedDocsReadmeContent = (Get-Content $docsReadmePath -Raw).Replace('`reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md`', '`reference/01-占位漂移.md`')
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-public-rule-entry-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

$agentsPath = Join-Path $repoRootPath 'AGENTS.md'
$originalAgentsBytes = [System.IO.File]::ReadAllBytes($agentsPath)
$agentsLines = Get-Content $agentsPath
$agentsRuleGuideLineText = '- 反屎山总纲：`docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md`'
$agentsLockListLineText = '- 目录锁定清单：`docs/30-方案/02-V4-目录锁定清单.md`'
$agentsRuleGuideIndex = [Array]::IndexOf($agentsLines, $agentsRuleGuideLineText)
$agentsLockListIndex = [Array]::IndexOf($agentsLines, $agentsLockListLineText)

if ($agentsRuleGuideIndex -lt 0 -or $agentsLockListIndex -lt 0) {
    throw "测试前置条件不满足：$agentsPath 中缺少 AGENTS 核心约束测试行。"
}

try {
    $driftedAgentsLines = @(
        $agentsLines | Where-Object { $_ -ne $agentsRuleGuideLineText }
    )
    $driftedAgentsContent = ($driftedAgentsLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($agentsPath, $driftedAgentsContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('AGENTS.md') -ExpectedExitCode 1 -TestName 'block-agents-core-rule-entry-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($agentsPath, $originalAgentsBytes)
}

if ($agentsRuleGuideIndex -gt $agentsLockListIndex) {
    throw "测试前置条件不满足：$agentsPath 中 AGENTS 核心约束顺序已不是当前现状。"
}

try {
    $driftedAgentsLines = @($agentsLines)
    $driftedAgentsLines[$agentsRuleGuideIndex] = $agentsLockListLineText
    $driftedAgentsLines[$agentsLockListIndex] = $agentsRuleGuideLineText
    $driftedAgentsContent = ($driftedAgentsLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($agentsPath, $driftedAgentsContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('AGENTS.md') -ExpectedExitCode 1 -TestName 'block-agents-core-rule-entry-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($agentsPath, $originalAgentsBytes)
}

$localSafeFlowPath = Join-Path $repoRootPath 'docs/40-执行/10-本地安全提交流程.md'
$originalLocalSafeFlowBytes = [System.IO.File]::ReadAllBytes($localSafeFlowPath)
$localSafeFlowLines = Get-Content $localSafeFlowPath
$coreGovernanceRuleSourceMarkerLineText = '## 核心治理规则入口真源'

if ($localSafeFlowLines -notcontains $coreGovernanceRuleSourceMarkerLineText) {
    throw "测试前置条件不满足：$localSafeFlowPath 中缺少 $coreGovernanceRuleSourceMarkerLineText"
}

try {
    $driftedLocalSafeFlowLines = @(
        $localSafeFlowLines | Where-Object { $_ -ne $coreGovernanceRuleSourceMarkerLineText }
    )
    $driftedLocalSafeFlowContent = ($driftedLocalSafeFlowLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($localSafeFlowPath, $driftedLocalSafeFlowContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/10-本地安全提交流程.md') -ExpectedExitCode 1 -TestName 'block-core-rule-source-section-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($localSafeFlowPath, $originalLocalSafeFlowBytes)
}

$coreGovernanceRuleSourceMiddleLineText = '2. `docs/reference/02-仓库卫生与命名规范.md`'

if ($localSafeFlowLines -notcontains $coreGovernanceRuleSourceMiddleLineText) {
    throw "测试前置条件不满足：$localSafeFlowPath 中缺少 $coreGovernanceRuleSourceMiddleLineText"
}

try {
    $driftedLocalSafeFlowLines = @(
        $localSafeFlowLines | Where-Object { $_ -ne $coreGovernanceRuleSourceMiddleLineText }
    )
    $driftedLocalSafeFlowContent = ($driftedLocalSafeFlowLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($localSafeFlowPath, $driftedLocalSafeFlowContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/10-本地安全提交流程.md') -ExpectedExitCode 1 -TestName 'block-core-rule-source-middle-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($localSafeFlowPath, $originalLocalSafeFlowBytes)
}

$coreGovernanceRuleSourceGuideLineText = '1. `docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md`'
$coreGovernanceRuleSourceNamingLineText = '2. `docs/reference/02-仓库卫生与命名规范.md`'
$coreGovernanceRuleSourceGuideIndex = [Array]::IndexOf($localSafeFlowLines, $coreGovernanceRuleSourceGuideLineText)
$coreGovernanceRuleSourceNamingIndex = [Array]::IndexOf($localSafeFlowLines, $coreGovernanceRuleSourceNamingLineText)

if ($coreGovernanceRuleSourceGuideIndex -lt 0 -or $coreGovernanceRuleSourceNamingIndex -lt 0) {
    throw '测试前置条件不满足：核心治理规则入口真源顺序测试行缺失。'
}

if ($coreGovernanceRuleSourceGuideIndex -gt $coreGovernanceRuleSourceNamingIndex) {
    throw '测试前置条件不满足：核心治理规则入口真源顺序已不是当前现状。'
}

try {
    $driftedLocalSafeFlowLines = @($localSafeFlowLines)
    $driftedLocalSafeFlowLines[$coreGovernanceRuleSourceGuideIndex] = $coreGovernanceRuleSourceNamingLineText
    $driftedLocalSafeFlowLines[$coreGovernanceRuleSourceNamingIndex] = $coreGovernanceRuleSourceGuideLineText
    $driftedLocalSafeFlowContent = ($driftedLocalSafeFlowLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($localSafeFlowPath, $driftedLocalSafeFlowContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/10-本地安全提交流程.md') -ExpectedExitCode 1 -TestName 'block-core-rule-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($localSafeFlowPath, $originalLocalSafeFlowBytes)
}

$blockedTaskReadmeExceptionSourceLineText = 'except:.codex/chancellor/tasks/README.md'
$blockedLogsPrefixSourceLineText = 'prefix:logs/'
$blockedLogsReadmeExceptionSourceLineText = 'except:logs/README.md'

if ($localSafeFlowLines -notcontains $blockedTaskReadmeExceptionSourceLineText -or $localSafeFlowLines -notcontains $blockedLogsPrefixSourceLineText -or $localSafeFlowLines -notcontains $blockedLogsReadmeExceptionSourceLineText) {
    throw '测试前置条件不满足：公开提交禁止路径真源测试行缺失。'
}

Invoke-GateForTestCase -Paths @('.codex/chancellor/tasks/README.md') -ExpectedExitCode 0 -TestName 'allow-task-readme-prefix-exception'

try {
    $driftedLocalSafeFlowLines = @(
        $localSafeFlowLines | Where-Object { $_ -ne $blockedTaskReadmeExceptionSourceLineText }
    )
    $driftedLocalSafeFlowContent = ($driftedLocalSafeFlowLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($localSafeFlowPath, $driftedLocalSafeFlowContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('.codex/chancellor/tasks/README.md') -ExpectedExitCode 1 -TestName 'block-task-readme-prefix-exception-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($localSafeFlowPath, $originalLocalSafeFlowBytes)
}

try {
    $driftedLocalSafeFlowLines = @(
        $localSafeFlowLines | Where-Object { $_ -ne $blockedLogsPrefixSourceLineText }
    )
    $driftedLocalSafeFlowContent = ($driftedLocalSafeFlowLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($localSafeFlowPath, $driftedLocalSafeFlowContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('logs/probe.md') -ExpectedExitCode 0 -TestName 'allow-blocked-prefix-source-sync'
}
finally {
    [System.IO.File]::WriteAllBytes($localSafeFlowPath, $originalLocalSafeFlowBytes)
}

try {
    $driftedLocalSafeFlowLines = @(
        $localSafeFlowLines | Where-Object { $_ -ne $blockedLogsReadmeExceptionSourceLineText }
    )
    $driftedLocalSafeFlowContent = ($driftedLocalSafeFlowLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($localSafeFlowPath, $driftedLocalSafeFlowContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('logs/README.md') -ExpectedExitCode 1 -TestName 'block-blocked-prefix-exception-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($localSafeFlowPath, $originalLocalSafeFlowBytes)
}

$blockedTempGeneratedPrefixSourceLineText = 'prefix:temp/generated/'
$blockedLogsPrefixSourceIndex = [Array]::IndexOf($localSafeFlowLines, $blockedLogsPrefixSourceLineText)
$blockedTempGeneratedPrefixSourceIndex = [Array]::IndexOf($localSafeFlowLines, $blockedTempGeneratedPrefixSourceLineText)

if ($blockedLogsPrefixSourceIndex -lt 0 -or $blockedTempGeneratedPrefixSourceIndex -lt 0) {
    throw '测试前置条件不满足：公开提交禁止路径前缀顺序测试行缺失。'
}

if ($blockedLogsPrefixSourceIndex -gt $blockedTempGeneratedPrefixSourceIndex) {
    throw '测试前置条件不满足：公开提交禁止路径前缀顺序已不是当前现状。'
}

try {
    $driftedLocalSafeFlowLines = @($localSafeFlowLines)
    $driftedLocalSafeFlowLines[$blockedLogsPrefixSourceIndex] = $blockedTempGeneratedPrefixSourceLineText
    $driftedLocalSafeFlowLines[$blockedTempGeneratedPrefixSourceIndex] = $blockedLogsPrefixSourceLineText
    $driftedLocalSafeFlowContent = ($driftedLocalSafeFlowLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($localSafeFlowPath, $driftedLocalSafeFlowContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/10-本地安全提交流程.md') -ExpectedExitCode 1 -TestName 'block-blocked-prefix-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($localSafeFlowPath, $originalLocalSafeFlowBytes)
}

$blockedTempGeneratedReadmeExceptionSourceLineText = 'except:temp/generated/README.md'
$blockedTaskReadmeExceptionSourceIndex = [Array]::IndexOf($localSafeFlowLines, $blockedTaskReadmeExceptionSourceLineText)
$blockedLogsReadmeExceptionSourceIndex = [Array]::IndexOf($localSafeFlowLines, $blockedLogsReadmeExceptionSourceLineText)
$blockedTempGeneratedReadmeExceptionSourceIndex = [Array]::IndexOf($localSafeFlowLines, $blockedTempGeneratedReadmeExceptionSourceLineText)

if ($blockedTaskReadmeExceptionSourceIndex -lt 0 -or $blockedLogsReadmeExceptionSourceIndex -lt 0 -or $blockedTempGeneratedReadmeExceptionSourceIndex -lt 0) {
    throw '测试前置条件不满足：公开提交禁止路径例外顺序测试行缺失。'
}

if ($blockedTaskReadmeExceptionSourceIndex -gt $blockedLogsReadmeExceptionSourceIndex -or $blockedLogsReadmeExceptionSourceIndex -gt $blockedTempGeneratedReadmeExceptionSourceIndex) {
    throw '测试前置条件不满足：公开提交禁止路径例外顺序已不是当前现状。'
}

try {
    $driftedLocalSafeFlowLines = @($localSafeFlowLines)
    $driftedLocalSafeFlowLines[$blockedTaskReadmeExceptionSourceIndex] = $blockedLogsReadmeExceptionSourceLineText
    $driftedLocalSafeFlowLines[$blockedLogsReadmeExceptionSourceIndex] = $blockedTaskReadmeExceptionSourceLineText
    $driftedLocalSafeFlowContent = ($driftedLocalSafeFlowLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($localSafeFlowPath, $driftedLocalSafeFlowContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/10-本地安全提交流程.md') -ExpectedExitCode 1 -TestName 'block-blocked-prefix-exception-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($localSafeFlowPath, $originalLocalSafeFlowBytes)
}

if ($docsReadmeLines -notcontains $docsReadmeTargetEntrySourceLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $docsReadmeTargetEntrySourceLineText"
}

try {
    $driftedDocsReadmeLines = @(
        $docsReadmeLines | Where-Object { $_ -ne $docsReadmeTargetEntrySourceLineText }
    )
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-target-entry-source-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

if ($docsReadmeLines -notcontains $docsReadmeTargetMainlineSourceLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $docsReadmeTargetMainlineSourceLineText"
}

try {
    $driftedDocsReadmeContent = (Get-Content $docsReadmePath -Raw).Replace($docsReadmeTargetMainlineSourceLineText, '- Target 主线以后再整理。')
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-target-mainline-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

if ($docsReadmeLines -notcontains $docsReadmeTargetOrderSourceLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $docsReadmeTargetOrderSourceLineText"
}

try {
    $driftedDocsReadmeContent = (Get-Content $docsReadmePath -Raw).Replace($docsReadmeTargetOrderSourceLineText, '- Target 顺序以后再补。')
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-target-order-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

if ($docsReadmeLines -notcontains $docsReadmeStartupEntrySourceLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $docsReadmeStartupEntrySourceLineText"
}

try {
    $driftedDocsReadmeLines = @(
        $docsReadmeLines | Where-Object { $_ -ne $docsReadmeStartupEntrySourceLineText }
    )
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-startup-entry-source-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

if ($docsReadmeLines -notcontains $docsReadmeStartupCoreSourceLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $docsReadmeStartupCoreSourceLineText"
}

try {
    $driftedDocsReadmeContent = (Get-Content $docsReadmePath -Raw).Replace($docsReadmeStartupCoreSourceLineText, '- 启动阶段核心入口以后再整理。')
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-startup-core-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

if ($docsReadmeLines -notcontains $docsReadmeStartupPhaseSourceLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $docsReadmeStartupPhaseSourceLineText"
}

try {
    $driftedDocsReadmeContent = (Get-Content $docsReadmePath -Raw).Replace($docsReadmeStartupPhaseSourceLineText, '- 启动阶段顺序以后再补。')
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-startup-phase-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

$docsReadmeStartupCoreSourceIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeStartupCoreSourceLineText)
$docsReadmeStartupPhaseSourceIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeStartupPhaseSourceLineText)

if ($docsReadmeStartupCoreSourceIndex -lt 0 -or $docsReadmeStartupPhaseSourceIndex -lt 0) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少启动阶段入口真源说明测试行。"
}

if ($docsReadmeStartupCoreSourceIndex -gt $docsReadmeStartupPhaseSourceIndex) {
    throw "测试前置条件不满足：$docsReadmePath 中启动阶段入口真源说明顺序已不是当前现状。"
}

try {
    $driftedDocsReadmeLines = @($docsReadmeLines)
    $driftedDocsReadmeLines[$docsReadmeStartupCoreSourceIndex] = $docsReadmeStartupPhaseSourceLineText
    $driftedDocsReadmeLines[$docsReadmeStartupPhaseSourceIndex] = $docsReadmeStartupCoreSourceLineText
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-startup-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

$restartGuidePath = Join-Path $repoRootPath 'docs/00-导航/01-V4-重启导读.md'
$originalRestartGuideBytes = [System.IO.File]::ReadAllBytes($restartGuidePath)
$restartGuideLines = Get-Content $restartGuidePath
$restartGuideDecisionLineText = '2. `docs/20-决策/01-V4-重启ADR.md`'
$restartGuideAssetLineText = '3. `docs/10-输入材料/01-旧仓必需资产清单.md`'
$restartGuideDecisionIndex = [Array]::IndexOf($restartGuideLines, $restartGuideDecisionLineText)
$restartGuideAssetIndex = [Array]::IndexOf($restartGuideLines, $restartGuideAssetLineText)

if ($restartGuideDecisionIndex -lt 0 -or $restartGuideAssetIndex -lt 0) {
    throw "测试前置条件不满足：$restartGuidePath 中缺少重启导读顺序真源测试行。"
}

if ($restartGuideDecisionIndex -gt $restartGuideAssetIndex) {
    throw "测试前置条件不满足：$restartGuidePath 中重启导读顺序已不是当前现状。"
}

try {
    $driftedRestartGuideLines = @($restartGuideLines)
    $driftedRestartGuideLines[$restartGuideDecisionIndex] = $restartGuideAssetLineText
    $driftedRestartGuideLines[$restartGuideAssetIndex] = $restartGuideDecisionLineText
    $driftedRestartGuideContent = ($driftedRestartGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($restartGuidePath, $driftedRestartGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/01-V4-重启导读.md') -ExpectedExitCode 1 -TestName 'block-restart-guide-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($restartGuidePath, $originalRestartGuideBytes)
}

$restartGuideRuleHygieneLineText = '11. `docs/reference/02-仓库卫生与命名规范.md`'

if ($restartGuideLines -notcontains $restartGuideRuleHygieneLineText) {
    throw "测试前置条件不满足：$restartGuidePath 中缺少 $restartGuideRuleHygieneLineText"
}

try {
    $driftedRestartGuideLines = @(
        $restartGuideLines | Where-Object { $_ -ne $restartGuideRuleHygieneLineText }
    )
    $driftedRestartGuideContent = ($driftedRestartGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($restartGuidePath, $driftedRestartGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/01-V4-重启导读.md') -ExpectedExitCode 1 -TestName 'block-restart-guide-source-middle-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($restartGuidePath, $originalRestartGuideBytes)
}

$startupPhaseSourceMarkerLineText = '## 启动阶段真源'
$startupPhaseSourceDecisionLineText = 'docs/20-决策/01-V4-重启ADR.md'
$startupPhaseSourceMarkerIndex = [Array]::IndexOf($restartGuideLines, $startupPhaseSourceMarkerLineText)
$startupPhaseSourceDecisionIndex = -1
for ($lineIndex = $startupPhaseSourceMarkerIndex + 1; $lineIndex -lt $restartGuideLines.Count; $lineIndex++) {
    if ($restartGuideLines[$lineIndex] -like '## *') {
        break
    }

    if ($restartGuideLines[$lineIndex] -eq $startupPhaseSourceDecisionLineText) {
        $startupPhaseSourceDecisionIndex = $lineIndex
        break
    }
}

if ($startupPhaseSourceMarkerIndex -lt 0 -or $startupPhaseSourceDecisionIndex -lt 0) {
    throw "测试前置条件不满足：$restartGuidePath 中缺少启动阶段真源测试行。"
}

try {
    $driftedRestartGuideLines = New-Object System.Collections.Generic.List[string]
    foreach ($lineIndex in 0..($restartGuideLines.Count - 1)) {
        if ($lineIndex -ne $startupPhaseSourceDecisionIndex) {
            [void]$driftedRestartGuideLines.Add($restartGuideLines[$lineIndex])
        }
    }
    $driftedRestartGuideContent = ($driftedRestartGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($restartGuidePath, $driftedRestartGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/01-V4-重启导读.md') -ExpectedExitCode 1 -TestName 'block-startup-phase-source-boundary-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($restartGuidePath, $originalRestartGuideBytes)
}

$startupPhaseSourceInputLineText = 'docs/10-输入材料/01-旧仓必需资产清单.md'
$startupPhaseSourceInputIndex = -1
for ($lineIndex = $startupPhaseSourceMarkerIndex + 1; $lineIndex -lt $restartGuideLines.Count; $lineIndex++) {
    if ($restartGuideLines[$lineIndex] -like '## *') {
        break
    }

    if ($restartGuideLines[$lineIndex] -eq $startupPhaseSourceInputLineText) {
        $startupPhaseSourceInputIndex = $lineIndex
        break
    }
}

if ($startupPhaseSourceDecisionIndex -gt $startupPhaseSourceInputIndex -or $startupPhaseSourceInputIndex -lt 0) {
    throw "测试前置条件不满足：$restartGuidePath 中启动阶段真源顺序已不是当前现状。"
}

try {
    $driftedRestartGuideLines = @($restartGuideLines)
    $driftedRestartGuideLines[$startupPhaseSourceDecisionIndex] = $startupPhaseSourceInputLineText
    $driftedRestartGuideLines[$startupPhaseSourceInputIndex] = $startupPhaseSourceDecisionLineText
    $driftedRestartGuideContent = ($driftedRestartGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($restartGuidePath, $driftedRestartGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/01-V4-重启导读.md') -ExpectedExitCode 1 -TestName 'block-startup-phase-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($restartGuidePath, $originalRestartGuideBytes)
}

if ($docsReadmeLines -notcontains $docsReadmeMaintenanceEntrySourceLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $docsReadmeMaintenanceEntrySourceLineText"
}

try {
    $driftedDocsReadmeLines = @(
        $docsReadmeLines | Where-Object { $_ -ne $docsReadmeMaintenanceEntrySourceLineText }
    )
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-maintenance-entry-source-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

if ($docsReadmeLines -notcontains $docsReadmeMaintenanceMainlineSourceLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $docsReadmeMaintenanceMainlineSourceLineText"
}

try {
    $driftedDocsReadmeContent = (Get-Content $docsReadmePath -Raw).Replace($docsReadmeMaintenanceMainlineSourceLineText, '- 维护层主线以后再整理。')
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-maintenance-mainline-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

if ($docsReadmeLines -notcontains $docsReadmeMaintenanceCapabilitySourceLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $docsReadmeMaintenanceCapabilitySourceLineText"
}

try {
    $driftedDocsReadmeContent = (Get-Content $docsReadmePath -Raw).Replace($docsReadmeMaintenanceCapabilitySourceLineText, '- 维护层补充能力以后再补。')
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-maintenance-capability-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

$maintenanceGuidePath = Join-Path $repoRootPath 'docs/40-执行/13-维护层总入口.md'
$originalMaintenanceGuideBytes = [System.IO.File]::ReadAllBytes($maintenanceGuidePath)
$maintenanceGuideLines = Get-Content $maintenanceGuidePath
$removedMaintenanceGuideArchiveSourceLineText = '- 文档：`docs/90-归档/01-执行区证据稿归档规则.md`'

if ($maintenanceGuideLines -notcontains $removedMaintenanceGuideArchiveSourceLineText) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中缺少 $removedMaintenanceGuideArchiveSourceLineText"
}

try {
    $driftedMaintenanceGuideLines = @(
        $maintenanceGuideLines | Where-Object { $_ -ne $removedMaintenanceGuideArchiveSourceLineText }
    )
    $driftedMaintenanceGuideContent = ($driftedMaintenanceGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($maintenanceGuidePath, $driftedMaintenanceGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/13-维护层总入口.md') -ExpectedExitCode 1 -TestName 'block-maintenance-capability-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceGuidePath, $originalMaintenanceGuideBytes)
}

$removedMaintenanceGuidePanelSourceLineText = '- 文档：`docs/40-执行/03-面板入口验收.md`'

if ($maintenanceGuideLines -notcontains $removedMaintenanceGuidePanelSourceLineText) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中缺少 $removedMaintenanceGuidePanelSourceLineText"
}

try {
    $driftedMaintenanceGuideLines = @(
        $maintenanceGuideLines | Where-Object { $_ -ne $removedMaintenanceGuidePanelSourceLineText }
    )
    $driftedMaintenanceGuideContent = ($driftedMaintenanceGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($maintenanceGuidePath, $driftedMaintenanceGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/13-维护层总入口.md') -ExpectedExitCode 1 -TestName 'block-maintenance-capability-panel-entry-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceGuidePath, $originalMaintenanceGuideBytes)
}

$maintenanceGuidePanelCapabilityLineText = '- 文档：`docs/40-执行/03-面板入口验收.md`'
$maintenanceGuideGovernanceCapabilityLineText = '- 文档：`docs/30-方案/08-V4-治理审计候选规范.md`'
$maintenanceGuideConfigCapabilityLineText = '- 文档：`docs/40-执行/21-关键配置来源与漂移复核模板.md`'
$maintenanceGuidePanelCapabilityIndex = [Array]::IndexOf($maintenanceGuideLines, $maintenanceGuidePanelCapabilityLineText)
$maintenanceGuideGovernanceCapabilityIndex = [Array]::IndexOf($maintenanceGuideLines, $maintenanceGuideGovernanceCapabilityLineText)
$maintenanceGuideConfigCapabilityIndex = [Array]::IndexOf($maintenanceGuideLines, $maintenanceGuideConfigCapabilityLineText)

if ($maintenanceGuidePanelCapabilityIndex -lt 0 -or $maintenanceGuideGovernanceCapabilityIndex -lt 0 -or $maintenanceGuideConfigCapabilityIndex -lt 0) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中缺少维护层能力顺序测试行。"
}

if ($maintenanceGuidePanelCapabilityIndex -gt $maintenanceGuideGovernanceCapabilityIndex -or $maintenanceGuideGovernanceCapabilityIndex -gt $maintenanceGuideConfigCapabilityIndex) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中维护层能力顺序已不是当前现状。"
}

try {
    $driftedMaintenanceGuideLines = @($maintenanceGuideLines)
    $driftedMaintenanceGuideLines[$maintenanceGuidePanelCapabilityIndex] = $maintenanceGuideGovernanceCapabilityLineText
    $driftedMaintenanceGuideLines[$maintenanceGuideGovernanceCapabilityIndex] = $maintenanceGuidePanelCapabilityLineText
    $driftedMaintenanceGuideContent = ($driftedMaintenanceGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($maintenanceGuidePath, $driftedMaintenanceGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/13-维护层总入口.md') -ExpectedExitCode 1 -TestName 'block-maintenance-capability-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceGuidePath, $originalMaintenanceGuideBytes)
}

$maintenanceGuideMainlineMarkerLineText = '## 维护层主线真源'
$maintenanceGuideMainlineGateLineText = 'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
$maintenanceGuideMainlineConcurrentLineText = 'docs/40-执行/20-复杂并存汇报骨架模板.md'
$maintenanceGuideRecommendedOrderPushGateLineText = '5. 若当前轮准备推送公开改动，确认 `pre-push` 治理门禁已安装并可自动触发'
$maintenanceGuideRecommendedOrderCloseoutLineText = '6. 完成动作后，按收口检查表确认本轮已闭环'
$maintenanceGuideDefaultBoundaryLineText = '- 维护层动作继续视为维护层，不对普通面板使用者外露复杂终端流程。'
$maintenanceGuideDefaultReuseLineText = '- 维护层动作优先复用当前仓已有规则与脚本，不另起外部依赖。'
$maintenanceGuideDefaultSyncLineText = '- 维护层动作完成后，如影响入口口径，应同步更新总览、首页或 docs 入口。'
$maintenanceGuideTriggerUnclearLineText = '- 不确定该先看哪份维护文档时'
$maintenanceGuideTriggerBeforeActionLineText = '- 准备开始维护层动作前'
$maintenanceGuideTriggerHandoffLineText = '- 需要交接维护动作给下一位执行者时'
$maintenanceGuideValueSingleEntryLineText = '- 把零散维护规则收成单一入口。'
$maintenanceGuideValueShortenPathLineText = '- 缩短维护层上手路径。'
$maintenanceGuideValueReduceMisuseLineText = '- 降低因找错入口而导致的误操作概率。'
$maintenanceGuideMainlineGateIndex = [Array]::IndexOf($maintenanceGuideLines, $maintenanceGuideMainlineGateLineText)
$maintenanceGuideMainlineConcurrentIndex = [Array]::IndexOf($maintenanceGuideLines, $maintenanceGuideMainlineConcurrentLineText)

if ($maintenanceGuideLines -notcontains $maintenanceGuideMainlineMarkerLineText -or $maintenanceGuideMainlineGateIndex -lt 0 -or $maintenanceGuideMainlineConcurrentIndex -lt 0) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中缺少维护层主线真源测试行。"
}

if ($maintenanceGuideMainlineGateIndex -gt $maintenanceGuideMainlineConcurrentIndex) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中维护层主线真源顺序已不是当前现状。"
}

try {
    $driftedMaintenanceGuideLines = @($maintenanceGuideLines)
    $driftedMaintenanceGuideLines[$maintenanceGuideMainlineGateIndex] = $maintenanceGuideMainlineConcurrentLineText
    $driftedMaintenanceGuideLines[$maintenanceGuideMainlineConcurrentIndex] = $maintenanceGuideMainlineGateLineText
    $driftedMaintenanceGuideContent = ($driftedMaintenanceGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($maintenanceGuidePath, $driftedMaintenanceGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/13-维护层总入口.md') -ExpectedExitCode 1 -TestName 'block-maintenance-mainline-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceGuidePath, $originalMaintenanceGuideBytes)
}

try {
    $driftedMaintenanceGuideLines = @(
        $maintenanceGuideLines | Where-Object { $_ -ne $maintenanceGuideMainlineGateLineText }
    )
    $driftedMaintenanceGuideContent = ($driftedMaintenanceGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($maintenanceGuidePath, $driftedMaintenanceGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/13-维护层总入口.md') -ExpectedExitCode 1 -TestName 'block-maintenance-mainline-source-middle-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceGuidePath, $originalMaintenanceGuideBytes)
}

$maintenanceGuideRecommendedOrderPushGateIndex = [Array]::IndexOf($maintenanceGuideLines, $maintenanceGuideRecommendedOrderPushGateLineText)
$maintenanceGuideRecommendedOrderCloseoutIndex = [Array]::IndexOf($maintenanceGuideLines, $maintenanceGuideRecommendedOrderCloseoutLineText)

if ($maintenanceGuideRecommendedOrderPushGateIndex -lt 0 -or $maintenanceGuideRecommendedOrderCloseoutIndex -lt 0) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中缺少推荐使用顺序测试行。"
}

if ($maintenanceGuideRecommendedOrderPushGateIndex -gt $maintenanceGuideRecommendedOrderCloseoutIndex) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中推荐使用顺序已不是当前现状。"
}

try {
    $driftedMaintenanceGuideLines = @($maintenanceGuideLines)
    $driftedMaintenanceGuideLines[$maintenanceGuideRecommendedOrderPushGateIndex] = $maintenanceGuideRecommendedOrderCloseoutLineText
    $driftedMaintenanceGuideLines[$maintenanceGuideRecommendedOrderCloseoutIndex] = $maintenanceGuideRecommendedOrderPushGateLineText
    $driftedMaintenanceGuideContent = ($driftedMaintenanceGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($maintenanceGuidePath, $driftedMaintenanceGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/13-维护层总入口.md') -ExpectedExitCode 1 -TestName 'block-maintenance-guide-recommended-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceGuidePath, $originalMaintenanceGuideBytes)
}

if ($maintenanceGuideLines -notcontains $maintenanceGuideDefaultBoundaryLineText -or $maintenanceGuideLines -notcontains $maintenanceGuideDefaultReuseLineText -or $maintenanceGuideLines -notcontains $maintenanceGuideDefaultSyncLineText) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中缺少当前默认原则测试行。"
}

try {
    $driftedMaintenanceGuideContent = (Get-Content $maintenanceGuidePath -Raw).Replace($maintenanceGuideDefaultSyncLineText, '- 维护层动作完成后，看情况再决定是否同步入口。')
    [System.IO.File]::WriteAllText($maintenanceGuidePath, $driftedMaintenanceGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/13-维护层总入口.md') -ExpectedExitCode 1 -TestName 'block-maintenance-guide-defaults-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceGuidePath, $originalMaintenanceGuideBytes)
}

if ($maintenanceGuideLines -notcontains $maintenanceGuideTriggerUnclearLineText -or $maintenanceGuideLines -notcontains $maintenanceGuideTriggerBeforeActionLineText -or $maintenanceGuideLines -notcontains $maintenanceGuideTriggerHandoffLineText) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中缺少什么时候优先看这份入口测试行。"
}

try {
    $driftedMaintenanceGuideContent = (Get-Content $maintenanceGuidePath -Raw).Replace($maintenanceGuideTriggerHandoffLineText, '- 最后再看看是否需要交接。')
    [System.IO.File]::WriteAllText($maintenanceGuidePath, $driftedMaintenanceGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/13-维护层总入口.md') -ExpectedExitCode 1 -TestName 'block-maintenance-guide-trigger-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceGuidePath, $originalMaintenanceGuideBytes)
}

if ($maintenanceGuideLines -notcontains $maintenanceGuideValueSingleEntryLineText -or $maintenanceGuideLines -notcontains $maintenanceGuideValueShortenPathLineText -or $maintenanceGuideLines -notcontains $maintenanceGuideValueReduceMisuseLineText) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中缺少本文档的价值测试行。"
}

try {
    $driftedMaintenanceGuideContent = (Get-Content $maintenanceGuidePath -Raw).Replace($maintenanceGuideValueReduceMisuseLineText, '- 最后再补一眼就好。')
    [System.IO.File]::WriteAllText($maintenanceGuidePath, $driftedMaintenanceGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/13-维护层总入口.md') -ExpectedExitCode 1 -TestName 'block-maintenance-guide-value-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceGuidePath, $originalMaintenanceGuideBytes)
}

$maintenanceMatrixPath = Join-Path $repoRootPath 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
$originalMaintenanceMatrixBytes = [System.IO.File]::ReadAllBytes($maintenanceMatrixPath)
$maintenanceMatrixConclusionLineText = '先用动作矩阵判断该走哪条维护路径，再按收口检查表完成留痕、导航同步、提交与推送。'
$maintenanceMatrixHeaderLineText = '| 动作类型 | 什么时候用 | 主入口 | 最低产出 | 公开仓边界 | 风险级别 |'
$maintenanceMatrixLocalSafeCommitRowLineText = '| 本地安全提交 | 有公开安全改动需要进入远端时 | `docs/40-执行/10-本地安全提交流程.md` | 一次串行 `add`/`commit`/`pull --rebase`/`push` | 只提交公开安全文件；禁止带上 `.codex/`、`logs/` | 低 |'
$maintenanceMatrixTaskPackSemiAutoRowLineText = '| 任务包半自动起包 | 需要开始一条新任务并保留本地运行态时 | `docs/40-执行/11-任务包半自动起包.md` | 任务包 5 件套骨架 + 收口提示 | 任务包运行态留在本地；不进入公开仓 | 低 |'
$maintenanceMatrixSyncSlotLineText = '- `收口要求`：完成同步后，确认 `03-面板入口验收.md` 与 `13-维护层总入口.md` 口径一致，并通过公开提交治理门禁。'
$maintenanceMatrixDecisionOrderLineText = '- `结束条件`：只有通过收口检查，才算本轮维护层动作结束。'
$maintenanceMatrixBasicCloseoutLineText = '- `下一步说明`：已经给出下一步建议，并说明是否需要主公拍板。'
$maintenanceMatrixGovernanceAuditLineText = '- `边界复核`：已经复核公开仓边界，确保 `.codex/`、`logs/`、`temp/generated/`、`.vscode/`、`.serena/` 等运行态与本地工具状态不进入公开仓。'
$maintenanceMatrixPublicBoundaryLineText = '- `本地运行态`：`.codex/chancellor/tasks/`、`.codex/chancellor/active-task.txt`、`logs/` 继续作为本地运行态与留痕区，不进入公开仓。'
$maintenanceMatrixPairingLineText = '- `公开口径变更前`：追加一次 `08-V4-治理审计候选规范.md` 对应的治理审计复核。'
$maintenanceMatrixValueLineText = '- `保留控制平面`：为后续更强自动化保留稳定的人类控制平面。'
$gatePackageDocPath = Join-Path $repoRootPath 'docs/40-执行/15-拍板包准备与收口规范.md'
$originalGatePackageDocBytes = [System.IO.File]::ReadAllBytes($gatePackageDocPath)
$gatePackageConclusionLineText = '当任务进入 `waiting_gate` 或存在 `must_gate` 事项时，应先形成标准拍板包，再向主公汇报，不直接把半成品判断抛给主公。'
$gatePackageTriggerLineText = '- `contract.yaml` 中 `must_gate` 不为空。'
$gatePackageMinimumCompositionLineText = '4. 建议：明确推荐项，并说明推荐理由。'
$gatePackageTemplateDocPath = Join-Path $repoRootPath 'docs/40-执行/16-拍板包半自动模板.md'
$originalGatePackageTemplateDocBytes = [System.IO.File]::ReadAllBytes($gatePackageTemplateDocPath)
$gatePackageTemplateConclusionLineText = '当任务已具备待拍板问题、且 `gates.yaml` 仍为空时，优先使用当前仓内的拍板包半自动模板，而不是手工分别改四个文件。'
$gatePackageTemplateScenarioLineText = '- `gates.yaml` 仍为 `items: []`。'
$gatePackageTemplateOutputLineText = '- `state.yaml`：切为 `waiting_gate`'
$gatePackageResolveDocPath = Join-Path $repoRootPath 'docs/40-执行/17-拍板结果回写模板.md'
$originalGatePackageResolveDocBytes = [System.IO.File]::ReadAllBytes($gatePackageResolveDocPath)
$gatePackageResolveConclusionLineText = '当主公已经拍板，且任务需要从 `waiting_gate` 恢复推进时，优先使用当前仓内的拍板结果回写模板，而不是手工分别改四个文件。'
$gatePackageResolveScenarioLineText = '- `gates.yaml` 中已存在 `pending` 状态的待拍板事项。'
$gatePackageResolveOutputLineText = '- `state.yaml`：恢复为新的真实状态，并更新 `next_action`'
$exceptionTemplateDocPath = Join-Path $repoRootPath 'docs/40-执行/18-异常路径与回退模板.md'
$originalExceptionTemplateDocBytes = [System.IO.File]::ReadAllBytes($exceptionTemplateDocPath)
$exceptionTemplateConclusionLineText = '当任务不能继续按正常链路推进时，优先使用当前仓内的异常路径与回退模板，而不是只在聊天里说明“先停一下”。'
$exceptionTemplateScenarioLineText = '- 当前动作失败，需暂停并保留恢复点。'
$exceptionTemplateOutputLineText = '- `state.yaml`：切换到异常后的真实状态，并更新 `next_action`'
$configReviewDocPath = Join-Path $repoRootPath 'docs/40-执行/21-关键配置来源与漂移复核模板.md'
$originalConfigReviewDocBytes = [System.IO.File]::ReadAllBytes($configReviewDocPath)
$configReviewSummaryLineText = '- `统一落盘复核`：再用本模板把配置来源、版本依据与漂移检查统一落进任务包。'
$configReviewTriggerLineText = '- `提交前预检落盘`：当前轮正在执行 `docs/40-执行/10-本地安全提交流程.md`，需要把提交前预检结果落盘。'
$configReviewResultSkeletonLineText = '- `下一步`：写清是否继续提交前收口。'
$configReviewDecisionLogSkeletonLineText = '- `影响`：写清是否可以继续进入提交前收口。'
$configReviewLongTermValueLineText = '- `目录内自含`：保持当前目录内自含，不引入额外系统或依赖。'
$configReviewOutputLineText = '- `先修平再提交`：复核后如发现漂移，优先修平口径，再继续提交。'
$configReviewScriptEntryLineText = '- `收口入口`：`docs/40-执行/14-维护层动作矩阵与收口检查表.md`'
$configReviewSourceLineText = '- `冻结边界依据`：`docs/30-方案/05-V4-Target-冻结清单.md`'
$concurrentRuleDocPath = Join-Path $repoRootPath 'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
$originalConcurrentRuleDocBytes = [System.IO.File]::ReadAllBytes($concurrentRuleDocPath)
$concurrentRuleSinglePrimaryLineText = '- `主阻塞唯一`：若同时存在多个阻塞，必须选出“当前最先阻断推进”的主阻塞。'
$concurrentRuleNextActorPriorityLineText = '- `running / ready / verifying / done`：无主阻塞，进入正常推进态。'
$concurrentRuleGatePriorityLineText = '- `次要待处理项留档`：未被选为主 gate 的事项继续保留在 `gates.yaml`，并在 `result.md` 中列为“次要待处理项”。'
$concurrentRuleGateExceptionDecisionLineText = '- `拍板回退先回写`：若拍板结果本身要求回退，先完成 `decided/dropped` 回写，再按异常模板切换到新的异常态。'
$concurrentRuleDocumentSplitLineText = '- `result.md`：写清“主阻塞”“次要待处理项”“恢复顺序”。'
$concurrentRuleReportOrderLineText = '- `恢复顺序`：最后说明一旦主阻塞解除，恢复顺序是什么。'
$concurrentRuleCloseoutCheckLineText = '- `恢复后重评`：是否已在恢复后重新评估主状态，而不是沿用旧状态。'
$concurrentReportDocPath = Join-Path $repoRootPath 'docs/40-执行/20-复杂并存汇报骨架模板.md'
$originalConcurrentReportDocBytes = [System.IO.File]::ReadAllBytes($concurrentReportDocPath)
$concurrentReportSummaryLineText = '- `一次性落盘`：再用本模板把 `result.md` 与 `decision-log.md` 一次性落盘。'
$concurrentReportTriggerLineText = '- `超出单一模板`：任务已经不适合只靠单一 gate 或单一异常模板表达。'
$concurrentReportOutputLineText = '- `状态同步`：如已确定当前主推进口径，可同步更新 `state.yaml`。'
$concurrentReportScriptEntryLineText = '- `收口`：`docs/40-执行/14-维护层动作矩阵与收口检查表.md`'
$concurrentReportSemiAutoWriteLineText = '- `SyncState`：如当前主状态已确定，允许同步更新 `state.yaml`。'
$concurrentReportResultSkeletonLineText = '- `治理复核结果`：写清主状态依据、次要待处理项、口径漂移与治理审计复核状态。'
$concurrentReportDecisionLogSkeletonLineText = '- `影响`：写清 `result.md` 与 `decision-log.md` 是否已统一口径。'
$concurrentReportValueLineText = '- `自动化入口`：为后续更强的复杂裁决自动化保留轻量入口。'

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixSyncSlotLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少 $maintenanceMatrixSyncSlotLineText"
}

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixDecisionOrderLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少 $maintenanceMatrixDecisionOrderLineText"
}

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixBasicCloseoutLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少 $maintenanceMatrixBasicCloseoutLineText"
}

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixGovernanceAuditLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少 $maintenanceMatrixGovernanceAuditLineText"
}

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixPublicBoundaryLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少 $maintenanceMatrixPublicBoundaryLineText"
}

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixPairingLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少 $maintenanceMatrixPairingLineText"
}

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixValueLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少 $maintenanceMatrixValueLineText"
}

if ((Get-Content $configReviewDocPath) -notcontains $configReviewSummaryLineText) {
    throw "测试前置条件不满足：$configReviewDocPath 中缺少 $configReviewSummaryLineText"
}

if ((Get-Content $configReviewDocPath) -notcontains $configReviewTriggerLineText) {
    throw "测试前置条件不满足：$configReviewDocPath 中缺少 $configReviewTriggerLineText"
}

if ((Get-Content $configReviewDocPath) -notcontains $configReviewResultSkeletonLineText) {
    throw "测试前置条件不满足：$configReviewDocPath 中缺少 $configReviewResultSkeletonLineText"
}

if ((Get-Content $configReviewDocPath) -notcontains $configReviewDecisionLogSkeletonLineText) {
    throw "测试前置条件不满足：$configReviewDocPath 中缺少 $configReviewDecisionLogSkeletonLineText"
}

if ((Get-Content $configReviewDocPath) -notcontains $configReviewLongTermValueLineText) {
    throw "测试前置条件不满足：$configReviewDocPath 中缺少 $configReviewLongTermValueLineText"
}

if ((Get-Content $configReviewDocPath) -notcontains $configReviewOutputLineText) {
    throw "测试前置条件不满足：$configReviewDocPath 中缺少 $configReviewOutputLineText"
}

if ((Get-Content $configReviewDocPath) -notcontains $configReviewScriptEntryLineText) {
    throw "测试前置条件不满足：$configReviewDocPath 中缺少 $configReviewScriptEntryLineText"
}

if ((Get-Content $configReviewDocPath) -notcontains $configReviewSourceLineText) {
    throw "测试前置条件不满足：$configReviewDocPath 中缺少 $configReviewSourceLineText"
}

if ((Get-Content $concurrentRuleDocPath) -notcontains $concurrentRuleSinglePrimaryLineText) {
    throw "测试前置条件不满足：$concurrentRuleDocPath 中缺少 $concurrentRuleSinglePrimaryLineText"
}

if ((Get-Content $concurrentRuleDocPath) -notcontains $concurrentRuleNextActorPriorityLineText) {
    throw "测试前置条件不满足：$concurrentRuleDocPath 中缺少 $concurrentRuleNextActorPriorityLineText"
}

if ((Get-Content $concurrentRuleDocPath) -notcontains $concurrentRuleGatePriorityLineText) {
    throw "测试前置条件不满足：$concurrentRuleDocPath 中缺少 $concurrentRuleGatePriorityLineText"
}

if ((Get-Content $concurrentRuleDocPath) -notcontains $concurrentRuleGateExceptionDecisionLineText) {
    throw "测试前置条件不满足：$concurrentRuleDocPath 中缺少 $concurrentRuleGateExceptionDecisionLineText"
}

if ((Get-Content $concurrentRuleDocPath) -notcontains $concurrentRuleDocumentSplitLineText) {
    throw "测试前置条件不满足：$concurrentRuleDocPath 中缺少 $concurrentRuleDocumentSplitLineText"
}

if ((Get-Content $concurrentRuleDocPath) -notcontains $concurrentRuleReportOrderLineText) {
    throw "测试前置条件不满足：$concurrentRuleDocPath 中缺少 $concurrentRuleReportOrderLineText"
}

if ((Get-Content $concurrentRuleDocPath) -notcontains $concurrentRuleCloseoutCheckLineText) {
    throw "测试前置条件不满足：$concurrentRuleDocPath 中缺少 $concurrentRuleCloseoutCheckLineText"
}

if ((Get-Content $concurrentReportDocPath) -notcontains $concurrentReportSummaryLineText) {
    throw "测试前置条件不满足：$concurrentReportDocPath 中缺少 $concurrentReportSummaryLineText"
}

if ((Get-Content $concurrentReportDocPath) -notcontains $concurrentReportTriggerLineText) {
    throw "测试前置条件不满足：$concurrentReportDocPath 中缺少 $concurrentReportTriggerLineText"
}

if ((Get-Content $concurrentReportDocPath) -notcontains $concurrentReportOutputLineText) {
    throw "测试前置条件不满足：$concurrentReportDocPath 中缺少 $concurrentReportOutputLineText"
}

if ((Get-Content $concurrentReportDocPath) -notcontains $concurrentReportScriptEntryLineText) {
    throw "测试前置条件不满足：$concurrentReportDocPath 中缺少 $concurrentReportScriptEntryLineText"
}

if ((Get-Content $concurrentReportDocPath) -notcontains $concurrentReportSemiAutoWriteLineText) {
    throw "测试前置条件不满足：$concurrentReportDocPath 中缺少 $concurrentReportSemiAutoWriteLineText"
}

if ((Get-Content $concurrentReportDocPath) -notcontains $concurrentReportResultSkeletonLineText) {
    throw "测试前置条件不满足：$concurrentReportDocPath 中缺少 $concurrentReportResultSkeletonLineText"
}

if ((Get-Content $concurrentReportDocPath) -notcontains $concurrentReportDecisionLogSkeletonLineText) {
    throw "测试前置条件不满足：$concurrentReportDocPath 中缺少 $concurrentReportDecisionLogSkeletonLineText"
}

if ((Get-Content $concurrentReportDocPath) -notcontains $concurrentReportValueLineText) {
    throw "测试前置条件不满足：$concurrentReportDocPath 中缺少 $concurrentReportValueLineText"
}

if ((Get-Content $gatePackageTemplateDocPath) -notcontains $gatePackageTemplateConclusionLineText) {
    throw "测试前置条件不满足：$gatePackageTemplateDocPath 中缺少拍板包半自动模板一句话结论测试行。"
}

if ((Get-Content $gatePackageTemplateDocPath) -notcontains $gatePackageTemplateScenarioLineText) {
    throw "测试前置条件不满足：$gatePackageTemplateDocPath 中缺少拍板包半自动模板适用场景测试行。"
}

if ((Get-Content $gatePackageTemplateDocPath) -notcontains $gatePackageTemplateOutputLineText) {
    throw "测试前置条件不满足：$gatePackageTemplateDocPath 中缺少拍板包半自动模板输出结果测试行。"
}

if ((Get-Content $gatePackageResolveDocPath) -notcontains $gatePackageResolveConclusionLineText) {
    throw "测试前置条件不满足：$gatePackageResolveDocPath 中缺少拍板结果回写模板一句话结论测试行。"
}

if ((Get-Content $gatePackageResolveDocPath) -notcontains $gatePackageResolveScenarioLineText) {
    throw "测试前置条件不满足：$gatePackageResolveDocPath 中缺少拍板结果回写模板适用场景测试行。"
}

if ((Get-Content $gatePackageResolveDocPath) -notcontains $gatePackageResolveOutputLineText) {
    throw "测试前置条件不满足：$gatePackageResolveDocPath 中缺少拍板结果回写模板输出结果测试行。"
}

if ((Get-Content $exceptionTemplateDocPath) -notcontains $exceptionTemplateConclusionLineText) {
    throw "测试前置条件不满足：$exceptionTemplateDocPath 中缺少异常路径与回退模板一句话结论测试行。"
}

if ((Get-Content $exceptionTemplateDocPath) -notcontains $exceptionTemplateScenarioLineText) {
    throw "测试前置条件不满足：$exceptionTemplateDocPath 中缺少异常路径与回退模板适用场景测试行。"
}

if ((Get-Content $exceptionTemplateDocPath) -notcontains $exceptionTemplateOutputLineText) {
    throw "测试前置条件不满足：$exceptionTemplateDocPath 中缺少异常路径与回退模板输出结果测试行。"
}

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixConclusionLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少维护层动作矩阵一句话结论测试行。"
}

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixHeaderLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少维护层动作矩阵表头测试行。"
}

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixLocalSafeCommitRowLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少维护层动作矩阵首行测试行。"
}

if ((Get-Content $maintenanceMatrixPath) -notcontains $maintenanceMatrixTaskPackSemiAutoRowLineText) {
    throw "测试前置条件不满足：$maintenanceMatrixPath 中缺少维护层动作矩阵第二行测试行。"
}

if ((Get-Content $gatePackageDocPath) -notcontains $gatePackageConclusionLineText) {
    throw "测试前置条件不满足：$gatePackageDocPath 中缺少拍板包一句话结论测试行。"
}

if ((Get-Content $gatePackageDocPath) -notcontains $gatePackageTriggerLineText) {
    throw "测试前置条件不满足：$gatePackageDocPath 中缺少拍板包必须准备条件测试行。"
}

if ((Get-Content $gatePackageDocPath) -notcontains $gatePackageMinimumCompositionLineText) {
    throw "测试前置条件不满足：$gatePackageDocPath 中缺少拍板包最低组成测试行。"
}

try {
    $driftedMaintenanceMatrixContent = (Get-Content $maintenanceMatrixPath -Raw).Replace($maintenanceMatrixConclusionLineText, '先看情况再决定走哪条维护路径。')
    [System.IO.File]::WriteAllText($maintenanceMatrixPath, $driftedMaintenanceMatrixContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/14-维护层动作矩阵与收口检查表.md') -ExpectedExitCode 1 -TestName 'block-maintenance-matrix-conclusion-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceMatrixPath, $originalMaintenanceMatrixBytes)
}

try {
    $driftedMaintenanceMatrixContent = (Get-Content $maintenanceMatrixPath -Raw).Replace($maintenanceMatrixLocalSafeCommitRowLineText, '| 本地安全提交 | 有公开安全改动需要进入远端时 | `docs/40-执行/10-本地安全提交流程.md` | 一次串行 `add`/`commit`/`pull --rebase`/`push` | 只提交公开安全文件；禁止带上 `.codex/`、`logs/` | 中 |')
    [System.IO.File]::WriteAllText($maintenanceMatrixPath, $driftedMaintenanceMatrixContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/14-维护层动作矩阵与收口检查表.md') -ExpectedExitCode 1 -TestName 'block-maintenance-matrix-table-risk-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceMatrixPath, $originalMaintenanceMatrixBytes)
}

try {
    $driftedMaintenanceMatrixContent = (Get-Content $maintenanceMatrixPath -Raw).Replace($maintenanceMatrixLocalSafeCommitRowLineText, '__MAINTENANCE_MATRIX_SWAP_PLACEHOLDER__').Replace($maintenanceMatrixTaskPackSemiAutoRowLineText, $maintenanceMatrixLocalSafeCommitRowLineText).Replace('__MAINTENANCE_MATRIX_SWAP_PLACEHOLDER__', $maintenanceMatrixTaskPackSemiAutoRowLineText)
    [System.IO.File]::WriteAllText($maintenanceMatrixPath, $driftedMaintenanceMatrixContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/14-维护层动作矩阵与收口检查表.md') -ExpectedExitCode 1 -TestName 'block-maintenance-matrix-table-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceMatrixPath, $originalMaintenanceMatrixBytes)
}

try {
    $driftedMaintenanceMatrixContent = (Get-Content $maintenanceMatrixPath -Raw).Replace($maintenanceMatrixSyncSlotLineText, '- `收口要求`：同步完成后再看情况。')
    [System.IO.File]::WriteAllText($maintenanceMatrixPath, $driftedMaintenanceMatrixContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/14-维护层动作矩阵与收口检查表.md') -ExpectedExitCode 1 -TestName 'block-maintenance-entry-sync-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceMatrixPath, $originalMaintenanceMatrixBytes)
}

try {
    $driftedMaintenanceMatrixContent = (Get-Content $maintenanceMatrixPath -Raw).Replace($maintenanceMatrixDecisionOrderLineText, '- `结束条件`：最后再决定是否结束。')
    [System.IO.File]::WriteAllText($maintenanceMatrixPath, $driftedMaintenanceMatrixContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/14-维护层动作矩阵与收口检查表.md') -ExpectedExitCode 1 -TestName 'block-maintenance-decision-order-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceMatrixPath, $originalMaintenanceMatrixBytes)
}

try {
    $driftedMaintenanceMatrixContent = (Get-Content $maintenanceMatrixPath -Raw).Replace($maintenanceMatrixBasicCloseoutLineText, '- `下一步说明`：最后再看看情况。')
    [System.IO.File]::WriteAllText($maintenanceMatrixPath, $driftedMaintenanceMatrixContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/14-维护层动作矩阵与收口检查表.md') -ExpectedExitCode 1 -TestName 'block-maintenance-basic-closeout-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceMatrixPath, $originalMaintenanceMatrixBytes)
}

try {
    $driftedMaintenanceMatrixContent = (Get-Content $maintenanceMatrixPath -Raw).Replace($maintenanceMatrixGovernanceAuditLineText, '- `边界复核`：最后再人工看看。')
    [System.IO.File]::WriteAllText($maintenanceMatrixPath, $driftedMaintenanceMatrixContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/14-维护层动作矩阵与收口检查表.md') -ExpectedExitCode 1 -TestName 'block-maintenance-governance-audit-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceMatrixPath, $originalMaintenanceMatrixBytes)
}

try {
    $driftedMaintenanceMatrixContent = (Get-Content $maintenanceMatrixPath -Raw).Replace($maintenanceMatrixPublicBoundaryLineText, '- `本地运行态`：这些内容先放公开仓也行。')
    [System.IO.File]::WriteAllText($maintenanceMatrixPath, $driftedMaintenanceMatrixContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/14-维护层动作矩阵与收口检查表.md') -ExpectedExitCode 1 -TestName 'block-maintenance-public-boundary-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceMatrixPath, $originalMaintenanceMatrixBytes)
}

try {
    $driftedMaintenanceMatrixContent = (Get-Content $maintenanceMatrixPath -Raw).Replace($maintenanceMatrixPairingLineText, '- `公开口径变更前`：到时候再看情况。')
    [System.IO.File]::WriteAllText($maintenanceMatrixPath, $driftedMaintenanceMatrixContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/14-维护层动作矩阵与收口检查表.md') -ExpectedExitCode 1 -TestName 'block-maintenance-pairing-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceMatrixPath, $originalMaintenanceMatrixBytes)
}

try {
    $driftedMaintenanceMatrixContent = (Get-Content $maintenanceMatrixPath -Raw).Replace($maintenanceMatrixValueLineText, '- `保留控制平面`：以后再说。')
    [System.IO.File]::WriteAllText($maintenanceMatrixPath, $driftedMaintenanceMatrixContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/14-维护层动作矩阵与收口检查表.md') -ExpectedExitCode 1 -TestName 'block-maintenance-value-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($maintenanceMatrixPath, $originalMaintenanceMatrixBytes)
}

try {
    $driftedGatePackageTemplateContent = (Get-Content $gatePackageTemplateDocPath -Raw).Replace($gatePackageTemplateConclusionLineText, '先手工改一圈，再看要不要用模板。')
    [System.IO.File]::WriteAllText($gatePackageTemplateDocPath, $driftedGatePackageTemplateContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/16-拍板包半自动模板.md') -ExpectedExitCode 1 -TestName 'block-gate-package-template-conclusion-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($gatePackageTemplateDocPath, $originalGatePackageTemplateDocBytes)
}

try {
    $driftedGatePackageTemplateContent = (Get-Content $gatePackageTemplateDocPath -Raw).Replace($gatePackageTemplateScenarioLineText, '- 有空时再看是否需要 `gates.yaml`。')
    [System.IO.File]::WriteAllText($gatePackageTemplateDocPath, $driftedGatePackageTemplateContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/16-拍板包半自动模板.md') -ExpectedExitCode 1 -TestName 'block-gate-package-template-scenario-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($gatePackageTemplateDocPath, $originalGatePackageTemplateDocBytes)
}

try {
    $driftedGatePackageTemplateContent = (Get-Content $gatePackageTemplateDocPath -Raw).Replace($gatePackageTemplateOutputLineText, '- `state.yaml`：最后再看是否切状态')
    [System.IO.File]::WriteAllText($gatePackageTemplateDocPath, $driftedGatePackageTemplateContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/16-拍板包半自动模板.md') -ExpectedExitCode 1 -TestName 'block-gate-package-template-output-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($gatePackageTemplateDocPath, $originalGatePackageTemplateDocBytes)
}

try {
    $driftedExceptionTemplateContent = (Get-Content $exceptionTemplateDocPath -Raw).Replace($exceptionTemplateConclusionLineText, '先在聊天里说一下，再看要不要落模板。')
    [System.IO.File]::WriteAllText($exceptionTemplateDocPath, $driftedExceptionTemplateContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/18-异常路径与回退模板.md') -ExpectedExitCode 1 -TestName 'block-exception-template-conclusion-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($exceptionTemplateDocPath, $originalExceptionTemplateDocBytes)
}

try {
    $driftedExceptionTemplateContent = (Get-Content $exceptionTemplateDocPath -Raw).Replace($exceptionTemplateScenarioLineText, '- 看情况决定是否暂停。')
    [System.IO.File]::WriteAllText($exceptionTemplateDocPath, $driftedExceptionTemplateContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/18-异常路径与回退模板.md') -ExpectedExitCode 1 -TestName 'block-exception-template-scenario-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($exceptionTemplateDocPath, $originalExceptionTemplateDocBytes)
}

try {
    $driftedExceptionTemplateContent = (Get-Content $exceptionTemplateDocPath -Raw).Replace($exceptionTemplateOutputLineText, '- `state.yaml`：之后再看看要不要切状态')
    [System.IO.File]::WriteAllText($exceptionTemplateDocPath, $driftedExceptionTemplateContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/18-异常路径与回退模板.md') -ExpectedExitCode 1 -TestName 'block-exception-template-output-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($exceptionTemplateDocPath, $originalExceptionTemplateDocBytes)
}

try {
    $driftedGatePackageResolveContent = (Get-Content $gatePackageResolveDocPath -Raw).Replace($gatePackageResolveConclusionLineText, '先手工回写一圈，再看要不要用模板。')
    [System.IO.File]::WriteAllText($gatePackageResolveDocPath, $driftedGatePackageResolveContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/17-拍板结果回写模板.md') -ExpectedExitCode 1 -TestName 'block-gate-package-resolve-conclusion-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($gatePackageResolveDocPath, $originalGatePackageResolveDocBytes)
}

try {
    $driftedGatePackageResolveContent = (Get-Content $gatePackageResolveDocPath -Raw).Replace($gatePackageResolveScenarioLineText, '- 主公大概有个方向时再说。')
    [System.IO.File]::WriteAllText($gatePackageResolveDocPath, $driftedGatePackageResolveContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/17-拍板结果回写模板.md') -ExpectedExitCode 1 -TestName 'block-gate-package-resolve-scenario-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($gatePackageResolveDocPath, $originalGatePackageResolveDocBytes)
}

try {
    $driftedGatePackageResolveContent = (Get-Content $gatePackageResolveDocPath -Raw).Replace($gatePackageResolveOutputLineText, '- `state.yaml`：之后再看要不要恢复状态')
    [System.IO.File]::WriteAllText($gatePackageResolveDocPath, $driftedGatePackageResolveContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/17-拍板结果回写模板.md') -ExpectedExitCode 1 -TestName 'block-gate-package-resolve-output-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($gatePackageResolveDocPath, $originalGatePackageResolveDocBytes)
}

try {
    $driftedGatePackageContent = (Get-Content $gatePackageDocPath -Raw).Replace($gatePackageConclusionLineText, '先说个大概方向，再看要不要拍板。')
    [System.IO.File]::WriteAllText($gatePackageDocPath, $driftedGatePackageContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/15-拍板包准备与收口规范.md') -ExpectedExitCode 1 -TestName 'block-gate-package-conclusion-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($gatePackageDocPath, $originalGatePackageDocBytes)
}

try {
    $driftedGatePackageContent = (Get-Content $gatePackageDocPath -Raw).Replace($gatePackageTriggerLineText, '- 有争议时再看是否需要准备拍板包。')
    [System.IO.File]::WriteAllText($gatePackageDocPath, $driftedGatePackageContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/15-拍板包准备与收口规范.md') -ExpectedExitCode 1 -TestName 'block-gate-package-trigger-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($gatePackageDocPath, $originalGatePackageDocBytes)
}

try {
    $driftedGatePackageContent = (Get-Content $gatePackageDocPath -Raw).Replace($gatePackageMinimumCompositionLineText, '4. 建议：最后给个倾向即可。')
    [System.IO.File]::WriteAllText($gatePackageDocPath, $driftedGatePackageContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/15-拍板包准备与收口规范.md') -ExpectedExitCode 1 -TestName 'block-gate-package-minimum-composition-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($gatePackageDocPath, $originalGatePackageDocBytes)
}

try {
    $driftedConfigReviewContent = (Get-Content $configReviewDocPath -Raw).Replace($configReviewSummaryLineText, '- `统一落盘复核`：之后再看。')
    [System.IO.File]::WriteAllText($configReviewDocPath, $driftedConfigReviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/21-关键配置来源与漂移复核模板.md') -ExpectedExitCode 1 -TestName 'block-config-review-summary-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($configReviewDocPath, $originalConfigReviewDocBytes)
}

try {
    $driftedConfigReviewContent = (Get-Content $configReviewDocPath -Raw).Replace($configReviewTriggerLineText, '- `提交前预检落盘`：有空再补。')
    [System.IO.File]::WriteAllText($configReviewDocPath, $driftedConfigReviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/21-关键配置来源与漂移复核模板.md') -ExpectedExitCode 1 -TestName 'block-config-review-trigger-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($configReviewDocPath, $originalConfigReviewDocBytes)
}

try {
    $driftedConfigReviewContent = (Get-Content $configReviewDocPath -Raw).Replace($configReviewResultSkeletonLineText, '- `下一步`：之后再说。')
    [System.IO.File]::WriteAllText($configReviewDocPath, $driftedConfigReviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/21-关键配置来源与漂移复核模板.md') -ExpectedExitCode 1 -TestName 'block-config-review-result-skeleton-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($configReviewDocPath, $originalConfigReviewDocBytes)
}

try {
    $driftedConfigReviewContent = (Get-Content $configReviewDocPath -Raw).Replace($configReviewDecisionLogSkeletonLineText, '- `影响`：之后再定。')
    [System.IO.File]::WriteAllText($configReviewDocPath, $driftedConfigReviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/21-关键配置来源与漂移复核模板.md') -ExpectedExitCode 1 -TestName 'block-config-review-decision-log-skeleton-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($configReviewDocPath, $originalConfigReviewDocBytes)
}

try {
    $driftedConfigReviewContent = (Get-Content $configReviewDocPath -Raw).Replace($configReviewLongTermValueLineText, '- `目录内自含`：以后再看。')
    [System.IO.File]::WriteAllText($configReviewDocPath, $driftedConfigReviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/21-关键配置来源与漂移复核模板.md') -ExpectedExitCode 1 -TestName 'block-config-review-long-term-value-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($configReviewDocPath, $originalConfigReviewDocBytes)
}

try {
    $driftedConfigReviewContent = (Get-Content $configReviewDocPath -Raw).Replace($configReviewOutputLineText, '- `先修平再提交`：之后再看。')
    [System.IO.File]::WriteAllText($configReviewDocPath, $driftedConfigReviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/21-关键配置来源与漂移复核模板.md') -ExpectedExitCode 1 -TestName 'block-config-review-output-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($configReviewDocPath, $originalConfigReviewDocBytes)
}

try {
    $driftedConfigReviewContent = (Get-Content $configReviewDocPath -Raw).Replace($configReviewScriptEntryLineText, '- `收口入口`：之后再找。')
    [System.IO.File]::WriteAllText($configReviewDocPath, $driftedConfigReviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/21-关键配置来源与漂移复核模板.md') -ExpectedExitCode 1 -TestName 'block-config-review-script-entry-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($configReviewDocPath, $originalConfigReviewDocBytes)
}

try {
    $driftedConfigReviewContent = (Get-Content $configReviewDocPath -Raw).Replace($configReviewSourceLineText, '- `冻结边界依据`：`docs/30-方案/08-V4-治理审计候选规范.md`')
    [System.IO.File]::WriteAllText($configReviewDocPath, $driftedConfigReviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/21-关键配置来源与漂移复核模板.md') -ExpectedExitCode 1 -TestName 'block-config-review-source-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($configReviewDocPath, $originalConfigReviewDocBytes)
}

try {
    $driftedConcurrentRuleContent = (Get-Content $concurrentRuleDocPath -Raw).Replace($concurrentRuleSinglePrimaryLineText, '- `主阻塞唯一`：之后再看。')
    [System.IO.File]::WriteAllText($concurrentRuleDocPath, $driftedConcurrentRuleContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/19-多 gate 与多异常并存处理规则.md') -ExpectedExitCode 1 -TestName 'block-concurrent-rule-single-primary-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentRuleDocPath, $originalConcurrentRuleDocBytes)
}

try {
    $driftedConcurrentRuleContent = (Get-Content $concurrentRuleDocPath -Raw).Replace($concurrentRuleNextActorPriorityLineText, '- `running / ready / verifying / done`：之后再看。')
    [System.IO.File]::WriteAllText($concurrentRuleDocPath, $driftedConcurrentRuleContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/19-多 gate 与多异常并存处理规则.md') -ExpectedExitCode 1 -TestName 'block-concurrent-rule-next-actor-priority-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentRuleDocPath, $originalConcurrentRuleDocBytes)
}

try {
    $driftedConcurrentRuleContent = (Get-Content $concurrentRuleDocPath -Raw).Replace($concurrentRuleGatePriorityLineText, '- `次要待处理项留档`：之后再看。')
    [System.IO.File]::WriteAllText($concurrentRuleDocPath, $driftedConcurrentRuleContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/19-多 gate 与多异常并存处理规则.md') -ExpectedExitCode 1 -TestName 'block-concurrent-rule-gate-priority-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentRuleDocPath, $originalConcurrentRuleDocBytes)
}

try {
    $driftedConcurrentRuleContent = (Get-Content $concurrentRuleDocPath -Raw).Replace($concurrentRuleGateExceptionDecisionLineText, '- `拍板回退先回写`：之后再看。')
    [System.IO.File]::WriteAllText($concurrentRuleDocPath, $driftedConcurrentRuleContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/19-多 gate 与多异常并存处理规则.md') -ExpectedExitCode 1 -TestName 'block-concurrent-rule-gate-exception-decision-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentRuleDocPath, $originalConcurrentRuleDocBytes)
}

try {
    $driftedConcurrentRuleContent = (Get-Content $concurrentRuleDocPath -Raw).Replace($concurrentRuleDocumentSplitLineText, '- `result.md`：之后再看。')
    [System.IO.File]::WriteAllText($concurrentRuleDocPath, $driftedConcurrentRuleContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/19-多 gate 与多异常并存处理规则.md') -ExpectedExitCode 1 -TestName 'block-concurrent-rule-document-split-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentRuleDocPath, $originalConcurrentRuleDocBytes)
}

try {
    $driftedConcurrentRuleContent = (Get-Content $concurrentRuleDocPath -Raw).Replace($concurrentRuleReportOrderLineText, '- `恢复顺序`：之后再说。')
    [System.IO.File]::WriteAllText($concurrentRuleDocPath, $driftedConcurrentRuleContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/19-多 gate 与多异常并存处理规则.md') -ExpectedExitCode 1 -TestName 'block-concurrent-rule-report-order-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentRuleDocPath, $originalConcurrentRuleDocBytes)
}

try {
    $driftedConcurrentRuleContent = (Get-Content $concurrentRuleDocPath -Raw).Replace($concurrentRuleCloseoutCheckLineText, '- `恢复后重评`：以后再说。')
    [System.IO.File]::WriteAllText($concurrentRuleDocPath, $driftedConcurrentRuleContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/19-多 gate 与多异常并存处理规则.md') -ExpectedExitCode 1 -TestName 'block-concurrent-rule-closeout-check-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentRuleDocPath, $originalConcurrentRuleDocBytes)
}

try {
    $driftedConcurrentReportContent = (Get-Content $concurrentReportDocPath -Raw).Replace($concurrentReportSummaryLineText, '- `一次性落盘`：之后再说。')
    [System.IO.File]::WriteAllText($concurrentReportDocPath, $driftedConcurrentReportContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/20-复杂并存汇报骨架模板.md') -ExpectedExitCode 1 -TestName 'block-concurrent-report-summary-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentReportDocPath, $originalConcurrentReportDocBytes)
}

try {
    $driftedConcurrentReportContent = (Get-Content $concurrentReportDocPath -Raw).Replace($concurrentReportTriggerLineText, '- `超出单一模板`：到时候再看。')
    [System.IO.File]::WriteAllText($concurrentReportDocPath, $driftedConcurrentReportContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/20-复杂并存汇报骨架模板.md') -ExpectedExitCode 1 -TestName 'block-concurrent-report-trigger-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentReportDocPath, $originalConcurrentReportDocBytes)
}

try {
    $driftedConcurrentReportContent = (Get-Content $concurrentReportDocPath -Raw).Replace($concurrentReportOutputLineText, '- `状态同步`：之后再决定。')
    [System.IO.File]::WriteAllText($concurrentReportDocPath, $driftedConcurrentReportContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/20-复杂并存汇报骨架模板.md') -ExpectedExitCode 1 -TestName 'block-concurrent-report-output-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentReportDocPath, $originalConcurrentReportDocBytes)
}

try {
    $driftedConcurrentReportContent = (Get-Content $concurrentReportDocPath -Raw).Replace($concurrentReportScriptEntryLineText, '- `收口`：之后再找。')
    [System.IO.File]::WriteAllText($concurrentReportDocPath, $driftedConcurrentReportContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/20-复杂并存汇报骨架模板.md') -ExpectedExitCode 1 -TestName 'block-concurrent-report-script-entry-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentReportDocPath, $originalConcurrentReportDocBytes)
}

try {
    $driftedConcurrentReportContent = (Get-Content $concurrentReportDocPath -Raw).Replace($concurrentReportSemiAutoWriteLineText, '- `SyncState`：之后再看。')
    [System.IO.File]::WriteAllText($concurrentReportDocPath, $driftedConcurrentReportContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/20-复杂并存汇报骨架模板.md') -ExpectedExitCode 1 -TestName 'block-concurrent-report-semi-auto-write-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentReportDocPath, $originalConcurrentReportDocBytes)
}

try {
    $driftedConcurrentReportContent = (Get-Content $concurrentReportDocPath -Raw).Replace($concurrentReportResultSkeletonLineText, '- `治理复核结果`：之后再看。')
    [System.IO.File]::WriteAllText($concurrentReportDocPath, $driftedConcurrentReportContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/20-复杂并存汇报骨架模板.md') -ExpectedExitCode 1 -TestName 'block-concurrent-report-result-skeleton-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentReportDocPath, $originalConcurrentReportDocBytes)
}

try {
    $driftedConcurrentReportContent = (Get-Content $concurrentReportDocPath -Raw).Replace($concurrentReportDecisionLogSkeletonLineText, '- `影响`：之后再看。')
    [System.IO.File]::WriteAllText($concurrentReportDocPath, $driftedConcurrentReportContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/20-复杂并存汇报骨架模板.md') -ExpectedExitCode 1 -TestName 'block-concurrent-report-decision-log-skeleton-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentReportDocPath, $originalConcurrentReportDocBytes)
}

try {
    $driftedConcurrentReportContent = (Get-Content $concurrentReportDocPath -Raw).Replace($concurrentReportValueLineText, '- `自动化入口`：以后再说。')
    [System.IO.File]::WriteAllText($concurrentReportDocPath, $driftedConcurrentReportContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/20-复杂并存汇报骨架模板.md') -ExpectedExitCode 1 -TestName 'block-concurrent-report-value-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($concurrentReportDocPath, $originalConcurrentReportDocBytes)
}

$docsReadmeMaintenanceMainlineSourceIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeMaintenanceMainlineSourceLineText)
$docsReadmeMaintenanceCapabilitySourceIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeMaintenanceCapabilitySourceLineText)

if ($docsReadmeMaintenanceMainlineSourceIndex -lt 0 -or $docsReadmeMaintenanceCapabilitySourceIndex -lt 0) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少维护层入口真源说明测试行。"
}

if ($docsReadmeMaintenanceMainlineSourceIndex -gt $docsReadmeMaintenanceCapabilitySourceIndex) {
    throw "测试前置条件不满足：$docsReadmePath 中维护层入口真源说明顺序已不是当前现状。"
}

try {
    $driftedDocsReadmeLines = @($docsReadmeLines)
    $driftedDocsReadmeLines[$docsReadmeMaintenanceMainlineSourceIndex] = $docsReadmeMaintenanceCapabilitySourceLineText
    $driftedDocsReadmeLines[$docsReadmeMaintenanceCapabilitySourceIndex] = $docsReadmeMaintenanceMainlineSourceLineText
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-maintenance-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

$navOverviewPath = Join-Path $repoRootPath 'docs/00-导航/02-现行标准件总览.md'
$originalNavOverviewBytes = [System.IO.File]::ReadAllBytes($navOverviewPath)
$navOverviewLines = Get-Content $navOverviewPath
$execReadmeTitleLineText = '# 40-执行 目录说明'
$execReadmeTopSummaryMarkerLineText = '这里放：'
$execReadmeTopSummaryPlanLineText = '- 试运行计划'
$execReadmeTopSummaryTaskLineText = '- 任务清单'
$execReadmeTopSummaryRecordLineText = '- 执行记录'
$execReadmeTopSummaryAcceptanceLineText = '- 验收单'
$execReadmeSectionMarkerLineText = '当前现行标准件：'
$execReadmeSourceNoteLineText = '本区块是执行区现行标准件真源；公开入口同步与提交门禁均以此为准。'
$execReadmeTimestampNoteLineText = '带时间戳的文件默认视为过程稿或证据稿，不自动等同于现行标准件。'
$execReadmeUsageGuideLineText = '具体区分与使用顺序见：`04-执行区现行件与证据稿说明.md`'
$execReadmeArchiveGuideLineText = '已完成归档规则见：`docs/90-归档/01-执行区证据稿归档规则.md`'
$execStandardGuidePath = Join-Path $repoRootPath 'docs/40-执行/04-执行区现行件与证据稿说明.md'
$originalExecStandardGuideBytes = [System.IO.File]::ReadAllBytes($execStandardGuidePath)
$execStandardGuideLines = Get-Content $execStandardGuidePath
$execStandardGuideConclusionLineText = '在 `docs/40-执行/` 下，固定编号文件是现行标准件，带时间戳的文件默认是证据稿或过程稿。'
$execStandardGuideUsageOrderLineText1 = '1. 先读 `01-任务包规范.md`'
$execStandardGuideUsageOrderLineText2 = '2. 再读 `02-任务包模板.md`'
$execStandardGuideUsageOrderLineText3 = '3. 进入试跑前读 `03-面板入口验收.md`'
$execStandardGuideUsageOrderLineText4 = '4. 需要追溯历史判断时，再看时间戳证据稿'
$execStandardGuideEvidenceDraftLineText1 = '- 带时间戳的执行文档'
$execStandardGuideEvidenceDraftLineText2 = '- 某轮推进中的提炼稿、冻结稿、过程说明稿'
$execStandardGuideEvidenceDraftLineText3 = '- 仅用于还原当时判断过程的阶段性文档'
$execStandardGuideNamingRuleLineText1 = '- 新增现行标准件时，优先使用固定编号文件名，再补本文件中的列表。'
$execStandardGuideNamingRuleLineText2 = '- 新增带时间戳的过程稿时，不得默认视为现行标准件。'
$execStandardGuideNamingRuleLineText3 = '- 若固定编号文件与时间戳稿出现差异，以固定编号文件为准。'
$execStandardGuideNamingRuleLineText4 = '- 若某份时间戳稿已失去参考价值，应转入 `docs/90-归档/` 而不是继续留在执行区长期混放。'
$execStandardGuideArchivedEvidenceLineText1 = '- `docs/90-归档/20260328-232458-v4-mvp-boundary-and-first-task-package.md`'
$execStandardGuideArchivedEvidenceLineText2 = '- `docs/90-归档/20260328-233811-v4-trial-001-mvp-boundary-freeze.md`'
$execStandardGuideValueLineText1 = '- 降低后续 Trial 留痕越来越多时的检索成本。'
$execStandardGuideValueLineText2 = '- 避免把过程稿误当成现行标准件继续扩写。'
$execStandardGuideValueLineText3 = '- 让执行区保持“现行件少而稳，证据稿可追溯”的长期结构。'
if ($execReadmeLines -notcontains $execReadmeTitleLineText) {
    throw "测试前置条件不满足：$execReadmePath 中缺少 $execReadmeTitleLineText"
}

try {
    $driftedExecReadmeContent = (Get-Content $execReadmePath -Raw).Replace($execReadmeTitleLineText, '# 40-执行 区域说明')
    [System.IO.File]::WriteAllText($execReadmePath, $driftedExecReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/README.md') -ExpectedExitCode 1 -TestName 'block-exec-readme-title-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execReadmePath, $originalExecReadmeBytes)
}

if ($execReadmeLines -notcontains $execReadmeSectionMarkerLineText) {
    throw "测试前置条件不满足：$execReadmePath 中缺少 $execReadmeSectionMarkerLineText"
}

try {
    $driftedExecReadmeLines = @(
        $execReadmeLines | Where-Object { $_ -ne $execReadmeSectionMarkerLineText }
    )
    $driftedExecReadmeContent = ($driftedExecReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($execReadmePath, $driftedExecReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/README.md') -ExpectedExitCode 1 -TestName 'block-exec-standard-source-section-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($execReadmePath, $originalExecReadmeBytes)
}

if ($execReadmeLines -notcontains $execReadmeTopSummaryMarkerLineText -or $execReadmeLines -notcontains $execReadmeTopSummaryPlanLineText -or $execReadmeLines -notcontains $execReadmeTopSummaryTaskLineText -or $execReadmeLines -notcontains $execReadmeTopSummaryRecordLineText -or $execReadmeLines -notcontains $execReadmeTopSummaryAcceptanceLineText) {
    throw "测试前置条件不满足：$execReadmePath 中缺少执行区 README 顶部用途摘要测试行。"
}

try {
    $driftedExecReadmeContent = (Get-Content $execReadmePath -Raw).Replace($execReadmeTopSummaryAcceptanceLineText, '- 结果看看')
    [System.IO.File]::WriteAllText($execReadmePath, $driftedExecReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/README.md') -ExpectedExitCode 1 -TestName 'block-exec-readme-top-summary-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execReadmePath, $originalExecReadmeBytes)
}

if ($execReadmeLines -notcontains $execReadmeSourceNoteLineText -or $execReadmeLines -notcontains $execReadmeTimestampNoteLineText -or $execReadmeLines -notcontains $execReadmeUsageGuideLineText -or $execReadmeLines -notcontains $execReadmeArchiveGuideLineText) {
    throw "测试前置条件不满足：$execReadmePath 中缺少执行区 README 真源说明测试行。"
}

try {
    $driftedExecReadmeContent = (Get-Content $execReadmePath -Raw).Replace($execReadmeArchiveGuideLineText, '已完成归档规则见：`docs/90-归档/README.md`')
    [System.IO.File]::WriteAllText($execReadmePath, $driftedExecReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/README.md') -ExpectedExitCode 1 -TestName 'block-exec-standard-source-note-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execReadmePath, $originalExecReadmeBytes)
}

if ($execStandardGuideLines -notcontains $execStandardGuideConclusionLineText) {
    throw "测试前置条件不满足：$execStandardGuidePath 中缺少执行区现行件说明一句话结论测试行。"
}

try {
    $driftedExecStandardGuideContent = (Get-Content $execStandardGuidePath -Raw).Replace($execStandardGuideConclusionLineText, '在 `docs/40-执行/` 下，固定编号文件通常可视为现行件，时间戳文档按情况参考。')
    [System.IO.File]::WriteAllText($execStandardGuidePath, $driftedExecStandardGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/04-执行区现行件与证据稿说明.md') -ExpectedExitCode 1 -TestName 'block-exec-standard-guide-conclusion-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execStandardGuidePath, $originalExecStandardGuideBytes)
}

if ($execStandardGuideLines -notcontains $execStandardGuideUsageOrderLineText1 -or $execStandardGuideLines -notcontains $execStandardGuideUsageOrderLineText2 -or $execStandardGuideLines -notcontains $execStandardGuideUsageOrderLineText3 -or $execStandardGuideLines -notcontains $execStandardGuideUsageOrderLineText4) {
    throw "测试前置条件不满足：$execStandardGuidePath 中缺少执行区现行件说明使用顺序测试行。"
}

try {
    $driftedExecStandardGuideContent = (Get-Content $execStandardGuidePath -Raw).Replace($execStandardGuideUsageOrderLineText4, '4. 需要追溯历史判断时，按情况查找时间戳文档')
    [System.IO.File]::WriteAllText($execStandardGuidePath, $driftedExecStandardGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/04-执行区现行件与证据稿说明.md') -ExpectedExitCode 1 -TestName 'block-exec-standard-guide-usage-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execStandardGuidePath, $originalExecStandardGuideBytes)
}

if ($execStandardGuideLines -notcontains $execStandardGuideEvidenceDraftLineText1 -or $execStandardGuideLines -notcontains $execStandardGuideEvidenceDraftLineText2 -or $execStandardGuideLines -notcontains $execStandardGuideEvidenceDraftLineText3) {
    throw "测试前置条件不满足：$execStandardGuidePath 中缺少执行区现行件说明证据稿与过程稿测试行。"
}

try {
    $driftedExecStandardGuideContent = (Get-Content $execStandardGuidePath -Raw).Replace($execStandardGuideEvidenceDraftLineText3, '- 仅供参考的阶段性说明')
    [System.IO.File]::WriteAllText($execStandardGuidePath, $driftedExecStandardGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/04-执行区现行件与证据稿说明.md') -ExpectedExitCode 1 -TestName 'block-exec-standard-guide-evidence-draft-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execStandardGuidePath, $originalExecStandardGuideBytes)
}

if ($execStandardGuideLines -notcontains $execStandardGuideNamingRuleLineText1 -or $execStandardGuideLines -notcontains $execStandardGuideNamingRuleLineText2 -or $execStandardGuideLines -notcontains $execStandardGuideNamingRuleLineText3 -or $execStandardGuideLines -notcontains $execStandardGuideNamingRuleLineText4) {
    throw "测试前置条件不满足：$execStandardGuidePath 中缺少执行区现行件说明命名与维护规则测试行。"
}

try {
    $driftedExecStandardGuideContent = (Get-Content $execStandardGuidePath -Raw).Replace($execStandardGuideNamingRuleLineText4, '- 若某份时间戳稿后续再说')
    [System.IO.File]::WriteAllText($execStandardGuidePath, $driftedExecStandardGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/04-执行区现行件与证据稿说明.md') -ExpectedExitCode 1 -TestName 'block-exec-standard-guide-naming-rule-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execStandardGuidePath, $originalExecStandardGuideBytes)
}

if ($execStandardGuideLines -notcontains $execStandardGuideArchivedEvidenceLineText1 -or $execStandardGuideLines -notcontains $execStandardGuideArchivedEvidenceLineText2) {
    throw "测试前置条件不满足：$execStandardGuidePath 中缺少执行区现行件说明已迁入归档区的证据稿测试行。"
}

try {
    $driftedExecStandardGuideContent = (Get-Content $execStandardGuidePath -Raw).Replace($execStandardGuideArchivedEvidenceLineText2, '- `docs/90-归档/20260328-233811-v4-trial-001-boundary-freeze.md`')
    [System.IO.File]::WriteAllText($execStandardGuidePath, $driftedExecStandardGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/04-执行区现行件与证据稿说明.md') -ExpectedExitCode 1 -TestName 'block-exec-standard-guide-archived-evidence-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execStandardGuidePath, $originalExecStandardGuideBytes)
}

if ($execStandardGuideLines -notcontains $execStandardGuideValueLineText1 -or $execStandardGuideLines -notcontains $execStandardGuideValueLineText2 -or $execStandardGuideLines -notcontains $execStandardGuideValueLineText3) {
    throw "测试前置条件不满足：$execStandardGuidePath 中缺少执行区现行件说明本文件的价值测试行。"
}

try {
    $driftedExecStandardGuideContent = (Get-Content $execStandardGuidePath -Raw).Replace($execStandardGuideValueLineText3, '- 让执行区大概保持长期稳定。')
    [System.IO.File]::WriteAllText($execStandardGuidePath, $driftedExecStandardGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/04-执行区现行件与证据稿说明.md') -ExpectedExitCode 1 -TestName 'block-exec-standard-guide-value-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execStandardGuidePath, $originalExecStandardGuideBytes)
}
$navOverviewRuleGuideMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+`docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）\.md`$'
$navOverviewRuleHygieneMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+`docs/reference/02-仓库卫生与命名规范\.md`$'
$navOverviewRuleGuideLineText = $navOverviewRuleGuideMatch.LineText
$navOverviewRuleHygieneLineText = $navOverviewRuleHygieneMatch.LineText
$navOverviewRuleGuideIndex = $navOverviewRuleGuideMatch.Index
$navOverviewRuleHygieneIndex = $navOverviewRuleHygieneMatch.Index

if ($null -eq $navOverviewRuleGuideMatch -or $null -eq $navOverviewRuleHygieneMatch) {
    throw "测试前置条件不满足：$navOverviewPath 中缺少规则入口顺序测试行。"
}

if ($navOverviewRuleGuideIndex -gt $navOverviewRuleHygieneIndex) {
    throw "测试前置条件不满足：$navOverviewPath 中规则入口顺序已不是当前现状。"
}

try {
    $driftedNavOverviewLines = @($navOverviewLines)
    $driftedNavOverviewLines[$navOverviewRuleGuideIndex] = $navOverviewRuleHygieneLineText
    $driftedNavOverviewLines[$navOverviewRuleHygieneIndex] = $navOverviewRuleGuideLineText
    $driftedNavOverviewContent = ($driftedNavOverviewLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($navOverviewPath, $driftedNavOverviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/02-现行标准件总览.md') -ExpectedExitCode 1 -TestName 'block-public-rule-entry-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($navOverviewPath, $originalNavOverviewBytes)
}

$execReadmeCurrentEntryLineText = '- `11-任务包半自动起包.md`'
$execReadmeTargetEntryLineText = '- `12-V4-Target-实施计划.md`'
$navOverviewCurrentExecEntryMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+`docs/40-执行/11-任务包半自动起包\.md`$'
$navOverviewReadingExecEntryMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+需要更快起包时，看 `docs/40-执行/11-任务包半自动起包\.md`$'
$navOverviewCurrentExecEntryLineText = $navOverviewCurrentExecEntryMatch.LineText
$navOverviewReadingExecEntryLineText = $navOverviewReadingExecEntryMatch.LineText

if ($execReadmeLines -notcontains $execReadmeCurrentEntryLineText -or $execReadmeLines -notcontains $execReadmeTargetEntryLineText -or $null -eq $navOverviewCurrentExecEntryMatch -or $null -eq $navOverviewReadingExecEntryMatch) {
    throw '测试前置条件不满足：执行区真源联动测试行缺失。'
}

$execReadmeCurrentEntryIndex = [Array]::IndexOf($execReadmeLines, $execReadmeCurrentEntryLineText)
$execReadmeTargetEntryIndex = [Array]::IndexOf($execReadmeLines, $execReadmeTargetEntryLineText)

if ($execReadmeCurrentEntryIndex -lt 0 -or $execReadmeTargetEntryIndex -lt 0) {
    throw '测试前置条件不满足：执行区顺序测试行缺失。'
}

if ($execReadmeCurrentEntryIndex -gt $execReadmeTargetEntryIndex) {
    throw '测试前置条件不满足：执行区顺序已不是当前现状。'
}

try {
    $driftedExecReadmeLines = @($execReadmeLines)
    $driftedExecReadmeLines[$execReadmeCurrentEntryIndex] = $execReadmeTargetEntryLineText
    $driftedExecReadmeLines[$execReadmeTargetEntryIndex] = $execReadmeCurrentEntryLineText
    $driftedExecReadmeContent = ($driftedExecReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($execReadmePath, $driftedExecReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/README.md') -ExpectedExitCode 1 -TestName 'block-exec-standard-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($execReadmePath, $originalExecReadmeBytes)
}

try {
    $driftedExecReadmeLines = @(
        $execReadmeLines | Where-Object { $_ -ne $execReadmeCurrentEntryLineText }
    )
    $driftedExecReadmeContent = ($driftedExecReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($execReadmePath, $driftedExecReadmeContent, $utf8NoBom)

    $driftedNavOverviewLines = @(
        $navOverviewLines | Where-Object { $_ -ne $navOverviewCurrentExecEntryLineText -and $_ -ne $navOverviewReadingExecEntryLineText }
    )
    $driftedNavOverviewContent = ($driftedNavOverviewLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($navOverviewPath, $driftedNavOverviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/02-现行标准件总览.md', 'docs/40-执行/README.md') -ExpectedExitCode 0 -TestName 'allow-exec-standard-source-sync'
}
finally {
    [System.IO.File]::WriteAllBytes($execReadmePath, $originalExecReadmeBytes)
    [System.IO.File]::WriteAllBytes($navOverviewPath, $originalNavOverviewBytes)
}

$coreGovernanceRuleSourceExtraLineText = '7. `docs/40-执行/21-关键配置来源与漂移复核模板.md`'
if ($localSafeFlowLines -notcontains $coreGovernanceRuleSourceExtraLineText) {
    throw '测试前置条件不满足：核心治理规则真源联动测试行缺失。'
}

try {
    $driftedLocalSafeFlowLines = @(
        $localSafeFlowLines | Where-Object { $_ -ne $coreGovernanceRuleSourceExtraLineText }
    )
    $driftedLocalSafeFlowContent = ($driftedLocalSafeFlowLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($localSafeFlowPath, $driftedLocalSafeFlowContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/10-本地安全提交流程.md') -ExpectedExitCode 0 -TestName 'allow-core-rule-source-sync'
}
finally {
    [System.IO.File]::WriteAllBytes($localSafeFlowPath, $originalLocalSafeFlowBytes)
}

$targetPlanPath = Join-Path $repoRootPath 'docs/40-执行/12-V4-Target-实施计划.md'
$originalTargetPlanBytes = [System.IO.File]::ReadAllBytes($targetPlanPath)
$targetPlanLines = Get-Content $targetPlanPath
$removedReadingOrderTargetSourceStartLineText = 'docs/20-决策/02-V4-Target-进入决议.md'

if ($targetPlanLines -notcontains $removedReadingOrderTargetSourceStartLineText) {
    throw "测试前置条件不满足：$targetPlanPath 中缺少 $removedReadingOrderTargetSourceStartLineText"
}

try {
    $driftedTargetPlanLines = @(
        $targetPlanLines | Where-Object { $_ -ne $removedReadingOrderTargetSourceStartLineText }
    )
    $driftedTargetPlanContent = ($driftedTargetPlanLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($targetPlanPath, $driftedTargetPlanContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/12-V4-Target-实施计划.md') -ExpectedExitCode 1 -TestName 'block-reading-order-target-source-boundary-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($targetPlanPath, $originalTargetPlanBytes)
}

$removedTargetSourcePlanningLineText = 'docs/30-方案/07-V4-规划策略候选规范.md'

if ($targetPlanLines -notcontains $removedTargetSourcePlanningLineText) {
    throw "测试前置条件不满足：$targetPlanPath 中缺少 $removedTargetSourcePlanningLineText"
}

try {
    $driftedTargetPlanLines = @(
        $targetPlanLines | Where-Object { $_ -ne $removedTargetSourcePlanningLineText }
    )
    $driftedTargetPlanContent = ($driftedTargetPlanLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($targetPlanPath, $driftedTargetPlanContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/12-V4-Target-实施计划.md') -ExpectedExitCode 1 -TestName 'block-target-mainline-source-middle-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($targetPlanPath, $originalTargetPlanBytes)
}

$navOverviewBackgroundPlanningEntryMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+`docs/30-方案/07-V4-规划策略候选规范\.md`$'
$navOverviewBackgroundGovernanceEntryMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+`docs/30-方案/08-V4-治理审计候选规范\.md`$'
$navOverviewBackgroundPlanningEntryLineText = $navOverviewBackgroundPlanningEntryMatch.LineText
$navOverviewBackgroundGovernanceEntryLineText = $navOverviewBackgroundGovernanceEntryMatch.LineText
$navOverviewBackgroundPlanningEntryIndex = $navOverviewBackgroundPlanningEntryMatch.Index
$navOverviewBackgroundGovernanceEntryIndex = $navOverviewBackgroundGovernanceEntryMatch.Index
$navOverviewReadingOrderPlanningEntryMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+需要明确规划层第一条高复利候选时，看 `docs/30-方案/07-V4-规划策略候选规范\.md`$'
$navOverviewReadingOrderGovernanceEntryMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+需要明确治理层第二条高复利候选时，看 `docs/30-方案/08-V4-治理审计候选规范\.md`$'
$navOverviewReadingOrderPlanningEntryLineText = $navOverviewReadingOrderPlanningEntryMatch.LineText
$navOverviewReadingOrderGovernanceEntryLineText = $navOverviewReadingOrderGovernanceEntryMatch.LineText
$navOverviewReadingOrderPlanningEntryIndex = $navOverviewReadingOrderPlanningEntryMatch.Index
$navOverviewReadingOrderGovernanceEntryIndex = $navOverviewReadingOrderGovernanceEntryMatch.Index
$targetPlanPlanningEntryLineText = 'docs/30-方案/07-V4-规划策略候选规范.md'
$targetPlanGovernanceEntryLineText = 'docs/30-方案/08-V4-治理审计候选规范.md'
$targetPlanPlanningEntryIndex = [Array]::IndexOf($targetPlanLines, $targetPlanPlanningEntryLineText)
$targetPlanGovernanceEntryIndex = [Array]::IndexOf($targetPlanLines, $targetPlanGovernanceEntryLineText)

if ($null -eq $navOverviewBackgroundPlanningEntryMatch -or $null -eq $navOverviewBackgroundGovernanceEntryMatch) {
    throw "测试前置条件不满足：$navOverviewPath 中缺少入口与背景真源联动测试行。"
}

if ($null -eq $navOverviewReadingOrderPlanningEntryMatch -or $null -eq $navOverviewReadingOrderGovernanceEntryMatch) {
    throw "测试前置条件不满足：$navOverviewPath 中缺少阅读顺序真源联动测试行。"
}

if ($targetPlanPlanningEntryIndex -lt 0 -or $targetPlanGovernanceEntryIndex -lt 0) {
    throw "测试前置条件不满足：$targetPlanPath 中缺少 Target 主线真源联动测试行。"
}

if ($navOverviewBackgroundPlanningEntryIndex -gt $navOverviewBackgroundGovernanceEntryIndex -or $navOverviewReadingOrderPlanningEntryIndex -gt $navOverviewReadingOrderGovernanceEntryIndex -or $targetPlanPlanningEntryIndex -gt $targetPlanGovernanceEntryIndex) {
    throw '测试前置条件不满足：规划与治理入口顺序已不是当前现状。'
}

try {
    $driftedTargetPlanLines = @($targetPlanLines)
    $driftedTargetPlanLines[$targetPlanPlanningEntryIndex] = $targetPlanGovernanceEntryLineText
    $driftedTargetPlanLines[$targetPlanGovernanceEntryIndex] = $targetPlanPlanningEntryLineText
    $driftedTargetPlanContent = ($driftedTargetPlanLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($targetPlanPath, $driftedTargetPlanContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/12-V4-Target-实施计划.md') -ExpectedExitCode 1 -TestName 'block-target-mainline-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($targetPlanPath, $originalTargetPlanBytes)
}

try {
    $driftedNavOverviewLines = @($navOverviewLines)
    $driftedNavOverviewLines[$navOverviewReadingOrderPlanningEntryIndex] = $navOverviewReadingOrderGovernanceEntryLineText
    $driftedNavOverviewLines[$navOverviewReadingOrderGovernanceEntryIndex] = $navOverviewReadingOrderPlanningEntryLineText
    $driftedNavOverviewContent = ($driftedNavOverviewLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($navOverviewPath, $driftedNavOverviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/02-现行标准件总览.md') -ExpectedExitCode 1 -TestName 'block-reading-order-target-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($navOverviewPath, $originalNavOverviewBytes)
}

try {
    $driftedNavOverviewLines = @($navOverviewLines)
    $driftedNavOverviewLines[$navOverviewBackgroundPlanningEntryIndex] = $navOverviewBackgroundGovernanceEntryLineText
    $driftedNavOverviewLines[$navOverviewBackgroundGovernanceEntryIndex] = $navOverviewBackgroundPlanningEntryLineText
    $driftedNavOverviewContent = ($driftedNavOverviewLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($navOverviewPath, $driftedNavOverviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/02-现行标准件总览.md') -ExpectedExitCode 1 -TestName 'block-public-target-entry-order-drift-nav-overview'
}
finally {
    [System.IO.File]::WriteAllBytes($navOverviewPath, $originalNavOverviewBytes)
}

$docsReadmeTargetMainlineSourceIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeTargetMainlineSourceLineText)
$docsReadmeTargetOrderSourceIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeTargetOrderSourceLineText)

if ($docsReadmeTargetMainlineSourceIndex -lt 0 -or $docsReadmeTargetOrderSourceIndex -lt 0) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 Target 主线入口真源说明测试行。"
}

if ($docsReadmeTargetMainlineSourceIndex -gt $docsReadmeTargetOrderSourceIndex) {
    throw "测试前置条件不满足：$docsReadmePath 中 Target 主线入口真源说明顺序已不是当前现状。"
}

try {
    $driftedDocsReadmeLines = @($docsReadmeLines)
    $driftedDocsReadmeLines[$docsReadmeTargetMainlineSourceIndex] = $docsReadmeTargetOrderSourceLineText
    $driftedDocsReadmeLines[$docsReadmeTargetOrderSourceIndex] = $docsReadmeTargetMainlineSourceLineText
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-docs-readme-target-source-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

$navOverviewMaintenanceGateEntryMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+`docs/40-执行/19-多 gate 与多异常并存处理规则\.md`$'
$navOverviewMaintenanceConcurrentEntryMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+`docs/40-执行/20-复杂并存汇报骨架模板\.md`$'
$navOverviewMaintenanceGateEntryLineText = $navOverviewMaintenanceGateEntryMatch.LineText
$navOverviewMaintenanceConcurrentEntryLineText = $navOverviewMaintenanceConcurrentEntryMatch.LineText
$navOverviewMaintenanceGateEntryIndex = $navOverviewMaintenanceGateEntryMatch.Index
$navOverviewMaintenanceConcurrentEntryIndex = $navOverviewMaintenanceConcurrentEntryMatch.Index

if ($null -eq $navOverviewMaintenanceGateEntryMatch -or $null -eq $navOverviewMaintenanceConcurrentEntryMatch) {
    throw "测试前置条件不满足：$navOverviewPath 中缺少维护层主线入口背景区测试行。"
}

if ($navOverviewMaintenanceGateEntryIndex -gt $navOverviewMaintenanceConcurrentEntryIndex) {
    throw "测试前置条件不满足：$navOverviewPath 中维护层主线入口背景区顺序已不是当前现状。"
}

try {
    $driftedNavOverviewLines = @($navOverviewLines)
    $driftedNavOverviewLines[$navOverviewMaintenanceGateEntryIndex] = $navOverviewMaintenanceConcurrentEntryLineText
    $driftedNavOverviewLines[$navOverviewMaintenanceConcurrentEntryIndex] = $navOverviewMaintenanceGateEntryLineText
    $driftedNavOverviewContent = ($driftedNavOverviewLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($navOverviewPath, $driftedNavOverviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/02-现行标准件总览.md') -ExpectedExitCode 1 -TestName 'block-public-maintenance-entry-order-drift-nav-overview'
}
finally {
    [System.IO.File]::WriteAllBytes($navOverviewPath, $originalNavOverviewBytes)
}

$readingOrderGateMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+需要裁决多 gate 或多异常的主状态时，看 `docs/40-执行/19-多 gate 与多异常并存处理规则\.md`$'
$readingOrderConcurrentMatch = Find-LineMatch -Lines $navOverviewLines -Pattern '^\d+\.\s+需要把复杂并存场景快速落进任务包时，看 `docs/40-执行/20-复杂并存汇报骨架模板\.md`$'
$readingOrderGateLineText = $readingOrderGateMatch.LineText
$readingOrderConcurrentLineText = $readingOrderConcurrentMatch.LineText
$readingOrderGateIndex = $readingOrderGateMatch.Index
$readingOrderConcurrentIndex = $readingOrderConcurrentMatch.Index

if ($null -eq $readingOrderGateMatch -or $null -eq $readingOrderConcurrentMatch) {
    throw "测试前置条件不满足：$navOverviewPath 中缺少阅读顺序测试行。"
}

if ($readingOrderGateIndex -gt $readingOrderConcurrentIndex) {
    throw "测试前置条件不满足：$navOverviewPath 中阅读顺序已不是当前现状。"
}

try {
    $driftedNavOverviewLines = @($navOverviewLines)
    $driftedNavOverviewLines[$readingOrderGateIndex] = $readingOrderConcurrentLineText
    $driftedNavOverviewLines[$readingOrderConcurrentIndex] = $readingOrderGateLineText
    $driftedNavOverviewContent = ($driftedNavOverviewLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($navOverviewPath, $driftedNavOverviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/02-现行标准件总览.md') -ExpectedExitCode 1 -TestName 'block-reading-order-maintenance-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($navOverviewPath, $originalNavOverviewBytes)
}

$lockListPath = Join-Path $repoRootPath 'docs/30-方案/02-V4-目录锁定清单.md'
$originalLockListBytes = [System.IO.File]::ReadAllBytes($lockListPath)
$lockListLines = Get-Content $lockListPath
$approvedTopLevelReadmeLineText = 'README.md'
$approvedTopLevelExportDirectoryLineText = '└─ codex-home-export/'
$approvedTrackedGateScriptLineText = '.codex/chancellor/invoke-public-commit-governance-gate.ps1'

if ($lockListLines -notcontains $approvedTopLevelReadmeLineText) {
    throw "测试前置条件不满足：$lockListPath 中缺少 $approvedTopLevelReadmeLineText"
}

if ($lockListLines -notcontains $approvedTopLevelExportDirectoryLineText) {
    throw "测试前置条件不满足：$lockListPath 中缺少 $approvedTopLevelExportDirectoryLineText"
}

if ($lockListLines -notcontains $approvedTrackedGateScriptLineText) {
    throw "测试前置条件不满足：$lockListPath 中缺少 $approvedTrackedGateScriptLineText"
}

try {
    $driftedLockListLines = @(
        $lockListLines | Where-Object { $_ -ne $approvedTopLevelReadmeLineText }
    )
    $driftedLockListContent = ($driftedLockListLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($lockListPath, $driftedLockListContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/30-方案/02-V4-目录锁定清单.md') -ExpectedExitCode 1 -TestName 'block-lock-list-approved-root-entry-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($lockListPath, $originalLockListBytes)
}

try {
    $driftedLockListLines = @(
        $lockListLines | Where-Object { $_ -ne $approvedTopLevelExportDirectoryLineText }
    )
    $driftedLockListContent = ($driftedLockListLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($lockListPath, $driftedLockListContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/30-方案/02-V4-目录锁定清单.md') -ExpectedExitCode 1 -TestName 'block-lock-list-approved-export-directory-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($lockListPath, $originalLockListBytes)
}

try {
    $driftedLockListLines = @(
        $lockListLines | Where-Object { $_ -ne $approvedTrackedGateScriptLineText }
    )
    $driftedLockListContent = ($driftedLockListLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($lockListPath, $driftedLockListContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/30-方案/02-V4-目录锁定清单.md') -ExpectedExitCode 1 -TestName 'block-lock-list-approved-codex-file-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($lockListPath, $originalLockListBytes)
}

$approvedTopLevelAgentsLineText = 'AGENTS.md'
$approvedTopLevelReadmeIndex = [Array]::IndexOf($lockListLines, $approvedTopLevelReadmeLineText)
$approvedTopLevelAgentsIndex = [Array]::IndexOf($lockListLines, $approvedTopLevelAgentsLineText)

if ($approvedTopLevelReadmeIndex -lt 0 -or $approvedTopLevelAgentsIndex -lt 0) {
    throw '测试前置条件不满足：目录锁定清单缺少顶层批准顺序测试行。'
}

if ($approvedTopLevelReadmeIndex -gt $approvedTopLevelAgentsIndex) {
    throw '测试前置条件不满足：目录锁定清单顶层批准顺序已不是当前现状。'
}

try {
    $driftedLockListLines = @($lockListLines)
    $driftedLockListLines[$approvedTopLevelReadmeIndex] = $approvedTopLevelAgentsLineText
    $driftedLockListLines[$approvedTopLevelAgentsIndex] = $approvedTopLevelReadmeLineText
    $driftedLockListContent = ($driftedLockListLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($lockListPath, $driftedLockListContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/30-方案/02-V4-目录锁定清单.md') -ExpectedExitCode 1 -TestName 'block-lock-list-approved-root-entry-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($lockListPath, $originalLockListBytes)
}

$approvedTrackedResolveGateScriptLineText = '.codex/chancellor/resolve-gate-package.ps1'
$approvedTrackedGateScriptIndex = [Array]::IndexOf($lockListLines, $approvedTrackedGateScriptLineText)
$approvedTrackedResolveGateScriptIndex = [Array]::IndexOf($lockListLines, $approvedTrackedResolveGateScriptLineText)

if ($approvedTrackedGateScriptIndex -lt 0 -or $approvedTrackedResolveGateScriptIndex -lt 0) {
    throw '测试前置条件不满足：目录锁定清单缺少运行态白名单顺序测试行。'
}

if ($approvedTrackedGateScriptIndex -gt $approvedTrackedResolveGateScriptIndex) {
    throw '测试前置条件不满足：目录锁定清单运行态白名单顺序已不是当前现状。'
}

try {
    $driftedLockListLines = @($lockListLines)
    $driftedLockListLines[$approvedTrackedGateScriptIndex] = $approvedTrackedResolveGateScriptLineText
    $driftedLockListLines[$approvedTrackedResolveGateScriptIndex] = $approvedTrackedGateScriptLineText
    $driftedLockListContent = ($driftedLockListLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($lockListPath, $driftedLockListContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/30-方案/02-V4-目录锁定清单.md') -ExpectedExitCode 1 -TestName 'block-lock-list-approved-codex-file-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($lockListPath, $originalLockListBytes)
}

$codexHomeExportManifestPath = Join-Path $repoRootPath 'codex-home-export/manifest.json'
$codexHomeExportVersionPath = Join-Path $repoRootPath 'codex-home-export/VERSION.json'
$codexHomeExportReadmePath = Join-Path $repoRootPath 'codex-home-export/README.md'
$originalCodexHomeExportManifestBytes = [System.IO.File]::ReadAllBytes($codexHomeExportManifestPath)
$originalCodexHomeExportVersionBytes = [System.IO.File]::ReadAllBytes($codexHomeExportVersionPath)
$originalCodexHomeExportReadmeBytes = [System.IO.File]::ReadAllBytes($codexHomeExportReadmePath)
$codexHomeExportManifestInfo = Get-Content $codexHomeExportManifestPath -Raw | ConvertFrom-Json
$codexHomeExportReadmeLines = Get-Content $codexHomeExportReadmePath
$codexHomeExportStageLineText = @(
    $codexHomeExportReadmeLines |
        Where-Object { $_ -match '^- `stage`：`[^`]+`$' }
) | Select-Object -First 1
$codexHomeExportLandedSourceLineText = '- `manifest.json` 的 `included` 是当前生产母体受管文件清单唯一真源。'
$codexHomeExportManifestIncludedTarget = 'verify-cutover.ps1'

if ($codexHomeExportManifestInfo.included -notcontains $codexHomeExportManifestIncludedTarget) {
    throw "测试前置条件不满足：$codexHomeExportManifestPath 中缺少 $codexHomeExportManifestIncludedTarget"
}

if ([string]::IsNullOrWhiteSpace($codexHomeExportStageLineText)) {
    throw "测试前置条件不满足：$codexHomeExportReadmePath 中缺少 stage 行。"
}

if ($codexHomeExportReadmeLines -notcontains $codexHomeExportLandedSourceLineText) {
    throw "测试前置条件不满足：$codexHomeExportReadmePath 中缺少 $codexHomeExportLandedSourceLineText"
}

try {
    $driftedManifestInfo = Get-Content $codexHomeExportManifestPath -Raw | ConvertFrom-Json
    $driftedManifestInfo.included = @(
        $driftedManifestInfo.included | Where-Object { $_ -ne $codexHomeExportManifestIncludedTarget }
    )
    $driftedManifestContent = ($driftedManifestInfo | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($codexHomeExportManifestPath, $driftedManifestContent + [Environment]::NewLine, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/manifest.json') -ExpectedExitCode 1 -TestName 'block-codex-home-export-manifest-included-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportManifestPath, $originalCodexHomeExportManifestBytes)
}

$untrackedCodexHomeExportFileName = 'temp-untracked-codex-home-export-probe.ps1'
$untrackedCodexHomeExportFilePath = Join-Path $repoRootPath ('codex-home-export\' + $untrackedCodexHomeExportFileName)
try {
    [System.IO.File]::WriteAllText($untrackedCodexHomeExportFilePath, "Write-Host 'probe'" + [Environment]::NewLine, $utf8NoBom)

    $driftedManifestInfo = Get-Content $codexHomeExportManifestPath -Raw | ConvertFrom-Json
    $driftedManifestInfo.included = @($driftedManifestInfo.included) + @($untrackedCodexHomeExportFileName)
    $driftedManifestContent = ($driftedManifestInfo | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($codexHomeExportManifestPath, $driftedManifestContent + [Environment]::NewLine, $utf8NoBom)

    $readmeLandedStartIndex = [Array]::IndexOf($codexHomeExportReadmeLines, '## 当前已落文件')
    $readmeLandedEndIndex = [Array]::IndexOf($codexHomeExportReadmeLines, '## 当前未落文件')
    if ($readmeLandedStartIndex -lt 0 -or $readmeLandedEndIndex -le $readmeLandedStartIndex) {
        throw "测试前置条件不满足：$codexHomeExportReadmePath 未解析到当前已落文件区块。"
    }

    $driftedReadmeLines = New-Object System.Collections.Generic.List[string]
    foreach ($readmeLine in $codexHomeExportReadmeLines[0..($readmeLandedEndIndex - 1)]) {
        [void]$driftedReadmeLines.Add($readmeLine)
    }
    [void]$driftedReadmeLines.Insert($readmeLandedEndIndex - 1, ('- `{0}` 已被视为当前受管文件。' -f $untrackedCodexHomeExportFileName))
    foreach ($readmeLine in $codexHomeExportReadmeLines[$readmeLandedEndIndex..($codexHomeExportReadmeLines.Count - 1)]) {
        [void]$driftedReadmeLines.Add($readmeLine)
    }
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($codexHomeExportReadmePath, $driftedReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/manifest.json', 'codex-home-export/README.md') -ExpectedExitCode 1 -TestName 'block-codex-home-export-untracked-included-file'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportManifestPath, $originalCodexHomeExportManifestBytes)
    [System.IO.File]::WriteAllBytes($codexHomeExportReadmePath, $originalCodexHomeExportReadmeBytes)
    if (Test-Path $untrackedCodexHomeExportFilePath) {
        Remove-Item -LiteralPath $untrackedCodexHomeExportFilePath -Force
    }
}

try {
    $driftedReadmeLines = @($codexHomeExportReadmeLines)
    $stageLineIndex = [Array]::IndexOf($driftedReadmeLines, $codexHomeExportStageLineText)
    if ($stageLineIndex -lt 0) {
        throw '测试前置条件不满足：生产母体 README stage 行索引不存在。'
    }

    $driftedStageLineText = if ($codexHomeExportStageLineText -eq '- `stage`：`install-ready`') {
        '- `stage`：`bridge-ready`'
    }
    else {
        '- `stage`：`install-ready`'
    }
    $driftedReadmeLines[$stageLineIndex] = $driftedStageLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($codexHomeExportReadmePath, $driftedReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/README.md') -ExpectedExitCode 1 -TestName 'block-codex-home-export-readme-stage-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportReadmePath, $originalCodexHomeExportReadmeBytes)
}

try {
    $driftedVersionInfo = Get-Content $codexHomeExportVersionPath -Raw | ConvertFrom-Json
    $driftedVersionInfo.cx_version = '{0}-drift' -f $driftedVersionInfo.cx_version
    $driftedVersionContent = ($driftedVersionInfo | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($codexHomeExportVersionPath, $driftedVersionContent + [Environment]::NewLine, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/VERSION.json') -ExpectedExitCode 1 -TestName 'block-codex-home-export-version-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportVersionPath, $originalCodexHomeExportVersionBytes)
}

$agentsTaskEntryLineText = '| `传令：XXXX` | 唯一做事入口；`XXXX` 直接写自然语言需求 |'
$agentsUpgradeLineText = '| `传令：升级` | 仅在用户主动要求时，再处理升级动作 |'
$agentsHandoffLineText = '| `传令：交班` | 为当前激活任务生成交班单与进度快照 |'
$agentsReplySkeletonLineText = '- 开工默认骨架固定为：`开场白 → 接令句`'
$panelProtocolLineText = '- 3 个可查命令：`传令：状态 / 传令：版本 / 传令：升级`'
$panelCrossChatLineText = '- 2 个跨聊天命令：`传令：交班 / 传令：接班`'
$panelBoundaryLineText = '- 固定边界提示：`提示：丞相在检查阶段只检查自己，不会查看你的项目；执行阶段只按你的传令办事，不会擅自审查项目。`'
$panelReplySkeletonLineText = '- 固定开工骨架：`开场白 → 接令句`'
$panelProcessQuoteLineText = '- `收口`：`此事已交卷，现呈结果。`'
$panelStatusSlotLineText = '- `关键文件一致性`：关键文件是否一致。'
$panelUpgradeStepLineText = '9. 如需确认升级口径，再输入 `传令：升级`，检查是否明确“默认不自动升级，需用户主动提出”。'
$checklistCommandSourceLineText = '当前验板命令口径以 `codex-home-export/VERSION.json` 为准。'
$checklistProtocolLineText = '- 3 个可查命令：`传令：状态 / 传令：版本 / 传令：升级`'
$checklistCrossChatLineText = '- 2 个跨聊天命令：`传令：交班 / 传令：接班`'
$checklistBoundaryLineText = '- 固定边界提示：`提示：丞相在检查阶段只检查自己，不会查看你的项目；执行阶段只按你的传令办事，不会擅自审查项目。`'
$checklistReplySkeletonLineText = '- 固定开工骨架：`开场白 → 接令句`'
$checklistCloseoutLineText = '- `收口顺不顺`：如触发收口，能否按 `已完成 / 结果 / 下一步`'
$checklistStepLineText = '7. 如需确认升级口径，再输入：`传令：升级`'
$checklistLegacyGuardLineText = '- 入口口径没有回退为旧的多命令体系。'
$legacyPanelCommandText = '传令 检查'
$legacyOpeningLineText = '丞相亮启奏：谨呈本次事宜。'
$codexHomeAgentsPath = Join-Path $repoRootPath 'codex-home-export/AGENTS.md'
$codexHomeExportPanelChecklistPath = Join-Path $repoRootPath 'codex-home-export/panel-acceptance-checklist.md'
$panelAcceptanceDocPath = Join-Path $repoRootPath 'docs/40-执行/03-面板入口验收.md'
$originalAgentsPanelBytes = [System.IO.File]::ReadAllBytes($agentsPath)
$originalCodexHomeAgentsBytes = [System.IO.File]::ReadAllBytes($codexHomeAgentsPath)
$originalCodexHomeExportPanelChecklistBytes = [System.IO.File]::ReadAllBytes($codexHomeExportPanelChecklistPath)
$originalPanelAcceptanceDocBytes = [System.IO.File]::ReadAllBytes($panelAcceptanceDocPath)

if ($agentsLines -notcontains $agentsTaskEntryLineText) {
    throw "测试前置条件不满足：$agentsPath 中缺少 $agentsTaskEntryLineText"
}

if ($agentsLines -notcontains $agentsUpgradeLineText) {
    throw "测试前置条件不满足：$agentsPath 中缺少 $agentsUpgradeLineText"
}

if ($agentsLines -notcontains $agentsHandoffLineText) {
    throw "测试前置条件不满足：$agentsPath 中缺少 $agentsHandoffLineText"
}

if ($agentsLines -notcontains $agentsReplySkeletonLineText) {
    throw "测试前置条件不满足：$agentsPath 中缺少 $agentsReplySkeletonLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelProtocolLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelProtocolLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelCrossChatLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelCrossChatLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelBoundaryLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelBoundaryLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelReplySkeletonLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelReplySkeletonLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelProcessQuoteLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelProcessQuoteLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelStatusSlotLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelStatusSlotLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelUpgradeStepLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelUpgradeStepLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistCommandSourceLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistCommandSourceLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistProtocolLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistProtocolLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistCrossChatLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistCrossChatLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistBoundaryLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistBoundaryLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistReplySkeletonLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistReplySkeletonLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistCloseoutLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistCloseoutLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistStepLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistStepLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistLegacyGuardLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistLegacyGuardLineText"
}

try {
    $driftedVersionInfo = Get-Content $codexHomeExportVersionPath -Raw | ConvertFrom-Json
    $driftedVersionInfo.task_entry_prefix = '开始：'
    $driftedVersionContent = ($driftedVersionInfo | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($codexHomeExportVersionPath, $driftedVersionContent + [Environment]::NewLine, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/VERSION.json') -ExpectedExitCode 1 -TestName 'block-panel-version-entry-prefix-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportVersionPath, $originalCodexHomeExportVersionBytes)
}

try {
    $driftedVersionInfo = Get-Content $codexHomeExportVersionPath -Raw | ConvertFrom-Json
    $driftedVersionInfo.panel_commands = @('传令：状态','传令：版本','传令：检查')
    $driftedVersionContent = ($driftedVersionInfo | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($codexHomeExportVersionPath, $driftedVersionContent + [Environment]::NewLine, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/VERSION.json') -ExpectedExitCode 1 -TestName 'block-panel-version-command-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportVersionPath, $originalCodexHomeExportVersionBytes)
}

try {
    $driftedVersionInfo = Get-Content $codexHomeExportVersionPath -Raw | ConvertFrom-Json
    $driftedVersionInfo.quote_system_version = '1.0'
    $driftedVersionContent = ($driftedVersionInfo | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($codexHomeExportVersionPath, $driftedVersionContent + [Environment]::NewLine, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/VERSION.json') -ExpectedExitCode 1 -TestName 'block-panel-version-quote-system-version-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportVersionPath, $originalCodexHomeExportVersionBytes)
}

try {
    $driftedVersionInfo = Get-Content $codexHomeExportVersionPath -Raw | ConvertFrom-Json
    $driftedVersionInfo.standard_response_templates.task_entry[1] = '军令已明，亮先随便看看。'
    $driftedVersionContent = ($driftedVersionInfo | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($codexHomeExportVersionPath, $driftedVersionContent + [Environment]::NewLine, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/VERSION.json') -ExpectedExitCode 1 -TestName 'block-panel-version-task-entry-template-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportVersionPath, $originalCodexHomeExportVersionBytes)
}

try {
    $driftedVersionInfo = Get-Content $codexHomeExportVersionPath -Raw | ConvertFrom-Json
    $driftedVersionInfo.boundary_prompt = '提示：先检查你的项目，再决定是否执行。'
    $driftedVersionContent = ($driftedVersionInfo | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($codexHomeExportVersionPath, $driftedVersionContent + [Environment]::NewLine, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/VERSION.json') -ExpectedExitCode 1 -TestName 'block-panel-version-boundary-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportVersionPath, $originalCodexHomeExportVersionBytes)
}

try {
    $driftedAgentsContent = (Get-Content $agentsPath -Raw).Replace($agentsTaskEntryLineText, '| `开始：XXXX` | 唯一做事入口；`XXXX` 直接写自然语言需求 |')
    [System.IO.File]::WriteAllText($agentsPath, $driftedAgentsContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('AGENTS.md') -ExpectedExitCode 1 -TestName 'block-panel-agents-entry-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($agentsPath, $originalAgentsPanelBytes)
}

try {
    $driftedAgentsContent = (Get-Content $agentsPath -Raw).Replace($agentsReplySkeletonLineText, '- 开工默认骨架固定为：`开场白 → 先解释一大段内部流程 → 接令句`')
    [System.IO.File]::WriteAllText($agentsPath, $driftedAgentsContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('AGENTS.md') -ExpectedExitCode 1 -TestName 'block-panel-agents-reply-skeleton-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($agentsPath, $originalAgentsPanelBytes)
}

try {
    $driftedAgentsContent = (Get-Content $agentsPath -Raw).Replace($agentsUpgradeLineText, '| `传令 检查` | 做最小必要检查 |')
    [System.IO.File]::WriteAllText($agentsPath, $driftedAgentsContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('AGENTS.md') -ExpectedExitCode 1 -TestName 'block-panel-agents-legacy-command-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($agentsPath, $originalAgentsPanelBytes)
}

try {
    $driftedCodexHomeAgentsContent = (Get-Content $codexHomeAgentsPath -Raw).Replace($agentsReplySkeletonLineText, '- 开工默认骨架固定为：`开场白 → 先解释一大段内部流程 → 接令句`')
    [System.IO.File]::WriteAllText($codexHomeAgentsPath, $driftedCodexHomeAgentsContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/AGENTS.md') -ExpectedExitCode 1 -TestName 'block-codex-home-agents-reply-skeleton-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeAgentsPath, $originalCodexHomeAgentsBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelProtocolLineText, '- 3 个可查命令：`传令：状态 / 传令：版本 / 传令：检查`')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-command-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelReplySkeletonLineText, '- 固定开工骨架：`开场白 → 先解释一大段内部流程 → 接令句`')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-reply-skeleton-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelProcessQuoteLineText, '- `收口`：`这事差不多就这样吧。`')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-process-quote-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelBoundaryLineText, '- 固定边界提示：`提示：丞相会先检查你的项目，再决定是否执行。`')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-boundary-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelStatusSlotLineText, '- `关键文件一致性`：大概没问题就行。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-status-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelUpgradeStepLineText, '9. 如需确认升级口径，再输入 `传令：检查`。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-upgrade-step-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistCommandSourceLineText, '当前验板命令口径以面板实际表现为准。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-command-source-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistProtocolLineText, '- 3 个可查命令：`传令：状态 / 传令：版本 / 传令：检查`')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-command-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistReplySkeletonLineText, '- 固定开工骨架：`开场白 → 先解释一大段内部流程 → 接令句`')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-reply-skeleton-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistCloseoutLineText, '- `收口顺不顺`：收口随便说几句也行')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-closeout-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistBoundaryLineText, '- 固定边界提示：`提示：先检查你的项目，再决定是否执行。`')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-boundary-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistStepLineText, '7. 如需确认升级口径，再输入：`传令：检查`')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-step-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistLegacyGuardLineText, '- 入口口径已经回退为旧的多命令体系。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-legacy-guard-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace('传令：版本', '传令 版本')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-legacy-marker-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

Write-Host 'PASS: test-public-commit-governance-gate.ps1'
