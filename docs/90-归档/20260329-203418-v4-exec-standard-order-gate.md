# V4 执行区现行标准件顺序硬门禁记录

时间：2026-03-29 20:34:18
任务：第五十一刀（执行区现行标准件顺序硬门禁）

## 动作

1. 复盘 `Get-CanonicalExecStandardDocNames` 与公开入口消费链路，确认此前只校验“是否存在/是否有额外项”，没有硬校验顺序，且 helper 会把结果直接 `Sort-Object -Unique`，天然抹平源头顺序信息。
2. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增两条负例：
   - `block-exec-standard-source-order-drift`
   - `block-public-exec-entry-order-drift`
3. 首轮回归打出真实缺口：
   - 执行区真源内部把 `11-任务包半自动起包.md` 与 `12-V4-Target-实施计划.md` 交换后，门禁静默通过。
   - `README.md` 公开入口把这两项交换后，门禁也静默通过。
4. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 完成根因修复：
   - `Get-CanonicalExecStandardDocNames` 改为保留原始出现顺序
   - `Get-MatchedExecStandardDocNamesFromFile` 改为保留入口出现顺序
   - 新增执行区公开入口顺序校验链路
   - 仅锁定关键相对顺序 `11-任务包半自动起包.md` → `12-V4-Target-实施计划.md`，不打破既有 `allow-exec-standard-source-sync` 同步删项演练能力
5. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认新增负例命中且总矩阵通过。

## 结果

- 执行区真源内部顺序漂移现在会被自动阻断。
- `README.md`、`docs/README.md`、`docs/00-导航/02-现行标准件总览.md` 的执行区入口顺序漂移现在会被自动阻断。
- 这条链路现在从“只验集合”升级为“关键顺序也验”，但仍保留对同步删项演练的兼容性。

## 理由

- 执行区现行标准件是公开口径同步的核心上游之一；若这里顺序漂移而门禁无感知，后续公开入口会整体失真。
- 这轮选择只硬锁关键顺序，不把整段标准件列表完全冻结，兼顾了长期秩序与现有可演练能力。

## 下一步

1. 暂存本轮脚本与归档改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描仍缺“关键相对顺序断言”的真源或公开入口链路。
