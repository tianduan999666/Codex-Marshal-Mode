# V4 一键收口补入 034 归一化开关记录

时间：2026-04-01 00:07:51
任务：第一百五十八刀（finalize 接入 034 归一化开关）

## 动作

1. 增强 `.codex/chancellor/finalize-panel-acceptance-closeout.ps1`，新增 `-NormalizeTrial034ToDone` 开关。
2. 当真实人工验板结果为“通过”且显式带上该开关时，一键收口会在完成 `v4-trial-035` 回写后，继续把 `v4-trial-034` 从 `completed` 统一归一为 `done`。
3. 同步更新 `.codex/chancellor/README.md`，明确一键入口现在可以在主公已拍板时连带处理 `034`。
4. 扩展 `.codex/chancellor/test-panel-acceptance-closeout-review.ps1`，验证一键入口在通过态会输出 `034` 归一化提示，并把 `034` 的状态写为 `done`。
5. 执行 `test-panel-acceptance-closeout-review.ps1`，结果为 `PASS`。

## 理由

- 当前真实总收口只差两个输入：结果稿与 `034` 拍板。若拍板后仍要再做一轮单独维护动作，最后一公里还有摩擦。
- 把 `034` 归一化接入现有 `finalize` 后，主公在拍板完成时，只需一条命令就能把这两个输入一并落盘。

## 结果

- 未来真实人工验板通过后，若主公已拍板 `034`，现在可以直接执行：
  - `finalize-panel-acceptance-closeout.ps1 -ResultPath <结果稿> -NormalizeTrial034ToDone`
- 上述命令会同时完成：
  - 结果稿复核
  - `v4-trial-035` 回写
  - `v4-trial-034` 状态归一化为 `done`
- 定向回归测试已覆盖该路径，后续再改不会轻易把这条最终捷径打坏。

## 下一步

1. 主公完成真实人工验板后，若尚未拍板 `034`，先执行不带开关的 `finalize-panel-acceptance-closeout.ps1 -ResultPath <结果稿>`。
2. 主公若已拍板 `034`，直接执行带开关的一键收口命令。
3. 上述动作完成后，我即可推进最终总收口。
