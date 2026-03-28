# .codex/chancellor 目录说明

这里是新 V4 的试运行任务包目录。

规则：
- `active-task.txt` 记录当前激活任务
- `tasks/` 承载任务包
- 运行态在这里，不进 `docs/`
- 维护层起包脚手架见：`create-task-package.ps1`（已含主假设、最小推进步、验证信号骨架）
- 拍板包半自动模板见：`create-gate-package.ps1`
- 拍板结果回写模板见：`resolve-gate-package.ps1`
- 异常路径与回退模板见：`record-exception-state.ps1`
- 复杂并存汇报骨架模板见：`write-concurrent-status-report.ps1`
