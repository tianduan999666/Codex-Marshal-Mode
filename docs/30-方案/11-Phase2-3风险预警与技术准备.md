# Phase 2-3 风险预警与技术准备

最后更新：2026-04-03
状态：风险预警
优先级：高（必须在 Phase 2 启动前解决）

## 一、核心风险识别

### 风险 1：文件并发锁的跨平台隐患

**问题描述**：
- VibeCoding 融合方案中提到的 Agent 并行编排需要文件锁机制
- 原方案使用 `flock -x 200`（Linux/Bash 专用）
- 当前丞相模式运行在 Windows PowerShell 环境

**技术冲突**：
```bash
# 原方案（不可用）
(
  flock -x 200
  cat code-review-result.md >> decision-log.md
) 200>/tmp/decision-log.lock
```

**正确实现（PowerShell）**：
```powershell
# 方案 A：使用 Mutex
$mutex = New-Object System.Threading.Mutex($false, "Global\DecisionLogMutex")
try {
    $mutex.WaitOne() | Out-Null
    Get-Content "code-review-result.md" | Add-Content "decision-log.md"
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

# 方案 B：文件访问冲突重试机制
$maxRetries = 3
$retryCount = 0
$backoffMs = 100

while ($retryCount -lt $maxRetries) {
    try {
        # 尝试独占写入
        $stream = [System.IO.File]::Open(
            "decision-log.md",
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $writer = New-Object System.IO.StreamWriter($stream)
        $content = Get-Content "code-review-result.md" -Raw
        $writer.Write($content)
        $writer.Close()
        $stream.Close()
        break
    } catch {
        $retryCount++
        if ($retryCount -ge $maxRetries) {
            throw "文件写入失败，已重试 $maxRetries 次"
        }
        Start-Sleep -Milliseconds $backoffMs
        $backoffMs = $backoffMs * 2
    }
}
```

**行动建议**：
- ✅ 立即采纳：方案 B（文件访问冲突重试）
- ✅ 实施时机：Phase 2 启动前
- ✅ 实施成本：2-3 小时（封装为通用函数）

---

### 风险 2：API 并发限流（Rate Limit）

**问题描述**：
- Phase 2 并行 Agent 编排会同时触发多个 API 请求
- 非企业版 API 节点有严格的 RPM/TPD 限制
- 5 个并发请求可能触发 429 限流错误

**实测数据**（假设）：
- Claude API：60 RPM（每分钟请求数）
- 并行 3 个 Agent：瞬时 3 个请求
- 如果 10 秒内重试 3 次：9 个请求 → 可能触发限流

**技术方案**：

#### 方案 A：请求队列 + 指数退避
```powershell
# .codex/chancellor/agent-dispatcher.ps1
$global:RequestQueue = [System.Collections.Queue]::new()
$global:LastRequestTime = Get-Date
$global:MinIntervalMs = 1000  # 最小请求间隔 1 秒

function Invoke-AgentWithRateLimit {
    param(
        [string]$AgentName,
        [string]$Input
    )
    
    # 加入队列
    $global:RequestQueue.Enqueue(@{
        AgentName = $AgentName
        Input = $Input
        Timestamp = Get-Date
    })
    
    # 处理队列
    while ($global:RequestQueue.Count -gt 0) {
        $request = $global:RequestQueue.Dequeue()
        
        # 检查间隔
        $elapsed = (Get-Date) - $global:LastRequestTime
        if ($elapsed.TotalMilliseconds -lt $global:MinIntervalMs) {
            $sleepMs = $global:MinIntervalMs - $elapsed.TotalMilliseconds
            Start-Sleep -Milliseconds $sleepMs
        }
        
        # 发送请求
        try {
            $result = Invoke-Agent -Name $request.AgentName -Input $request.Input
            $global:LastRequestTime = Get-Date
            return $result
        } catch {
            if ($_.Exception.Message -match '429') {
                # 检测到限流，指数退避
                Write-Warning "检测到 API 限流，等待 5 秒后重试"
                Start-Sleep -Seconds 5
                $global:RequestQueue.Enqueue($request)  # 重新入队
            } else {
                throw
            }
        }
    }
}
```

#### 方案 B：并发数限制
```powershell
# 限制最大并发数为 2
$maxConcurrent = 2
$runningJobs = @()

foreach ($agent in $agents) {
    # 等待空闲槽位
    while ($runningJobs.Count -ge $maxConcurrent) {
        $completed = $runningJobs | Where-Object { $_.State -eq 'Completed' }
        foreach ($job in $completed) {
            Receive-Job $job
            Remove-Job $job
            $runningJobs = $runningJobs | Where-Object { $_.Id -ne $job.Id }
        }
        Start-Sleep -Milliseconds 500
    }
    
    # 启动新任务
    $job = Start-Job -ScriptBlock {
        param($agentName, $input)
        Invoke-Agent -Name $agentName -Input $input
    } -ArgumentList $agent.Name, $agent.Input
    
    $runningJobs += $job
}
```

**行动建议**：
- ✅ 立即采纳：方案 A（请求队列 + 指数退避）+ 方案 B（并发数限制）
- ✅ 实施时机：Phase 2 启动前（必须前置开发）
- ✅ 实施成本：4-6 小时
- ⚠️ 风险等级：高（不解决会导致 Phase 2 完全不可用）

---

## 二、技术准备清单

### Phase 2 启动前必须完成

| 项目 | 优先级 | 预估工时 | 负责人 | 状态 |
|-----|--------|---------|--------|------|
| 文件并发锁（PowerShell 实现） | P0 | 2-3 小时 | 待定 | 待开始 |
| API 限流队列机制 | P0 | 4-6 小时 | 待定 | 待开始 |
| Agent 并发数限制 | P0 | 2 小时 | 待定 | 待开始 |
| 限流检测与重试 | P1 | 2 小时 | 待定 | 待开始 |
| 并发写入集成测试 | P1 | 3 小时 | 待定 | 待开始 |

**总计**：13-16 小时（约 2 个工作日）

---

## 三、降级方案

### 如果 Phase 2 启动时未完成技术准备

**降级策略**：
1. 禁用并行 Agent 编排
2. 回退到串行执行模式
3. 单 Agent 审查（code-reviewer only）
4. 人工触发多轮审查

**降级成本**：
- 效率提升从 1.6 倍降至 1.2 倍
- 但保证系统稳定性

---

## 四、验收标准

### 文件并发锁验收
- [ ] 3 个并发进程同时写入 decision-log.md，无内容撕裂
- [ ] 10 次并发测试，100% 成功率
- [ ] 失败时自动重试，最多 3 次

### API 限流验收
- [ ] 模拟 429 错误，自动指数退避
- [ ] 5 个并发请求，自动排队执行
- [ ] 请求间隔 ≥ 1 秒
- [ ] 限流后自动重试，成功率 ≥ 95%

---

**下一步行动**：
1. 评审本文档
2. 确定技术准备负责人
3. 启动 Phase 2 前置开发（预计 2 个工作日）
