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

$blockedLogsPrefixSourceLineText = 'prefix:logs/'
$blockedLogsReadmeExceptionSourceLineText = 'except:logs/README.md'

if ($localSafeFlowLines -notcontains $blockedLogsPrefixSourceLineText -or $localSafeFlowLines -notcontains $blockedLogsReadmeExceptionSourceLineText) {
    throw '测试前置条件不满足：公开提交禁止路径真源测试行缺失。'
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
$blockedLogsReadmeExceptionSourceIndex = [Array]::IndexOf($localSafeFlowLines, $blockedLogsReadmeExceptionSourceLineText)
$blockedTempGeneratedReadmeExceptionSourceIndex = [Array]::IndexOf($localSafeFlowLines, $blockedTempGeneratedReadmeExceptionSourceLineText)

if ($blockedLogsReadmeExceptionSourceIndex -lt 0 -or $blockedTempGeneratedReadmeExceptionSourceIndex -lt 0) {
    throw '测试前置条件不满足：公开提交禁止路径例外顺序测试行缺失。'
}

if ($blockedLogsReadmeExceptionSourceIndex -gt $blockedTempGeneratedReadmeExceptionSourceIndex) {
    throw '测试前置条件不满足：公开提交禁止路径例外顺序已不是当前现状。'
}

try {
    $driftedLocalSafeFlowLines = @($localSafeFlowLines)
    $driftedLocalSafeFlowLines[$blockedLogsReadmeExceptionSourceIndex] = $blockedTempGeneratedReadmeExceptionSourceLineText
    $driftedLocalSafeFlowLines[$blockedTempGeneratedReadmeExceptionSourceIndex] = $blockedLogsReadmeExceptionSourceLineText
    $driftedLocalSafeFlowContent = ($driftedLocalSafeFlowLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($localSafeFlowPath, $driftedLocalSafeFlowContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/10-本地安全提交流程.md') -ExpectedExitCode 1 -TestName 'block-blocked-prefix-exception-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($localSafeFlowPath, $originalLocalSafeFlowBytes)
}

$removedTargetEntryLineText = '- `30-方案/04-V4-Target-蓝图.md`'

if ($docsReadmeLines -notcontains $removedTargetEntryLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $removedTargetEntryLineText"
}

try {
    $driftedDocsReadmeLines = @(
        $docsReadmeLines | Where-Object { $_ -ne $removedTargetEntryLineText }
    )
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-public-target-entry-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

$readmePath = Join-Path $repoRootPath 'README.md'
$originalReadmeBytes = [System.IO.File]::ReadAllBytes($readmePath)
$readmeLines = Get-Content $readmePath
$planningEntryLineText = '- V4-规划策略候选规范：`docs/30-方案/07-V4-规划策略候选规范.md`'
$governanceEntryLineText = '- V4-治理审计候选规范：`docs/30-方案/08-V4-治理审计候选规范.md`'
$planningEntryIndex = [Array]::IndexOf($readmeLines, $planningEntryLineText)
$governanceEntryIndex = [Array]::IndexOf($readmeLines, $governanceEntryLineText)

if ($planningEntryIndex -lt 0 -or $governanceEntryIndex -lt 0) {
    throw "测试前置条件不满足：$readmePath 中缺少 Target 主线关键入口测试行。"
}

if ($planningEntryIndex -gt $governanceEntryIndex) {
    throw "测试前置条件不满足：$readmePath 中规划与治理入口顺序已不是当前现状。"
}

try {
    $driftedReadmeLines = @($readmeLines)
    $driftedReadmeLines[$planningEntryIndex] = $governanceEntryLineText
    $driftedReadmeLines[$governanceEntryIndex] = $planningEntryLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md') -ExpectedExitCode 1 -TestName 'block-public-target-entry-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
}

$removedRestartGuideCoreEntryLineText = '- `10-输入材料/01-旧仓必需资产清单.md`'

if ($docsReadmeLines -notcontains $removedRestartGuideCoreEntryLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $removedRestartGuideCoreEntryLineText"
}

try {
    $driftedDocsReadmeLines = @(
        $docsReadmeLines | Where-Object { $_ -ne $removedRestartGuideCoreEntryLineText }
    )
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-restart-guide-core-entry-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

$restartDecisionEntryLineText = '- 重启决策：`docs/20-决策/01-V4-重启ADR.md`'
$restartAssetEntryLineText = '- 必需资产清单：`docs/10-输入材料/01-旧仓必需资产清单.md`'
$restartDecisionEntryIndex = [Array]::IndexOf($readmeLines, $restartDecisionEntryLineText)
$restartAssetEntryIndex = [Array]::IndexOf($readmeLines, $restartAssetEntryLineText)

if ($restartDecisionEntryIndex -lt 0 -or $restartAssetEntryIndex -lt 0) {
    throw "测试前置条件不满足：$readmePath 中缺少启动阶段入口顺序测试行。"
}

if ($restartDecisionEntryIndex -gt $restartAssetEntryIndex) {
    throw "测试前置条件不满足：$readmePath 中启动阶段入口顺序已不是当前现状。"
}

try {
    $driftedReadmeLines = @($readmeLines)
    $driftedReadmeLines[$restartDecisionEntryIndex] = $restartAssetEntryLineText
    $driftedReadmeLines[$restartAssetEntryIndex] = $restartDecisionEntryLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md') -ExpectedExitCode 1 -TestName 'block-startup-phase-entry-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
}

$restartGuideTaskSpecEntryLineText = '- 任务包规范：`docs/40-执行/01-任务包规范.md`'
$restartGuideTaskTemplateEntryLineText = '- 任务包模板：`docs/40-执行/02-任务包模板.md`'
$restartGuideTaskSpecEntryIndex = [Array]::IndexOf($readmeLines, $restartGuideTaskSpecEntryLineText)
$restartGuideTaskTemplateEntryIndex = [Array]::IndexOf($readmeLines, $restartGuideTaskTemplateEntryLineText)

if ($restartGuideTaskSpecEntryIndex -lt 0 -or $restartGuideTaskTemplateEntryIndex -lt 0) {
    throw "测试前置条件不满足：$readmePath 中缺少重启导读核心顺序测试行。"
}

if ($restartGuideTaskSpecEntryIndex -gt $restartGuideTaskTemplateEntryIndex) {
    throw "测试前置条件不满足：$readmePath 中重启导读核心顺序已不是当前现状。"
}

try {
    $driftedReadmeLines = @($readmeLines)
    $driftedReadmeLines[$restartGuideTaskSpecEntryIndex] = $restartGuideTaskTemplateEntryLineText
    $driftedReadmeLines[$restartGuideTaskTemplateEntryIndex] = $restartGuideTaskSpecEntryLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md') -ExpectedExitCode 1 -TestName 'block-restart-guide-core-entry-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
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

$removedMaintenanceEntryLineText = '- `40-执行/16-拍板包半自动模板.md`'

if ($docsReadmeLines -notcontains $removedMaintenanceEntryLineText) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少 $removedMaintenanceEntryLineText"
}

try {
    $driftedDocsReadmeLines = @(
        $docsReadmeLines | Where-Object { $_ -ne $removedMaintenanceEntryLineText }
    )
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-public-maintenance-entry-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

$removedMaintenanceArchiveEntryLineText = '- 归档规则：`docs/90-归档/01-执行区证据稿归档规则.md`'

if ($readmeLines -notcontains $removedMaintenanceArchiveEntryLineText) {
    throw "测试前置条件不满足：$readmePath 中缺少 $removedMaintenanceArchiveEntryLineText"
}

try {
    $driftedReadmeLines = @(
        $readmeLines | Where-Object { $_ -ne $removedMaintenanceArchiveEntryLineText }
    )
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md') -ExpectedExitCode 1 -TestName 'block-public-maintenance-capability-entry-missing'
}
finally {
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
}

$readmeGovernanceCapabilityEntryLineText = '- V4-治理审计候选规范：`docs/30-方案/08-V4-治理审计候选规范.md`'
$readmeConfigCapabilityEntryLineText = '- 关键配置来源与漂移复核模板：`docs/40-执行/21-关键配置来源与漂移复核模板.md`'
$docsReadmeGovernanceCapabilityEntryLineText = '- `30-方案/08-V4-治理审计候选规范.md`'
$docsReadmeConfigCapabilityEntryLineText = '- `40-执行/21-关键配置来源与漂移复核模板.md`'
$readmeGovernanceCapabilityEntryIndex = [Array]::IndexOf($readmeLines, $readmeGovernanceCapabilityEntryLineText)
$readmeConfigCapabilityEntryIndex = [Array]::IndexOf($readmeLines, $readmeConfigCapabilityEntryLineText)
$docsReadmeGovernanceCapabilityEntryIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeGovernanceCapabilityEntryLineText)
$docsReadmeConfigCapabilityEntryIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeConfigCapabilityEntryLineText)

if ($readmeGovernanceCapabilityEntryIndex -lt 0 -or $readmeConfigCapabilityEntryIndex -lt 0 -or $docsReadmeGovernanceCapabilityEntryIndex -lt 0 -or $docsReadmeConfigCapabilityEntryIndex -lt 0) {
    throw '测试前置条件不满足：维护层补充入口顺序测试行缺失。'
}

if ($readmeGovernanceCapabilityEntryIndex -gt $readmeConfigCapabilityEntryIndex -or $docsReadmeGovernanceCapabilityEntryIndex -gt $docsReadmeConfigCapabilityEntryIndex) {
    throw '测试前置条件不满足：维护层补充入口顺序已不是当前现状。'
}

try {
    $driftedReadmeLines = @($readmeLines)
    $driftedReadmeLines[$readmeGovernanceCapabilityEntryIndex] = $readmeConfigCapabilityEntryLineText
    $driftedReadmeLines[$readmeConfigCapabilityEntryIndex] = $readmeGovernanceCapabilityEntryLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md') -ExpectedExitCode 1 -TestName 'block-public-maintenance-capability-entry-order-drift-readme'
}
finally {
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
}

try {
    $driftedReadmeLines = @($readmeLines)
    $driftedReadmeLines[$readmeGovernanceCapabilityEntryIndex] = $readmeConfigCapabilityEntryLineText
    $driftedReadmeLines[$readmeConfigCapabilityEntryIndex] = $readmeGovernanceCapabilityEntryLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    $driftedDocsReadmeLines = @($docsReadmeLines)
    $driftedDocsReadmeLines[$docsReadmeGovernanceCapabilityEntryIndex] = $docsReadmeConfigCapabilityEntryLineText
    $driftedDocsReadmeLines[$docsReadmeConfigCapabilityEntryIndex] = $docsReadmeGovernanceCapabilityEntryLineText
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md', 'docs/README.md') -ExpectedExitCode 1 -TestName 'block-public-maintenance-capability-entry-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
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

$maintenanceGuideGovernanceCapabilityLineText = '- 文档：`docs/30-方案/08-V4-治理审计候选规范.md`'
$maintenanceGuideConfigCapabilityLineText = '- 文档：`docs/40-执行/21-关键配置来源与漂移复核模板.md`'
$maintenanceGuideGovernanceCapabilityIndex = [Array]::IndexOf($maintenanceGuideLines, $maintenanceGuideGovernanceCapabilityLineText)
$maintenanceGuideConfigCapabilityIndex = [Array]::IndexOf($maintenanceGuideLines, $maintenanceGuideConfigCapabilityLineText)

if ($maintenanceGuideGovernanceCapabilityIndex -lt 0 -or $maintenanceGuideConfigCapabilityIndex -lt 0) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中缺少维护层能力顺序测试行。"
}

if ($maintenanceGuideGovernanceCapabilityIndex -gt $maintenanceGuideConfigCapabilityIndex) {
    throw "测试前置条件不满足：$maintenanceGuidePath 中维护层能力顺序已不是当前现状。"
}

try {
    $driftedMaintenanceGuideLines = @($maintenanceGuideLines)
    $driftedMaintenanceGuideLines[$maintenanceGuideGovernanceCapabilityIndex] = $maintenanceGuideConfigCapabilityLineText
    $driftedMaintenanceGuideLines[$maintenanceGuideConfigCapabilityIndex] = $maintenanceGuideGovernanceCapabilityLineText
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

$maintenanceGateEntryLineText = '- 多 gate 与多异常并存处理规则：`docs/40-执行/19-多 gate 与多异常并存处理规则.md`'
$maintenanceConcurrentEntryLineText = '- 复杂并存汇报骨架模板：`docs/40-执行/20-复杂并存汇报骨架模板.md`'
$maintenanceGateEntryIndex = [Array]::IndexOf($readmeLines, $maintenanceGateEntryLineText)
$maintenanceConcurrentEntryIndex = [Array]::IndexOf($readmeLines, $maintenanceConcurrentEntryLineText)

if ($maintenanceGateEntryIndex -lt 0 -or $maintenanceConcurrentEntryIndex -lt 0) {
    throw "测试前置条件不满足：$readmePath 中缺少维护层主线关键入口测试行。"
}

if ($maintenanceGateEntryIndex -gt $maintenanceConcurrentEntryIndex) {
    throw "测试前置条件不满足：$readmePath 中维护层入口顺序已不是当前现状。"
}

try {
    $driftedReadmeLines = @($readmeLines)
    $driftedReadmeLines[$maintenanceGateEntryIndex] = $maintenanceConcurrentEntryLineText
    $driftedReadmeLines[$maintenanceConcurrentEntryIndex] = $maintenanceGateEntryLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md') -ExpectedExitCode 1 -TestName 'block-public-maintenance-entry-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
}

$docsReadmeMaintenanceGateEntryLineText = '- `40-执行/19-多 gate 与多异常并存处理规则.md`'
$docsReadmeMaintenanceConcurrentEntryLineText = '- `40-执行/20-复杂并存汇报骨架模板.md`'
$docsReadmeMaintenanceGateEntryIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeMaintenanceGateEntryLineText)
$docsReadmeMaintenanceConcurrentEntryIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeMaintenanceConcurrentEntryLineText)

if ($docsReadmeMaintenanceGateEntryIndex -lt 0 -or $docsReadmeMaintenanceConcurrentEntryIndex -lt 0) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少维护层主线关键入口测试行。"
}

if ($docsReadmeMaintenanceGateEntryIndex -gt $docsReadmeMaintenanceConcurrentEntryIndex) {
    throw "测试前置条件不满足：$docsReadmePath 中维护层入口顺序已不是当前现状。"
}

try {
    $driftedDocsReadmeLines = @($docsReadmeLines)
    $driftedDocsReadmeLines[$docsReadmeMaintenanceGateEntryIndex] = $docsReadmeMaintenanceConcurrentEntryLineText
    $driftedDocsReadmeLines[$docsReadmeMaintenanceConcurrentEntryIndex] = $docsReadmeMaintenanceGateEntryLineText
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-public-maintenance-entry-order-drift-docs-readme'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

$navOverviewPath = Join-Path $repoRootPath 'docs/00-导航/02-现行标准件总览.md'
$originalNavOverviewBytes = [System.IO.File]::ReadAllBytes($navOverviewPath)
$navOverviewLines = Get-Content $navOverviewPath
$execReadmeSectionMarkerLineText = '当前现行标准件：'

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

$navOverviewRuleGuideLineText = '4. `docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md`'
$navOverviewRuleHygieneLineText = '5. `docs/reference/02-仓库卫生与命名规范.md`'
$navOverviewRuleGuideIndex = [Array]::IndexOf($navOverviewLines, $navOverviewRuleGuideLineText)
$navOverviewRuleHygieneIndex = [Array]::IndexOf($navOverviewLines, $navOverviewRuleHygieneLineText)

if ($navOverviewRuleGuideIndex -lt 0 -or $navOverviewRuleHygieneIndex -lt 0) {
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
$readmeExecCurrentEntryLineText = '- 任务包半自动起包：`docs/40-执行/11-任务包半自动起包.md`'
$readmeExecTargetEntryLineText = '- V4-Target 实施计划：`docs/40-执行/12-V4-Target-实施计划.md`'
$docsReadmeExecCurrentEntryLineText = '- `40-执行/11-任务包半自动起包.md`'
$navOverviewCurrentExecEntryLineText = '12. `docs/40-执行/11-任务包半自动起包.md`'
$navOverviewReadingExecEntryLineText = '12. 需要更快起包时，看 `docs/40-执行/11-任务包半自动起包.md`'
$maintenanceGuideExecEntryLineText = '- 文档：`docs/40-执行/11-任务包半自动起包.md`'

if ($execReadmeLines -notcontains $execReadmeCurrentEntryLineText -or $execReadmeLines -notcontains $execReadmeTargetEntryLineText -or $readmeLines -notcontains $readmeExecCurrentEntryLineText -or $readmeLines -notcontains $readmeExecTargetEntryLineText -or $docsReadmeLines -notcontains $docsReadmeExecCurrentEntryLineText -or $navOverviewLines -notcontains $navOverviewCurrentExecEntryLineText -or $navOverviewLines -notcontains $navOverviewReadingExecEntryLineText -or $maintenanceGuideLines -notcontains $maintenanceGuideExecEntryLineText) {
    throw '测试前置条件不满足：执行区真源联动测试行缺失。'
}

$execReadmeCurrentEntryIndex = [Array]::IndexOf($execReadmeLines, $execReadmeCurrentEntryLineText)
$execReadmeTargetEntryIndex = [Array]::IndexOf($execReadmeLines, $execReadmeTargetEntryLineText)
$readmeExecCurrentEntryIndex = [Array]::IndexOf($readmeLines, $readmeExecCurrentEntryLineText)
$readmeExecTargetEntryIndex = [Array]::IndexOf($readmeLines, $readmeExecTargetEntryLineText)

if ($execReadmeCurrentEntryIndex -lt 0 -or $execReadmeTargetEntryIndex -lt 0 -or $readmeExecCurrentEntryIndex -lt 0 -or $readmeExecTargetEntryIndex -lt 0) {
    throw '测试前置条件不满足：执行区顺序测试行缺失。'
}

if ($execReadmeCurrentEntryIndex -gt $execReadmeTargetEntryIndex -or $readmeExecCurrentEntryIndex -gt $readmeExecTargetEntryIndex) {
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
    $driftedReadmeLines = @($readmeLines)
    $driftedReadmeLines[$readmeExecCurrentEntryIndex] = $readmeExecTargetEntryLineText
    $driftedReadmeLines[$readmeExecTargetEntryIndex] = $readmeExecCurrentEntryLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md') -ExpectedExitCode 1 -TestName 'block-public-exec-entry-order-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
}

try {
    $driftedExecReadmeLines = @(
        $execReadmeLines | Where-Object { $_ -ne $execReadmeCurrentEntryLineText }
    )
    $driftedExecReadmeContent = ($driftedExecReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($execReadmePath, $driftedExecReadmeContent, $utf8NoBom)

    $driftedReadmeLines = @(
        $readmeLines | Where-Object { $_ -ne $readmeExecCurrentEntryLineText }
    )
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    $driftedDocsReadmeLines = @(
        $docsReadmeLines | Where-Object { $_ -ne $docsReadmeExecCurrentEntryLineText }
    )
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    $driftedNavOverviewLines = @(
        $navOverviewLines | Where-Object { $_ -ne $navOverviewCurrentExecEntryLineText -and $_ -ne $navOverviewReadingExecEntryLineText }
    )
    $driftedNavOverviewContent = ($driftedNavOverviewLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($navOverviewPath, $driftedNavOverviewContent, $utf8NoBom)

    $driftedMaintenanceGuideLines = @(
        $maintenanceGuideLines | Where-Object { $_ -ne $maintenanceGuideExecEntryLineText }
    )
    $driftedMaintenanceGuideContent = ($driftedMaintenanceGuideLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($maintenanceGuidePath, $driftedMaintenanceGuideContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md', 'docs/README.md', 'docs/00-导航/02-现行标准件总览.md', 'docs/40-执行/README.md', 'docs/40-执行/13-维护层总入口.md') -ExpectedExitCode 0 -TestName 'allow-exec-standard-source-sync'
}
finally {
    [System.IO.File]::WriteAllBytes($execReadmePath, $originalExecReadmeBytes)
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
    [System.IO.File]::WriteAllBytes($navOverviewPath, $originalNavOverviewBytes)
    [System.IO.File]::WriteAllBytes($maintenanceGuidePath, $originalMaintenanceGuideBytes)
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

$docsReadmePlanningEntryLineText = '- `30-方案/07-V4-规划策略候选规范.md`'
$docsReadmeGovernanceEntryLineText = '- `30-方案/08-V4-治理审计候选规范.md`'
$docsReadmePlanningEntryIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmePlanningEntryLineText)
$docsReadmeGovernanceEntryIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeGovernanceEntryLineText)
$navOverviewBackgroundPlanningEntryLineText = '10. `docs/30-方案/07-V4-规划策略候选规范.md`'
$navOverviewBackgroundGovernanceEntryLineText = '11. `docs/30-方案/08-V4-治理审计候选规范.md`'
$navOverviewBackgroundPlanningEntryIndex = [Array]::IndexOf($navOverviewLines, $navOverviewBackgroundPlanningEntryLineText)
$navOverviewBackgroundGovernanceEntryIndex = [Array]::IndexOf($navOverviewLines, $navOverviewBackgroundGovernanceEntryLineText)
$navOverviewReadingOrderPlanningEntryLineText = '17. 需要明确规划层第一条高复利候选时，看 `docs/30-方案/07-V4-规划策略候选规范.md`'
$navOverviewReadingOrderGovernanceEntryLineText = '18. 需要明确治理层第二条高复利候选时，看 `docs/30-方案/08-V4-治理审计候选规范.md`'
$navOverviewReadingOrderPlanningEntryIndex = [Array]::IndexOf($navOverviewLines, $navOverviewReadingOrderPlanningEntryLineText)
$navOverviewReadingOrderGovernanceEntryIndex = [Array]::IndexOf($navOverviewLines, $navOverviewReadingOrderGovernanceEntryLineText)
$targetPlanPlanningEntryLineText = 'docs/30-方案/07-V4-规划策略候选规范.md'
$targetPlanGovernanceEntryLineText = 'docs/30-方案/08-V4-治理审计候选规范.md'
$targetPlanPlanningEntryIndex = [Array]::IndexOf($targetPlanLines, $targetPlanPlanningEntryLineText)
$targetPlanGovernanceEntryIndex = [Array]::IndexOf($targetPlanLines, $targetPlanGovernanceEntryLineText)

if ($docsReadmePlanningEntryIndex -lt 0 -or $docsReadmeGovernanceEntryIndex -lt 0) {
    throw "测试前置条件不满足：$docsReadmePath 中缺少真源联动测试行。"
}

if ($navOverviewBackgroundPlanningEntryIndex -lt 0 -or $navOverviewBackgroundGovernanceEntryIndex -lt 0) {
    throw "测试前置条件不满足：$navOverviewPath 中缺少入口与背景真源联动测试行。"
}

if ($navOverviewReadingOrderPlanningEntryIndex -lt 0 -or $navOverviewReadingOrderGovernanceEntryIndex -lt 0) {
    throw "测试前置条件不满足：$navOverviewPath 中缺少阅读顺序真源联动测试行。"
}

if ($targetPlanPlanningEntryIndex -lt 0 -or $targetPlanGovernanceEntryIndex -lt 0) {
    throw "测试前置条件不满足：$targetPlanPath 中缺少 Target 主线真源联动测试行。"
}

if ($planningEntryIndex -gt $governanceEntryIndex -or $docsReadmePlanningEntryIndex -gt $docsReadmeGovernanceEntryIndex -or $navOverviewBackgroundPlanningEntryIndex -gt $navOverviewBackgroundGovernanceEntryIndex -or $navOverviewReadingOrderPlanningEntryIndex -gt $navOverviewReadingOrderGovernanceEntryIndex -or $targetPlanPlanningEntryIndex -gt $targetPlanGovernanceEntryIndex) {
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

try {
    $driftedDocsReadmeLines = @($docsReadmeLines)
    $driftedDocsReadmeLines[$docsReadmePlanningEntryIndex] = $docsReadmeGovernanceEntryLineText
    $driftedDocsReadmeLines[$docsReadmeGovernanceEntryIndex] = $docsReadmePlanningEntryLineText
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/README.md') -ExpectedExitCode 1 -TestName 'block-public-target-entry-order-drift-docs-readme'
}
finally {
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
}

try {
    $driftedReadmeLines = @($readmeLines)
    $driftedReadmeLines[$planningEntryIndex] = $governanceEntryLineText
    $driftedReadmeLines[$governanceEntryIndex] = $planningEntryLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    $driftedDocsReadmeLines = @($docsReadmeLines)
    $driftedDocsReadmeLines[$docsReadmePlanningEntryIndex] = $docsReadmeGovernanceEntryLineText
    $driftedDocsReadmeLines[$docsReadmeGovernanceEntryIndex] = $docsReadmePlanningEntryLineText
    $driftedDocsReadmeContent = ($driftedDocsReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($docsReadmePath, $driftedDocsReadmeContent, $utf8NoBom)

    $driftedNavOverviewLines = @($navOverviewLines)
    $driftedNavOverviewLines[$navOverviewBackgroundPlanningEntryIndex] = $navOverviewBackgroundGovernanceEntryLineText
    $driftedNavOverviewLines[$navOverviewBackgroundGovernanceEntryIndex] = $navOverviewBackgroundPlanningEntryLineText
    $driftedNavOverviewLines[$navOverviewReadingOrderPlanningEntryIndex] = $navOverviewReadingOrderGovernanceEntryLineText
    $driftedNavOverviewLines[$navOverviewReadingOrderGovernanceEntryIndex] = $navOverviewReadingOrderPlanningEntryLineText
    $driftedNavOverviewContent = ($driftedNavOverviewLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($navOverviewPath, $driftedNavOverviewContent, $utf8NoBom)

    $driftedTargetPlanLines = @($targetPlanLines)
    $driftedTargetPlanLines[$targetPlanPlanningEntryIndex] = $targetPlanGovernanceEntryLineText
    $driftedTargetPlanLines[$targetPlanGovernanceEntryIndex] = $targetPlanPlanningEntryLineText
    $driftedTargetPlanContent = ($driftedTargetPlanLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($targetPlanPath, $driftedTargetPlanContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md', 'docs/README.md', 'docs/00-导航/02-现行标准件总览.md', 'docs/40-执行/12-V4-Target-实施计划.md') -ExpectedExitCode 0 -TestName 'allow-reading-order-source-sync'
}
finally {
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
    [System.IO.File]::WriteAllBytes($docsReadmePath, $originalDocsReadmeBytes)
    [System.IO.File]::WriteAllBytes($navOverviewPath, $originalNavOverviewBytes)
    [System.IO.File]::WriteAllBytes($targetPlanPath, $originalTargetPlanBytes)
}

$navOverviewMaintenanceGateEntryLineText = '19. `docs/40-执行/19-多 gate 与多异常并存处理规则.md`'
$navOverviewMaintenanceConcurrentEntryLineText = '20. `docs/40-执行/20-复杂并存汇报骨架模板.md`'
$navOverviewMaintenanceGateEntryIndex = [Array]::IndexOf($navOverviewLines, $navOverviewMaintenanceGateEntryLineText)
$navOverviewMaintenanceConcurrentEntryIndex = [Array]::IndexOf($navOverviewLines, $navOverviewMaintenanceConcurrentEntryLineText)

if ($navOverviewMaintenanceGateEntryIndex -lt 0 -or $navOverviewMaintenanceConcurrentEntryIndex -lt 0) {
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

$readingOrderGateLineText = '26. 需要裁决多 gate 或多异常的主状态时，看 `docs/40-执行/19-多 gate 与多异常并存处理规则.md`'
$readingOrderConcurrentLineText = '27. 需要把复杂并存场景快速落进任务包时，看 `docs/40-执行/20-复杂并存汇报骨架模板.md`'
$readingOrderGateIndex = [Array]::IndexOf($navOverviewLines, $readingOrderGateLineText)
$readingOrderConcurrentIndex = [Array]::IndexOf($navOverviewLines, $readingOrderConcurrentLineText)

if ($readingOrderGateIndex -lt 0 -or $readingOrderConcurrentIndex -lt 0) {
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

Write-Host 'PASS: test-public-commit-governance-gate.ps1'
