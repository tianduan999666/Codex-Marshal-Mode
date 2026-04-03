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

# 检查是否需要 tech-spec.md
if (-not (Test-Path $contractPath)) {
    throw "❌ 任务包缺少 contract.yaml：$TaskDir"
}

$contractContent = Get-Content $contractPath -Raw
$planningRequired = $false

# 解析 planning_required 字段
if ($contractContent -match 'planning_required:\s*(true|false)') {
    $planningRequired = $matches[1] -eq 'true'
}

# 如果不需要技术方案，跳过检查
if (-not $planningRequired) {
    Write-Host "✓ 任务包不需要 tech-spec.md，跳过检查"
    exit 0
}

# 检查 tech-spec.md 是否存在
if (-not (Test-Path $techSpecPath)) {
    throw "❌ 复杂任务缺少 tech-spec.md：$TaskDir"
}

$content = Get-Content $techSpecPath -Raw

# 检查 Markdown 表格（改动文件清单）
$hasTable = $content | Select-String -Pattern '^\|.*\|.*\|' -Quiet
if (-not $hasTable) {
    throw "❌ tech-spec.md 缺少 Markdown 表格（改动文件清单）"
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
        throw "❌ tech-spec.md 缺少必需章节：$section"
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
            # 检查是否有代码文件修改
            $changedFiles = @(git diff --name-only 2>$null)
            $codeFiles = $changedFiles | Where-Object {
                $_ -match '\.(ts|js|py|go|rs|java|cs|cpp|c|h|tsx|jsx)$'
            }

            if ($codeFiles.Count -gt 0) {
                throw @"
❌ 状态机门禁拦截：当前任务状态为 $status，禁止修改代码文件。

检测到以下代码文件被修改：
$($codeFiles -join "`n")

请先完成以下步骤：
1. 完成 tech-spec.md 技术方案文档
2. 将 planning_status 改为 'approved'
3. 将 status 改为 'running'

然后才能开始编写代码。
"@
            }
        }
    }
}

Write-Host "✓ tech-spec.md 门禁检查通过"
exit 0
