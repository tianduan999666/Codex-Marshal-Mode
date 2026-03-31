# codex-home-export

这是当前仓 `V4` 的**本机生产母体最小骨架**。

## 当前口径

- 默认入口仍是官方 `Codex` 面板
- 本目录当前只承载“单机生产接管最小闭环”的最小必要件
- 当前已完成“本机生产桥接切换”，但仍不宣称已经完成全量生产母体重构

## 当前阶段

- `stage`：`bridge-ready`
- 已完成当前新 V4 仓到本机 `~/.codex` 的最小桥接切换
- 当前新仓已接管本机生产的最小真源与控制面
- 当前仍保留既有未覆盖运行资产，不视为全量生产母体重建

## 当前已落文件

- `README.md`
- `VERSION.json`
- `manifest.json`
- `install-to-home.ps1`
- `initialize-workspace.ps1`
- `new-task.ps1`
- `rollback-from-backup.ps1`
- `verify-cutover.ps1`
- `start-panel-acceptance.ps1`
- `new-panel-acceptance-result.ps1`
- `verify-panel-acceptance-result.ps1`
- `panel-acceptance-checklist.md`
- `panel-acceptance-three-step-card.md`
- `panel-acceptance-pass-fail-sheet.md`
- `panel-acceptance-result-template.md`

## 当前未落文件

- 无必须缺口；当前仍建议保留人工面板验板记录
- 完整导出内容（如 `prompts/`、`scripts/`、`skills/`、`agents/` 等）

## 使用原则

1. 若想尽量一条命令跑通本机准备，可先执行 `initialize-workspace.ps1`
2. 需要单独同步最小骨架时，再执行 `install-to-home.ps1`
3. 再执行 `verify-cutover.ps1` 完成自动验板
4. 若异常则执行 `rollback-from-backup.ps1` 回退
5. 若想一步完成验板准备，可执行 `start-panel-acceptance.ps1`
6. 需要傻瓜版入口时，先看 `panel-acceptance-three-step-card.md`
7. 需要打勾记录时，使用 `panel-acceptance-pass-fail-sheet.md`
8. 验板结束后，可执行 `new-panel-acceptance-result.ps1` 生成结果稿
9. 结果细节按 `panel-acceptance-result-template.md` 留痕
10. 补齐结果稿后，可执行 `verify-panel-acceptance-result.ps1 -ResultPath <结果稿>` 做结果复核，并直接查看脚本输出的收口提示
11. 最后按 `panel-acceptance-checklist.md` 做完整面板人工验板
12. 若需要一条命令创建新任务，可执行 `new-task.ps1 -Title "任务标题"`；这是维护层动作，建完后立即回到官方 Codex 面板继续

## 说明

当前目录的存在，表示“新仓已完成本机生产桥接切换，并开始承担生产母体最小真源与控制面”；不表示“已经完成全量生产母体重构”。