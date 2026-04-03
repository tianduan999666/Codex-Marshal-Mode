# 丞相模式与 ECC 功能对比分析

最后更新：2026-04-03
状态：现行分析文档
适用范围：判断“是否冗余、缺什么、哪里更强”时使用
信息来源：本仓当前实现 + ECC 官方公开 README（2026-04-03 复核）

## 一句话结论

丞相模式和 ECC 不是重复产品。
丞相模式主打 `官方 Codex 面板 + 中文单入口 + 真源控口径 + 本机稳态`；ECC 主打 `跨 harness 工程能力包 + 多 Agent + Skills + Hooks + 扩展生态`。

## 对比总表

| 维度 | 丞相模式当前实装 | ECC 当前公开口径 | 判断 |
| --- | --- | --- | --- |
| 日常入口 | `传令：XXXX` + `状态 / 版本 / 升级` 3 个查询命令 | 多入口并存；插件安装、手动安装、slash 命令、skills、agents 都存在 | 丞相更简单；ECC 更大更全 |
| 面板感知 | 固定开场白、固定边界提示、固定 6 行状态栏、固定收口骨架 | README 未体现类似“面板状态栏 + 真源顺序渲染”能力 | 丞相在面板可感知上更强 |
| 入口路由 | `invoke-panel-command.ps1` 统一路由，查询与做事同源 | ECC 更偏插件/skills/commands 组合，不是单一中文入口协议 | 丞相更适合中文面板场景 |
| 安装策略 | `install.cmd` 单入口；默认不覆盖用户 `~/.codex/config.toml`；安装后补 provider/auth 探针 | ECC 公开 Codex 参考配置强调 project-local，且不主动 pin `model_provider` | 两边都重视别乱改全局；丞相更偏“装完能直接在这台机上稳用” |
| 轻量复核 | 同版本先轻检，再决定是否完整验真 | README 未体现同类“版本镜像 + 关键文件”轻检链路 | 丞相更贴近你现在的单机开工场景 |
| 自动修复 | 漂移时先修再开工；安装/升级/自检统一补真链探针 | ECC 有更大范围的 scripts/hooks/rules，但不是围绕你这套单机面板开工链设计 | 场景不同，不是简单谁替代谁 |
| 多 Agent | 当前没有独立多 Agent 编排运行时 | ECC 公开结构里有 `agents/`、36 个 specialized subagents | ECC 明显更强 |
| Skills | 当前没有大规模可复用 skill 库 | ECC 公开结构里有大量 skills；Codex 部分 README 列出 16 个 auto-loaded skills | ECC 明显更强 |
| Hooks / 自动触发 | 当前主要靠显式脚本与真源路由 | ECC README 明确有 hooks、Node.js scripts；但也明确 `Codex` 还没有 Claude 式 hook parity | ECC 整体更强；Codex 落地仍有平台边界 |
| 持续学习 | 当前没有 instincts / 自动抽取模式 | ECC 公开口径有 continuous-learning、continuous-learning-v2、skill-create、instinct-* | ECC 明显更强 |
| 跨平台/跨 harness | 当前目标是你这套 Windows + Codex 面板主链 | ECC 公开支持 Windows/macOS/Linux，并面向多种 harness | ECC 明显更强 |

## 是否冗余

| 问题 | 结论 | 理由 |
| --- | --- | --- |
| 丞相模式是否和 ECC 完全重复 | 否 | 丞相模式解决的是“中文单入口、状态可感知、真源收口、单机稳态” |
| 当前还要不要单独做独立面板 | 不要 | 你现在真正可控的是官方 Codex 面板的入口层、脚本层、真源层 |
| 当前还有没有多余命令 | 现行口径已基本收紧 | 对外只保留 `传令：XXXX / 状态 / 版本 / 升级`；这部分已经不冗余 |

## 当前缺什么

| 缺口 | 当前是否具备 | 对照 ECC | 结论 |
| --- | --- | --- | --- |
| 多 Agent 分工 | 否 | ECC 有专门 agent 目录与多角色协作 | 真实缺口 |
| 可复用技能库 | 弱 | ECC 有 skills 体系 | 真实缺口 |
| 持续学习 / 模式沉淀 | 否 | ECC 有 continuous-learning 与 instinct 相关能力 | 真实缺口 |
| 跨 harness 兼容 | 弱 | ECC 明确面向多 harness | 真实缺口 |
| 自动化工作流运行时 | 弱 | ECC 有 `multi-*` 命令，但依赖额外 `ccg-workflow` runtime | 真实缺口，但不是零成本补齐 |

## 当前哪里已经更强

| 点 | 丞相模式当前优势 | 为什么成立 |
| --- | --- | --- |
| 中文心智成本 | 只记 `传令：XXXX` | 对普通中文用户更短、更稳 |
| 面板状态感知 | 6 行状态栏按真源顺序固定渲染 | 用户能一眼看清系统在干嘛 |
| 真源一致性 | 开场白、示例句、边界提示、状态栏、收口模板都从 `VERSION.json` 出 | 文案不容易各处漂移 |
| 单机生产稳态 | 安装/升级默认不覆盖全局 provider；并补真实 provider/auth 探针 | 这正是你近期真实踩过的坑后补强出来的能力 |
| 开工链路贴合 | 轻量检查 → 必要时完整验真 → 必要时自动修复 → 自动建任务 → 进入执行 | 这条链现在就是围绕面板实际使用路径做的 |

## 不要自欺的地方

```text
丞相模式还没有超越 ECC 的地方：
1. 多 Agent 体系
2. Skills 生态
3. 持续学习
4. 跨 harness 能力
5. 大规模自动化运行时
```

```text
丞相模式已经比 ECC 更适合你的地方：
1. 中文单入口
2. 面板状态可感知
3. 真源控表达
4. 单机安装稳态
5. 官方 Codex 面板开工链
```

## 最终判断

| 问题 | 结论 |
| --- | --- |
| 我们是否冗余 | 否 |
| 我们是否缺功能 | 是，且主要缺在多 Agent / Skills / 持续学习 / 跨 harness |
| 我们是否已经超越 ECC | 只在“中文单入口 + 面板状态感知 + 单机稳态”这条窄主线上更强；整体能力面仍未超越 |

## 参考来源

- ECC 官方仓：<https://github.com/probinger/00-everything-claude-code>
- ECC 官方 README（Codex / 安装 / 结构说明）：<https://raw.githubusercontent.com/probinger/00-everything-claude-code/main/README.md>
- 当前丞相真源：`codex-home-export/VERSION.json`
- 当前安装母体说明：`codex-home-export/README.md`
