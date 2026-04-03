# V4 README 维护层补充入口顺序回归补强记录

时间：2026-03-29 21:27:09
任务：第五十九刀（README 维护层补充入口顺序回归补强）

## 动作

1. 复盘 `publicMaintenanceCapabilityOrderEntryChecks` 的公开口径门禁，确认门禁本体已覆盖 `README.md` 与 `docs/README.md` 两处维护层补充入口顺序。
2. 检查 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认此前只有 `README + docs/README` 联合负例，仍缺 `README.md` 单点顺序回归。
3. 新增 `block-public-maintenance-capability-entry-order-drift-readme`，只交换 `README.md` 中两条维护层补充入口顺序：
   - `docs/30-方案/08-V4-治理审计候选规范.md`
   - `docs/40-执行/21-关键配置来源与漂移复核模板.md`
4. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，验证“只改 README 补充入口顺序”会被门禁单独阻断。

## 结果

- `README 维护层补充入口` 现在具备独立负例回归保护。
- 以后若有人只改 `README.md` 中治理候选规范与关键配置模板的公开顺序，而未同步真源链路，测试会直接失败。
- 本轮继续保持最小切片：不改门禁本体，只补既有硬规则的单点自证。

## 理由

- 维护层补充入口已是硬门禁的一部分；单点回归补齐后，能更快定位到底是 `README` 口径漂移还是联动链路整体失真。
- 已有能力优先补负例回归，长期复利最高，且风险最低。

## 下一步

1. 执行暂存区治理门禁，确认本轮改动满足公开提交规则。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续补 `docs/README 维护层补充入口` 的独立顺序负例回归。