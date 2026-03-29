# .codex/chancellor 目录说明

这里是新 V4 的试运行任务包目录。

规则：
- `active-task.txt` 记录当前激活任务
- `tasks/` 承载任务包
- 运行态在这里，不进 `docs/`
- 维护层起包脚手架见：`create-task-package.ps1`（已含主假设、最小推进步、验证信号、治理复核骨架）
- 拍板包半自动模板见：`create-gate-package.ps1`（已含治理提示与治理复核骨架）
- 拍板结果回写模板见：`resolve-gate-package.ps1`（已含治理提示与治理复核骨架）
- 异常路径与回退模板见：`record-exception-state.ps1`（已含治理提示与治理复核骨架）
- 复杂并存汇报骨架模板见：`write-concurrent-status-report.ps1`（已含治理提示与治理复核骨架）
- 关键配置来源与漂移复核模板见：`write-governance-config-review.ps1`（已含配置来源、版本依据与漂移检查骨架）
- 公开提交治理门禁见：`invoke-public-commit-governance-gate.ps1`（会校验运行态混入、顶层跟踪面、必需规则文件、四处公开入口对执行区现行标准件的同步、三处关键规则入口同步，以及三处 Target 主线关键入口、维护层主线关键入口的存在性与顺序；同时校验现行总览“阅读顺序建议”中的 Target/维护层主线顺序，以及两个公开首页对重启导读核心入口的同步）
- 本地硬门禁安装见：`install-public-commit-governance-hook.ps1`（会自动把门禁接到 `.git/hooks/pre-push`）
- 公开提交治理门禁测试见：`test-public-commit-governance-gate.ps1`（用于验证允许样例与阻断样例）
