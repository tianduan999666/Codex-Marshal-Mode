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

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifyScriptPath = Join-Path $scriptRootPath 'verify-provider-auth.ps1'
$tempRootPath = Join-Path ([System.IO.Path]::GetTempPath()) ('verify-provider-auth-test-' + [System.Guid]::NewGuid().ToString('N'))
$targetCodexHomePath = Join-Path $tempRootPath 'codex-home'
$configPath = Join-Path $targetCodexHomePath 'config.toml'
$authPath = Join-Path $targetCodexHomePath 'auth.json'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$port = Get-FreeTcpPort
$serverJob = $null

try {
    New-Item -ItemType Directory -Force -Path $targetCodexHomePath | Out-Null

    $configContent = @"
model_provider = "crs"
preferred_auth_method = "apikey"

[model_providers.crs]
name = "crs"
base_url = "http://127.0.0.1:$port/openai"
requires_openai_auth = true
"@
    [System.IO.File]::WriteAllText($configPath, $configContent, $utf8Bom)
    [System.IO.File]::WriteAllText($authPath, '{ "OPENAI_API_KEY": "test-key" }', $utf8Bom)

    $serverJob = Start-Job -ArgumentList $port -ScriptBlock {
        param([int]$Port)

        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), $Port)
        $listener.Start()
        try {
            for ($requestIndex = 0; $requestIndex -lt 2; $requestIndex++) {
                $client = $listener.AcceptTcpClient()
                $stream = $null
                try {
                    $stream = $client.GetStream()
                    $buffer = New-Object byte[] 4096
                    [void]$stream.Read($buffer, 0, $buffer.Length)
                    $responseBytes = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                    $stream.Write($responseBytes, 0, $responseBytes.Length)
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

    Start-Sleep -Milliseconds 200

    $commandOutput = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyScriptPath -TargetCodexHome $targetCodexHomePath 2>&1
    )
    $actualExitCode = $LASTEXITCODE

    Assert-ExitCode -Actual $actualExitCode -Expected 0 -Message 'CRS 404 探针应改为警告并提示真人验证'
    Assert-OutputContains -Lines $commandOutput -ExpectedText 'provider=crs 的候选 models 端点均返回 404' -Message '应说明统一探针无法完成'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '当前 provider=crs；统一 /models 探针暂不能替代真人验板。' -Message '应提示 CRS 真人验证前置说明'
    Assert-OutputContains -Lines $commandOutput -ExpectedText '传令：修一下登录页' -Message '应提示真人验证入口命令'

    Wait-Job -Job $serverJob | Out-Null
    Receive-Job -Job $serverJob | Out-Null
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
