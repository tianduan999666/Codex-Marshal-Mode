# V4 公开提交治理硬门禁记录

时间：2026-03-29 11:54:03
任务：v4-trial-021-public-commit-governance-gate

## 动作

1. 识别当前主瓶颈是“规则存在，但公开提交前缺少机器门禁”。
2. 先写 `test-public-commit-governance-gate.ps1`，并在门禁脚本缺失时跑出首个失败信号。
3. 新增 `invoke-public-commit-governance-gate.ps1`，把运行态混入、顶层跟踪面与必需规则文件校验收成可执行门禁。
4. 新增 `install-public-commit-governance-hook.ps1`，把门禁自动安装到 `.git/hooks/pre-push`。
5. 同步更新目录锁定清单、治理候选规范、提交流程、维护入口与收口检查表。

## 结果

- 当前仓已具备本地自动触发的公开提交治理硬门禁。
- 推送前会自动阻断 `.codex/chancellor/tasks/`、`.codex/chancellor/active-task.txt`、`logs/`、`temp/generated/`、`.vscode/`、`.serena/` 等路径进入公开仓。
- 门禁已通过允许样例与阻断样例测试，并已实际安装到当前仓 `pre-push` hook。

## 理由

- 仅靠 `docs/reference` 与现行流程文档，仍属于“人要记得执行”的软约束。
- 把门禁接到 `pre-push`，才能把“提醒式要求”升级为“默认自动执行”。
- 当前实现保持在已批准目录内，不新增顶层目录、不引入外部依赖。

## 下一步

1. 对当前真实暂存面再跑一次门禁验证。
2. 完成本轮提交、`pull --rebase` 与 `push`。
3. 收口回写任务包状态，并清空活动指针。
