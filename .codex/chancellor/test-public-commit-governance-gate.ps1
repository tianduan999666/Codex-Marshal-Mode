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

$navOverviewPath = Join-Path $repoRootPath 'docs/00-导航/02-现行标准件总览.md'
$originalNavOverviewBytes = [System.IO.File]::ReadAllBytes($navOverviewPath)
$navOverviewLines = Get-Content $navOverviewPath
$removedReadingOrderTargetLineText = '14. 需要看 Target 目标态时，看 `docs/30-方案/04-V4-Target-蓝图.md`'

if ($navOverviewLines -notcontains $removedReadingOrderTargetLineText) {
    throw "测试前置条件不满足：$navOverviewPath 中缺少 $removedReadingOrderTargetLineText"
}

try {
    $driftedNavOverviewLines = @(
        $navOverviewLines | Where-Object { $_ -ne $removedReadingOrderTargetLineText }
    )
    $driftedNavOverviewContent = ($driftedNavOverviewLines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($navOverviewPath, $driftedNavOverviewContent, $utf8NoBom)

    Invoke-GateForTestCase -Paths @('docs/00-导航/02-现行标准件总览.md') -ExpectedExitCode 1 -TestName 'block-reading-order-target-missing'
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

Write-Host 'PASS: test-public-commit-governance-gate.ps1'
