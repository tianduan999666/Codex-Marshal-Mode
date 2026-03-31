# V4 补齐一键新任务轻入口记录

时间：2026-04-01 00:56:35
任务：第一百六十一刀（Phase 1 一键新任务轻入口）

## 一句话结论

已补齐 `codex-home-export/new-task.ps1`，现在 Windows 用户可以先用一条命令创建任务包，再回到官方 Codex 面板继续，不必手工创建 5 个文件。

## 动作

1. 新增 `codex-home-export/new-task.ps1`。
2. 轻入口会自动：
   - 计算下一个 `v4-trial-<三位序号>`
   - 根据标题生成语义任务名
   - 调用 `.codex/chancellor/create-task-package.ps1` 创建任务包 5 件套
   - 更新 `active-task.txt`
   - 打印一段可直接贴回官方 Codex 面板的话术
3. 增强 `.codex/chancellor/create-task-package.ps1`，新增可选参数 `InitialStatus`，让维护层脚手架可显式决定起包初始状态。
4. 让 `new-task.ps1` 默认把用户向新任务落为 `running`，对齐主公新路线中的 Phase 1 口径。
5. 更新 `README.md`、`codex-home-export/README.md`、`codex-home-export/manifest.json`、`docs/40-执行/11-任务包半自动起包.md` 与 `docs/30-方案/09-V4-本机生产切换最小闭环方案.md`，同步公开入口、生产母体文件清单与使用说明。
6. 使用临时目录做烟测，验证新入口会创建 `v4-trial-001-修复登录页-bug`，并把 `state.yaml` 默认写成 `running`。

## 理由

- 主公已明确：当前大众化第一步不是 UI，而是先把高频机械动作压缩成最小命令。
- 若还要求用户手工创建 5 件套文件，Phase 1 的 10 分钟上手目标就站不住。
- 当前默认用户入口是官方 Codex 面板，因此轻入口的终点不是“继续停在终端”，而是“建完任务后立刻回到面板继续”。

## 结果

- 现在 Windows 用户可直接执行：
  - `powershell.exe -ExecutionPolicy Bypass -File .\codex-home-export\new-task.ps1 -Title "修复登录页 bug"`
- 执行后会得到：
  - 新任务目录
  - 已更新的 `active-task.txt`
  - 一段可直接粘贴到官方 Codex 面板的继续话术
- 维护层仍保留完整控制入口：
  - `.codex/chancellor/create-task-package.ps1`

## 下一步

1. 继续补 `一键初始化`，把当前公开试用链从“会建任务”推进到“会开工”。
2. 再写一份真正给新手的 `10 分钟上手指南`。
3. 等这两项补齐后，再发第一轮公开试用文案，验证是否有人愿意试用与付费辅导。
