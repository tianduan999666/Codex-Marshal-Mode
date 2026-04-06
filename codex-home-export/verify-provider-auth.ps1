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

function Stop-FriendlyProviderAuthCheck {
    param(
        [string]$Summary,
        [string]$Detail = '',
        [string]$NextStep = ''
    )

    Write-Host ''
    Write-Host "[ERROR] $Summary" -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-WarnLine ("原因：{0}" -f $Detail)
    }

    if (-not [string]::IsNullOrWhiteSpace($NextStep)) {
        Write-Info ("下一步：{0}" -f $NextStep)
    }

    exit 1
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

function Get-ProviderManualValidationHint([string]$ProviderName) {
    $normalizedProviderName = $ProviderName.Trim().ToLowerInvariant()
    if ($normalizedProviderName -eq 'crs') {
        return '当前 provider=crs；统一 /models 探针暂不能替代真人验板。请回官方 Codex 面板依次输入 `传令：版本`、`传令：状态`、`传令：修一下登录页` 做一次真人验证。'
    }

    return ''
}

function Test-ProviderBillingBlocked([int]$StatusCode, [string]$ResponseBody, [string]$MessageText) {
    if ($StatusCode -eq 402) {
        return $true
    }

    $combinedText = (([string]$ResponseBody) + ' ' + ([string]$MessageText)).ToLowerInvariant()
    return (
        $combinedText.Contains('402') -or
        $combinedText.Contains('payment') -or
        $combinedText.Contains('billing') -or
        $combinedText.Contains('quota') -or
        $combinedText.Contains('insufficient_quota') -or
        $combinedText.Contains('credit') -or
        $combinedText.Contains('需要付款') -or
        $combinedText.Contains('额度') -or
        $combinedText.Contains('欠费')
    )
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
    Write-WarnLine '当前机器还没有可用于真实探针的全局 provider 配置，本次先跳过。'
    exit 0
}

$configContent = Get-Content -Raw -Encoding UTF8 -Path $configPath
$providerName = Get-TomlScalarValueFromContent -Content $configContent -KeyName 'model_provider'
$preferredAuthMethod = Get-TomlScalarValueFromContent -Content $configContent -KeyName 'preferred_auth_method'

if ([string]::IsNullOrWhiteSpace($providerName)) {
    Write-WarnLine 'config.toml 没写 model_provider，本次无法判断该验哪个 provider，先跳过。'
    exit 0
}

$providerSectionBody = Get-TomlSectionBody -Content $configContent -SectionName ('model_providers.' + $providerName)
$providerBaseUrl = Get-TomlScalarValueFromContent -Content $providerSectionBody -KeyName 'base_url'
$requiresOpenAiAuth = Get-TomlScalarValueFromContent -Content $providerSectionBody -KeyName 'requires_openai_auth'

if ([string]::IsNullOrWhiteSpace($providerBaseUrl)) {
    Write-WarnLine ("当前 provider={0} 缺少 base_url，本次没法做真实探针，先跳过。" -f $providerName)
    exit 0
}

if ((-not [string]::IsNullOrWhiteSpace($preferredAuthMethod)) -and ($preferredAuthMethod -ne 'apikey')) {
    Write-WarnLine ("当前 preferred_auth_method={0}；脚本目前只支持 apikey 探针，所以这次先跳过。" -f $preferredAuthMethod)
    exit 0
}

if (($requiresOpenAiAuth -ne '') -and ($requiresOpenAiAuth -ne 'true')) {
    Write-WarnLine ("当前 provider={0} 没声明 requires_openai_auth=true；脚本这次先跳过。" -f $providerName)
    exit 0
}

if (-not (Test-Path $authPath)) {
    Write-WarnLine "未检测到 auth.json：$authPath"
    Write-WarnLine '当前机器还没拿到可用 key，本次先跳过真实鉴权检查。'
    exit 0
}

$authInfo = Get-Content -Raw -Encoding UTF8 -Path $authPath | ConvertFrom-Json
$apiKey = Get-JsonPropertyText -Payload $authInfo -CandidateNames @('OPENAI_API_KEY', 'openai_api_key', 'api_key')
if ([string]::IsNullOrWhiteSpace($apiKey) -and (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY))) {
    $apiKey = $env:OPENAI_API_KEY
}

if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-WarnLine 'auth.json 中没找到 OPENAI_API_KEY，本次先跳过真实鉴权检查。'
    exit 0
}

$candidateUrls = Get-ProviderCheckCandidateUrls -BaseUrl $providerBaseUrl
if ($candidateUrls.Count -eq 0) {
    Write-WarnLine ("当前 provider={0} 没有可探测的候选 URL，本次先跳过。" -f $providerName)
    exit 0
}

Write-Info ("Provider={0}" -f $providerName)
Write-Info ("ProbeBaseUrl={0}" -f $providerBaseUrl.Trim().TrimEnd('/'))
Write-Info '本次只检查当前 provider/auth 能不能连通，不会改你的项目。'

$lastResult = $null
$bestFailureResult = $null
$bestFailureUrl = ''
foreach ($candidateUrl in $candidateUrls) {
    Write-Info ("尝试真实鉴权探针：GET {0}" -f $candidateUrl)
    $probeResult = Test-ProviderProbeUrl -Uri $candidateUrl -ApiKey $apiKey
    $lastResult = $probeResult

    if ($probeResult.success) {
        Write-Ok ("真实 provider/auth 鉴权检查通过：HTTP {0}" -f $probeResult.status_code)
        exit 0
    }

    if (($probeResult.status_code -gt 0) -and ($probeResult.status_code -ne 404) -and ($null -eq $bestFailureResult)) {
        $bestFailureResult = $probeResult
        $bestFailureUrl = $candidateUrl
    }

    $responseBody = [string]$probeResult.body
    $lowerBody = $responseBody.ToLowerInvariant()
    if (($probeResult.status_code -in @(401, 403)) -or $lowerBody.Contains('user not found') -or $lowerBody.Contains('invalid') -or $lowerBody.Contains('unauthorized') -or $lowerBody.Contains('forbidden') -or $lowerBody.Contains('api key')) {
        Stop-FriendlyProviderAuthCheck `
            -Summary ("当前 provider={0} 的真实鉴权没通过。" -f $providerName) `
            -Detail ("真实鉴权接口拒绝了这次请求（URL：{0}，HTTP 状态：{1}）。" -f $candidateUrl, $probeResult.status_code) `
            -NextStep '先确认 config.toml 里的 provider、base_url 和 auth.json 里的 key 是同一套；确认前先不要直接开始真实开发任务。'
    }

    if (Test-ProviderBillingBlocked -StatusCode $probeResult.status_code -ResponseBody $responseBody -MessageText $probeResult.message) {
        Stop-FriendlyProviderAuthCheck `
            -Summary ("当前 provider={0} 的真实鉴权被额度或账单状态拦住了。" -f $providerName) `
            -Detail ("真实鉴权接口返回了疑似额度/账单异常（URL：{0}，HTTP 状态：{1}，原始信息：{2}）。" -f $candidateUrl, $probeResult.status_code, $probeResult.message) `
            -NextStep '先确认当前 provider 对应账号还有可用额度、账单状态正常，再回官方 Codex 面板做一次真人验证。'
    }

    if ($probeResult.status_code -eq 404) {
        continue
    }
}

if (($null -ne $lastResult) -and ($lastResult.status_code -eq 404)) {
    Write-WarnLine ("provider={0} 的候选 models 端点均返回 404；脚本无法完成统一真实鉴权检查。" -f $providerName)
    $manualValidationHint = Get-ProviderManualValidationHint -ProviderName $providerName
    if (-not [string]::IsNullOrWhiteSpace($manualValidationHint)) {
        Write-WarnLine $manualValidationHint
    }
    exit 0
}

if ($null -ne $bestFailureResult) {
    Stop-FriendlyProviderAuthCheck `
        -Summary ("当前 provider={0} 的真实鉴权检查没拿到可用响应。" -f $providerName) `
        -Detail ("真实鉴权接口没返回可用结果（URL：{0}，HTTP 状态：{1}，原始信息：{2}）。" -f $bestFailureUrl, $bestFailureResult.status_code, $bestFailureResult.message) `
        -NextStep '先确认网络、base_url 和 key，再回官方 Codex 面板做一次真人验证。'
}

if ($null -ne $lastResult) {
    Stop-FriendlyProviderAuthCheck `
        -Summary ("当前 provider={0} 的真实鉴权检查没拿到可用响应。" -f $providerName) `
        -Detail ("真实鉴权接口没返回可用结果（HTTP 状态：{0}，原始信息：{1}）。" -f $lastResult.status_code, $lastResult.message) `
        -NextStep '先确认网络、base_url 和 key，再回官方 Codex 面板做一次真人验证。'
}

Stop-FriendlyProviderAuthCheck `
    -Summary ("当前 provider={0} 的真实鉴权检查没拿到可用响应。" -f $providerName) `
    -NextStep '先确认当前机器能联网，再检查 provider 配置和 key。'
