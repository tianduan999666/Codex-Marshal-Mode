# 面板人工验板清单

适用场景：完成 `install-to-home.ps1` 与 `verify-cutover.ps1` 后，人工确认本机生产切换是否丝滑。
当前验板命令口径以 `codex-home-export/VERSION.json` 的 `panel_commands` 为准。

## 验板步骤

1. 关闭当前 `Codex` 会话。
2. 重新打开官方 `Codex` 面板，新开一个全新会话。
3. 首句输入：`丞相版本`
4. 继续输入：`丞相检查`
5. 如需再验一层，继续输入：`丞相状态`

## 通过标准

- `丞相版本` 能返回当前丞相模式版本与版本来源。
- `丞相检查` 能做最小必要检查并返回人话结论。
- `丞相状态` 能汇报当前模式、是否稳态、下一步。
- 整个过程不出现明显崩溃、失焦或命令失效。
- 整个过程无需再手改本地文件。

## 若不通过

1. 先执行：`codex-home-export/verify-cutover.ps1`
2. 若仍异常，再执行：`codex-home-export/rollback-from-backup.ps1`
3. 回退后重新打开面板，再次验板。
