# V4 本地任务状态审计脚本落地记录

时间：2026-03-31 20:43:22
任务：第一百五十一刀（本地任务状态审计脚本落地）

## 动作

1. 新增 `.codex/chancellor/audit-local-task-status.ps1`，统一汇总 `active-task.txt`、状态计数、非终态任务与非规范状态。
2. 更新 `.codex/chancellor/README.md`，补入本地任务状态审计入口说明。
3. 更新 `docs/30-方案/02-V4-目录锁定清单.md`，把新脚本补进运行态批准结构与公开仓允许跟踪白名单。
4. 更新 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 的硬编码白名单，使门禁校验与目录锁定清单重新一致。
5. 运行 `audit-local-task-status.ps1` 与 `invoke-public-commit-governance-gate.ps1 -ChangedPaths ...` 做真实验证。

## 理由

- 当前公开侧准备件已基本齐备，后续高频风险不再是“少一个说明”，而是本地任务状态需要靠人眼翻目录，长期不稳。
- 把状态审计脚本化后，每次收口前都能一眼看到激活任务、剩余非终态任务和非规范状态，后续维护更轻松。

## 结果

- 审计脚本已确认当前本地任务总数为 `35`，其中 `done=30`、`running=2`、`ready_to_resume=1`、`waiting_assist=1`、`completed=1`。
- 审计脚本已稳定识别 3 个优先人工关注点：`v4-trial-019`、`v4-trial-034`、`v4-trial-035`。
- 真实门禁已通过当前公开改动校验，说明“目录锁定清单真源 + 门禁硬校验 + README 入口说明”三处口径已重新对齐。

## 下一步

1. 主公进入官方 Codex 面板执行一次真实人工验板，并补齐结果稿。
2. 验板完成后，先跑 `verify-panel-acceptance-result.ps1`，再结合本审计脚本决定是否统一收口 `v4-trial-017`、`018`、`019`、`034`。
3. 若 `v4-trial-034` 继续保留 `completed`，建议主公拍板是否统一改为 `done`，避免最终收口时重复解释。
