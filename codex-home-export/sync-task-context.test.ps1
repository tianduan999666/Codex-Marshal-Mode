param()

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$syncScriptPath = Join-Path $scriptRootPath 'sync-task-context.ps1'

function Assert-TextContains([string]$Actual, [string]$Expected, [string]$Message) {
    if (($null -eq $Actual) -or (-not $Actual.Contains($Expected))) {
        throw ('{0}；期望包含：{1}；实际：{2}' -f $Message, $Expected, $Actual)
    }
}

function Assert-ExitCode([int]$Actual, [int]$Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw ('{0}；期望退出码：{1}；实际退出码：{2}' -f $Message, $Expected, $Actual)
    }
}

function Assert-LineEqual([string[]]$Lines, [int]$Index, [string]$Expected, [string]$Message) {
    if ($Lines[$Index] -ne $Expected) {
        throw ('{0}；期望：{1}；实际：{2}' -f $Message, $Expected, $Lines[$Index])
    }
}

function Invoke-SyncTaskContextExternal([hashtable]$Arguments) {
    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $syncScriptPath)
    foreach ($key in $Arguments.Keys) {
        $argumentList += ('-{0}' -f $key)
        $argumentList += [string]$Arguments[$key]
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

function New-TestTaskRuntime {
    param(
        [string]$RepoRootPath,
        [string]$TargetCodexHome,
        [string]$TaskId,
        [string]$TaskTitle
    )

    $taskRootPath = Join-Path $RepoRootPath ('.codex\chancellor\tasks\' + $TaskId)
    $taskMetaRootPath = Join-Path $TargetCodexHome 'config\chancellor-mode'
    New-Item -ItemType Directory -Force -Path $taskRootPath | Out-Null
    New-Item -ItemType Directory -Force -Path $taskMetaRootPath | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $TargetCodexHome 'config') | Out-Null

    Set-Content -Path (Join-Path $RepoRootPath '.codex\chancellor\active-task.txt') -Value $TaskId -Encoding UTF8
    Set-Content -Path (Join-Path $taskRootPath 'contract.yaml') -Value @(
        ('task_id: {0}' -f $TaskId)
        ('title: {0}' -f $TaskTitle)
        'goal: >-'
        '  补齐交班与接班链路，确保跨聊天连续性可用。'
        'planning_hint: >-'
        '  先补任务快照，再补交班单。'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $taskRootPath 'state.yaml') -Value @(
        ('task_id: {0}' -f $TaskId)
        'status: running'
        'risk_level: medium'
        'next_action: 接通交班与接班命令'
        'blocked_by: []'
        "updated_at: '2026-04-05 18:20:00'"
        'phase_hint: panel-entry'
        'plan_step: 先补测试，再落实现'
        'verify_signal: 交班与接班命令可直接续上当前任务'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $taskRootPath 'decision-log.md') -Value @(
        '# 决策记录'
        ''
        '## 2026-04-05 18:22:00'
        ''
        '- 决策：把交班材料落到当前任务目录'
        '- 原因：避免新建平行状态目录'
        '- 影响：接班时只需读 active-task.txt 与 handoff.md'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $taskRootPath 'gates.yaml') -Value @(
        ('task_id: {0}' -f $TaskId)
        'items: []'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $taskRootPath 'result.md') -Value @(
        '# 结果摘要'
        ''
        '## 已完成'
        ''
        '- 已梳理交班与接班需求'
        '- 已确认任务快照应挂在当前任务目录'
        ''
        '## 验证证据'
        ''
        '- 任务包文件齐全'
        ''
        '## 遗留事项'
        ''
        '- 还未落地公开命令'
        ''
        '## 下一步建议'
        ''
        '- 先补测试，再实现脚本'
        '- 完成后重跑自检与验板'
    ) -Encoding UTF8
    Set-Content -Path (Join-Path $TargetCodexHome 'config\cx-version.json') -Value @'
{
  "cx_version": "CX-TEST-LOCAL"
}
'@ -Encoding UTF8
    Set-Content -Path (Join-Path $taskMetaRootPath 'task-start-state.json') -Value @'
{
  "verified_at": "2026-04-05 18:30:00",
  "verify_status": "passed",
  "repair_used": false
}
'@ -Encoding UTF8

    return $taskRootPath
}

if (-not (Test-Path $syncScriptPath)) {
    throw "缺少任务上下文同步脚本：$syncScriptPath"
}

$testRootPath = Join-Path $env:TEMP ('cx-sync-task-context-' + [guid]::NewGuid().ToString('N'))
try {
    $repoRootPath = Join-Path $testRootPath 'repo'
    $targetCodexHome = Join-Path $testRootPath 'home'
    $taskId = 'v4-target-001-panel-handoff'
    $taskTitle = '补齐交班接班主链'
    $taskRootPath = New-TestTaskRuntime -RepoRootPath $repoRootPath -TargetCodexHome $targetCodexHome -TaskId $taskId -TaskTitle $taskTitle

    $writeLines = @(
        & $syncScriptPath `
            -Mode write `
            -RepoRootPath $repoRootPath `
            -TargetCodexHome $targetCodexHome `
            -BackgroundSummary '本轮围绕跨聊天连续性补主链。' `
            -OverallGoal '补齐交班、接班和任务快照。' `
            -RecommendedApproach '先让交班写文件，再让接班读文件，最后把快照自动刷新接到开工与续做。' `
            -NextStepText '新聊天输入传令：接班，继续补高频复用件。' `
            -ImportantNotes @('对外统一称业务项目。', '交班材料只落当前任务目录。')
    )
    $progressSnapshotPath = Join-Path $taskRootPath 'progress-snapshot.md'
    $handoffPath = Join-Path $taskRootPath 'handoff.md'
    if (-not (Test-Path $progressSnapshotPath)) {
        throw "交班后未生成任务快照：$progressSnapshotPath"
    }
    if (-not (Test-Path $handoffPath)) {
        throw "交班后未生成交班文件：$handoffPath"
    }

    $progressSnapshotContent = Get-Content -Raw -Encoding UTF8 -Path $progressSnapshotPath
    $handoffContent = Get-Content -Raw -Encoding UTF8 -Path $handoffPath
    Assert-TextContains -Actual $progressSnapshotContent -Expected '# 任务级进度快照' -Message '任务快照应写入固定标题'
    Assert-TextContains -Actual $progressSnapshotContent -Expected '当前状态：running' -Message '任务快照应落盘当前状态'
    Assert-TextContains -Actual $progressSnapshotContent -Expected '接通交班与接班命令' -Message '任务快照应落盘下一步'
    Assert-TextContains -Actual $handoffContent -Expected '# 交班单' -Message '交班文件应写入固定标题'
    Assert-TextContains -Actual $handoffContent -Expected '本轮围绕跨聊天连续性补主链。' -Message '交班文件应落盘背景摘要'
    Assert-TextContains -Actual $handoffContent -Expected '新聊天输入传令：接班，继续补高频复用件。' -Message '交班文件应落盘下一步'

    Assert-LineEqual -Lines $writeLines -Index 0 -Expected '已完成：已为当前任务生成交班材料。' -Message 'write 模式第 1 行应说明已生成交班材料'
    Assert-LineEqual -Lines $writeLines -Index 1 -Expected ('任务编号：{0}（{1}）' -f $taskId, $taskTitle) -Message 'write 模式第 2 行应返回任务显示名'

    $readLines = @(
        & $syncScriptPath `
            -Mode read `
            -RepoRootPath $repoRootPath `
            -TargetCodexHome $targetCodexHome
    )
    Assert-LineEqual -Lines $readLines -Index 0 -Expected ('当前任务：{0}（{1}）' -f $taskId, $taskTitle) -Message 'read 模式第 1 行应返回当前任务'
    Assert-LineEqual -Lines $readLines -Index 2 -Expected '背景：本轮围绕跨聊天连续性补主链。' -Message 'read 模式应读取交班背景'
    Assert-LineEqual -Lines $readLines -Index 5 -Expected '下一步：新聊天输入传令：接班，继续补高频复用件。' -Message 'read 模式应返回交班下一步'

    Remove-Item -LiteralPath $handoffPath -Force
    $fallbackLines = @(
        & $syncScriptPath `
            -Mode read `
            -RepoRootPath $repoRootPath `
            -TargetCodexHome $targetCodexHome
    )
    Assert-LineEqual -Lines $fallbackLines -Index 1 -Expected '交班文件：未找到 handoff.md，已按当前任务包临时重建接班摘要。' -Message 'read 模式应在缺少 handoff.md 时明确走回退摘要'
    Assert-LineEqual -Lines $fallbackLines -Index 5 -Expected '下一步：接通交班与接班命令' -Message 'read 模式回退时应返回 state.yaml 的下一步'
}
finally {
    if (Test-Path $testRootPath) {
        Remove-Item -Recurse -Force -LiteralPath $testRootPath
    }
}

$missingActiveTaskRoot = Join-Path $env:TEMP ('cx-sync-task-context-missing-active-' + [guid]::NewGuid().ToString('N'))
try {
    $missingActiveTaskResult = Invoke-SyncTaskContextExternal -Arguments @{
        Mode = 'snapshot'
        RepoRootPath = $missingActiveTaskRoot
        TargetCodexHome = (Join-Path $missingActiveTaskRoot 'home')
    }
    Assert-ExitCode -Actual $missingActiveTaskResult.ExitCode -Expected 1 -Message '无激活任务时 sync-task-context 应失败'
    Assert-TextContains -Actual $missingActiveTaskResult.Text -Expected '当前没有激活任务，不能同步任务上下文。' -Message '无激活任务时应返回明确人话'
}
finally {
    if (Test-Path $missingActiveTaskRoot) {
        Remove-Item -Recurse -Force -LiteralPath $missingActiveTaskRoot
    }
}

$missingRequiredFileRoot = Join-Path $env:TEMP ('cx-sync-task-context-missing-file-' + [guid]::NewGuid().ToString('N'))
try {
    $repoRootPath = Join-Path $missingRequiredFileRoot 'repo'
    $targetCodexHome = Join-Path $missingRequiredFileRoot 'home'
    $taskId = 'v4-target-002-missing-result'
    $taskRootPath = New-TestTaskRuntime -RepoRootPath $repoRootPath -TargetCodexHome $targetCodexHome -TaskId $taskId -TaskTitle '缺件失败分流'
    Remove-Item -LiteralPath (Join-Path $taskRootPath 'result.md') -Force

    $missingRequiredFileResult = Invoke-SyncTaskContextExternal -Arguments @{
        Mode = 'write'
        RepoRootPath = $repoRootPath
        TargetCodexHome = $targetCodexHome
    }
    Assert-ExitCode -Actual $missingRequiredFileResult.ExitCode -Expected 1 -Message '任务包缺件时 sync-task-context 应失败'
    Assert-TextContains -Actual $missingRequiredFileResult.Text -Expected '任务上下文缺少必要文件' -Message '任务包缺件时应说明缺少必要文件'
    Assert-TextContains -Actual $missingRequiredFileResult.Text -Expected 'result.md' -Message '任务包缺件时应指出具体缺失文件'
}
finally {
    if (Test-Path $missingRequiredFileRoot) {
        Remove-Item -Recurse -Force -LiteralPath $missingRequiredFileRoot
    }
}

Write-Host 'PASS: sync-task-context.test.ps1'
