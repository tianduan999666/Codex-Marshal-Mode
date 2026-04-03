# V4 重启导读核心入口真源完整性硬门禁记录

时间：2026-03-29 19:17:46
任务：第四十二刀（重启导读核心入口真源完整性硬门禁）

## 动作

1. 复盘 `docs/reference` 相关剩余薄弱点，确认 `docs/00-导航/01-V4-重启导读.md` 的 `## 先看什么` 目前仍作为 `README.md` 与 `docs/README.md` 的重启导读核心入口真源，但删除其中 `docs/reference/02-仓库卫生与命名规范.md` 时，门禁仍会静默通过。
2. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 新增 `Get-CanonicalRestartGuideEntryPaths`，把重启导读核心入口真源抽成专用 helper。
3. 给该 helper 补入必需路径集合断言，强制要求重启导读核心入口真源至少保留：现行总览、重启 ADR、旧仓资产清单、目录蓝图、目录锁定、MVP 边界、任务包规范、任务包模板、面板入口验收、`docs/reference/01`、`docs/reference/02`。
4. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增 `block-restart-guide-source-middle-missing` 回归，删除 `11. docs/reference/02-仓库卫生与命名规范.md` 后要求门禁失败。
5. 同步更新 `.codex/chancellor/README.md`、`docs/40-执行/10-本地安全提交流程.md`、`docs/30-方案/08-V4-治理审计候选规范.md`，明确重启导读核心入口真源自身缺少关键项也会被自动阻断。

## 结果

- `docs/reference` 在重启导读主入口链路里的两条核心规则文档，现在不再能从真源区块中静默消失。
- 删除 `docs/reference/02-仓库卫生与命名规范.md` 后，门禁会直接失败。
- 重启导读核心入口顺序仍由 `## 先看什么` 真源自身定义；本轮只补“关键项不能缩水”的硬门禁。
- 总回归与当前工作集门禁均已通过。

## 理由

- 仅有公开首页对重启导读的反向校验，不足以阻止重启导读真源自己缩水。
- 把重启导读核心入口真源也纳入必需集合断言，才能让 `docs/reference` 相关高优先级规则在主导航链路上实现真正自动强制。

## 下一步

1. 暂存本轮公开安全改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描 `docs/reference` 相关、但尚未具备真源完整性硬门禁的公开口径链路。