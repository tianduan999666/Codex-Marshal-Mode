# V4 目录锁定清单顺序回归补强记录

时间：2026-03-29 20:14:35
任务：第四十九刀（目录锁定清单顺序回归补强）

## 动作

1. 复盘 `docs/30-方案/02-V4-目录锁定清单.md` 的现有门禁，确认此前只覆盖“顶层批准项缺项”与“运行态白名单缺项”，尚未对顺序漂移做硬阻断。
2. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增两条负例：
   - `block-lock-list-approved-root-entry-order-drift`
   - `block-lock-list-approved-codex-file-order-drift`
3. 首轮回归暴露真实缺口：门禁脚本当前只把锁定清单解析成集合使用，没有对批准顺序做显式断言，因此单纯交换顺序时会静默通过。
4. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 新增通用 `Assert-ExactOrderedValues`，并把它接入：
   - 顶层批准项顺序
   - 公开仓允许跟踪的运行态文件顺序
5. 让锁定清单从“缺项拦截”升级为“缺项 + 未批准项 + 顺序漂移”三类都可自动阻断。
6. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认新增负例命中且总矩阵通过。

## 结果

- `目录锁定清单` 现在具备顶层批准项顺序硬门禁。
- `目录锁定清单` 现在具备运行态白名单顺序硬门禁。
- 如果未来误改 `README.md` / `AGENTS.md` 的批准顺序，或误改 `.codex/chancellor/` 白名单文件顺序，门禁会自动失败。

## 理由

- 锁定清单不是普通文档，而是“哪些结构被批准存在”的真源；若这里只剩集合校验，没有顺序硬约束，后续人工维护很容易逐步漂移。
- 这轮先让负例真实打出缺口，再补门禁根因，符合 V8 的“短期更难、长期更稳、长期更轻松”。

## 下一步

1. 暂存本轮脚本与归档改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫仍缺“源头顺序漂移负例”或“显式有序断言”的真源入口。
