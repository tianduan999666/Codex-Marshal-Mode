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

### 当前唯一主线（先看这 3 条）

1. 日常开工优先回官方 `Codex` 面板，直接说：`丞相：我要做 XX`。
2. 面板内默认先走 `start-panel-task.ps1`：先验真；若发现可修复漂移，先安全修复；然后自动建任务，并留在当前会话继续。
3. 第一次准备或维护层排障时，再执行 `initialize-workspace.ps1`、`install-to-home.ps1`、`verify-cutover.ps1` 与 `new-task.ps1`。

### 当前次级材料（先不作为日常主路径）

- `rollback-from-backup.ps1`：只有安装或验真异常时再用。
- `start-panel-acceptance.ps1`、`new-panel-acceptance-result.ps1`、`verify-panel-acceptance-result.ps1`：保留作维护层补充动作，不作为当前自用 MVP 主路径。
- `panel-acceptance-*` 文档：保留作补充参考，不作为当前日常必经步骤。

## 说明

当前目录的存在，表示“新仓已完成本机生产桥接切换，并开始承担生产母体最小真源与控制面”；不表示“已经完成全量生产母体重构”。