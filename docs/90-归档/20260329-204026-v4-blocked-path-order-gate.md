# V4 公开提交禁止路径顺序硬门禁记录

时间：2026-03-29 20:40:26
任务：第五十二刀（公开提交禁止路径顺序硬门禁）

## 动作

1. 复盘 `Get-BlockedPathRulesFromLocalSafeFlow` 与 `公开提交禁止路径真源`，确认此前只保证“规则可解析、行为有效”，未把关键相对顺序下沉成硬断言。
2. 在 `.codex/chancellor/test-public-commit-governance-gate.ps1` 新增两条负例：
   - `block-blocked-prefix-source-order-drift`
   - `block-blocked-prefix-exception-order-drift`
3. 选择最小且高价值的两组关键顺序：
   - `prefix:logs/` → `prefix:temp/generated/`
   - `except:logs/README.md` → `except:temp/generated/README.md`
4. 在 `.codex/chancellor/invoke-public-commit-governance-gate.ps1` 为禁止路径真源增加关键相对顺序断言；仅在两项都存在时才校验顺序，不打破现有 `allow-blocked-prefix-source-sync` 的动态真源演练能力。
5. 复跑 `.codex/chancellor/test-public-commit-governance-gate.ps1`，确认新增负例命中且总矩阵通过。

## 结果

- `公开提交禁止路径真源` 现在具备关键前缀顺序硬门禁。
- `公开提交禁止路径真源` 现在具备关键例外顺序硬门禁。
- 如果未来误把 `logs/` 与 `temp/generated/` 的前缀顺序交换，或误把两条 README 例外顺序交换，门禁会自动阻断。

## 理由

- 这条真源控制的是“什么绝不能进公开推送”的本地自动边界，属于高风险入口；顺序一旦漂移，后续维护心智会越来越乱。
- 本轮仍坚持“只锁关键相对顺序、不锁死整段规则”，兼顾长期秩序与真源可演进性。

## 下一步

1. 暂存本轮脚本与归档改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 下一刀继续扫描仍缺“关键相对顺序断言”的真源或公开入口链路。
