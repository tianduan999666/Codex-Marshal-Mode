# V4 启动阶段入口顺序门禁记录

时间：2026-03-29 13:32:46
任务：v4-trial-028-startup-phase-entry-order-gate

## 动作

1. 识别新的真实漂移点：`README.md` 的启动阶段入口顺序仍与 `docs/README.md` 不一致，尚未进入硬门禁。
2. 先修当前仓真实顺序，把 `README.md` 中 `重启决策` 调整到 `必需资产清单` 之前，与 `docs/README.md` 的启动阶段语义对齐。
3. 扩展 `.codex/chancellor/invoke-public-commit-governance-gate.ps1`，新增启动阶段关键入口数组，并把 `README.md`、`docs/README.md` 的启动阶段顺序纳入统一顺序校验函数。
4. 扩展 `.codex/chancellor/test-public-commit-governance-gate.ps1`，新增“调换 README 中重启决策 / 必需资产顺序时失败”的场景，并同步更新门禁说明文档。

## 结果

- 当前自动门禁已从“重启导读核心入口同步”继续扩到“两个公开首页的启动阶段入口顺序同步”。
- 当前仓现状通过新门禁。
- 人为调换 `README.md` 中 `重启决策` 与 `必需资产清单` 顺序时，门禁会自动失败。

## 理由

- 启动阶段顺序决定用户第一轮阅读与判断路径；存在即使都挂上了，顺序错了也会让人先看错文档。
- 这一步仍是最小切片，只冻结两个公开首页的启动阶段顺序，不扩到更多导航语义。

## 下一步

1. 暂存本轮公开安全改动并执行提交。
2. 完成 `pull --rebase origin main` 与 `push origin main`，确认 `pre-push` 自动门禁通过。
3. 回写任务包状态并清空活动指针。
