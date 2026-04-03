# V4 本机生产桥接切换落地记录

时间：2026-03-29 23:13:39
任务：第六十四刀（本机生产桥接切换 + 自动验板）

## 动作

1. 在 `codex-home-export/` 中新增 `verify-cutover.ps1`，把自动验板收敛为固定脚本。
2. 新增 `panel-acceptance-checklist.md`，把面板人工验板步骤固定下来，方便次日直接照单验板。
3. 更新 `VERSION.json`、`manifest.json`、`README.md` 与 `docs/30-方案/09-V4-本机生产切换最小闭环方案.md`，使当前状态切换为“bridge-ready”。
4. 对真实 `C:\Users\tianduan999\.codex` 执行一次非 DryRun 的 `install-to-home.ps1`，完成当前新 V4 仓到本机生产的桥接切换。
5. 紧接着执行 `verify-cutover.ps1 -RequireBackupRoot` 与 `rollback-from-backup.ps1 -DryRun`，确认切后状态与回退路径都成立。

## 结果

- 当前新 V4 仓已经完成到本机生产态的桥接切换。
- 本机 `~/.codex/config/cx-version.json` 已切到 `CX-202603292219`，并声明真源为 `codex-home-export`。
- 本机 `~/.codex/config/marshal-mode/install-record.json` 已记录本次切换来源、版本与回滚备份路径。
- 真实本机现已具备：自动安装、自动回滚、自动验板、人工面板验板清单。

## 说明

- 本次属于“桥接切换”，目标是让当前新 V4 仓成为本机生产母体的最小真源与控制面。
- 现有 `~/.codex` 中未被当前脚本覆盖的存量运行文件仍保留原状，因此本次切换强调平滑、不惊扰当前可用能力。
- 是否完全通过，仍建议在下一次新开官方面板会话后按清单补做人眼验板。

## 下一步

1. 主公休息后，新开官方面板会话，按 `codex-home-export/panel-acceptance-checklist.md` 做人工验板。
2. 若人工验板通过，可把“当前已切桥接生产”视为稳定状态。
3. 后续再评估是否需要把更多运行资产逐步收敛进当前仓的 `codex-home-export/`。