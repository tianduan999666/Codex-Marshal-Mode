# V4 Target 主线真源顺序回归补强记录

时间：2026-03-29 19:57:31
任务：第四十七刀（Target 主线真源顺序回归补强）

## 动作

1. 复盘 `Target 主线真源` 校验链路，确认 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 已把 `docs/40-执行/12-V4-Target-实施计划.md` 作为 Target 主线入口的单一真源。
2. 检查 `.codex/chancellor/test-public-commit-governance-gate.ps1` 后确认：当前已覆盖边界缺项与中项缺失，但仍缺少“真源内部顺序漂移必须失败”的单独负例。
3. 新增 `block-target-mainline-source-order-drift`：仅交换 `docs/30-方案/07-V4-规划策略候选规范.md` 与 `docs/30-方案/08-V4-治理审计候选规范.md` 在 `Target 主线真源` 内的顺序，要求公开提交治理门禁失败。
4. 保留现有 `allow-reading-order-source-sync` 联动用例，继续允许“真源与所有公开入口同步改序”的受控演练场景。
5. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认新增负例通过且未破坏现有矩阵。

## 结果

- `Target 主线真源` 的源头顺序漂移现在有独立回归保护。
- 如果未来误把 `07-V4-规划策略候选规范.md` 与 `08-V4-治理审计候选规范.md` 的先后顺序交换，门禁会自动阻断。
- 现在 Target 链路同时具备“缺项必拦”“单点顺序漂移必拦”“全链路同步改序可控放行”三层保护。

## 理由

- `Target 主线真源` 是 README、docs/README 与现行总览等公开入口的上游单一真源；源头顺序一旦漂移，公开口径会整体跟着错。
- 先补源头顺序负例，比继续堆新规则更符合 V8 的长期稳定与高复利原则。

## 下一步

1. 暂存本轮测试与归档改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描其它仍缺“源头顺序漂移负例”的治理入口。
