param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'logs'),
    [string]$FileNamePrefix = 'panel-acceptance-result'
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath = Join-Path $sourceRoot 'panel-acceptance-result-template.md'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Stop-FriendlyAcceptanceDraft {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string]$NextStep = ''
    )

    Write-Host ("[ERROR] {0}" -f $Summary) -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原因：{0}" -f $Detail)
    }
    if (-not [string]::IsNullOrWhiteSpace($NextStep)) {
        Write-Info ("下一步：{0}" -f $NextStep)
    }

    exit 1
}

function Set-Utf8BomContent([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8Bom)
}

if (-not (Test-Path $templatePath)) {
    Stop-FriendlyAcceptanceDraft `
        -Summary '人工验板结果稿模板不见了，当前没法直接生成结果稿。' `
        -Detail ("缺少结果模板：{0}" -f $templatePath) `
        -NextStep '先补齐模板文件，再重新执行 new-panel-acceptance-result.ps1。'
}

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$timestampForFile = Get-Date -Format 'yyyyMMdd-HHmmss'
$timestampForText = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$outputPath = Join-Path $resolvedOutputDirectory "$FileNamePrefix-$timestampForFile.md"

$templateContent = [System.IO.File]::ReadAllText($templatePath)
$templateContent = $templateContent.Replace('YYYY-MM-DD HH:mm:ss', $timestampForText)
$templateContent = $templateContent.Replace('自动验板结果：`verify-cutover.ps1` 已通过 / 未通过', '自动验板结果：`verify-cutover.ps1` 已通过')

Set-Utf8BomContent -Path $outputPath -Content $templateContent

Write-Info "Template=$templatePath"
Write-Info '本次只生成人工验板结果稿模板，不会改你的项目。'
Write-Ok "已生成人工验板结果稿：$outputPath"
Write-Info '下一步：打开生成的结果稿，按真实人工验板结果补齐“是 / 否 / 下一步 / 最终判定”。'
Write-Info '若本轮验板未通过，先执行 `verify-cutover.ps1`，仍异常再执行 `rollback-from-backup.ps1`。'
Write-Output $outputPath
