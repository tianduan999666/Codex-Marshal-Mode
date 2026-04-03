param()

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$renderScriptPath = Join-Path $scriptRootPath 'render-panel-response.ps1'
$versionPath = Join-Path $scriptRootPath 'VERSION.json'
$versionInfo = Get-Content -Raw -Encoding UTF8 -Path $versionPath | ConvertFrom-Json

function Assert-PanelResponseEqual([string]$Actual, [string]$Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw ('{0}；期望：{1}；实际：{2}' -f $Message, $Expected, $Actual)
    }
}

function Assert-PanelResponseLineCount([string[]]$ActualLines, [int]$ExpectedCount, [string]$Message) {
    if (@($ActualLines).Count -ne $ExpectedCount) {
        throw ('{0}；期望行数：{1}；实际行数：{2}' -f $Message, $ExpectedCount, @($ActualLines).Count)
    }
}

if (-not (Test-Path $renderScriptPath)) {
    throw "缺少渲染脚本：$renderScriptPath"
}

$hintLines = @(& $renderScriptPath -Kind 'hint' -VersionPath $versionPath)
Assert-PanelResponseLineCount -ActualLines $hintLines -ExpectedCount 1 -Message 'hint 应只返回 1 行'
Assert-PanelResponseEqual -Actual $hintLines[0] -Expected $versionInfo.new_chat_hint -Message 'hint 应返回真源示例句'

$taskEntryLines = @(& $renderScriptPath -Kind 'task-entry' -VersionPath $versionPath)
Assert-PanelResponseLineCount -ActualLines $taskEntryLines -ExpectedCount 2 -Message 'task-entry 应返回 2 行固定骨架'
Assert-PanelResponseEqual -Actual $taskEntryLines[0] -Expected $versionInfo.opening_line -Message 'task-entry 第 1 行应返回真源开场白'
Assert-PanelResponseEqual -Actual $taskEntryLines[1] -Expected $versionInfo.boundary_prompt -Message 'task-entry 第 2 行应返回真源边界提示'

$analysisQuote = @(& $renderScriptPath -Kind 'process-quote' -Phase 'analysis' -VersionPath $versionPath)
Assert-PanelResponseLineCount -ActualLines $analysisQuote -ExpectedCount 1 -Message 'process-quote 应只返回 1 行'
Assert-PanelResponseEqual -Actual $analysisQuote[0] -Expected $versionInfo.process_quotes_minimal.analysis -Message 'analysis 过程金句应来自真源'

$versionLines = @(& $renderScriptPath -Kind 'version' -VersionPath $versionPath)
Assert-PanelResponseLineCount -ActualLines $versionLines -ExpectedCount 3 -Message 'version 应返回 3 行固定槽位'
Assert-PanelResponseEqual -Actual $versionLines[0] -Expected ('版本号：{0}' -f $versionInfo.cx_version) -Message 'version 第 1 行应返回当前版本'
Assert-PanelResponseEqual -Actual $versionLines[1] -Expected ('版本来源：{0}' -f $versionInfo.source_of_truth) -Message 'version 第 2 行应返回版本来源'
Assert-PanelResponseEqual -Actual $versionLines[2] -Expected '真源路径：codex-home-export/VERSION.json' -Message 'version 第 3 行应返回真源路径'

$upgradeLines = @(& $renderScriptPath -Kind 'upgrade' -VersionPath $versionPath)
Assert-PanelResponseLineCount -ActualLines $upgradeLines -ExpectedCount 3 -Message 'upgrade 应返回 3 行固定槽位'
Assert-PanelResponseEqual -Actual $upgradeLines[0] -Expected '触发方式：只在用户主动输入 `传令：升级` 时触发' -Message 'upgrade 第 1 行应返回触发方式'
Assert-PanelResponseEqual -Actual $upgradeLines[2] -Expected '默认策略：未收到明确升级传令时，不自动升级' -Message 'upgrade 第 3 行应返回默认策略'

$statusLines = @(& $renderScriptPath -Kind 'status' -VersionPath $versionPath -CxVersion 'VX' -LastCheck 'LC' -AutoRepair 'AR' -KeyFileConsistency 'KC' -CurrentMode 'CM' -CurrentTask 'CT')
Assert-PanelResponseLineCount -ActualLines $statusLines -ExpectedCount 6 -Message 'status 应返回 6 行固定状态栏'
$expectedStatusLines = @(
    '版本：VX'
    '上次检查：LC'
    '自动修复：AR'
    '关键文件一致性：KC'
    '当前模式：CM'
    '当前任务：CT'
)
for ($index = 0; $index -lt $expectedStatusLines.Count; $index++) {
    Assert-PanelResponseEqual -Actual $statusLines[$index] -Expected $expectedStatusLines[$index] -Message ('status 第 {0} 行顺序或内容不对' -f ($index + 1))
}

$closeoutLines = @(& $renderScriptPath -Kind 'closeout' -VersionPath $versionPath -CompletedText '已完成 A' -ResultText '结果 B' -NextStepText '下一步 C')
Assert-PanelResponseLineCount -ActualLines $closeoutLines -ExpectedCount 4 -Message 'closeout 应返回 4 行'
Assert-PanelResponseEqual -Actual $closeoutLines[0] -Expected $versionInfo.process_quotes_minimal.closeout -Message 'closeout 首行应返回真源收口金句'
Assert-PanelResponseEqual -Actual $closeoutLines[1] -Expected '已完成：已完成 A' -Message 'closeout 已完成段不对'
Assert-PanelResponseEqual -Actual $closeoutLines[2] -Expected '结果：结果 B' -Message 'closeout 结果段不对'
Assert-PanelResponseEqual -Actual $closeoutLines[3] -Expected '下一步：下一步 C' -Message 'closeout 下一步段不对'

Write-Host 'PASS: render-panel-response.test.ps1'
