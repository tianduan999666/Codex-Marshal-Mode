# V4 核心治理规则真源顺序回归补强记录

时间：2026-03-29 20:05:49
任务：第四十八刀（核心治理规则真源顺序回归补强）

## 动作

1. 复盘 `核心治理规则入口真源` 现有门禁，确认此前只覆盖区块缺失与必需路径缺失，尚未对真源内部顺序漂移做硬阻断。
2. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增 `block-core-rule-source-order-drift`，交换 `docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md` 与 `docs/reference/02-仓库卫生与命名规范.md` 后要求门禁失败。
3. 首轮回归暴露真实缺口：门禁脚本会把 `本地安全提交流程` 当前内容直接当作 canonical 顺序来源，导致“文件自己和自己比”无法抓到内部改序。
4. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 为 `核心治理规则入口真源` 接入通用顺序检查器，并改为使用显式必需顺序列表，只锁定 6 个必须稳定的核心治理入口，不误伤可选补充项。
5. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认新增负例命中且总矩阵通过。

## 结果

- `核心治理规则入口真源` 现在具备源头顺序漂移硬门禁。
- 如果未来误把 `docs/reference/01` 与 `docs/reference/02` 在真源中的先后顺序交换，门禁会自动阻断。
- 这条链路现在同时具备：区块缺失阻断、必需路径缺失阻断、源头顺序漂移阻断。

## 理由

- 这轮不是单纯补测试，而是先用负例打出真实缺口，再把门禁本体补到能自动拦截，符合 V8 的“短期更难、长期更稳”。
- `本地安全提交流程` 是核心治理规则入口的单一真源；若这里顺序漂移无人值守，公开口径会从最上游开始失真。

## 下一步

1. 暂存本轮脚本与归档改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描其它仍缺“源头顺序漂移负例”的真源入口，优先看是否还有类似“canonical 来自自身、未显式定序”的点。
