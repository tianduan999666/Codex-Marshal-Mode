param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [ValidateSet('failed', 'rolled_back', 'blocked')]
    [string]$ExceptionType = 'failed',
    [Parameter(Mandatory = $true)]
    [string]$Summary,
    [Parameter(Mandatory = $true)]
    [string]$RollbackScope,
    [Parameter(Mandatory = $true)]
    [string]$ResumeHint,
    [ValidateSet('paused', 'ready_to_resume', 'waiting_assist')]
    [string]$NextStatus = 'paused',
    [string]$NextAction = '按异常记录完成收口后再恢复推进'
)

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskDirectoryPath = Join-Path (Join-Path $scriptRootPath 'tasks') $TaskId
$timestampText = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$closeoutGuideRelativePath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
$recoveryGuideRelativePath = 'docs/40-执行/05-跨轮恢复说明.md'
$governanceGuideRelativePath = 'docs/30-方案/08-V4-治理审计候选规范.md'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlyRecordException {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string[]]$NextSteps = @()
    )

    Write-Host ''
    Write-Host "[ERROR] $Summary" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原因：{0}" -f $Detail)
    }

    foreach ($nextStep in $NextSteps) {
        Write-Info $nextStep
    }

    exit 1
}

if ($TaskId -notmatch '^v4-trial-\d{3}-.+$') {
    Stop-FriendlyRecordException `
        -Summary '任务包编号格式不对，当前没法记录异常路径。' `
        -Detail 'TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 格式。' `
        -NextSteps @(
            '先把任务编号改成例如 v4-trial-001-语义名。',
            '确认任务编号无误后再重新记录异常。'
        )
}

if (-not (Test-Path $taskDirectoryPath)) {
    Stop-FriendlyRecordException `
        -Summary '任务目录不存在，当前没法记录异常路径。' `
        -Detail ("任务目录不存在：{0}" -f $taskDirectoryPath) `
        -NextSteps @(
            '先确认 TaskId 是否写对了。',
            '确认对应任务包已经创建后再重新记录异常。'
        )
}
$stateFilePath = Join-Path $taskDirectoryPath 'state.yaml'
$resultFilePath = Join-Path $taskDirectoryPath 'result.md'
$decisionLogFilePath = Join-Path $taskDirectoryPath 'decision-log.md'

foreach ($requiredFilePath in @($stateFilePath, $resultFilePath, $decisionLogFilePath)) {
    if (-not (Test-Path $requiredFilePath)) {
        Stop-FriendlyRecordException `
            -Summary '任务包资料还没补齐，当前不能记录异常路径。' `
            -Detail ("缺少必需文件：{0}" -f $requiredFilePath) `
            -NextSteps @(
                '先补齐 state.yaml、result.md、decision-log.md。',
                '补齐后再重新记录异常。'
            )
    }
}

$stateYamlText = Get-Content -Raw $stateFilePath
$updatedStateYamlText = $stateYamlText
$updatedStateYamlText = [regex]::Replace($updatedStateYamlText, '(?m)^status:\s*.*$', "status: $NextStatus")
$updatedStateYamlText = [regex]::Replace($updatedStateYamlText, '(?m)^next_action:\s*.*$', "next_action: $NextAction")
$updatedStateYamlText = [regex]::Replace($updatedStateYamlText, "(?m)^updated_at:\s*'.*'$", "updated_at: '$timestampText'")
Set-Content -Path $stateFilePath -Value $updatedStateYamlText -Encoding UTF8

$decisionLogAppendText = @"

## $timestampText

- 决策：记录异常路径 $ExceptionType
- 原因：$Summary
- 回退范围：$RollbackScope
- 恢复提示：$ResumeHint
- 影响：任务状态切换为 $NextStatus，下一步为 $NextAction
- 治理提示：异常收口与提交前，应确认异常原因、恢复提示与公开边界已完成治理审计复核
"@
Add-Content -Path $decisionLogFilePath -Value $decisionLogAppendText -Encoding UTF8
$resultAppendText = @"

## 异常路径记录（$ExceptionType）

- 摘要：$Summary
- 回退范围：$RollbackScope
- 恢复提示：$ResumeHint
- 当前状态：$NextStatus
- 下一步：$NextAction
- 治理复核：$governanceGuideRelativePath
- 恢复参考：$recoveryGuideRelativePath
- 收口参考：$closeoutGuideRelativePath

## 治理复核（$ExceptionType）

- 当前异常原因来源是否已说明：待补说明
- 当前恢复提示是否可追溯：待补说明
- 当前是否发现口径漂移：待复核
- 提交前是否已完成治理审计复核：待确认
"@
Add-Content -Path $resultFilePath -Value $resultAppendText -Encoding UTF8

Write-Info ("异常路径已记录：{0}" -f $taskDirectoryPath)
Write-Info ("异常类型：{0}" -f $ExceptionType)
Write-Info ("当前状态：{0}" -f $NextStatus)
Write-Info ("恢复参考：{0}" -f $recoveryGuideRelativePath)
Write-Info ("收口参考：{0}" -f $closeoutGuideRelativePath)
