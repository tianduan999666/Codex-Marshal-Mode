# V4 面板命令口径硬门禁落地记录

时间：2026-03-29 23:47:32
任务：第六十六刀（面板命令口径一致性硬门禁）

## 动作

1. 在 `AGENTS.md` 正式补回“面板丞相命令”表，明确当前六个面板内置命令及其含义。
2. 在 `codex-home-export/panel-acceptance-checklist.md` 增加说明，明确人工验板口径以 `codex-home-export/VERSION.json` 的 `panel_commands` 为准。
3. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 新增面板命令一致性检查：
   - `AGENTS.md` 的命令表必须保持当前六个固定命令与顺序
   - `codex-home-export/VERSION.json` 的 `panel_commands` 必须与该命令表一致
   - `codex-home-export/panel-acceptance-checklist.md` 的验板命令序列必须保持 `丞相版本 → 丞相检查 → 丞相状态`
4. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 补充回归测试，覆盖：
   - 正常命令链路通过
   - `VERSION.json.panel_commands` 漂移被拦截
   - `AGENTS.md` 命令表漂移被拦截
   - 验板清单命令序列漂移被拦截
5. 更新 `docs/30-方案/09-V4-本机生产切换最小闭环方案.md`，把该硬门禁纳入当前最小闭环现状。

## 结果

- 面板命令不再只靠口头约定维持，而是进入公开提交前的自动门禁。
- 当前“官方面板入口 → 版本真源 → 人工验板清单”三处公开口径已形成硬一致性链路。
- 今后若有人改了命令名、顺序或验板顺序而未同步其余真源，提交前会被直接拦截。

## 下一步

1. 继续把 `丞相版本` / `丞相检查` / `丞相状态` 的公开响应口径与对应文档验收标准进一步对齐。
2. 等主公开机后，只需按 `codex-home-export/panel-acceptance-checklist.md` 做一次人工验板，即可补完桥接切换的人眼确认。
