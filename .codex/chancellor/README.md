# .codex/chancellor 目录说明

这里是新 V4 的本地运行态目录，不作为普通用户公开入口。

## 当前只看这 4 件事

- `active-task.txt` 记录当前激活任务；`tasks/` 承载任务包与本地留痕。
- 维护层动作入口、主线顺序、补充入口统一以 `docs/40-执行/13-维护层总入口.md` 为准；本文件不再重复抄整套能力清单。
- 允许公开跟踪的运行态文件清单统一以 `docs/30-方案/02-V4-目录锁定清单.md` 为准。
- 公开提交门禁规则与公开仓边界统一以 `docs/40-执行/10-本地安全提交流程.md` 为准。

## 本地在研边界

- `Measure-Phase2Baseline.ps1`、`Test-Phase2Baseline.ps1`、`Invoke-Phase2AgentWorker.ps1`、`Invoke-Phase2AgentDispatcher.ps1`、`Test-Phase2AgentDispatcher.ps1` 属于 Phase 2 本地在研链路。
- `Invoke-VibeCodingGateDryRun.ps1`、`Test-VibeCodingGateDryRun.ps1` 属于 VibeCoding 本地在研链路。
- 上述在研脚本当前只表示“仓内存在脚本或样例验证能力”，不代表已经纳入公开现行主线。
- 若相关脚本仍处于脏工作树，或只完成本地样例验证，提交前仍需补治理审计、口径复核与必要回归。

## 使用建议

- 想知道“当前该走哪条维护路径”，先看 `docs/40-执行/13-维护层总入口.md`。
- 想确认“这个运行态文件能不能进公开仓”，先看 `docs/30-方案/02-V4-目录锁定清单.md`，再看 `docs/40-执行/10-本地安全提交流程.md`。
- 想直接查看当前目录已有脚本，再执行 `Get-ChildItem .codex/chancellor`。
