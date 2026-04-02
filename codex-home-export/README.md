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
- `AGENTS.md`
- `config.toml`
- `VERSION.json`
- `manifest.json`
- `install-to-home.ps1`
- `initialize-workspace.ps1`
- `new-task.ps1`
- `start-panel-task.ps1`
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

### 当前唯一主线（先看这 4 条）

1. 日常开工优先回官方 `Codex` 面板，直接说：`传令：我要做 XX`。
2. 面板内默认先走 `start-panel-task.ps1`：对外按“先确认丞相能正常接到传令 → 再确认丞相自身状态良好 → 接着把丞相调整到最佳工作状态 → 丞相记录这次要做的任务 → 丞相开始执行任务”解释流程；内部仍按最小必要原则执行轻量检查、必要时完整验真与自动修复。
3. 若当前版本在本机已经验过，后续任务默认跳过重复验真，直接建任务，并留在当前会话继续。
4. 跳过前仍会轻量复核 `AGENTS.md` 与 `config.toml` 是否和当前真源一致；若不一致，自动回到验真流程。
5. 第一次准备或维护层排障时，再执行 `initialize-workspace.ps1`、`install-to-home.ps1`、`verify-cutover.ps1` 与 `new-task.ps1`。

### 当前对外感知

- 对外统一叫 `丞相`，不再对外使用 `大都督`、`都督模式` 等名字。
- `传令：XXXX` 是唯一做事入口；`传令：状态 / 传令：版本 / 传令：升级` 是仅保留的 3 个可选查询命令。
- 默认开场白固定为：`🪶 军令入帐。亮，即刻接管全局。`
- 新对话优先展示示例：`例如：传令：计算1+1=?`
- `传令：状态` 固定优先展示 6 行：`版本 / 上次检查 / 自动修复 / 关键文件一致性 / 当前模式 / 当前任务`。
- `传令：升级` 必须由用户主动提出，系统默认不自动升级。
- 固定边界提示是：`提示：丞相在检查阶段只检查自己，不会查看你的项目；执行阶段只按你的传令办事，不会擅自审查项目。`

### 当前次级材料（先不作为日常主路径）

- `rollback-from-backup.ps1`：只有安装或验真异常时再用。
- `start-panel-acceptance.ps1`、`new-panel-acceptance-result.ps1`、`verify-panel-acceptance-result.ps1`：保留作维护层补充动作，不作为当前自用 MVP 主路径。
- `panel-acceptance-*` 文档：保留作补充参考，不作为当前日常必经步骤。

## 说明

当前目录的存在，表示“新仓已完成本机生产桥接切换，并开始承担生产母体最小真源与控制面”；不表示“已经完成全量生产母体重构”。
