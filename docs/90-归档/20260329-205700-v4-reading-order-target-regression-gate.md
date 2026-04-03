# V4 现行总览阅读顺序 Target 回归补强记录

时间：2026-03-29 20:57:00
任务：第五十四刀（现行总览阅读顺序 Target 回归补强）

## 动作

1. 复盘 `现行总览阅读顺序 Target 主线` 的门禁链路，确认 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 已存在对应顺序检查，但 `.codex/chancellor/test-public-commit-governance-gate.ps1` 仍缺少独立负例回归。
2. 在测试脚本中新增 `block-reading-order-target-order-drift`，只交换 `docs/00-导航/02-现行标准件总览.md` 的阅读顺序区块里：
   - `docs/30-方案/07-V4-规划策略候选规范.md`
   - `docs/30-方案/08-V4-治理审计候选规范.md`
   的先后顺序。
3. 让该负例只改阅读顺序区，不改 Target 真源、不改 README / docs/README，验证“现行总览自身阅读顺序漂移”会被单独阻断。
4. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认新增回归通过且不需要再改门禁本体。

## 结果

- `现行总览阅读顺序 Target 主线` 现在有独立负例回归保护。
- 以后若有人只改 `docs/00-导航/02-现行标准件总览.md` 的 Target 阅读顺序，而未同步整体链路，测试会直接把问题打出来。
- 这刀属于“已有实现、缺回归”的最小补口，风险低、复利高。

## 理由

- 门禁本体已具备能力时，优先补独立负例回归，可以最低成本防止后续重构把已有硬门禁悄悄改坏。
- 阅读顺序属于公开口径的重要组成部分；源头和首页都锁了后，现行总览这层也要有单独自证。

## 下一步

1. 暂存本轮测试与归档改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描其余“门禁已实现但仍缺独立负例回归”的点。
