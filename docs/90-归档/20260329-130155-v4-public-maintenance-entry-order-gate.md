# V4 维护层主线入口顺序门禁记录

时间：2026-03-29 13:01:55
任务：v4-trial-025-public-maintenance-entry-order-gate

## 动作

1. 识别下一层公开口径瓶颈是 `README.md`、`docs/README.md` 与现行总览虽已挂出维护层 13-21 文档，但还没有自动拦截“漏挂”和“顺序错位”。
2. 先扩 `.codex/chancellor/test-public-commit-governance-gate.ps1`，新增“删掉 docs/README 的维护层入口时失败”和“调换 README 中维护层顺序时失败”两类场景。
3. 扩展 `.codex/chancellor/invoke-public-commit-governance-gate.ps1`，并把顺序校验抽成可复用小函数，让 Target 主线与维护层主线共用同一套顺序门禁逻辑。
4. 同步更新 `.codex/chancellor/README.md`、`docs/40-执行/10-本地安全提交流程.md`、`docs/30-方案/08-V4-治理审计候选规范.md` 的现行说明。

## 结果

- 当前自动门禁已从“Target 主线关键入口存在性与顺序同步”继续扩到“维护层主线关键入口存在性与顺序同步”。
- 当前仓现状通过新门禁。
- 人为删掉 `docs/README.md` 的 `40-执行/16-拍板包半自动模板.md` 或调乱 `README.md` 中 `19/20` 顺序时，门禁会自动失败。

## 理由

- 维护层 13-21 是长期操作链路；只要入口顺序漂移，后续执行与恢复都会被误导。
- 这一步仍在现有门禁里自含完成，没有新增目录、没有新增依赖，长期维护成本更低。

## 下一步

1. 暂存本轮公开安全改动并执行提交。
2. 完成 `pull --rebase origin main` 与 `push origin main`，确认 `pre-push` 自动门禁通过。
3. 回写任务包状态并清空活动指针。
