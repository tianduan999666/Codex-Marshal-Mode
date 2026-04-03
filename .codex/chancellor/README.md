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
- 本地任务状态审计见：`audit-local-task-status.ps1`（会汇总 `active-task.txt`、状态分布、非终态任务、非规范状态、陈旧任务与建议主公拍板项，便于收口前快速巡检）
- 面板人工验板收口联动见：`review-panel-acceptance-closeout.ps1`（会串联结果稿复核与本地任务审计，直接给出当前是否可收口、还剩哪些陈旧任务、还有哪些主公拍板项）
- 面板人工验板结果回写见：`resolve-panel-acceptance-closeout.ps1`（会把真实结果稿回写到本地任务包，更新状态、结果摘要与决策记录）
- 面板人工验板一键收口见：`finalize-panel-acceptance-closeout.ps1`（会顺序执行 review + resolve，把真实结果稿从复核一路推进到本地任务包回写；通过态会自动清空仍指向旧任务的 `active-task.txt`；若主公已拍板，也可加 `-NormalizeTrial034ToDone` 一并归一化 `v4-trial-034`）
- 面板人工验板收口联动回归测试见：`test-panel-acceptance-closeout-review.ps1`（会构造可控样例任务与结果稿，验证通过态 / 不通过态的联动输出口径、结果回写逻辑与一键收口入口）
- 公开提交治理门禁见：`invoke-public-commit-governance-gate.ps1`（会校验运行态混入、顶层跟踪面、必需规则文件、四处公开入口对执行区现行标准件的同步、三处关键规则入口同步与现行总览规则入口顺序校验、根 AGENTS 核心约束入口校验，以及三处 Target 主线关键入口、维护层主线关键入口的存在性与顺序；同时校验 `README.md` 与 `docs/README.md` 的维护层补充入口集合、现行总览“阅读顺序建议”中的 Target/维护层主线顺序、两个公开首页对重启导读核心入口的存在性与顺序、以及两个公开首页的启动阶段入口顺序，并阻断重启导读核心入口真源、核心治理规则入口真源、Target 主线真源、维护层主线真源、启动阶段真源自身缺少关键项；其中核心治理规则入口与公开提交禁止路径现由 `docs/40-执行/10-本地安全提交流程.md` 的对应真源区块提供真源，执行区现行标准件现由 `docs/40-执行/README.md` 的“当前现行标准件”区块提供真源，受控顶层跟踪面与公开仓允许跟踪的运行态文件现由 `docs/30-方案/02-V4-目录锁定清单.md` 提供真源，`README.md` 与 `docs/README.md` 的维护层补充入口现由 `docs/40-执行/13-维护层总入口.md` 的“当前维护层能力”区块提供真源，维护层主线顺序现由 `docs/40-执行/13-维护层总入口.md` 的“维护层主线真源”区块提供真源，Target 主线顺序现由 `docs/40-执行/12-V4-Target-实施计划.md` 的“Target 主线真源”区块提供真源，启动阶段顺序现由 `docs/00-导航/01-V4-重启导读.md` 的“启动阶段真源”区块提供真源）
- 本地硬门禁安装见：`install-public-commit-governance-hook.ps1`（会自动把门禁接到 `.git/hooks/pre-push`）
- 公开提交治理门禁测试见：`test-public-commit-governance-gate.ps1`（用于验证允许样例与阻断样例）
