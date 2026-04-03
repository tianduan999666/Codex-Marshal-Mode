# V4 一键收口补齐 active-task 自动清空记录

时间：2026-04-01 00:23:30
任务：第一百五十九刀（finalize 收口后自动清空 active-task）

## 动作

1. 增强 `.codex/chancellor/finalize-panel-acceptance-closeout.ps1`，补入默认 `active-task.txt` 解析与 UTF-8 无 BOM 写回能力。
2. 当真实人工验板结果为“通过”，且 `active-task.txt` 仍指向本次收口任务 `v4-trial-035-panel-acceptance-closeout` 时，一键收口会自动把该文件清空。
3. 同步更新 `.codex/chancellor/README.md`，明确一键收口在通过态下会自动清理旧任务指针。
4. 扩展 `.codex/chancellor/test-panel-acceptance-closeout-review.ps1`，新增一键收口后 `active-task.txt` 被清空的断言，并兼容空文件读取为 `$null` 的情况。
5. 执行 `test-panel-acceptance-closeout-review.ps1`，结果为 `PASS`。

## 理由

- 当前真实总收口已经具备结果稿复核、任务回写与 `034` 归一化能力，但本地运行态仍可能残留一个“已完成任务仍是当前激活任务”的小毛刺。
- 若不把这一步一并自动化，主公完成真实验板后，维护层仍要多做一次手工清理，最终收口不够利落。

## 结果

- 未来真实人工验板通过后，一键收口不仅会完成结果稿复核与任务回写，还会自动清空仍指向已完成任务的 `active-task.txt`。
- 这使得通过态收口后的本地运行态更干净：
  - `v4-trial-035` 可落为 `done`
  - `active-task.txt` 不再误指向旧任务
  - 若主公已拍板，还可继续带上 `-NormalizeTrial034ToDone` 一并完成 `034` 归一化
- 定向回归测试已覆盖该路径，后续维护不容易把这条最后一公里再撞坏。

## 下一步

1. 主公完成真实人工验板后，先提供真实结果稿路径。
2. 若尚未拍板 `034`，执行：`finalize-panel-acceptance-closeout.ps1 -ResultPath <结果稿>`。
3. 若已拍板 `034`，执行：`finalize-panel-acceptance-closeout.ps1 -ResultPath <结果稿> -NormalizeTrial034ToDone`。
4. 上述真实输入到位后，即可推进最终总收口与完工汇总。
