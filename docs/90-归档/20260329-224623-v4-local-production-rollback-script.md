# V4 本机生产回滚脚本落地记录

时间：2026-03-29 22:46:23
任务：第六十三刀（本机生产回滚脚本首版）

## 动作

1. 在 `codex-home-export/` 中新增 `rollback-from-backup.ps1`，读取安装记录中的 `backup_root` 与受控文件列表，按“有备份则恢复、无备份则删除”的规则回退最小骨架同步结果。
2. 把 `install-to-home.ps1` 的安装记录补为 `managed_files`，让回滚脚本可以精准知道受控回退范围。
3. 同步更新 `codex-home-export/README.md`、`codex-home-export/manifest.json` 与 `docs/30-方案/09-V4-本机生产切换最小闭环方案.md`，把当前状态改为“已具备安装 + 回滚，仍缺固定验板闭环”。
4. 在 `temp/generated/local-production-rollback-smoke-20260329-2240` 下预置旧内容，执行一轮“安装 → 回滚”闭环演练。

## 结果

- 当前仓已具备首版单机回滚脚本。
- 临时目标演练表明，安装后可把 `config/cx-version.json`、`config/marshal-mode/manifest.json`、`README.md` 与 `install-record.json` 回退到安装前状态。
- 本机生产切换线现已具备“安装 + 回滚”双向最小闭环，距离真实试切只差固定验板清单。

## 验证

1. 临时目标：`temp/generated/local-production-rollback-smoke-20260329-2240`
2. 预置旧内容：
   - `config/cx-version.json`
   - `config/marshal-mode/manifest.json`
   - `config/marshal-mode/README.md`
   - `config/marshal-mode/install-record.json`
3. 执行：先跑 `install-to-home.ps1`，再跑 `rollback-from-backup.ps1`
4. 结果：四个文件均恢复为安装前内容。

## 下一步

1. 补切换后固定验板清单。
2. 再做第一次真实但可回滚的本机试切。
3. 试切通过后，才能宣称“可丝滑切到本机生产”。