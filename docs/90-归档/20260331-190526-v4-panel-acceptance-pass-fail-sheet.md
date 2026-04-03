# V4 面板人工验板打勾单落地记录

时间：2026-03-31 19:05:26
任务：第一百四十六刀（面板人工验板打勾单落地）

## 动作

1. 新增 `codex-home-export/panel-acceptance-pass-fail-sheet.md`，把人工验板压缩为“开始前 / 三关检查 / 最终判断 / 失败回退”的打勾单。
2. 更新 `codex-home-export/manifest.json` 与 `codex-home-export/README.md`，把打勾单纳入生产母体文件清单与使用说明。
3. 更新 `codex-home-export/verify-cutover.ps1`，在自动验板通过后直接提示打勾单入口。
4. 更新 `docs/30-方案/09-V4-本机生产切换最小闭环方案.md`，把人工验板的“三层结构”回写到方案现状。
5. 重新执行 `codex-home-export/verify-cutover.ps1` 与 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认自动验板与整套治理回归最终均为 `PASS`。

## 理由

- 当前主瓶颈只剩人工验板，继续补抽象说明不如把“是否通过”做成可打勾、可快速判断的固定入口。
- 把三步卡、打勾单、完整清单串成三层结构，后续维护者不必在“太简略”和“太冗长”之间反复切换。

## 结果

- 维护层现在具备“最短入口（三步卡）→ 过程判断（打勾单）→ 完整口径（完整清单）”三层人工验板链路。
- 自动验板脚本会直接提示打勾单入口。
- 自动验板通过；整套治理回归最终以 `PASS` 收口，退出码为 `0`。

## 下一步

1. 进入官方面板，按 `panel-acceptance-three-step-card.md` 与 `panel-acceptance-pass-fail-sheet.md` 执行人工验板。
2. 若人工验板出现漂移，再按最小缺口补 `1` 刀到 `2` 刀并立即回归。
