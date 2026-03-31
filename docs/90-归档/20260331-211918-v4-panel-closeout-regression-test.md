# V4 面板收口联动可测试性增强记录

时间：2026-03-31 21:19:18
任务：第一百五十五刀（面板收口联动可测试性增强）

## 动作

1. 增强 `.codex/chancellor/audit-local-task-status.ps1`，新增自定义输入能力：可注入 `TasksRootPath`、`ActiveTaskFilePath` 与 `AuditReferenceTimeText`，让审计不再依赖当前真实运行态。
2. 增强 `.codex/chancellor/review-panel-acceptance-closeout.ps1`，把上述可注入输入透传给审计脚本，使联动收口脚本可以针对受控样例任务集做确定性验证。
3. 新增 `.codex/chancellor/test-panel-acceptance-closeout-review.ps1`，自动构造样例任务包与通过 / 不通过两类结果稿，回归验证：
   - 审计脚本的任务总数、陈旧任务数、主公拍板项数
   - 联动脚本在通过态的拍板项剔除逻辑
   - 联动脚本在不通过态的阻塞提示逻辑
4. 更新 `.codex/chancellor/README.md`、`docs/30-方案/02-V4-目录锁定清单.md` 与 `.codex/chancellor/invoke-public-commit-governance-gate.ps1`，把测试脚本补入入口说明、运行态白名单真源和门禁硬校验。
5. 执行 `test-panel-acceptance-closeout-review.ps1`，结果为 `PASS`。

## 理由

- 现有联动脚本虽然可用，但回归验证仍依赖当前本地真实任务状态，后续一旦真实任务收口，样例验证就会漂移。
- 把输入注入能力和确定性测试补齐后，后续维护者可以在任何时候复验收口逻辑，而不必依赖当前仓库此刻的运行态长相。

## 结果

- 面板收口联动已具备可重复、可控、可回归的测试基础。
- `test-panel-acceptance-closeout-review.ps1` 已验证通过态会把 `v4-trial-035` 从主公拍板项中剔除，而不通过态会保留它。
- 审计脚本与联动脚本现在都支持基于受控样例输入做验证，后续重构风险显著降低。

## 下一步

1. 主公完成真实人工验板后，继续使用 `review-panel-acceptance-closeout.ps1 -ResultPath <结果稿>` 走真实收口链路。
2. 后续若继续调整收口逻辑，先跑 `test-panel-acceptance-closeout-review.ps1`，再提交，避免口径回退。
3. 真实人工验板结果一到位，只要主公再拍板 `v4-trial-034` 是否统一收为 `done`，我就可推进最终总收口。
