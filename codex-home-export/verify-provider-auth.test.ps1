$ErrorActionPreference = 'Stop'

function Assert-ExitCode {
    param(
        [int]$Actual,
        [int]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw ("{0}：期望退出码 {1}，实际 {2}。" -f $Message, $Expected, $Actual)
    }
}

function Assert-OutputContains {
    param(
        [string[]]$Lines,
        [string]$ExpectedText,
        [string]$Message
    )

    $joinedOutput = ($Lines -join [Environment]::NewLine)
    if ($joinedOutput -notlike ('*' + $ExpectedText + '*')) {
        throw ("{0}：未找到 `{1}`。" -f $Message, $ExpectedText)
    }
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    $listener.Start()
    try {
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

function Start-TestHttpServer {
    param(
        [int]$Port,
        [object[]]$Responses
    )

    return Start-Job -ArgumentList $Port, $Responses -ScriptBlock {
        param(
            [int]$Port,
            [object[]]$Responses
        )

        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), $Port)
        $listener.Start()
        try {
            foreach ($responseItem in $Responses) {
                $client = $listener.AcceptTcpClient()
                $stream = $null
                try {
                    $stream = $client.GetStream()
                    $buffer = New-Object byte[] 4096
                    [void]$stream.Read($buffer, 0, $buffer.Length)
                    $bodyText = [string]$responseItem.Body
                    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyText)
                    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes((
                        "HTTP/1.1 {0}`r`nContent-Type: application/json`r`nContent-Length: {1}`r`nConnection: close`r`n`r`n" -f
                        ([string]$responseItem.StatusLine),
                        $bodyBytes.Length
                    ))
                    $stream.Write($headerBytes, 0, $headerBytes.Length)
                    if ($bodyBytes.Length -gt 0) {
                        $stream.Write($bodyBytes, 0, $bodyBytes.Length)
                    }
                    $stream.Flush()
                }
                finally {
                    if ($null -ne $stream) {
                        $stream.Dispose()
                    }
                    $client.Dispose()
                }
            }
        }
        finally {
            $listener.Stop()
        }
    }
}

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifyScriptPath = Join-Path $scriptRootPath 'verify-provider-auth.ps1'
$tempRootPath = Join-Path ([System.IO.Path]::GetTempPath()) ('verify-provider-auth-test-' + [System.Guid]::NewGuid().ToString('N'))
$targetCodexHomePath = Join-Path $tempRootPath 'codex-home'
$configPath = Join-Path $targetCodexHomePath 'config.toml'
$authPath = Join-Path $targetCodexHomePath 'auth.json'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$serverJob = $null

try {
    New-Item -ItemType Directory -Force -Path $targetCodexHomePath | Out-Null

    $scenarios = @(
        [pscustomobject]@{
            Name = 'CRS 404 探针应改为警告并提示真人验证'
            Provider = 'crs'
            Responses = @(
                [pscustomobject]@{ StatusLine = '404 Not Found'; Body = '' }
                [pscustomobject]@{ StatusLine = '404 Not Found'; Body = '' }
            )
            ExpectedExitCode = 0
            ExpectedTexts = @(
                'provider=crs 的候选 models 端点均返回 404'
                '当前 provider=crs；统一 /models 探针暂不能替代真人验板。'
                '传令：修一下登录页'
            )
        }
        [pscustomobject]@{
            Name = '401 鉴权失败应直接返回人话错误'
            Provider = 'yunyi'
            Responses = @(
                [pscustomobject]@{ StatusLine = '401 Unauthorized'; Body = '{"error":"invalid api key"}' }
            )
            ExpectedExitCode = 1
            ExpectedTexts = @(
                '当前 provider=yunyi 的真实鉴权没通过。'
                'HTTP 状态：401'
                '确认前先不要直接开始真实开发任务。'
            )
        }
        [pscustomobject]@{
            Name = '500 异常应归类为未拿到可用响应'
            Provider = 'yunyi'
            Responses = @(
                [pscustomobject]@{ StatusLine = '500 Internal Server Error'; Body = '{"error":"server exploded"}' }
            )
            ExpectedExitCode = 1
            ExpectedTexts = @(
                '当前 provider=yunyi 的真实鉴权检查没拿到可用响应。'
                'HTTP 状态：500'
                '先确认网络、base_url 和 key，再回官方 Codex 面板做一次真人验证。'
            )
        }
    )

    foreach ($scenario in $scenarios) {
        $port = Get-FreeTcpPort
        $configContent = @"
model_provider = "$($scenario.Provider)"
preferred_auth_method = "apikey"

[model_providers.$($scenario.Provider)]
name = "$($scenario.Provider)"
base_url = "http://127.0.0.1:$port/openai"
requires_openai_auth = true
"@
        [System.IO.File]::WriteAllText($configPath, $configContent, $utf8Bom)
        [System.IO.File]::WriteAllText($authPath, '{ "OPENAI_API_KEY": "test-key" }', $utf8Bom)

        $serverJob = Start-TestHttpServer -Port $port -Responses $scenario.Responses
        Start-Sleep -Milliseconds 200

        $commandOutput = @(
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyScriptPath -TargetCodexHome $targetCodexHomePath 2>&1
        )
        $actualExitCode = $LASTEXITCODE

        Assert-ExitCode -Actual $actualExitCode -Expected $scenario.ExpectedExitCode -Message $scenario.Name
        foreach ($expectedText in $scenario.ExpectedTexts) {
            Assert-OutputContains -Lines $commandOutput -ExpectedText $expectedText -Message $scenario.Name
        }

        Wait-Job -Job $serverJob | Out-Null
        Receive-Job -Job $serverJob | Out-Null
        Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue | Out-Null
        $serverJob = $null
    }
}
finally {
    if ($null -ne $serverJob) {
        Stop-Job -Job $serverJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue | Out-Null
    }

    if (Test-Path $tempRootPath) {
        Remove-Item -LiteralPath $tempRootPath -Recurse -Force
    }
}

Write-Host 'PASS: verify-provider-auth.test.ps1'
