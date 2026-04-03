# V4 维护层补充能力真源顺序补强记录

时间：2026-03-29 20:23:38
任务：第五十刀（维护层补充能力真源顺序补强）

## 动作

1. 复盘 `docs/40-执行/13-维护层总入口.md` 的 `当前维护层能力` 区块，确认此前只覆盖“能力项缺失”负例，尚未对源头内部相对顺序漂移做硬阻断。
2. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增 `block-maintenance-capability-source-order-drift`，交换：
   - `docs/30-方案/08-V4-治理审计候选规范.md`
   - `docs/40-执行/21-关键配置来源与漂移复核模板.md`
   后要求门禁失败。
3. 首轮回归暴露真实缺口：`Get-CanonicalMaintenanceCapabilityDocPaths` 只把能力文档当集合消费，没有显式定序，因此单纯交换顺序时会静默通过。
4. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 为该真源增加关键相对顺序断言，只锁定“治理审计复核 → 配置漂移复核模板”这条高价值顺序，不打破既有 `allow-exec-standard-source-sync` 同步演练能力。
5. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认新增负例命中且总矩阵通过。

## 结果

- `当前维护层能力` 真源现在具备关键相对顺序硬门禁。
- 如果未来误把治理审计复核与配置漂移复核模板的先后顺序交换，门禁会自动阻断。
- 同时保留了执行区现行标准件整链路同步改源时的受控放行能力。

## 理由

- 这刀的目标不是把整段能力列表完全锁死，而是在不牺牲既有同步演练能力的前提下，把真正高价值的治理顺序钉死。
- 这符合 V8 的原则：短期多想一步，长期更稳、更轻松、更少返工。

## 下一步

1. 暂存本轮脚本与归档改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描其它仍缺“关键相对顺序断言”的真源入口。
