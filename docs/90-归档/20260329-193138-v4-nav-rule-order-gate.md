# V4 现行总览规则入口顺序硬门禁记录

时间：2026-03-29 19:31:38
任务：第四十三刀（现行总览规则入口顺序硬门禁）

## 动作

1. 复盘 `docs/reference` 相关剩余薄弱点，确认 `docs/00-导航/02-现行标准件总览.md` 中 `docs/reference/01` 与 `docs/reference/02` 的顺序漂移仍会静默漏过。
2. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 新增现行总览专用规则顺序检查，只读取 `### 入口与背景` 区块中的 `docs/reference/*.md` 引用。
3. 将顺序硬门禁严格收窄为 `docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md` 在前、`docs/reference/02-仓库卫生与命名规范.md` 在后，避免误把 README / docs/README / 其他规则入口布局强拉成同一排序。
4. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增 `block-public-rule-entry-order-drift` 回归，交换现行总览中的两条 `docs/reference` 规则入口后要求门禁失败。
5. 同步更新 `.codex/chancellor/README.md`、`docs/40-执行/10-本地安全提交流程.md`、`docs/30-方案/08-V4-治理审计候选规范.md`，明确当前新增的是“现行总览规则入口顺序校验”。

## 结果

- 现行总览中的 `docs/reference/01` / `docs/reference/02` 现在已具备自动顺序门禁。
- 交换这两条规则入口后，门禁会直接失败。
- 本轮保持最小切口，没有强行重排 `README.md` 与 `docs/README.md` 的整体规则入口布局。
- 总回归与当前工作集门禁均已通过。

## 理由

- 当前最真实的漏口只发生在现行总览，因此最小修补应只落在现行总览，不应把整仓不同文档的展示顺序无差别绑死。
- 这样既补上自动硬强制，又不引入额外的大范围口径重排成本。

## 下一步

1. 暂存本轮公开安全改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描 `docs/reference` 相关剩余未下沉为可执行断言的入口链路。