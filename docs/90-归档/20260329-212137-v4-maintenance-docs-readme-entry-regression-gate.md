# V4 docs README 维护层入口顺序回归补强记录

时间：2026-03-29 21:21:37
任务：第五十八刀（docs README 维护层入口顺序回归补强）

## 动作

1. 复盘 `publicMaintenanceEntryChecks` 的公开口径门禁，确认 `docs/README.md` 已在维护层主线入口的门禁覆盖范围内，但此前缺少独立顺序负例回归。
2. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增 `block-public-maintenance-entry-order-drift-docs-readme`。
3. 该回归只交换 `docs/README.md` 中两条维护层主线入口的先后顺序：
   - `40-执行/19-多 gate 与多异常并存处理规则.md`
   - `40-执行/20-复杂并存汇报骨架模板.md`
4. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，验证“只改 docs/README 维护层入口顺序”会被门禁单独阻断。

## 结果

- `docs/README 维护层主线入口` 现在具备独立负例回归保护。
- 以后若有人只改 `docs/README.md` 里 `19` / `20` 两条入口顺序，而未同步维护层真源链路，测试会直接失败。
- 本轮继续保持最小切片：不改门禁本体，只补既有硬规则的独立自证。

## 理由

- `docs/README.md` 是公开文档高频入口，维护层主线口径必须和 `README.md`、`现行标准件总览` 一样具备单点回归保护。
- 已有门禁能力时优先补负例回归，长期收益最高，且不会引入目录或结构风险。

## 下一步

1. 执行暂存区治理门禁，确认本轮改动满足公开提交规则。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描维护层补充入口中“已实现但仍缺独立负例回归”的最小缺口。