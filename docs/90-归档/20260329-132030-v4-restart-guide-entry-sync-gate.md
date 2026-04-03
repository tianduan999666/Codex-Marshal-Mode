# V4 重启导读核心入口同步门禁记录

时间：2026-03-29 13:20:30
任务：v4-trial-027-restart-guide-entry-sync-gate

## 动作

1. 识别下一层公开口径瓶颈是 `docs/00-导航/01-V4-重启导读.md` 的“先看什么”已经定义了重启阶段核心入口，但 `README.md` 与 `docs/README.md` 还没有硬门禁同步。
2. 先修真实漂移点：补齐 `docs/README.md` 缺失的 `10-输入材料/01-旧仓必需资产清单.md` 与 `30-方案/01-V4-最小目录蓝图.md`。
3. 扩展 `.codex/chancellor/invoke-public-commit-governance-gate.ps1`，把重启导读“先看什么”提取为真源，并校验 `README.md`、`docs/README.md` 两个公开首页对核心入口的同步。
4. 扩展 `.codex/chancellor/test-public-commit-governance-gate.ps1`，新增“删掉 docs/README 中重启导读核心入口时失败”的场景，并同步更新门禁说明文档。

## 结果

- 当前自动门禁已从“现行总览阅读顺序同步”继续扩到“重启导读核心入口同步”。
- `docs/README.md` 已补齐重启阶段缺失入口。
- 当前仓现状通过新门禁；人为删掉 `docs/README.md` 中 `10-输入材料/01-旧仓必需资产清单.md` 时，门禁会自动失败。

## 理由

- 重启导读定义的是启动阶段的最小共识，如果两个公开首页漏挂这些入口，用户会在一开始就读偏。
- 这一步只做存在性同步，不冻结跨文档顺序，符合“信息不足时缩短步长”的 V8 规则。

## 下一步

1. 暂存本轮公开安全改动并执行提交。
2. 完成 `pull --rebase origin main` 与 `push origin main`，确认 `pre-push` 自动门禁通过。
3. 回写任务包状态并清空活动指针。
