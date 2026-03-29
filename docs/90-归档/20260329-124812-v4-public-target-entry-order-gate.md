# V4 Target 主线入口顺序门禁记录

时间：2026-03-29 12:48:12
任务：v4-trial-024-public-target-entry-order-gate

## 动作

1. 识别下一层公开口径瓶颈是 `README.md`、`docs/README.md` 与现行总览虽已挂出 Target 主线文档，但还没有自动拦截“漏挂”和“顺序错位”。
2. 先扩 `.codex/chancellor/test-public-commit-governance-gate.ps1`，新增“删掉 docs/README 的 Target 蓝图入口时失败”和“调换 README 中规划/治理顺序时失败”两类场景。
3. 扩展 `.codex/chancellor/invoke-public-commit-governance-gate.ps1`，把三处公开入口中七个关键主线文档的存在性与顺序纳入校验。
4. 同步更新 `.codex/chancellor/README.md`、`docs/40-执行/10-本地安全提交流程.md`、`docs/30-方案/08-V4-治理审计候选规范.md` 的现行说明。

## 结果

- 当前自动门禁已从“执行区入口同步 / 关键规则入口同步”继续扩到“Target 主线关键入口存在性与顺序同步”。
- 当前仓现状通过新门禁。
- 人为删掉 `docs/README.md` 的 `30-方案/04-V4-Target-蓝图.md` 或调乱 `README.md` 中 `07/08` 顺序时，门禁会自动失败。

## 理由

- 主线入口顺序本身就是公开口径的一部分；只校验存在，不校验顺序，长期仍会漂。
- 这一步仍在现有门禁内完成，不新增目录、不引入新依赖，长期收益高于继续堆提醒文档。

## 下一步

1. 暂存本轮公开安全改动并执行提交。
2. 完成 `pull --rebase origin main` 与 `push origin main`，确认 `pre-push` 自动门禁通过。
3. 回写任务包状态并清空活动指针。
