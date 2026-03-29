# V4 AGENTS 核心约束顺序回归补强记录

时间：2026-03-29 19:46:58
任务：第四十五刀（AGENTS 核心约束顺序回归补强）

## 动作

1. 复盘上一轮已落地的根 `AGENTS.md` 核心约束入口顺序门禁，确认实现已存在，但测试层仍缺少“顺序漂移必须失败”的显式回归保护。
2. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 增加对根 `AGENTS.md` 两条核心约束入口的前置定位，统一校验 `docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md` 与 `docs/30-方案/02-V4-目录锁定清单.md` 同时存在。
3. 新增 `block-agents-core-rule-entry-order-drift` 回归：交换两条 AGENTS 核心约束入口后，要求公开提交治理门禁显式失败。
4. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1` 与当前工作集门禁，确认新增回归不会破坏现行治理链路。

## 结果

- 根 `AGENTS.md` 的核心约束顺序漂移现在有独立回归保护。
- 即使未来有人误改为“目录锁定在前、总纲在后”，门禁也会自动阻断。
- 当前总回归与当前工作集门禁均已通过。

## 理由

- 已有实现但缺少回归时，后续重构最容易把硬门禁悄悄改坏；先补测试，比继续加新规则更稳。
- 根 `AGENTS.md` 是会话级强约束入口，顺序漂移若无人值守，会直接削弱“自动遵循”的第一层保障。

## 下一步

1. 暂存本轮测试与归档改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描 `docs/reference` 相关 live 入口里“已有实现但缺回归”或“仍未下沉为硬门禁”的点。
