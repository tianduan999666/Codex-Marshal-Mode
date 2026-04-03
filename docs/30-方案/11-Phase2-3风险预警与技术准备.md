# Phase 2-3 风险预警与技术准备

最后更新：2026-04-04
状态：本地在研已验证（未纳入现行件）
优先级：高（真实多 Agent 联调前仍需继续收口）

> 口径说明：本文记录的是 Phase 2 本地在研准备情况，用于风险预警与技术评估；除已单独纳管提交的事项外，不代表当前公开现行件已全部收口。

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

**当前状态**：
- ✅ 本地已落地：`.codex/chancellor/Invoke-SafeFileAppend.ps1`
- ✅ 本地已验证：`.codex/chancellor/Test-Phase2Prerequisites.ps1 -TestFileAppend`
- ⚠️ 当前边界：只验证了本地共享文件安全追加，还没接真实外部 Agent 输出；当前尚未按现行件口径收口

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

**当前状态**：
- ✅ 本地已落地：`.codex/chancellor/Invoke-RateLimitedRequest.ps1`
- ✅ 本地已落地：`.codex/chancellor/Invoke-Phase2AgentDispatcher.ps1`
- ✅ 本地已验证：`.codex/chancellor/Test-Phase2Prerequisites.ps1 -TestRateLimit`
- ✅ 本地已验证：`.codex/chancellor/Test-Phase2AgentDispatcher.ps1`
- ⚠️ 当前边界：当前 Agent 仍是本地最小适配层，不是真实 provider 驱动的完整多 Agent 运行时；当前尚未按现行件口径收口

---

## 二、技术准备清单

### Phase 2 启动前必须完成

| 项目 | 优先级 | 预估工时 | 负责人 | 状态 |
|-----|--------|---------|--------|------|
| 文件并发锁（PowerShell 实现） | P0 | 2-3 小时 | 本地已完成 | 本地已验证 |
| API 限流队列机制 | P0 | 4-6 小时 | 本地已完成 | 本地已验证 |
| Agent 并发数限制 | P0 | 2 小时 | 本地已完成 | 本地已验证 |
| 限流检测与重试 | P1 | 2 小时 | 本地已完成 | 本地已验证 |
| 并发写入集成测试 | P1 | 3 小时 | 本地已完成 | 本地已验证 |
| 真实 provider 多 Agent 联调 | P0 | 4-8 小时 | 待定 | 待开始 |
| 第 3 个 Agent 接入评估 | P1 | 2-4 小时 | 待定 | 待开始 |

**当前结论**：最小前置开发已在本地在研链路完成验证；真实多 Agent 联调与扩角色仍未开始，当前还不能按现行件口径宣称完成。

---

## 三、降级方案

### 如果真实多 Agent 联调尚未完成

**降级策略**：
1. 保持当前最小两 Agent 本地适配层
2. 必要时回退到串行执行模式
3. 单 Agent 审查（code-reviewer only）
4. 人工触发多轮审查

**降级成本**：
- 当前最小并行仍可用
- 但无法宣称“真实多 Agent 生产运行时已完成”

---

## 四、验收标准

### 文件并发锁验收
- [x] 3 个并发进程同时写入 decision-log.md，无内容撕裂
- [x] 10 次并发测试，100% 成功率
- [x] 失败时自动重试，最多 3 次

### API 限流验收
- [x] 模拟 429 错误，自动指数退避
- [x] 5 个并发请求，自动排队执行
- [x] 请求间隔 ≥ 1 秒
- [x] 限流后自动重试，成功率 ≥ 95%
- [ ] 真实 provider 双 Agent 联调通过

---

**下一步行动**：
1. 继续观察 7 天基线数据
2. 决定是否接入真实 provider 双 Agent 联调
3. 再判断是否值得接第 3 个 Agent
