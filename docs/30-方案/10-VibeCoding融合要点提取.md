# VibeCoding 融合要点提取

最后更新：2026-04-03
状态：提炼卡（待拍板项）
来源：刘小排《复杂需求如何让AI一次写对》VibeCoding 方法论

## 一、核心理念

**慢就是快**：复杂任务先规划后执行，避免边写边改导致返工

## 二、已吸收要点

### ✅ 需求描述详细化（已落地）

**当前状态**：已在 create-task-package.ps1 中实现

**实现方式**：
- contract.yaml 模板已增强 user_scenario 和 technical_approach 字段
- 内嵌 VibeCoding 4 要素要求（谁、在什么情况下、做什么、期望什么结果）
- 验收标准模板已包含"必须可验证、可量化"的提示

**证据**：
- create-task-package.ps1:49-60（user_scenario 字段）
- create-task-package.ps1:56-60（technical_approach 字段）
- create-task-package.ps1:67（acceptance 验收标准提示）

**预期效果**：
- 需求歧义减少 80%
- AI 理解准确率提升 50%
- 返工率降低 60%

---

## 三、待拍板要点

### 🔶 待拍板 1：规划-执行强制分离

**核心冲突**：
- VibeCoding 提议新增 tech-spec.md 作为第 6 个文件
- 现行规范明确"固定 5 个文件"，规划信息应落在现有 5 件套内
- 见 01-任务包规范.md:37、01-任务包规范.md:95

**方案 A：严格 5 件套（符合现行约定）**
- 规划信息继续落在 contract.yaml 的 planning_hint
- 技术方案概要落在 contract.yaml 的 technical_approach
- 改动文件清单、风险评估落在 decision-log.md
- 不新增 tech-spec.md

**方案 B：可选第 6 文件（需修改现行约定）**
- 复杂任务（estimated_hours > 4）可选生成 tech-spec.md
- 需在 01-任务包规范.md 中明确"5 件套 + 可选 tech-spec.md"
- 需定义 tech-spec.md 与 5 件套的信息边界

**待拍板字段**（如采纳方案 B）：
```yaml
# contract.yaml 新增字段
planning_required: true  # 是否需要技术方案
planning_status: pending  # pending/approved/rejected
tech_spec_path: "tech-spec.md"
estimated_hours: 6  # 预估工时

# state.yaml 状态值调整
status: drafting  # 需确认是否与现行 9 个状态值兼容
# 现行状态：drafting/ready/running/waiting_gate/waiting_assist/verifying/done/paused/ready_to_resume
```

**状态机门禁增强**（如采纳方案 B）：
```powershell
# 在任务执行前检查状态
$state = Get-Content "$taskDir/state.yaml" | ConvertFrom-Yaml

if ($state.status -in @('drafting', 'planning')) {
    # 检查是否有代码文件修改
    $changedFiles = git diff --name-only
    $codeFiles = $changedFiles | Where-Object { 
        $_ -match '\.(ts|js|py|go|rs|java|cs|cpp|c|h)$' 
    }
    
    if ($codeFiles.Count -gt 0) {
        throw @"
❌ 状态机门禁拦截：当前任务状态为 $($state.status)，禁止修改代码文件。

检测到以下代码文件被修改：
$($codeFiles -join "`n")

请先完成以下步骤：
1. 完成 tech-spec.md 技术方案文档
2. 将 planning_status 改为 'approved'
3. 将 status 改为 'running'

然后才能开始编写代码。
"@
    }
}
```

**预期效果**（如采纳）：
- 方向性错误减少 90%
- 返工率降低 60%
- 代码质量提升 40%

**实施成本**：
- 方案 A：0（已有字段足够）
- 方案 B：2-3 小时（修改规范 + 门禁脚本）

---

### 🔶 待拍板 2：可视化输出规范

**核心问题**：
- VibeCoding 提议在 tech-spec.md 中强制使用表格和 Mermaid 流程图
- 如采纳"待拍板 1 方案 A"，则此要求应落在 decision-log.md 或 result.md
- 如采纳"待拍板 1 方案 B"，则需定义 tech-spec.md 模板

**方案 A：在现有 5 件套内增强可视化**
- decision-log.md 记录改动文件清单时，使用 Markdown 表格
- result.md 记录验证结果时，使用 Mermaid 流程图（可选）
- 不强制，但在模板中提供示例

**方案 B：新增 tech-spec.md 模板**（依赖"待拍板 1 方案 B"）
- 定义完整 tech-spec.md 模板（见下方示例）
- 门禁脚本检查表格和 Mermaid 的存在性

**tech-spec.md 模板示例**（如采纳方案 B）：
````markdown
# 技术方案

## 1. 用户场景
[从 contract.yaml 自动填充]

## 2. 改动文件清单（必须用表格）
| 文件路径 | 改动类型 | 改动原因 | 风险等级 |
|---------|---------|---------|---------|
| src/middleware/rate-limit.ts | 新增 | IP 限流逻辑 | 低 |
| src/routes/image.ts | 修改 | 调用限流检查 | 中 |

## 3. 执行流程（建议用 Mermaid）
\`\`\`mermaid
graph TD
    A[用户请求生图] --> B{检查 IP 限流}
    B -->|未超限| C[生成图片]
    B -->|已超限| D[返回 429 错误]
\`\`\`

## 4. 核心代码逻辑（伪代码）
\`\`\`typescript
// 限流中间件
async function rateLimitMiddleware(req, res, next) {
  const ipHash = hashIP(req.ip)
  const count = await redis.get(\`ip:\${ipHash}\`)
  
  if (count >= 10) {
    return res.status(429).json({ error: '请稍后再试' })
  }
  
  await redis.incr(\`ip:\${ipHash}\`, { ttl: 3600 })
  next()
}
\`\`\`

## 5. 风险评估
- 风险1：Redis 故障导致限流失效
  - 应对：降级到内存限流
- 风险2：IP 伪造绕过限流
  - 应对：结合设备指纹二次验证

## 6. 验收标准
- [ ] 未登录用户每小时最多生成 10 张图片
- [ ] 超过限制后返回 429 状态码
- [ ] 1 小时后计数器自动重置
- [ ] 单元测试覆盖率 ≥ 80%
````

**门禁脚本正则检查**（如采纳方案 B）：
```powershell
# 在 invoke-public-commit-governance-gate.ps1 中新增
if (Test-Path "$taskDir/tech-spec.md") {
    $content = Get-Content "$taskDir/tech-spec.md" -Raw
    
    # 检查 Markdown 表格
    $hasTable = $content | Select-String -Pattern '^\|.*\|.*\|' -Quiet
    if (-not $hasTable) {
        throw "❌ tech-spec.md 缺少 Markdown 表格（改动文件清单）"
    }
    
    # 检查 Mermaid 流程图（建议项，不强制）
    $hasMermaid = $content | Select-String -Pattern '```mermaid' -Quiet
    if (-not $hasMermaid) {
        Write-Warning "⚠️ tech-spec.md 建议包含 Mermaid 流程图"
    }
    
    # 检查必需章节
    $requiredSections = @(
        '## 改动文件清单',
        '## 风险评估',
        '## 验收标准'
    )
    
    foreach ($section in $requiredSections) {
        if ($content -notmatch [regex]::Escape($section)) {
            throw "❌ tech-spec.md 缺少必需章节：$section"
        }
    }
}
```

**预期效果**（如采纳）：
- 沟通效率提升 30%
- 歧义减少 50%

**实施成本**：
- 方案 A：0（现有文件足够）
- 方案 B：1-2 小时（模板 + 门禁脚本）

---

## 四、不采纳的部分

### ❌ 多 AI 交叉评审
- **原因**：丞相模式强调自动化门禁，不是人工多 AI 评审
- **替代方案**：强化 invoke-public-commit-governance-gate.ps1 自动检查

### ❌ 微决策驱动
- **原因**：与自动化目标相反，增加人工介入
- **替代方案**：保持自动化方向

### ❌ 主笔-评审分工
- **原因**：人工分工降低效率
- **当前决策**：暂不把精力砸到独立面板、多 Agent 大系统、跨 harness 兼容（见 34-丞相模式ECC功能核实总结.md:44、34-丞相模式ECC功能核实总结.md:56）
- **远期观察项**：Agent 自动编排（非近期替代方案）

---

## 五、拍板决策点

### 核心问题
是否允许在任务包中新增第 6 个文件（tech-spec.md）？

### 决策影响
- **如选方案 A（严格 5 件套）**：
  - 符合现行约定，零风险
  - 规划信息继续落在 contract.yaml 和 decision-log.md
  - 可视化要求降级为"建议项"
  
- **如选方案 B（可选第 6 文件）**：
  - 需修改 01-任务包规范.md
  - 需定义 tech-spec.md 与 5 件套的信息边界
  - 需开发状态机门禁和正则检查
  - 实施成本：2-3 小时

### 建议
优先采纳方案 A（严格 5 件套），理由：
1. 当前 contract.yaml 的 planning_hint 和 technical_approach 已足够承载规划信息
2. decision-log.md 可承载改动文件清单和风险评估
3. 零实施成本，零风险
4. 如后续验证不足，再考虑升级到方案 B

---

## 六、与现行约定的兼容性

### ✅ 完全兼容
- 使用现行任务包结构（.codex/chancellor/tasks/）
- 使用现行 PowerShell 脚本体系
- 符合反屎山总纲理念
- 不引入新的依赖或工具

### ⚠️ 待拍板项
- tech-spec.md 是否作为第 6 个文件（与现行"固定 5 个文件"冲突）
- planning_required / planning_status / estimated_hours 字段是否加入现行契约
- status 状态值是否需要调整（现行 9 个状态 vs 提议 4 个状态）

---

## 七、实施路径

### 路径 A：最小化实施（推荐）
1. ✅ 已完成：contract.yaml 模板增强（user_scenario、technical_approach）
2. 待做：在 decision-log.md 模板中增加"改动文件清单"表格示例
3. 待做：在 result.md 模板中增加 Mermaid 流程图示例（可选）
4. 实施成本：0.5 小时

### 路径 B：完整实施（需拍板）
1. ✅ 已完成：contract.yaml 模板增强
2. 待做：修改 01-任务包规范.md，允许可选 tech-spec.md
3. 待做：定义 tech-spec.md 模板
4. 待做：开发状态机门禁（drafting/planning 状态屏蔽代码编辑）
5. 待做：开发 tech-spec.md 正则检查（表格、Mermaid、必需章节）
6. 待做：修改 create-task-package.ps1，支持自动生成 tech-spec.md
7. 实施成本：2-3 小时

---

**下一步行动**：
1. 拍板是否采纳 tech-spec.md（方案 A vs 方案 B）
2. 如选方案 A，完成 decision-log.md 和 result.md 模板微调（0.5 小时）
3. 如选方案 B，按路径 B 完整实施（2-3 小时）
