# V4 公开提交禁止路径真源化记录

时间：2026-03-29 15:27:36
任务：第三十六刀（公开提交禁止路径真源化）

## 动作

1. 复盘公开提交治理门禁剩余硬编码，确认 `.codex/chancellor/active-task.txt`、`.codex/chancellor/tasks/`、`logs/`、`temp/generated/`、`.vscode/`、`.serena/` 及其例外白名单仍由脚本手写维护。
2. 在 `docs/40-执行/10-本地安全提交流程.md` 新增“公开提交禁止路径真源”区块，把 exact / prefix / except 三类规则收敛到文档真源。
3. 扩展 `.codex/chancellor/invoke-public-commit-governance-gate.ps1`，把禁止路径与例外路径改为从上述真源区块解析，而不再依赖脚本硬编码数组。
4. 扩展 `.codex/chancellor/test-public-commit-governance-gate.ps1`，新增“删掉 `logs/` 前缀源后 `logs/probe.md` 不再被阻断”“删掉 `logs/README.md` 例外源后重新被阻断”两条回归测试。
5. 同步更新 `.codex/chancellor/README.md`、`docs/40-执行/10-本地安全提交流程.md`、`docs/30-方案/08-V4-治理审计候选规范.md`，明确公开提交禁止路径已改为由提交流程文档真源供给。

## 结果

- 当前自动门禁已不再硬编码公开提交禁止路径与例外路径。
- `docs/40-执行/10-本地安全提交流程.md` 现同时提供“核心治理规则入口真源”与“公开提交禁止路径真源”。
- 删除 `logs/` 前缀源时，`logs/probe.md` 会按新真源结果放行；删除 `logs/README.md` 例外源时，`logs/README.md` 会重新被阻断。
- 当前仓现状通过全部门禁回归与本轮工作集验证。

## 理由

- 禁止路径本质上属于公开提交治理边界，继续藏在脚本里会制造“文档说一套、脚本做一套”的长期漂移风险。
- 直接把 exact / prefix / except 语义写进提交流程文档，短期多一步解析，长期最清楚、最稳、最方便复核。

## 下一步

1. 暂存本轮公开安全改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀可继续寻找仍由脚本硬编码、但本质应由现有治理文档供给的公开约束集合。
