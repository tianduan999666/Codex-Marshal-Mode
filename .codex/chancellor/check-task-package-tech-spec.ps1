# 检查任务包 tech-spec.md 的门禁脚本
# 用途：验证 tech-spec.md 是否包含必需章节和格式

param(
    [Parameter(Mandatory = $true)]
    [string]$TaskDir
)

$ErrorActionPreference = 'Stop'

$techSpecPath = Join-Path $TaskDir 'tech-spec.md'
$contractPath = Join-Path $TaskDir 'contract.yaml'
$statePath = Join-Path $TaskDir 'state.yaml'

function Throw-FriendlyTechSpecError {
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

# 检查是否需要 tech-spec.md
if (-not (Test-Path $contractPath)) {
    Throw-FriendlyTechSpecError `
        -Summary '任务包缺少 contract.yaml，当前没法判断要不要 tech-spec.md。' `
        -Detail ("任务目录：{0}" -f $TaskDir) `
        -NextSteps @(
            '先补齐 contract.yaml。',
            '补完后再重新跑 tech-spec 门禁。'
        )
}

$contractContent = Get-Content $contractPath -Raw
$planningRequired = $false
$estimatedHours = 0

# 解析 planning_required 字段
if ($contractContent -match 'planning_required:\s*(true|false)') {
    $planningRequired = $matches[1] -eq 'true'
}

# 解析 estimated_hours 字段
if ($contractContent -match 'estimated_hours:\s*(\d+)') {
    $estimatedHours = [int]$matches[1]
}

# 自动判断：estimated_hours > 4 触发 planning_required
if ($estimatedHours -gt 4) {
    $planningRequired = $true
}

# 如果不需要技术方案，跳过检查
if (-not $planningRequired) {
    Write-Host "✓ 当前任务不需要 tech-spec.md，这一项已跳过" -ForegroundColor Green
    exit 0
}

# 检查 tech-spec.md 是否存在
if (-not (Test-Path $techSpecPath)) {
    Throw-FriendlyTechSpecError `
        -Summary '这是复杂任务，但 tech-spec.md 还没补齐。' `
        -Detail ("任务目录：{0}" -f $TaskDir) `
        -NextSteps @(
            '先补齐 tech-spec.md。',
            '至少写清改动文件清单、风险评估和验收标准。'
        )
}

$content = Get-Content $techSpecPath -Raw

# 检查 Markdown 表格（改动文件清单）
$hasTable = ($content -split "`n") | Where-Object { $_ -match '^\|.*\|.*\|' }
if (-not $hasTable) {
    Throw-FriendlyTechSpecError `
        -Summary 'tech-spec.md 里缺少改动文件清单表格。' `
        -NextSteps @(
            '先补一个 Markdown 表格。',
            '表格里至少写文件路径、改动类型、改动原因和风险等级。'
        )
}

# 检查 Mermaid 流程图（建议项，不强制）
$hasMermaid = $content | Select-String -Pattern '```mermaid' -Quiet
if (-not $hasMermaid) {
    Write-Warning "⚠️ tech-spec.md 建议包含 Mermaid 流程图"
}

# 检查必需章节
$requiredSections = @(
    '## 改动文件清单',
    '## 风险评估',
    '## 验收标准'
)

foreach ($section in $requiredSections) {
    if ($content -notmatch [regex]::Escape($section)) {
        Throw-FriendlyTechSpecError `
            -Summary 'tech-spec.md 还没写完整，当前不能过门禁。' `
            -Detail ("缺少必需章节：{0}" -f $section) `
            -NextSteps @(
                '先补齐缺少的章节。',
                '补完后再重新跑 tech-spec 门禁。'
            )
    }
}

# 检查 planning_status
if ($contractContent -match 'planning_status:\s*(\w+)') {
    $planningStatus = $matches[1]

    if ($planningStatus -eq 'pending') {
        Write-Warning "⚠️ tech-spec.md 存在但 planning_status 仍为 pending，请审批后改为 approved"
    }
}

# 检查状态机：drafting/planning 状态下禁止修改代码文件
if (Test-Path $statePath) {
    $stateContent = Get-Content $statePath -Raw

    if ($stateContent -match 'status:\s*(\w+)') {
        $status = $matches[1]

        if ($status -in @('drafting', 'planning')) {
            # 检查任务包目录外的代码文件修改
            $taskDirNormalized = $TaskDir -replace '\\', '/'
            $changedFiles = @(git diff --name-only 2>$null | Where-Object {
                $normalized = $_ -replace '\\', '/'
                -not $normalized.StartsWith($taskDirNormalized)
            })

            # 定义代码文件后缀（包含 PowerShell）
            $codeExtensions = @('.ts', '.js', '.py', '.go', '.rs', '.java', '.cs', '.cpp', '.c', '.h', '.tsx', '.jsx', '.ps1', '.psm1')
            $codeFiles = $changedFiles | Where-Object {
                $ext = [System.IO.Path]::GetExtension($_).ToLower()
                $ext -in $codeExtensions
            }

            if ($codeFiles.Count -gt 0) {
                Throw-FriendlyTechSpecError `
                    -Summary '当前任务还没进入 running，先不要改代码文件。' `
                    -Detail ("当前状态：{0}" -f $status) `
                    -Issues $codeFiles `
                    -NextSteps @(
                        '先把 tech-spec.md 写完整。',
                        '把 planning_status 改成 approved。',
                        '再把 status 改成 running，然后再开始写代码。'
                    )
            }
        }
    }
}

Write-Host "✓ tech-spec.md 门禁检查通过"
exit 0
