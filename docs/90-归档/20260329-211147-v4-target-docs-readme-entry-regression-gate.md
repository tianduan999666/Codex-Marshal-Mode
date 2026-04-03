# V4 docs README Target 入口顺序回归补强记录

时间：2026-03-29 21:11:47
任务：第五十六刀（docs README Target 入口顺序回归补强）

## 动作

1. 复盘 `publicTargetEntryChecks` 的公开口径门禁，确认 `docs/README.md` 已在门禁本体覆盖范围内，但此前缺少独立顺序负例回归。
2. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增 `block-public-target-entry-order-drift-docs-readme`。
3. 该回归只交换 `docs/README.md` 中两条 Target 主线入口的先后顺序：
   - `30-方案/07-V4-规划策略候选规范.md`
   - `30-方案/08-V4-治理审计候选规范.md`
4. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，验证“只改 docs/README 入口顺序”会被门禁单独阻断。

## 结果

- `docs/README Target 主线入口` 现在具备独立负例回归保护。
- 以后若有人只改 `docs/README.md` 的规划/治理入口顺序，而未同步整条主线，测试会直接失败。
- 本轮仍然不改门禁本体，只补既有能力的独立自证，继续强化公开口径一致性的硬约束。

## 理由

- `docs/README.md` 是公开文档层的高频入口，必须和 `README.md`、`现行标准件总览` 一样具备单点回归保护。
- 已有门禁能力时优先补负例回归，长期收益最高，且不会引入额外结构风险。

## 下一步

1. 执行暂存区治理门禁，确认本轮改动满足公开提交规则。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描其余“门禁已实现但仍缺独立负例回归”的点。