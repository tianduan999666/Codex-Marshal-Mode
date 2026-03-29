# V4 维护层补充入口公开顺序硬门禁记录

时间：2026-03-29 20:48:58
任务：第五十三刀（维护层补充入口公开顺序硬门禁）

## 动作

1. 复盘 `README.md` 与 `docs/README.md` 的维护层补充入口链路，确认此前只覆盖“缺项 / 额外项”校验，尚未对公开口径顺序漂移做硬阻断。
2. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增 `block-public-maintenance-capability-entry-order-drift`，同步交换：
   - `docs/30-方案/08-V4-治理审计候选规范.md`
   - `docs/40-执行/21-关键配置来源与漂移复核模板.md`
   在 `README.md` 与 `docs/README.md` 中的顺序，要求门禁失败。
3. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 为维护层补充入口新增公开顺序检查链路，复用现有 `Get-OrderedEntryViolationMessages`，只锁定这组关键相对顺序，不把整段维护层补充入口完全冻结。
4. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认新增负例命中且总矩阵通过。

## 结果

- `README.md` 与 `docs/README.md` 的维护层补充入口现在具备关键顺序硬门禁。
- 如果未来误把治理审计候选规范与配置漂移复核模板的先后顺序交换，门禁会自动阻断。
- 现在这条链路已形成“真源关键顺序 + 公开入口关键顺序”双层约束。

## 理由

- 上一刀已锁定源头真源顺序；若公开口径仍不锁顺序，仍会发生“源头正确、首页口径漂移”的长期维护问题。
- 这刀只锁关键相对顺序，收益高、扰动小，符合 V8 的长期秩序原则。

## 下一步

1. 暂存本轮脚本与归档改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描剩余仍缺“关键相对顺序断言”的公开入口链路。
