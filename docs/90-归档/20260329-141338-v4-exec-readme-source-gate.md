# V4 执行区 README 真源门禁记录

时间：2026-03-29 14:13:38
任务：v4-trial-031-exec-readme-source-gate

## 动作

1. 识别长期维护瓶颈：执行区现行标准件同步虽然已进入公开门禁，但仍由目录扫描隐式推导，未来容易因新增或存留文件而误触公开入口漂移。
2. 扩展 `.codex/chancellor/invoke-public-commit-governance-gate.ps1`，把 `docs/40-执行/README.md` 的“当前现行标准件”区块升级为执行区现行标准件真源，并在区块缺失时输出友好阻断消息。
3. 扩展 `.codex/chancellor/test-public-commit-governance-gate.ps1`，新增“执行区真源区块缺失必须失败”和“同步改动真源与公开入口时允许通过”的场景。
4. 同步更新 `.codex/chancellor/README.md`、`docs/40-执行/README.md`、`docs/40-执行/10-本地安全提交流程.md`、`docs/30-方案/08-V4-治理审计候选规范.md`，明确执行区现行标准件真源已改为执行区 README 区块。

## 结果

- 当前自动门禁已把执行区现行标准件清单从目录扫描提升为“执行区 README section 真源”。
- 当前仓现状通过新门禁与测试。
- 人为破坏执行区真源区块时，门禁会给出明确阻断信息；若同步改动执行区真源与公开入口，门禁允许通过。

## 理由

- 真源若继续依赖目录扫描，仓内新增一个无意暴露的执行区文档，就可能把公开入口同步门槛意外抬高。
- 直接以执行区 README 区块驱动公开门禁，短期实现更难，但长期最稳、最轻，也更符合 V8 的复利目标。

## 下一步

1. 暂存本轮公开安全改动并执行暂存区门禁。
2. 完成 `commit`、`pull --rebase origin main` 与 `push origin main`。
3. 回写任务包状态、本地日志并清空活动指针。
