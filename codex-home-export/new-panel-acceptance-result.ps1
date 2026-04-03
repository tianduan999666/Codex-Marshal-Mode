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

function Set-Utf8NoBomContent([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

if (-not (Test-Path $templatePath)) {
    throw "缺少结果模板：$templatePath"
}

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$timestampForFile = Get-Date -Format 'yyyyMMdd-HHmmss'
$timestampForText = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$outputPath = Join-Path $resolvedOutputDirectory "$FileNamePrefix-$timestampForFile.md"

$templateContent = [System.IO.File]::ReadAllText($templatePath)
$templateContent = $templateContent.Replace('YYYY-MM-DD HH:mm:ss', $timestampForText)
$templateContent = $templateContent.Replace('自动验板结果：`verify-cutover.ps1` 已通过 / 未通过', '自动验板结果：`verify-cutover.ps1` 已通过')

Set-Utf8NoBomContent -Path $outputPath -Content $templateContent

Write-Info "Template=$templatePath"
Write-Ok "已生成人工验板结果稿：$outputPath"
Write-Info '下一步：打开生成的结果稿，按真实人工验板结果补齐“是 / 否 / 备注 / 最终判定”。'
Write-Info '若本轮验板未通过，先执行 `verify-cutover.ps1`，仍异常再执行 `rollback-from-backup.ps1`。'
Write-Output $outputPath
