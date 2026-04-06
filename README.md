# 丞相模式（Chancellor Mode）

给官方 `Codex` 面板加一层更稳的中文任务入口。

## 它解决什么痛点

- 开工前要反复解释背景，效率低。
- 换聊天后上下文容易断，任务接不上。
- 版本、真源、运行态不清楚，容易误判。
- 自检、升级、失败提示太硬，不知道下一步怎么做。
- 改了受管文件后，容易出现“同版本不同内容”。

## 我们做了什么

- 把日常入口统一成 `传令：XXXX`。
- 固定了 `传令：版本`、`传令：状态`、`传令：升级`。
- 做了 `传令：交班`、`传令：接班`，支持换聊天继续干活。
- 加了任务级进度快照，减少重复交代背景。
- 把安装、升级、自检、回滚收敛成固定维护入口。
- 给主链失败场景补了更清楚的人话收口。
- 建了版本纪律：受管文件变更后必须 bump 版本并重验。

## 用它有什么好处

- 开工更快：直接下任务，不先折腾脚本。
- 接力更稳：聊天切换不容易断线。
- 状态更清：版本、运行态、当前任务更容易看懂。
- 维护更稳：安装、升级、自检、回滚路径固定。
- 风险更低：默认不会覆盖你现有的 `~/.codex/config.toml`。

## 最短安装

```powershell
git clone https://github.com/tianduan999666/Codex-Chancellor-Mode.git
cd Codex-Chancellor-Mode
.\install.cmd
```

普通用户只做这 3 行。

## 装完先试

- `传令：版本`
- `传令：状态`
- `传令：修一下登录页`

## 常用命令

- `传令：继续`
- `传令：交班`
- `传令：接班`

## 维护入口

- `%USERPROFILE%\.codex\upgrade.cmd`
- `%USERPROFILE%\.codex\self-check.cmd`
- `%USERPROFILE%\.codex\rollback.cmd`

## 其他必要信息

- 普通用户默认回官方 `Codex` 面板使用，不需要长期在终端里操作。
- 当前公开真源在 `codex-home-export/`，版本真源是 `codex-home-export/VERSION.json`。
- 维护说明见 `docs/README.md`。
