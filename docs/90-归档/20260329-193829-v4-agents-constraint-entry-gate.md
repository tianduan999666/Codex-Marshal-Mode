# V4 AGENTS 核心约束入口硬门禁记录

时间：2026-03-29 19:38:29
任务：第四十四刀（AGENTS 核心约束入口硬门禁）

## 动作

1. 复盘 `docs/reference` 相关剩余入口链路，确认根 `AGENTS.md` 里的核心约束入口仍未纳入自动门禁；删除其中对 `docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md` 的引用时，公开提交治理门禁会静默通过。
2. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 新增根 `AGENTS.md` 专用入口校验，聚焦 `docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md` 与 `docs/30-方案/02-V4-目录锁定清单.md` 两条核心约束入口。
3. 让门禁对根 `AGENTS.md` 执行存在性与相对顺序校验，确保未来会话启动时仍会自动拿到“总纲 + 目录锁定”这两个最高优先级约束入口。
4. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增 `block-agents-core-rule-entry-missing` 回归，删除 AGENTS 中总纲入口后要求门禁失败。
5. 同步更新 `.codex/chancellor/README.md`、`docs/40-执行/10-本地安全提交流程.md`、`docs/30-方案/08-V4-治理审计候选规范.md`，明确根 `AGENTS.md` 核心约束入口也在自动门禁覆盖内。

## 结果

- 根 `AGENTS.md` 里的总纲/目录锁定入口现在已纳入自动硬门禁。
- 删除 AGENTS 中对 `docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md` 的引用时，门禁会自动失败。
- 这样一来，`docs/reference` 的核心治理入口不仅在公开文档链路里被强制，也在会话启动的根约束入口上被强制。
- 总回归与当前工作集门禁均已通过。

## 理由

- 根 `AGENTS.md` 是 Codex 会话启动时最直接的约束入口之一；如果这里漂移，后续自动遵循能力会在第一层就变弱。
- 把 AGENTS 入口也纳入门禁，是把“自动强制”从公开文档面继续推进到会话入口面，长期收益很高。

## 下一步

1. 暂存本轮公开安全改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描 `docs/reference` 相关剩余未下沉为可执行断言的入口或会话约束链路。