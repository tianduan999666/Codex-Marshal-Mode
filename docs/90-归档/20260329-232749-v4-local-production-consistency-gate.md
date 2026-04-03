# V4 本机生产母体一致性门禁落地记录

时间：2026-03-29 23:27:49
任务：第六十五刀（本机生产母体一致性硬门禁）

## 动作

1. 修正 `codex-home-export/README.md` 口径，把当前状态明确为“已完成本机生产桥接切换，但未完成全量生产母体重构”。
2. 在 `codex-home-export/README.md` 新增结构化 `stage` 行，作为公开口径与自动门禁共享的真源锚点。
3. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 新增生产母体一致性检查：
   - `VERSION.json.cx_version` 与 `manifest.json.version` 必须一致
   - `VERSION.json.source_of_truth` 必须保持 `codex-home-export`
   - `manifest.json.included` 必须覆盖 `codex-home-export/` 当前真实文件集
   - `README.md` 的“当前已落文件”必须与 `manifest.json.included` 一致
   - `README.md` 的 `stage` 必须与 `manifest.json.stage` 一致
4. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 补充回归测试，覆盖：
   - 正常一致性通过
   - manifest 文件清单漂移被拦截
   - README stage 漂移被拦截
   - VERSION 与 manifest 版本漂移被拦截
5. 同步更新 `docs/30-方案/09-V4-本机生产切换最小闭环方案.md`，把该硬门禁纳入当前方案现状。

## 结果

- 当前“本机生产母体”这条线的公开口径，不再只靠人工记忆维持。
- 生产母体的阶段、版本、文件清单三类关键事实，已下沉为自动门禁。
- 未来若有人改了 `README.md`、`VERSION.json`、`manifest.json` 但没同步其余真源，提交前会被硬拦。

## 下一步

1. 继续把面板侧关键命令口径与 `VERSION.json.panel_commands` 之间的一致性也下沉到自动门禁。
2. 等主公开机后，只需按 `codex-home-export/panel-acceptance-checklist.md` 做一次人工验板，即可补完桥接切换的人眼确认。
