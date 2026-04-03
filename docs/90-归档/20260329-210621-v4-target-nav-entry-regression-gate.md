# V4 现行总览 Target 入口顺序回归补强记录

时间：2026-03-29 21:06:21
任务：第五十五刀（现行总览 Target 入口顺序回归补强）

## 动作

1. 复盘 `publicTargetEntryChecks` 的公开口径门禁，确认门禁本体已覆盖三处 Target 主线入口：`README.md`、`docs/README.md`、`docs/00-导航/02-现行标准件总览.md`。
2. 检查 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认此前独立顺序负例只覆盖 `README.md`，总览背景入口仍缺单点回归。
3. 新增 `block-public-target-entry-order-drift-nav-overview`，只交换 `docs/00-导航/02-现行标准件总览.md` 中 Target 主线入口背景区的两条顺序：
   - `docs/30-方案/07-V4-规划策略候选规范.md`
   - `docs/30-方案/08-V4-治理审计候选规范.md`
4. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，验证“只改总览背景入口顺序”会被门禁单独阻断。

## 结果

- `现行标准件总览 Target 主线入口` 现在具备独立负例回归保护。
- 以后若有人只改总览背景入口中规划/治理两条的公开顺序，而未同步真源链路，测试会直接报错。
- 本轮不改门禁本体，只补回归，风险低且能继续强化“公开口径一致性”的硬约束。

## 理由

- 已有硬门禁能力时，优先补独立负例回归，最能以小成本防止后续重构把既有能力悄悄做虚。
- 总览背景入口属于公开阅读第一层，和阅读顺序区分开锁，能把漂移定位得更细。

## 下一步

1. 执行暂存区治理门禁，确认本轮改动满足公开提交规则。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续补 `docs/README Target 主线入口` 的独立顺序负例回归。