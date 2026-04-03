# V4 本机生产母体骨架落地记录

时间：2026-03-29 22:24:28
任务：第六十一刀（本机生产母体骨架 + 版本真源）

## 动作

1. 在已有“本机生产切换最小闭环方案”基础上，正式批准 `codex-home-export/` 进入当前仓顶层结构。
2. 更新 `docs/reference/root-layout-governance.md`、`docs/30-方案/01-V4-最小目录蓝图.md`、`docs/30-方案/02-V4-目录锁定清单.md` 与 `README.md`，把新顶层位、目录职责与入口说明同步到现行口径。
3. 更新 `.codex/chancellor/invoke-public-commit-governance-gate.ps1`，把 `codex-home-export` 纳入顶层批准项硬门禁。
4. 更新 `.codex/chancellor/test-public-commit-governance-gate.ps1`，新增 `block-lock-list-approved-export-directory-missing`，补上新顶层位的独立负例回归。
5. 新建 `codex-home-export/` 最小骨架，落入：
   - `README.md`
   - `VERSION.json`
   - `manifest.json`

## 结果

- 当前仓已具备合法的 `codex-home-export/` 顶层位与第一版生产母体骨架。
- 顶层新增目录不再只靠人工记忆；目录锁定清单与治理门禁已同时收紧。
- 当前版本真源已在新仓出现，但尚未切换本机运行态，因此还不能宣称“已接管本机生产”。

## 理由

- 生产切换线要走得稳，必须先有合法落点与最小真源文件，再补切换/回滚脚本。
- 先补目录与门禁，再补脚本，能显著降低后续切换脚本反复返工的概率。

## 下一步

1. 落第一版 `install-to-home.ps1`。
2. 补配套回滚脚本与回滚说明。
3. 补切换后固定验板清单，并在本机做第一次非破坏性试切。