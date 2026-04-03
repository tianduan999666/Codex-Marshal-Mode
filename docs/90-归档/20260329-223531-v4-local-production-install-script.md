# V4 本机生产切换脚本首版落地记录

时间：2026-03-29 22:35:31
任务：第六十二刀（本机生产切换脚本首版）

## 动作

1. 在 `codex-home-export/` 中新增首版 `install-to-home.ps1`，只做非破坏性最小同步。
2. 当前脚本同步范围仅限：
   - `config/cx-version.json`
   - `config/marshal-mode/manifest.json`
   - `config/marshal-mode/README.md`
   - `config/marshal-mode/install-record.json`
3. 脚本默认保留用户凭据与隐私文件，不触碰 `auth.json`、`sessions/` 等运行态私有内容。
4. 同步更新 `codex-home-export/README.md`、`codex-home-export/manifest.json` 与 `docs/30-方案/09-V4-本机生产切换最小闭环方案.md`，使文档口径与脚本现状一致。
5. 先对 `temp/generated/` 下临时目标做一次真实写入验证，再对真实 `~/.codex` 做一次 `DryRun` 验证。

## 结果

- 当前仓已经具备首版单机 `install-to-home` 能力。
- 该能力已能把新仓母体版本镜像与安装记录同步到目标 `~/.codex` 结构，但仍未覆盖完整生产接管内容。
- 当前仍不能宣称“已丝滑接管本机生产”，因为回滚脚本与固定验板闭环尚未落地。

## 验证

1. 真实写入验证目标：`temp/generated/local-production-cutover-smoke-20260329-2230`
2. 验证结果：成功生成
   - `config/cx-version.json`
   - `config/marshal-mode/manifest.json`
   - `config/marshal-mode/README.md`
   - `config/marshal-mode/install-record.json`
3. `~/.codex` 验证方式：`-DryRun`
4. 结果：通过，且未执行真实写入。

## 下一步

1. 补 `rollback-from-backup.ps1` 或等价回滚脚本。
2. 补切换后固定验板清单。
3. 再做第一次真实但可回滚的本机试切。