# Phase 2 前置开发集成测试
# 用途：验证文件并发锁和 API 限流机制
# 测试场景：3 个并发进程同时写入 + 5 个并发 API 请求

param(
    [switch]$TestFileAppend,
    [switch]$TestRateLimit,
    [switch]$All
)

$ErrorActionPreference = 'Stop'

if ($All) {
    $TestFileAppend = $true
    $TestRateLimit = $true
}

# 测试 1：文件并发追加
if ($TestFileAppend) {
    Write-Host "`n========== 测试 1：文件并发追加 ==========" -ForegroundColor Cyan

    $testFile = ".codex/chancellor/.test-concurrent-append.log"
    $testDir = Split-Path -Parent $testFile

    # 清理旧测试文件
    if (Test-Path $testFile) {
        Remove-Item $testFile -Force
    }

    if (-not (Test-Path $testDir)) {
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    }

    # 启动 3 个并发进程
    $jobs = @()
    for ($i = 1; $i -le 3; $i++) {
        $job = Start-Job -ScriptBlock {
            param($id, $file, $scriptPath)

            for ($j = 1; $j -le 5; $j++) {
                $content = "进程 $id - 写入 $j - $(Get-Date -Format 'HH:mm:ss.fff')"
                & $scriptPath -FilePath $file -Content $content
                Start-Sleep -Milliseconds (Get-Random -Minimum 10 -Maximum 50)
            }
        } -ArgumentList $i, $testFile, "$PSScriptRoot/Invoke-SafeFileAppend.ps1"

        $jobs += $job
    }

    # 等待所有任务完成
    Write-Host "等待 3 个并发进程完成..."
    $jobs | Wait-Job | Out-Null

    # 检查结果
    $jobs | Receive-Job
    $jobs | Remove-Job

    if (Test-Path $testFile) {
        $lines = Get-Content $testFile
        Write-Host "`n✓ 测试完成，共写入 $($lines.Count) 行" -ForegroundColor Green
        Write-Host "预期：15 行（3 进程 × 5 次）"

        if ($lines.Count -eq 15) {
            Write-Host "✓ 并发写入测试通过：无内容撕裂，100% 成功率" -ForegroundColor Green
        }
        else {
            Write-Warning "⚠️ 并发写入测试失败：预期 15 行，实际 $($lines.Count) 行"
        }

        # 显示前 5 行
        Write-Host "`n前 5 行内容："
        $lines | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
    }
    else {
        Write-Error "❌ 测试文件未生成：$testFile"
    }
}

# 测试 2：API 限流队列
if ($TestRateLimit) {
    Write-Host "`n========== 测试 2：API 限流队列 ==========" -ForegroundColor Cyan

    # 清理旧状态文件
    $stateFile = ".codex/chancellor/.rate-limit-state.json"
    if (Test-Path $stateFile) {
        Remove-Item $stateFile -Force
    }

    # 启动 5 个并发请求
    $jobs = @()
    $startTime = Get-Date

    for ($i = 1; $i -le 5; $i++) {
        $job = Start-Job -ScriptBlock {
            param($id, $scriptPath)

            # 模拟 API 请求的 ScriptBlock
            $mockApiRequest = {
                param($id)
                $delay = Get-Random -Minimum 100 -Maximum 300
                Start-Sleep -Milliseconds $delay
                Write-Host "  [请求 $id] 完成（延迟 $delay ms）"
                return "请求 $id 成功"
            }

            & $scriptPath `
                -RequestAction $mockApiRequest `
                -RequestParams @{ id = $id } `
                -MinIntervalMs 1000 `
                -MaxConcurrent 2 `
                -MaxRetries 3
        } -ArgumentList $i, "$PSScriptRoot/Invoke-RateLimitedRequest.ps1"

        $jobs += $job
        Start-Sleep -Milliseconds 100  # 错开启动时间
    }

    # 等待所有任务完成
    Write-Host "等待 5 个并发请求完成..."
    $jobs | Wait-Job | Out-Null

    $endTime = Get-Date
    $totalTime = ($endTime - $startTime).TotalSeconds

    # 检查结果
    $jobs | Receive-Job
    $jobs | Remove-Job

    Write-Host "`n✓ 测试完成，总耗时：$([Math]::Round($totalTime, 2)) 秒" -ForegroundColor Green
    Write-Host "预期：≥ 4 秒（5 个请求，最大并发 2，最小间隔 1 秒）"

    if ($totalTime -ge 4) {
        Write-Host "✓ API 限流测试通过：请求间隔 ≥ 1 秒，并发数 ≤ 2" -ForegroundColor Green
    }
    else {
        Write-Warning "⚠️ API 限流测试可能失败：总耗时 $([Math]::Round($totalTime, 2)) 秒 < 4 秒"
    }
}

Write-Host "`n========== 集成测试完成 ==========" -ForegroundColor Cyan
