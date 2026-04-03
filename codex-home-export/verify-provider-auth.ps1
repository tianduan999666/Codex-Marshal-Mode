param(
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex')
)

$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$configPath = Join-Path $resolvedTargetCodexHome 'config.toml'
$authPath = Join-Path $resolvedTargetCodexHome 'auth.json'

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnLine([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Get-TomlScalarValueFromContent([string]$Content, [string]$KeyName) {
    $pattern = '(?m)^\s*' + [regex]::Escape($KeyName) + '\s*=\s*["'']([^"'']+)["'']'
    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return ''
}

function Get-TomlSectionBody([string]$Content, [string]$SectionName) {
    $pattern = '(?ms)^\[' + [regex]::Escape($SectionName) + '\]\s*(?<body>.*?)(?=^\[[^\r\n]+\]|\z)'
    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) {
        return $match.Groups['body'].Value
    }

    return ''
}

function Get-JsonPropertyText([object]$Payload, [string[]]$CandidateNames) {
    if ($null -eq $Payload) {
        return ''
    }

    foreach ($candidateName in $CandidateNames) {
        if ($Payload.PSObject.Properties.Name -contains $candidateName) {
            return [string]$Payload.$candidateName
        }
    }

    return ''
}

function Get-ProviderCheckCandidateUrls([string]$BaseUrl) {
    $normalizedBaseUrl = $BaseUrl.Trim().TrimEnd('/')
    $candidateUrls = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($normalizedBaseUrl)) {
        $candidateUrls.Add($normalizedBaseUrl + '/models')
        if (-not $normalizedBaseUrl.EndsWith('/v1')) {
            $candidateUrls.Add($normalizedBaseUrl + '/v1/models')
        }
    }

    return @($candidateUrls | Select-Object -Unique)
}

function Read-ResponseBodyText([object]$Response) {
    if ($null -eq $Response) {
        return ''
    }

    try {
        $stream = $Response.GetResponseStream()
        if ($null -eq $stream) {
            return ''
        }

        $reader = New-Object System.IO.StreamReader($stream)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    }
    catch {
        return ''
    }
}

function Test-ProviderProbeUrl([string]$Uri, [string]$ApiKey) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $ApiKey" } -TimeoutSec 20
        return [pscustomobject]@{
            success = $true
            status_code = [int]$response.StatusCode
            body = ''
            message = ''
        }
    }
    catch {
        $exception = $_.Exception
        $statusCode = 0
        $responseBody = ''
        if ($exception.PSObject.Properties.Name -contains 'Response') {
            $response = $exception.Response
            if ($null -ne $response) {
                try {
                    $statusCode = [int]$response.StatusCode.value__
                }
                catch {
                    $statusCode = 0
                }
                $responseBody = Read-ResponseBodyText -Response $response
            }
        }

        return [pscustomobject]@{
            success = $false
            status_code = $statusCode
            body = $responseBody
            message = $exception.Message
        }
    }
}

if (-not (Test-Path $configPath)) {
    Write-WarnLine "未检测到全局 config.toml：$configPath"
    Write-WarnLine '已跳过真实 provider/auth 鉴权检查。'
    exit 0
}

$configContent = Get-Content -Raw -Encoding UTF8 -Path $configPath
$providerName = Get-TomlScalarValueFromContent -Content $configContent -KeyName 'model_provider'
$preferredAuthMethod = Get-TomlScalarValueFromContent -Content $configContent -KeyName 'preferred_auth_method'

if ([string]::IsNullOrWhiteSpace($providerName)) {
    Write-WarnLine 'config.toml 未声明 model_provider；已跳过真实 provider/auth 鉴权检查。'
    exit 0
}

$providerSectionBody = Get-TomlSectionBody -Content $configContent -SectionName ('model_providers.' + $providerName)
$providerBaseUrl = Get-TomlScalarValueFromContent -Content $providerSectionBody -KeyName 'base_url'
$requiresOpenAiAuth = Get-TomlScalarValueFromContent -Content $providerSectionBody -KeyName 'requires_openai_auth'

if ([string]::IsNullOrWhiteSpace($providerBaseUrl)) {
    Write-WarnLine ("当前 provider={0} 缺少 base_url；已跳过真实 provider/auth 鉴权检查。" -f $providerName)
    exit 0
}

if ((-not [string]::IsNullOrWhiteSpace($preferredAuthMethod)) -and ($preferredAuthMethod -ne 'apikey')) {
    Write-WarnLine ("当前 preferred_auth_method={0}；脚本暂只支持 apikey 真实鉴权检查。" -f $preferredAuthMethod)
    exit 0
}

if (($requiresOpenAiAuth -ne '') -and ($requiresOpenAiAuth -ne 'true')) {
    Write-WarnLine ("当前 provider={0} 未声明 requires_openai_auth=true；脚本暂跳过真实鉴权检查。" -f $providerName)
    exit 0
}

if (-not (Test-Path $authPath)) {
    Write-WarnLine "未检测到 auth.json：$authPath"
    Write-WarnLine '已跳过真实 provider/auth 鉴权检查。'
    exit 0
}

$authInfo = Get-Content -Raw -Encoding UTF8 -Path $authPath | ConvertFrom-Json
$apiKey = Get-JsonPropertyText -Payload $authInfo -CandidateNames @('OPENAI_API_KEY', 'openai_api_key', 'api_key')
if ([string]::IsNullOrWhiteSpace($apiKey) -and (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY))) {
    $apiKey = $env:OPENAI_API_KEY
}

if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-WarnLine 'auth.json 中未找到 OPENAI_API_KEY；已跳过真实 provider/auth 鉴权检查。'
    exit 0
}

$candidateUrls = Get-ProviderCheckCandidateUrls -BaseUrl $providerBaseUrl
if ($candidateUrls.Count -eq 0) {
    Write-WarnLine ("当前 provider={0} 没有可探测的候选 URL；已跳过真实 provider/auth 鉴权检查。" -f $providerName)
    exit 0
}

Write-Info ("Provider={0}" -f $providerName)
Write-Info ("ProbeBaseUrl={0}" -f $providerBaseUrl.Trim().TrimEnd('/'))

$lastResult = $null
foreach ($candidateUrl in $candidateUrls) {
    Write-Info ("尝试真实鉴权探针：GET {0}" -f $candidateUrl)
    $probeResult = Test-ProviderProbeUrl -Uri $candidateUrl -ApiKey $apiKey
    $lastResult = $probeResult

    if ($probeResult.success) {
        Write-Ok ("真实 provider/auth 鉴权检查通过：HTTP {0}" -f $probeResult.status_code)
        exit 0
    }

    $responseBody = [string]$probeResult.body
    $lowerBody = $responseBody.ToLowerInvariant()
    if (($probeResult.status_code -in @(401, 403)) -or $lowerBody.Contains('user not found') -or $lowerBody.Contains('invalid') -or $lowerBody.Contains('unauthorized') -or $lowerBody.Contains('forbidden') -or $lowerBody.Contains('api key')) {
        throw ("真实 provider/auth 鉴权检查失败：provider={0} url={1} status={2} body={3}" -f $providerName, $candidateUrl, $probeResult.status_code, (($responseBody -replace '\s+', ' ').Trim()))
    }

    if ($probeResult.status_code -eq 404) {
        continue
    }
}

if (($null -ne $lastResult) -and ($lastResult.status_code -eq 404)) {
    Write-WarnLine ("provider={0} 的候选 models 端点均返回 404；脚本无法完成统一真实鉴权检查。" -f $providerName)
    exit 0
}

if ($null -ne $lastResult) {
    throw ("真实 provider/auth 鉴权检查失败：provider={0} status={1} message={2}" -f $providerName, $lastResult.status_code, $lastResult.message)
}

throw ("真实 provider/auth 鉴权检查失败：provider={0} 未得到可用响应。" -f $providerName)
