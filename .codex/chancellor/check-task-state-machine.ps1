# 任务包状态机门禁检查
# 用途：验证任务包状态与修改文件的合法性
# 规则：
# - drafting 状态：只能修改任务包内文件，禁止修改任务包外代码文件
# - planning 状态：只能修改 tech-spec.md，禁止修改任务包外代码文件
# - running 状态：允许修改代码文件

param(
    [Parameter(Mandatory = $true)]
    [string]$TaskDir,

    [Parameter(Mandatory = $true)]
    [string[]]$ChangedFiles
)

$ErrorActionPreference = 'Stop'

$statePath = Join-Path $TaskDir 'state.yaml'
$contractPath = Join-Path $TaskDir 'contract.yaml'

function Throw-FriendlyStateMachineError {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string[]]$Issues = @(),
        [string[]]$NextSteps = @()
    )

    $messageLines = @($Summary)
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $messageLines += ("原因：{0}" -f $Detail)
    }

    if ($Issues.Count -gt 0) {
        $messageLines += ''
        $messageLines += '发现的问题：'
        foreach ($issue in $Issues) {
            $messageLines += ("- {0}" -f $issue)
        }
    }

    if ($NextSteps.Count -gt 0) {
        $messageLines += ''
        $messageLines += '下一步：'
        foreach ($nextStep in $NextSteps) {
            $messageLines += ("- {0}" -f $nextStep)
        }
    }

    throw ($messageLines -join [Environment]::NewLine)
}

if (-not (Test-Path $statePath)) {
    Throw-FriendlyStateMachineError `
        -Summary '任务包缺少 state.yaml，当前没法判断状态机规则。' `
        -Detail ("任务目录：{0}" -f $TaskDir) `
        -NextSteps @(
            '先补齐 state.yaml。',
            '补完后再重新跑状态机门禁。'
        )
}

if (-not (Test-Path $contractPath)) {
    Throw-FriendlyStateMachineError `
        -Summary '任务包缺少 contract.yaml，当前没法判断任务边界。' `
        -Detail ("任务目录：{0}" -f $TaskDir) `
        -NextSteps @(
            '先补齐 contract.yaml。',
            '补完后再重新跑状态机门禁。'
        )
}

# 解析任务状态
$stateContent = Get-Content $statePath -Raw
$currentStatus = 'unknown'

if ($stateContent -match 'status:\s*(\w+)') {
    $currentStatus = $matches[1]
}

# 解析任务 ID
$contractContent = Get-Content $contractPath -Raw
$taskId = 'unknown'

if ($contractContent -match 'task_id:\s*(.+)') {
    $taskId = $matches[1].Trim()
}

# 规范化任务包路径前缀
$taskDirNormalized = $TaskDir -replace '\\', '/'
$taskPackagePrefix = ".codex/chancellor/tasks/$taskId/"

# 检查修改的文件
$violations = @()

foreach ($file in $ChangedFiles) {
    $fileNormalized = $file -replace '\\', '/'

    # 判断是否为任务包内文件
    $isInsideTaskPackage = $fileNormalized.StartsWith($taskPackagePrefix)

    # 判断是否为代码文件（排除任务包内文件、文档、配置）
    $isCodeFile = $fileNormalized -match '\.(ps1|py|js|ts|tsx|jsx|go|rs|java|kt|swift|c|cpp|h|hpp)$' -and -not $isInsideTaskPackage

    # 状态机规则检查
    switch ($currentStatus) {
        'drafting' {
            if ($isCodeFile) {
                $violations += ("当前任务还在 drafting，先别改代码文件：{0}" -f $file)
            }
        }
        'planning' {
            if ($isCodeFile) {
                $violations += ("当前任务还在 planning，先别改代码文件：{0}" -f $file)
            }
            if ($isInsideTaskPackage -and $fileNormalized -notmatch 'tech-spec\.md$') {
                $violations += ("当前任务还在 planning，任务包内建议先只改 tech-spec.md：{0}" -f $file)
            }
        }
        'running' {
            # running 状态允许修改代码文件
        }
        default {
            Write-Warning "⚠️ 未知任务状态：$currentStatus"
        }
    }
}

# 输出结果
if ($violations.Count -gt 0) {
    Throw-FriendlyStateMachineError `
        -Summary '任务包状态机门禁没通过，本次改动先不要继续。' `
        -Detail ("任务 ID：{0}；当前状态：{1}" -f $taskId, $currentStatus) `
        -Issues $violations `
        -NextSteps @(
            'drafting 状态下，只改任务包内文件。',
            'planning 状态下，优先只改 tech-spec.md。',
            '要开始改代码前，先把任务状态切到 running。'
        )
}

Write-Host "✓ 任务包状态机门禁检查通过（状态：$currentStatus）" -ForegroundColor Green
