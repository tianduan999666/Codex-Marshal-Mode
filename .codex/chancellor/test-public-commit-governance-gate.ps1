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
    },
    @{
        Name = 'allow-codex-home-export-consistency'
        Paths = @('codex-home-export/README.md', 'codex-home-export/manifest.json', 'codex-home-export/VERSION.json')
        ExpectedExitCode = 0
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

$readmePanelCapabilityEntryLineText = '- 面板入口验收：`docs/40-执行/03-面板入口验收.md`'
$readmeGovernanceCapabilityEntryLineText = '- V4-治理审计候选规范：`docs/30-方案/08-V4-治理审计候选规范.md`'
$readmeConfigCapabilityEntryLineText = '- 关键配置来源与漂移复核模板：`docs/40-执行/21-关键配置来源与漂移复核模板.md`'
$docsReadmePanelCapabilityEntryLineText = '- `40-执行/03-面板入口验收.md`'
$docsReadmeGovernanceCapabilityEntryLineText = '- `30-方案/08-V4-治理审计候选规范.md`'
$docsReadmeConfigCapabilityEntryLineText = '- `40-执行/21-关键配置来源与漂移复核模板.md`'
$readmePanelCapabilityEntryIndex = [Array]::IndexOf($readmeLines, $readmePanelCapabilityEntryLineText)
$readmeGovernanceCapabilityEntryIndex = [Array]::IndexOf($readmeLines, $readmeGovernanceCapabilityEntryLineText)
$readmeConfigCapabilityEntryIndex = [Array]::IndexOf($readmeLines, $readmeConfigCapabilityEntryLineText)
$docsReadmePanelCapabilityEntryIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmePanelCapabilityEntryLineText)
$docsReadmeGovernanceCapabilityEntryIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeGovernanceCapabilityEntryLineText)
$docsReadmeConfigCapabilityEntryIndex = [Array]::IndexOf($docsReadmeLines, $docsReadmeConfigCapabilityEntryLineText)

if ($readmePanelCapabilityEntryIndex -lt 0 -or $readmeGovernanceCapabilityEntryIndex -lt 0 -or $readmeConfigCapabilityEntryIndex -lt 0 -or $docsReadmePanelCapabilityEntryIndex -lt 0 -or $docsReadmeGovernanceCapabilityEntryIndex -lt 0 -or $docsReadmeConfigCapabilityEntryIndex -lt 0) {
    throw '测试前置条件不满足：维护层补充入口顺序测试行缺失。'
}

if ($readmePanelCapabilityEntryIndex -gt $readmeGovernanceCapabilityEntryIndex -or $readmeGovernanceCapabilityEntryIndex -gt $readmeConfigCapabilityEntryIndex -or $docsReadmePanelCapabilityEntryIndex -gt $docsReadmeGovernanceCapabilityEntryIndex -or $docsReadmeGovernanceCapabilityEntryIndex -gt $docsReadmeConfigCapabilityEntryIndex) {
    throw '测试前置条件不满足：维护层补充入口顺序已不是当前现状。'
}

try {
    $driftedReadmeLines = @($readmeLines)
    $driftedReadmeLines[$readmePanelCapabilityEntryIndex] = $readmeGovernanceCapabilityEntryLineText
    $driftedReadmeLines[$readmeGovernanceCapabilityEntryIndex] = $readmePanelCapabilityEntryLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('README.md') -ExpectedExitCode 1 -TestName 'block-public-maintenance-capability-entry-order-drift-readme'
}
finally {
    [System.IO.File]::WriteAllBytes($readmePath, $originalReadmeBytes)
}

try {
    $driftedReadmeLines = @($readmeLines)
    $driftedReadmeLines[$readmePanelCapabilityEntryIndex] = $readmeGovernanceCapabilityEntryLineText
    $driftedReadmeLines[$readmeGovernanceCapabilityEntryIndex] = $readmePanelCapabilityEntryLineText
    $driftedReadmeContent = ($driftedReadmeLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($readmePath, $driftedReadmeContent, $utf8NoBom)

    $driftedDocsReadmeLines = @($docsReadmeLines)
    $driftedDocsReadmeLines[$docsReadmePanelCapabilityEntryIndex] = $docsReadmeGovernanceCapabilityEntryLineText
    $driftedDocsReadmeLines[$docsReadmeGovernanceCapabilityEntryIndex] = $docsReadmePanelCapabilityEntryLineText
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

$maintenanceMatrixPath = Join-Path $repoRootPath 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
$originalMaintenanceMatrixBytes = [System.IO.File]::ReadAllBytes($maintenanceMatrixPath)
$maintenanceMatrixSyncSlotLineText = '- `收口要求`：完成同步后，确认 `03-面板入口验收.md` 与 `13-维护层总入口.md` 口径一致，并通过公开提交治理门禁。'
$maintenanceMatrixDecisionOrderLineText = '- `结束条件`：只有通过收口检查，才算本轮维护层动作结束。'
$maintenanceMatrixBasicCloseoutLineText = '- `下一步说明`：已经给出下一步建议，并说明是否需要主公拍板。'
$maintenanceMatrixGovernanceAuditLineText = '- `边界复核`：已经复核公开仓边界，确保 `.codex/`、`logs/`、`temp/generated/`、`.vscode/`、`.serena/` 等运行态与本地工具状态不进入公开仓。'
$maintenanceMatrixPublicBoundaryLineText = '- `本地运行态`：`.codex/chancellor/tasks/`、`.codex/chancellor/active-task.txt`、`logs/` 继续作为本地运行态与留痕区，不进入公开仓。'
$maintenanceMatrixPairingLineText = '- `公开口径变更前`：追加一次 `08-V4-治理审计候选规范.md` 对应的治理审计复核。'
$maintenanceMatrixValueLineText = '- `保留控制平面`：为后续更强自动化保留稳定的人类控制平面。'
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
$codexHomeExportManifestIncludedTarget = 'verify-cutover.ps1'

if ($codexHomeExportManifestInfo.included -notcontains $codexHomeExportManifestIncludedTarget) {
    throw "测试前置条件不满足：$codexHomeExportManifestPath 中缺少 $codexHomeExportManifestIncludedTarget"
}

if ([string]::IsNullOrWhiteSpace($codexHomeExportStageLineText)) {
    throw "测试前置条件不满足：$codexHomeExportReadmePath 中缺少 stage 行。"
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

$agentsPanelCommandLineText = '| `丞相验板` | 给出进入官方面板人工验收的固定步骤 |'
$panelHelpUsageLineText = '- `丞相帮助`：显示当前用法、命令与注意事项。'
$panelHelpTemplateLineText = '- `注意事项`：最后提示维护层动作、安全边界与人工验板提醒。'
$panelHelpUsageItemLineText = '- `维护层说明`：如必须落到脚本层，要明确说明“这是维护层动作”。'
$panelHelpPanelCommandItemLineText = '- `公开边界`：普通用户只暴露面板命令，不主动推荐终端丞相别名。'
$panelHelpNoticeItemLineText = '- `新开会话验板提醒`：入口相关改动后，建议新开官方面板会话做人眼验板。'
$panelVersionCommandSlotLineText = '- `真源路径`：优先说明当前版本真源路径为 `codex-home-export/VERSION.json`。'
$panelCheckCommandSlotLineText = '- `建议动作`：如发现问题，给出下一步建议或引导到修复 / 验板。'
$panelStatusCommandSlotLineText = '- `稳态判断`：明确当前是否稳态。'
$panelRepairCommandSlotLineText = '- `升级条件`：超出安全边界或无法自动修复时停止扩展并提示人工处理。'
$panelAcceptanceCommandSlotLineText = '- `验板目标`：确认版本、模式与入口表现是否稳态。'
$panelAcceptanceStepItemLineText = '- `任务一致性`：若本地存在激活任务，检查回复口径是否与当前任务状态一致。'
$panelPassCriterionItemLineText = '- `复验闭环`：入口相关改动后，可通过新开会话与首句验板完成复验。'
$panelFailSignalItemLineText = '- `复验失败`：重新执行必要同步动作后，仍无法通过新开会话与首句验板完成复验。'
$panelRecoveryItemLineText = '- `缺陷收口`：若仍失败，记录为入口缺陷，不带着问题进入真实任务试跑。'
$panelTrialGateItemLineText = '- `公开边界`：本文档可进入公开仓；真实运行态与日志继续只留本地。'
$panelRepairBoundaryLineText = '- `丞相修复`：在安全边界内尝试自动修复常见问题。'
$checklistHelpUsageLineText = '- `丞相帮助`：显示当前用法、命令与注意事项。'
$checklistHelpTemplateLineText = '- `注意事项`：最后提示维护层动作、安全边界与人工验板提醒。'
$checklistHelpUsageItemLineText = '- `维护层说明`：如必须落到脚本层，要明确说明“这是维护层动作”。'
$checklistHelpPanelCommandItemLineText = '- `公开边界`：普通用户只暴露面板命令，不主动推荐终端丞相别名。'
$checklistHelpNoticeItemLineText = '- `新开会话验板提醒`：入口相关改动后，建议新开官方面板会话做人眼验板。'
$checklistVersionCommandSlotLineText = '- `真源路径`：优先说明当前版本真源路径为 `codex-home-export/VERSION.json`。'
$checklistCheckCommandSlotLineText = '- `建议动作`：如发现问题，给出下一步建议或引导到修复 / 验板。'
$checklistStatusCommandSlotLineText = '- `稳态判断`：明确当前是否稳态。'
$checklistRepairCommandSlotLineText = '- `升级条件`：超出安全边界或无法自动修复时停止扩展并提示人工处理。'
$checklistAcceptanceCommandSlotLineText = '- `验板目标`：确认版本、模式与入口表现是否稳态。'
$checklistStepItemLineText = '- `状态验证`：如需再验一层，继续输入：`丞相状态`'
$checklistPassCriterionItemLineText = '- `无需手改`：整个过程无需再手改本地文件。'
$checklistRecoveryItemLineText = '- `重新验板`：回退后重新打开面板，再次验板。'
$checklistAcceptanceBoundaryLineText = '- `丞相验板`：给出进入官方面板人工验收的固定步骤。'
$codexHomeExportPanelChecklistPath = Join-Path $repoRootPath 'codex-home-export/panel-acceptance-checklist.md'
$panelAcceptanceDocPath = Join-Path $repoRootPath 'docs/40-执行/03-面板入口验收.md'
$originalAgentsPanelBytes = [System.IO.File]::ReadAllBytes($agentsPath)
$originalCodexHomeExportPanelChecklistBytes = [System.IO.File]::ReadAllBytes($codexHomeExportPanelChecklistPath)
$originalPanelAcceptanceDocBytes = [System.IO.File]::ReadAllBytes($panelAcceptanceDocPath)

if ($agentsLines -notcontains $agentsPanelCommandLineText) {
    throw "测试前置条件不满足：$agentsPath 中缺少 $agentsPanelCommandLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelHelpUsageLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelHelpUsageLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelHelpTemplateLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelHelpTemplateLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelHelpUsageItemLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelHelpUsageItemLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelHelpPanelCommandItemLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelHelpPanelCommandItemLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelHelpNoticeItemLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelHelpNoticeItemLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelVersionCommandSlotLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelVersionCommandSlotLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelCheckCommandSlotLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelCheckCommandSlotLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelStatusCommandSlotLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelStatusCommandSlotLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelRepairCommandSlotLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelRepairCommandSlotLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelAcceptanceCommandSlotLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelAcceptanceCommandSlotLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelAcceptanceStepItemLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelAcceptanceStepItemLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelPassCriterionItemLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelPassCriterionItemLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelFailSignalItemLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelFailSignalItemLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelRecoveryItemLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelRecoveryItemLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelTrialGateItemLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelTrialGateItemLineText"
}

if ((Get-Content $panelAcceptanceDocPath) -notcontains $panelRepairBoundaryLineText) {
    throw "测试前置条件不满足：$panelAcceptanceDocPath 中缺少 $panelRepairBoundaryLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistHelpUsageLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistHelpUsageLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistHelpTemplateLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistHelpTemplateLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistHelpUsageItemLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistHelpUsageItemLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistHelpPanelCommandItemLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistHelpPanelCommandItemLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistHelpNoticeItemLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistHelpNoticeItemLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistVersionCommandSlotLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistVersionCommandSlotLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistCheckCommandSlotLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistCheckCommandSlotLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistStatusCommandSlotLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistStatusCommandSlotLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistRepairCommandSlotLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistRepairCommandSlotLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistAcceptanceCommandSlotLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistAcceptanceCommandSlotLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistStepItemLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistStepItemLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistPassCriterionItemLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistPassCriterionItemLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistRecoveryItemLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistRecoveryItemLineText"
}

if ((Get-Content $codexHomeExportPanelChecklistPath) -notcontains $checklistAcceptanceBoundaryLineText) {
    throw "测试前置条件不满足：$codexHomeExportPanelChecklistPath 中缺少 $checklistAcceptanceBoundaryLineText"
}

try {
    $driftedVersionInfo = Get-Content $codexHomeExportVersionPath -Raw | ConvertFrom-Json
    $driftedVersionInfo.panel_commands = @(
        $driftedVersionInfo.panel_commands | Where-Object { $_ -ne '丞相修复' }
    )
    $driftedVersionContent = ($driftedVersionInfo | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($codexHomeExportVersionPath, $driftedVersionContent + [Environment]::NewLine, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/VERSION.json') -ExpectedExitCode 1 -TestName 'block-panel-commands-version-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportVersionPath, $originalCodexHomeExportVersionBytes)
}

try {
    $driftedAgentsContent = (Get-Content $agentsPath -Raw).Replace($agentsPanelCommandLineText, '| `丞相回板` | 给出进入官方面板人工验收的固定步骤 |')
    [System.IO.File]::WriteAllText($agentsPath, $driftedAgentsContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('AGENTS.md') -ExpectedExitCode 1 -TestName 'block-panel-commands-agents-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($agentsPath, $originalAgentsPanelBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace('丞相状态', '丞相帮助')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-commands-checklist-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelHelpUsageLineText, '- `丞相帮助`：显示帮助。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-help-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelHelpTemplateLineText, '- `注意事项`：最后提示一些提醒。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-help-template-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelHelpUsageItemLineText, '- `维护层说明`：按情况决定是否说明。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-help-usage-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelHelpPanelCommandItemLineText, '- `公开边界`：必要时也可以推荐终端别名。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-help-panel-command-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelHelpNoticeItemLineText, '- `新开会话验板提醒`：最后再看看情况。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-help-notice-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelVersionCommandSlotLineText, '- `真源路径`：看情况再决定是否说明。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-version-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelCheckCommandSlotLineText, '- `建议动作`：发现问题再说。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-check-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelStatusCommandSlotLineText, '- `稳态判断`：大概看起来还行。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-status-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelRepairCommandSlotLineText, '- `升级条件`：遇到复杂情况再说。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-repair-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelAcceptanceCommandSlotLineText, '- `验板目标`：大概确认一下即可。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-panel-acceptance-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelAcceptanceStepItemLineText, '- `任务一致性`：最后再看看是否一致。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-step-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelPassCriterionItemLineText, '- `复验闭环`：入口改完后再看看情况。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-pass-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelFailSignalItemLineText, '- `复验失败`：再试试看。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-fail-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelRecoveryItemLineText, '- `缺陷收口`：先放一放再说。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-recovery-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelTrialGateItemLineText, '- `公开边界`：看情况决定是否公开。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-trial-gate-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace($panelRepairBoundaryLineText, '- `丞相修复`：尝试自动修复问题。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-boundary-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedPanelAcceptanceDocContent = (Get-Content $panelAcceptanceDocPath -Raw).Replace('`丞相版本`：返回当前丞相模式版本与版本来源。', '`丞相版本`：返回当前版本号。')
    [System.IO.File]::WriteAllText($panelAcceptanceDocPath, $driftedPanelAcceptanceDocContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/40-执行/03-面板入口验收.md') -ExpectedExitCode 1 -TestName 'block-panel-acceptance-doc-response-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($panelAcceptanceDocPath, $originalPanelAcceptanceDocBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistHelpUsageLineText, '- `丞相帮助`：显示帮助。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-help-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistHelpTemplateLineText, '- `注意事项`：最后提示一些提醒。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-help-template-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistHelpUsageItemLineText, '- `维护层说明`：按情况决定是否说明。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-help-usage-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistHelpPanelCommandItemLineText, '- `公开边界`：必要时也可以推荐终端别名。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-help-panel-command-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistHelpNoticeItemLineText, '- `新开会话验板提醒`：最后再看看情况。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-help-notice-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistVersionCommandSlotLineText, '- `真源路径`：看情况再决定是否说明。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-version-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistCheckCommandSlotLineText, '- `建议动作`：发现问题再说。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-check-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistStatusCommandSlotLineText, '- `稳态判断`：大概看起来还行。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-status-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistRepairCommandSlotLineText, '- `升级条件`：遇到复杂情况再说。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-repair-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistAcceptanceCommandSlotLineText, '- `验板目标`：大概确认一下即可。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-panel-acceptance-slot-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistStepItemLineText, '- `状态验证`：最后再看看情况。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-step-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistPassCriterionItemLineText, '- `无需手改`：必要时手动补一下。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-pass-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistRecoveryItemLineText, '- `重新验板`：先等等再说。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-recovery-item-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace($checklistAcceptanceBoundaryLineText, '- `丞相验板`：提供一个大概步骤。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-boundary-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

try {
    $driftedChecklistContent = (Get-Content $codexHomeExportPanelChecklistPath -Raw).Replace('`丞相检查` 能做最小必要检查并返回人话结论。', '`丞相检查` 能返回检查结果。')
    [System.IO.File]::WriteAllText($codexHomeExportPanelChecklistPath, $driftedChecklistContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('codex-home-export/panel-acceptance-checklist.md') -ExpectedExitCode 1 -TestName 'block-panel-checklist-response-drift'
}
finally {
    [System.IO.File]::WriteAllBytes($codexHomeExportPanelChecklistPath, $originalCodexHomeExportPanelChecklistBytes)
}

Write-Host 'PASS: test-public-commit-governance-gate.ps1'
