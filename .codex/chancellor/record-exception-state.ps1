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

if ($TaskId -notmatch '^v4-trial-\d{3}-.+$') {
    throw 'TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 格式。'
}

if (-not (Test-Path $taskDirectoryPath)) {
    throw "任务目录不存在：$taskDirectoryPath"
}
$stateFilePath = Join-Path $taskDirectoryPath 'state.yaml'
$resultFilePath = Join-Path $taskDirectoryPath 'result.md'
$decisionLogFilePath = Join-Path $taskDirectoryPath 'decision-log.md'

foreach ($requiredFilePath in @($stateFilePath, $resultFilePath, $decisionLogFilePath)) {
    if (-not (Test-Path $requiredFilePath)) {
        throw "缺少必需文件：$requiredFilePath"
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
"@
Add-Content -Path $decisionLogFilePath -Value $decisionLogAppendText -Encoding UTF8
$resultAppendText = @"

## 异常路径记录（$ExceptionType）

- 摘要：$Summary
- 回退范围：$RollbackScope
- 恢复提示：$ResumeHint
- 当前状态：$NextStatus
- 下一步：$NextAction
- 恢复参考：$recoveryGuideRelativePath
- 收口参考：$closeoutGuideRelativePath
"@
Add-Content -Path $resultFilePath -Value $resultAppendText -Encoding UTF8

Write-Output "异常路径已记录：$taskDirectoryPath"
Write-Output "异常类型：$ExceptionType"
Write-Output "当前状态：$NextStatus"
Write-Output "恢复参考：$recoveryGuideRelativePath"
Write-Output "收口参考：$closeoutGuideRelativePath"
