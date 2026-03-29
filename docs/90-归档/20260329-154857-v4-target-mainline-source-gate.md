# V4 Target 主线真源化记录

时间：2026-03-29 15:48:57
任务：第三十八刀（Target 主线真源化）

## 动作

1. 复盘公开提交治理门禁剩余借道真源，确认 Target 主线顺序仍通过现行总览“阅读顺序建议”切片间接供给，缺少 Target 自身的专用真源。
2. 在 `docs/40-执行/12-V4-Target-实施计划.md` 新增“Target 主线真源”区块，显式列出 `02`、`04`、`05`、`06`、`07`、`08`、`12` 的 Target 主线顺序。
3. 扩展 `.codex/chancellor/invoke-public-commit-governance-gate.ps1`，把 Target 主线顺序改为读取 `12-V4-Target-实施计划.md` 的主线真源区块，并补入起止边界校验，避免真源缺首尾时静默漂移。
4. 保持现行总览“阅读顺序建议”继续承担公开阅读顺序职责，并让门禁继续反向校验它是否与新的 Target 主线真源一致。
5. 扩展 `.codex/chancellor/test-public-commit-governance-gate.ps1`，把旧的 Target 来源缺失测试切到 `12-V4-Target-实施计划.md`，并让“联动通过”用例同时改写该真源；同时新增由新真源驱动的边界缺失校验。
6. 同步更新 `.codex/chancellor/README.md`、`docs/40-执行/10-本地安全提交流程.md`、`docs/30-方案/08-V4-治理审计候选规范.md`，明确新的 Target 真源关系。

## 结果

- 当前自动门禁已把 Target 主线顺序的真源收回 `docs/40-执行/12-V4-Target-实施计划.md`。
- 现行总览“阅读顺序建议”不再兼任 Target 主线真源，而是被门禁校验为需与真源保持一致的公开阅读口径。
- 删除 Target 主线真源中的起始路径时，门禁会自动失败，证明边界缺失不会再静默漏过。
- 当 Target 主线中的 `07` / `08` 被联动改写时，只要 `README.md`、`docs/README.md`、现行总览与 Target 真源保持一致，门禁仍可通过。

## 理由

- Target 主线是 Target 自己的推进秩序，最稳的做法是由 Target 实施计划自己声明，而不是继续借用导航总览切片推导。
- 这样做能把“导航展示”和“Target 主线定义”拆开，各自职责更清晰，长期维护更省心。

## 下一步

1. 暂存本轮公开安全改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀可继续寻找仍借道别处切片、但本质应由专属总入口自己供源的主线或集合约束。
