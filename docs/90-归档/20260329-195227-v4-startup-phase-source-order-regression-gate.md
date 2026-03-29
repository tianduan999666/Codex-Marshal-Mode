# V4 启动阶段真源顺序回归补强记录

时间：2026-03-29 19:52:27
任务：第四十六刀（启动阶段真源顺序回归补强）

## 动作

1. 复盘 `启动阶段真源` 校验链路，确认 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 已把 `docs/00-导航/01-V4-重启导读.md` 作为 `README.md` 与 `docs/README.md` 的启动阶段入口真源。
2. 检查 `.codex/chancellor/test-public-commit-governance-gate.ps1` 后确认：当前只有“边界缺项”负例，仍缺少“真源内部顺序漂移必须失败”的显式回归。
3. 在测试脚本中新增 `block-startup-phase-source-order-drift`：交换 `docs/20-决策/01-V4-重启ADR.md` 与 `docs/10-输入材料/01-旧仓必需资产清单.md` 后，要求公开提交治理门禁失败。
4. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认新增回归通过且未破坏既有门禁测试矩阵。

## 结果

- `启动阶段真源` 的顺序漂移现在有独立负例回归保护。
- 如果未来误把 `重启ADR` 与 `旧仓必需资产清单` 的先后顺序交换，门禁会自动阻断。
- 这使启动阶段链路从“缺项必拦”进一步升级为“顺序漂移也必拦”。

## 理由

- 启动阶段真源是公开入口顺序的上游单一真源；上游顺序若漂移，下游公开口径会整体失真。
- 先补源头顺序回归，比继续堆新规则更符合“短期更难、长期更稳”的 V8 原则。

## 下一步

1. 暂存本轮测试与归档改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描其它已实现但仍缺“源头顺序漂移”负例回归的门禁点。
