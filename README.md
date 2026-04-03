# 丞相模式（Chancellor Mode）

## 一句话简介

丞相模式（Chancellor Mode）是 Codex 的统一指挥模式。
让 Codex 按 `传令：XXXX` 执行任务，稳定、可控、可复核。

## 快速开始

1. `git clone https://github.com/tianduan999666/Codex-Chancellor-Mode.git`
2. 在仓库根目录运行：`.\codex-home-export\install.cmd`
3. 打开官方 Codex 面板，新建对话，输入：`传令：版本`

## 日常用法

```text
传令：我要做 修一下登录页
传令：状态
传令：版本
```

## 版本与真源

所有面板输出均来自真源 `codex-home-export/VERSION.json`。当前版本号用 `传令：版本` 查看；当前现行版本为 `CX-202604032031`。

## 升级

升级只走维护层标准入口，不直接跑底层 `.ps1`。

```powershell
cd Codex-Chancellor-Mode
%USERPROFILE%\.codex\upgrade.cmd
```

## 运行路径

运行态主路径：`%USERPROFILE%\.codex\config\chancellor-mode`。普通用户只记 `install.cmd / upgrade.cmd / self-check.cmd / rollback.cmd` 四个入口。

## 文档入口

- 启动：`docs/00-导航/02-现行标准件总览.md`、`docs/00-导航/01-V4-重启导读.md`、`docs/20-决策/01-V4-重启ADR.md`、`docs/10-输入材料/01-旧仓必需资产清单.md`、`docs/30-方案/01-V4-最小目录蓝图.md`、`docs/30-方案/02-V4-目录锁定清单.md`、`docs/30-方案/03-V4-MVP边界清单.md`
- 基线：`docs/40-执行/01-任务包规范.md`、`docs/40-执行/02-任务包模板.md`、`docs/40-执行/03-面板入口验收.md`、`docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md`、`docs/reference/02-仓库卫生与命名规范.md`、`docs/40-执行/04-执行区现行件与证据稿说明.md`、`docs/40-执行/05-跨轮恢复说明.md`、`docs/40-执行/06-跨轮恢复样本.md`、`docs/40-执行/07-V4-Trial-验收报告.md`、`docs/40-执行/08-V4-Trial-缺陷清单.md`、`docs/40-执行/09-V4-Trial-改进建议.md`、`docs/40-执行/10-本地安全提交流程.md`、`docs/40-执行/11-任务包半自动起包.md`
- Target：`docs/20-决策/02-V4-Target-进入决议.md`、`docs/30-方案/04-V4-Target-蓝图.md`、`docs/30-方案/05-V4-Target-冻结清单.md`、`docs/30-方案/06-V4-OS-参考技术采纳评估.md`、`docs/30-方案/07-V4-规划策略候选规范.md`、`docs/30-方案/08-V4-治理审计候选规范.md`、`docs/40-执行/12-V4-Target-实施计划.md`
- 维护：`docs/40-执行/13-维护层总入口.md`、`docs/40-执行/14-维护层动作矩阵与收口检查表.md`、`docs/40-执行/15-拍板包准备与收口规范.md`、`docs/40-执行/16-拍板包半自动模板.md`、`docs/40-执行/17-拍板结果回写模板.md`、`docs/40-执行/18-异常路径与回退模板.md`、`docs/40-执行/19-多 gate 与多异常并存处理规则.md`、`docs/40-执行/20-复杂并存汇报骨架模板.md`、`docs/40-执行/21-关键配置来源与漂移复核模板.md`、`docs/90-归档/01-执行区证据稿归档规则.md`
- 试用：`docs/40-执行/22-10分钟上手指南.md`、`docs/40-执行/23-公开试用招募文案包.md`、`docs/40-执行/24-第一轮试用反馈记录表.md`、`docs/40-执行/25-试用接待与跟进话术.md`、`docs/40-执行/26-第一轮试用周报模板.md`、`docs/40-执行/27-第一轮真实发帖执行清单.md`、`docs/40-执行/28-V2EX首发执行包.md`、`docs/40-执行/29-少数派首发执行包.md`、`docs/40-执行/30-朋友圈与熟人转介绍首发执行包.md`、`docs/40-执行/31-三渠道首发选择对比卡.md`
