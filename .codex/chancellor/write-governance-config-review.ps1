param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,
    [string[]]$ConfigSources = @(),
    [string[]]$VersionReferences = @(),
    [string[]]$DriftChecks = @(),
    [Parameter(Mandatory = $true)]
    [string]$ReviewConclusion,
    [string]$NextAction = '按复核结果修平口径后再继续推进'
)

function ConvertTo-BulletLines {
    param(
        [string[]]$Items,
        [string]$DefaultText
    )

    $normalizedItems = @($Items | Where-Object { $_ -and $_.Trim() -ne '' })
    if ($normalizedItems.Count -eq 0) {
        return @("- $DefaultText")
    }

    return @($normalizedItems | ForEach-Object { "- $_" })
}

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskDirectoryPath = Join-Path (Join-Path $scriptRootPath 'tasks') $TaskId
$timestampText = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$templateGuideRelativePath = 'docs/40-执行/21-关键配置来源与漂移复核模板.md'
$governanceGuideRelativePath = 'docs/30-方案/08-V4-治理审计候选规范.md'
$closeoutGuideRelativePath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlyGovernanceReview {
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
    Stop-FriendlyGovernanceReview `
        -Summary '任务包编号格式不对，当前没法写入治理复核。' `
        -Detail 'TaskId 必须匹配 v4-trial-<三位序号>-<语义名> 格式。' `
        -NextSteps @(
            '先把任务编号改成例如 v4-trial-001-语义名。',
            '确认任务编号无误后再重试。'
        )
}

if (-not (Test-Path $taskDirectoryPath)) {
    Stop-FriendlyGovernanceReview `
        -Summary '任务目录不存在，当前没法写入治理复核。' `
        -Detail ("任务目录不存在：{0}" -f $taskDirectoryPath) `
        -NextSteps @(
            '先确认 TaskId 是否写对了。',
            '确认对应任务包已经创建后再重试。'
        )
}

$resultFilePath = Join-Path $taskDirectoryPath 'result.md'
$decisionLogFilePath = Join-Path $taskDirectoryPath 'decision-log.md'
foreach ($requiredFilePath in @($resultFilePath, $decisionLogFilePath)) {
    if (-not (Test-Path $requiredFilePath)) {
        Stop-FriendlyGovernanceReview `
            -Summary '任务包资料还没补齐，当前不能写治理复核。' `
            -Detail ("缺少必需文件：{0}" -f $requiredFilePath) `
            -NextSteps @(
                '先补齐 result.md 和 decision-log.md。',
                '补齐后再重新执行治理复核写入。'
            )
    }
}

$configSourceLines = ConvertTo-BulletLines -Items $ConfigSources -DefaultText '当前轮未补充额外配置来源，请至少回看 README.md 与现行标准件总览'
$versionReferenceLines = ConvertTo-BulletLines -Items $VersionReferences -DefaultText '当前轮未补充额外版本依据，请至少回看 docs/40-执行/12-V4-Target-实施计划.md'
$driftCheckLines = ConvertTo-BulletLines -Items $DriftChecks -DefaultText '当前未发现明确口径漂移，提交前仍需人工复核'

$resultAppendLines = @(
    '',
    '',
    "## 关键配置来源与漂移复核（$timestampText）",
    '',
    "- 复核模板：$templateGuideRelativePath",
    "- 治理规范：$governanceGuideRelativePath",
    '',
    '### 配置来源',
    ''
)
$resultAppendLines += $configSourceLines
$resultAppendLines += @(
    '',
    '### 版本与现行依据',
    ''
)
$resultAppendLines += $versionReferenceLines

$resultAppendLines += @(
    '',
    '### 漂移检查',
    ''
)
$resultAppendLines += $driftCheckLines
$resultAppendLines += @(
    '',
    '### 复核结论',
    '',
    "- $ReviewConclusion",
    '',
    '### 下一步',
    '',
    "- $NextAction",
    '',
    '### 收口参考',
    '',
    "- $closeoutGuideRelativePath"
)

$decisionLogAppendLines = @(
    '',
    '',
    "## $timestampText",
    '',
    '- 决策：记录关键配置来源与漂移复核',
    "- 证据：依据 $templateGuideRelativePath 与 $governanceGuideRelativePath 形成统一复核口径",
    '- 配置来源：'
)
$decisionLogAppendLines += $configSourceLines
$decisionLogAppendLines += @(
    '',
    '- 版本依据：'
)
$decisionLogAppendLines += $versionReferenceLines
$decisionLogAppendLines += @(
    '',
    '- 漂移检查：'
)
$decisionLogAppendLines += $driftCheckLines
$decisionLogAppendLines += @(
    '',
    "- 结论：$ReviewConclusion",
    "- 影响：下一步为 $NextAction"
)

Add-Content -Path $resultFilePath -Value ($resultAppendLines -join [Environment]::NewLine) -Encoding UTF8
Add-Content -Path $decisionLogFilePath -Value ($decisionLogAppendLines -join [Environment]::NewLine) -Encoding UTF8

Write-Info ("关键配置来源与漂移复核已写入：{0}" -f $taskDirectoryPath)
Write-Info ("复核模板：{0}" -f $templateGuideRelativePath)
Write-Info ("治理规范：{0}" -f $governanceGuideRelativePath)
