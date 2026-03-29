# V4 核心治理规则真源完整性硬门禁记录

时间：2026-03-29 16:33:04
任务：第四十一刀（核心治理规则真源完整性硬门禁）

## 动作

1. 复盘 `docs/reference` 相关公开口径链路，确认 `docs/40-执行/10-本地安全提交流程.md` 的“核心治理规则入口真源”区块此前只校验“能解析到至少一条”，删除其中 `docs/reference/02-仓库卫生与命名规范.md` 这类关键项时会静默漏过。
2. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 新增 `Get-CanonicalCoreGovernanceRuleSourcePaths`，把核心治理规则入口真源统一收口为专用 helper。
3. 给该 helper 补入必需路径集合断言，强制要求核心治理规则真源至少保留：`docs/reference/01`、`docs/reference/02`、`docs/30-方案/02`、`docs/30-方案/08`、`docs/40-执行/10`、`docs/40-执行/14`。
4. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增 `block-core-rule-source-middle-missing` 回归，删除 `docs/reference/02-仓库卫生与命名规范.md` 后要求门禁失败。
5. 调整 `allow-core-rule-source-sync` 用例边界，只验证“非必需扩编项从规则真源中收缩时可通过”，避免误碰执行区与维护层自己的硬约束。
6. 同步更新 `.codex/chancellor/README.md`、`docs/40-执行/10-本地安全提交流程.md`、`docs/30-方案/08-V4-治理审计候选规范.md`，明确核心治理规则入口真源自身缺项也会被自动阻断。

## 结果

- `docs/reference` 相关两条核心规则文档现在已真正进入自动硬门禁，不再只是“入口被引用”。
- 删除核心治理规则真源中的 `docs/reference/02-仓库卫生与命名规范.md` 时，门禁会自动失败。
- 核心治理规则真源仍可保留非必需扩编项；只要不触碰必需集合，门禁不会误报。
- 总回归与当前工作集门禁均已通过。

## 理由

- 仅靠“公开入口缺不缺”不能保证真源自己不缩水；真源一旦缩水，公开口径会整体跟着变薄且无人告警。
- 把 `docs/reference` 关键规则文件提升为真源必需集合，才算真正做到“无需人工提醒”的硬强制。

## 下一步

1. 暂存本轮公开安全改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描仍属于 `docs/reference` 约束、但尚未落为可执行断言的公开口径一致性规则。