# codex-home-export

这是当前仓 `V4` 的**本机生产母体最小骨架**。

## 当前口径

- 默认入口仍是官方 `Codex` 面板
- 本目录当前只承载“单机生产接管最小闭环”的最小必要件
- 当前轮不整包搬旧母体，不宣称已经完成本机接管

## 当前已落文件

- `README.md`
- `VERSION.json`
- `manifest.json`
- `install-to-home.ps1`
- `rollback-from-backup.ps1`

## 当前未落文件

- 切换后固定验板脚本或清单
- 完整导出内容（如 `prompts/`、`scripts/`、`skills/`、`agents/` 等）

## 使用原则

1. 先执行 `install-to-home.ps1` 完成最小骨架同步
2. 若异常则执行 `rollback-from-backup.ps1` 回退
3. 再新开会话执行固定验板

## 说明

当前目录的存在，表示“新仓已开始建设生产母体”；不表示“当前本机生产已经切换到这里”。