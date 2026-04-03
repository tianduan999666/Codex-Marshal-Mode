# codex-home-export

这是当前仓 `V4` 的**本机生产母体最小骨架**。

## 当前口径

- 默认入口仍是官方 `Codex` 面板
- 工程英文名统一为 `Chancellor Mode`
- 当前 GitHub 仓库统一为 `Codex-Chancellor-Mode`
- 本目录当前只承载“单机生产接管最小闭环”的最小必要件
- 当前已完成“本机生产桥接切换”，但仍不宣称已经完成全量生产母体重构

## 当前阶段

- `stage`：`bridge-ready`
- 已完成当前新 V4 仓到本机 `~/.codex` 的最小桥接切换
- 当前新仓已接管本机生产的最小真源与控制面
- 当前仍保留既有未覆盖运行资产，不视为全量生产母体重建

## 其他电脑最短安装

```powershell
git clone https://github.com/tianduan999666/Codex-Chancellor-Mode.git
cd Codex-Chancellor-Mode
.\install.cmd
```

普通用户只走 `.cmd` 包装入口，不直接运行 `install-to-home.ps1`、`verify-cutover.ps1` 等底层维护脚本。默认安装不会静默覆盖你现有的 `~/.codex/config.toml`。

## 当前已落文件

- `README.md`
- `AGENTS.md`
- `config.toml`
- `VERSION.json`
- `manifest.json`
- `install.cmd`
- `install-to-home.ps1`
- `initialize-workspace.ps1`
- `invoke-panel-command.ps1`
- `invoke-panel-command.test.ps1`
- `new-task.ps1`
- `render-panel-response.ps1`
- `render-panel-response.test.ps1`
- `rollback.cmd`
- `start-panel-task.ps1`
- `run-managed-install.ps1`
- `run-managed-self-check.ps1`
- `rollback-from-backup.ps1`
- `self-check.cmd`
- `verify-cutover.ps1`
- `upgrade-managed-install.ps1`
- `upgrade.cmd`
- `verify-panel-command-smoke.ps1`
- `verify-provider-auth.ps1`
- `start-panel-acceptance.ps1`
- `new-panel-acceptance-result.ps1`
- `verify-panel-acceptance-result.ps1`
- `panel-acceptance-checklist.md`
- `panel-acceptance-three-step-card.md`
- `panel-acceptance-pass-fail-sheet.md`
- `panel-acceptance-result-template.md`

## 当前未落文件

- 无必须缺口；当前仍建议保留人工面板验板记录
- 完整导出内容（如 `prompts/`、`scripts/`、`skills/`、`agents/` 等）

## 受管文件与运行态状态边界

- `manifest.json` 的 `included` 是当前生产母体受管文件真源；`install-to-home.ps1` 与 `verify-cutover.ps1` 都按这份清单工作。
- `install-record.json` 是本机安装记录，属于受管本地记录，会随每次生产同步一起更新。
- `task-start-state.json` 是本地开工状态缓存，只用于同版本轻量复核；`verify-cutover.ps1` 验真通过后会主动回写它；它不属于 `manifest` 受管文件，也不参与公开提交。
- 当前内部工程命名已统一为 `Chancellor Mode`；运行态主目录统一为 `config/chancellor-mode`，不再继续把 `marshal-mode` 作为主路径。
- 仓内 `config.toml` 已降级为可选模板，默认只会同步到 `config/chancellor-mode/config.template.toml`；`~/.codex/config.toml` 视为用户自有全局模型配置，不再静默覆盖。
- 当前对普通用户公开的维护层动作只保留 4 个：`install.cmd / upgrade.cmd / self-check.cmd / rollback.cmd`；底层 `.ps1` 退回维护层。
- 上述 4 个 `.cmd` 会被同步到 `~/.codex` 根目录；升级、自检、回滚都支持不进仓库目录直接执行。
- 当前仓没有官方面板前端源码；当前真正可控的是官方 Codex 面板的入口层、脚本层与真源层，不单独扩展独立面板。
- `invoke-panel-command.ps1` 是当前 `传令：XXXX` 的统一脚本路由入口；查询命令与做事命令都先走它。
- `start-panel-acceptance.ps1` 当前也固定通过 `invoke-panel-command.ps1` 取提示、开工骨架、版本口径、状态口径与升级口径；验板预期与真实入口链保持同源。
- `render-panel-response.ps1` 是当前面板输出控制面的统一渲染器；开场白、示例句、状态栏顺序、过程金句与收口模板都应先回到它和 `VERSION.json` 验证。
- 当前可执行 `.ps1/.json` 固定按 Windows PowerShell 5.1 兼容口径治理：文件编码统一 `UTF-8 with BOM`，脚本内部读 JSON 一律显式指定 `UTF-8`。

## 使用原则

### 普通用户只看这 4 个动作

| 动作 | 命令 | 说明 |
| --- | --- | --- |
| 安装 | `.\install.cmd` | 首次安装到本机 `~/.codex`，自动做传令冒烟与真实 provider/auth 探针验证 |
| 升级 | `%USERPROFILE%\.codex\upgrade.cmd` | 从任何目录升级；自动回源仓 `git pull --ff-only` 后重装，并补真实 provider/auth 探针 |
| 自检 | `%USERPROFILE%\.codex\self-check.cmd` | 完整验真 + 传令冒烟 + 真实 provider/auth 探针 |
| 回滚 | `%USERPROFILE%\.codex\rollback.cmd` | 从最近一次备份回滚受管文件 |

### 当前唯一主线（先看这 4 条）

1. 首次安装先执行：`.\install.cmd`。
2. 日常开工优先回官方 `Codex` 面板，直接说：`传令：修一下登录页`。
3. 若当前版本在本机已经验过，后续任务默认跳过重复验真，直接建任务，并留在当前会话继续。
4. 若要升级、自检、回滚，只用：`upgrade.cmd / self-check.cmd / rollback.cmd`；普通用户不再直接记底层 `.ps1`。
5. 当前统一入口链固定为：`VERSION.json` → `invoke-panel-command.ps1` → `render-panel-response.ps1 / start-panel-task.ps1`；其中 `传令：状态` 必须按 `status_bar_slots` 顺序渲染，`传令：升级` 必须按真源 3 行口径渲染，不能自行换序或改写边界。
6. 当前验板链固定为：`start-panel-acceptance.ps1` → `invoke-panel-command.ps1`；不再允许验板脚本绕过统一路由直接拼查询口径。
7. 跳过重复验真前仍会轻量复核固定轻检清单：`VERSION.json → config/cx-version.json`、`AGENTS.md`、`invoke-panel-command.ps1 → config/chancellor-mode/invoke-panel-command.ps1`、`start-panel-task.ps1 → config/chancellor-mode/start-panel-task.ps1`、`render-panel-response.ps1 → config/chancellor-mode/render-panel-response.ps1`；若不一致，自动回到验真流程。
8. 如需显式套用仓内模板 provider，再单独执行：`.\install.cmd -ApplyTemplateConfig`；默认安装与升级都不会替你切 provider / key。

### 当前对外感知

- 对外统一叫 `丞相`。
- `传令：XXXX` 是唯一做事入口；`传令：状态 / 传令：版本 / 传令：升级` 是仅保留的 3 个可选查询命令。
- 默认开场白固定为：`🪶 军令入帐。亮，即刻接管全局。`
- 新对话优先展示示例：`例如：传令：计算1+1=?`
- `传令：状态` 固定优先展示 6 行：`版本 / 上次检查 / 自动修复 / 关键文件一致性 / 当前模式 / 当前任务`。
- `传令：升级` 必须由用户主动提出，系统默认不自动升级。
- 固定边界提示是：`提示：丞相在检查阶段只检查自己，不会查看你的项目；执行阶段只按你的传令办事，不会擅自审查项目。`

### 当前次级材料（先不作为日常主路径）

- `install-to-home.ps1`、`verify-cutover.ps1`、`rollback-from-backup.ps1`：维护层脚本，普通用户不必直接记。
- `run-managed-install.ps1`、`run-managed-self-check.ps1`、`upgrade-managed-install.ps1`：给 `.cmd` 包装入口调用的编排层，不作为普通用户公开心智负担。
- `start-panel-acceptance.ps1`、`new-panel-acceptance-result.ps1`、`verify-panel-acceptance-result.ps1`：保留作维护层补充动作，不作为当前自用 MVP 主路径。
- `panel-acceptance-*` 文档：保留作补充参考，不作为当前日常必经步骤。

### 维护层真源预览（只给维护者备用）

```powershell
# 预览新对话示例句
powershell.exe -ExecutionPolicy Bypass -File .\codex-home-export\render-panel-response.ps1 -Kind hint

# 模拟完整传令入口
powershell.exe -ExecutionPolicy Bypass -File .\codex-home-export\invoke-panel-command.ps1 "传令：状态"

# 预览版本 3 行固定口径
powershell.exe -ExecutionPolicy Bypass -File .\codex-home-export\render-panel-response.ps1 -Kind version

# 预览状态栏 6 行顺序
powershell.exe -ExecutionPolicy Bypass -File .\codex-home-export\render-panel-response.ps1 -Kind status
```

## 说明

当前目录的存在，表示“新仓已完成本机生产桥接切换，并开始承担生产母体最小真源与控制面”；不表示“已经完成全量生产母体重构”。
