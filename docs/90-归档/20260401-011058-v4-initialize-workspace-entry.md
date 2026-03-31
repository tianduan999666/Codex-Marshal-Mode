# V4 补齐一键初始化入口记录

时间：2026-04-01 01:10:58
任务：第一百六十二刀（Phase 1 一键初始化最小入口）

## 一句话结论

已补齐 `codex-home-export/initialize-workspace.ps1`，现在 Windows 用户可以用一条命令完成最小骨架同步、Git 门禁安装、首个示例任务创建，并直接回到官方 Codex 面板开工。

## 动作

1. 新增 `codex-home-export/initialize-workspace.ps1`。
2. 一键初始化入口会顺序执行：
   - `install-to-home.ps1`
   - `install-public-commit-governance-hook.ps1`
   - `new-task.ps1`
   - 条件满足时执行 `verify-cutover.ps1`
3. 增强 `.codex/chancellor/install-public-commit-governance-hook.ps1`，新增可选参数 `RepoRootPath`，让 hook 安装脚本可复用、可隔离烟测。
4. 更新 `codex-home-export/README.md`、`codex-home-export/manifest.json`、`README.md` 与 `docs/30-方案/09-V4-本机生产切换最小闭环方案.md`，同步公开入口与生产母体文件清单。
5. 使用隔离临时目录做烟测，验证初始化入口会：
   - 写入临时 `fake-codex-home`
   - 安装 `.git/hooks/pre-push`
   - 创建 `v4-trial-001-第一个示例任务`
   - 把 `state.yaml` 默认写成 `running`

## 理由

- 主公已明确当前目标是 `Phase 1`：让用户先能在 10 分钟内跑通，而不是立刻做 UI。
- 仅有“一键新任务”还不够；如果安装、门禁与首个任务仍要靠人工拼接，首次体验依旧太重。
- 当前默认入口是官方 Codex 面板，因此初始化脚本的终点不是“让用户停在终端”，而是“准备完环境后立即回到面板继续”。

## 结果

- 现在 Windows 用户可直接执行：
  - `powershell.exe -ExecutionPolicy Bypass -File .\codex-home-export\initialize-workspace.ps1`
- 该命令会尽量自动完成：
  - 本机最小骨架同步
  - Git pre-push 治理门禁安装
  - 首个示例任务创建
  - 已登录场景下的自动验板
- 若未检测到 `auth.json`，脚本会跳过自动验板并给出人话提示，而不是让初始化直接失败。
- 若仓内已存在任务包或 `active-task.txt` 非空，脚本会默认跳过自动创建示例任务，避免重复制造演示包；若确需强制创建，可加 `-ForceExampleTask`。

## 下一步

1. 继续补 `10 分钟上手指南`，把安装、建任务、继续开工、收口四步写成人话。
2. 再补一段 100 字内公开试用文案，用来验证第一批真实需求。
3. 若主公认可，也可在下一刀把 `initialize-workspace.ps1` 再包一层远程安装入口，贴近 `irm ... | iex` 形态。
