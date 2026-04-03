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

if (-not (Test-Path $statePath)) {
    throw "❌ 任务包缺少 state.yaml：$TaskDir"
}

if (-not (Test-Path $contractPath)) {
    throw "❌ 任务包缺少 contract.yaml：$TaskDir"
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
                $violations += "❌ drafting 状态禁止修改代码文件：$file"
            }
        }
        'planning' {
            if ($isCodeFile) {
                $violations += "❌ planning 状态禁止修改代码文件：$file"
            }
            if ($isInsideTaskPackage -and $fileNormalized -notmatch 'tech-spec\.md$') {
                $violations += "⚠️ planning 状态建议只修改 tech-spec.md，当前修改：$file"
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
    Write-Host "任务包状态机门禁检查失败：" -ForegroundColor Red
    Write-Host "任务 ID：$taskId" -ForegroundColor Yellow
    Write-Host "当前状态：$currentStatus" -ForegroundColor Yellow
    Write-Host ""
    foreach ($violation in $violations) {
        Write-Host $violation -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "状态机规则：" -ForegroundColor Cyan
    Write-Host "  - drafting 状态：只能修改任务包内文件" -ForegroundColor Cyan
    Write-Host "  - planning 状态：只能修改 tech-spec.md" -ForegroundColor Cyan
    Write-Host "  - running 状态：允许修改代码文件" -ForegroundColor Cyan
    throw "状态机门禁未通过"
}

Write-Host "✓ 任务包状态机门禁检查通过（状态：$currentStatus）" -ForegroundColor Green
