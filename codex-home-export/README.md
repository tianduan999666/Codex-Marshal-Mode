# codex-home-export

这是当前仓 `V4` 的**本机生产母体最小骨架**。

## 当前口径

- 默认入口仍是官方 `Codex` 面板
- 工程英文名统一为 `Chancellor Mode`
- 当前 GitHub 仓库统一为 `Codex-Chancellor-Mode`
- 本目录当前只承载“单机生产接管最小闭环”的最小必要件，已完成本机生产桥接切换，但不宣称已经完成全量生产母体重构

## 当前阶段

- `stage`：`bridge-ready`
- 已完成当前新 V4 仓到本机 `~/.codex` 的最小桥接切换，并接管本机生产的最小真源与控制面
- 当前仍保留既有未覆盖运行资产，不视为全量生产母体重建

## 其他电脑最短安装

```powershell
git clone https://github.com/tianduan999666/Codex-Chancellor-Mode.git
cd Codex-Chancellor-Mode
.\install.cmd
```

普通用户只走 `.cmd` 包装入口，不直接运行 `install-to-home.ps1`、`verify-cutover.ps1` 等底层维护脚本。默认安装不会静默覆盖你现有的 `~/.codex/config.toml`。

## 当前已落文件

- `manifest.json` 的 `included` 是当前生产母体受管文件清单唯一真源。
- README 这里只保留阶段、入口与使用说明，不再重复抄整份落文件列表。
- 如需核对具体受管文件，请直接查看 `manifest.json`。

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
- 当前公开受管的 `.ps1/.json/.md/.toml` 与入口 `.cmd` 已统一按 Windows PowerShell 5.1 兼容口径治理：文件编码固定 `UTF-8 with BOM`，脚本内部读 JSON 一律显式指定 `UTF-8`。

## 使用原则

### 普通用户只看这 4 个动作

| 动作 | 命令 | 说明 |
| --- | --- | --- |
| 安装 | `.\install.cmd` | 首次安装到本机 `~/.codex`，自动做传令冒烟与真实 provider/auth 探针验证 |
| 升级 | `%USERPROFILE%\.codex\upgrade.cmd` | 从任何目录升级；若源仓有未提交改动则停止，并先按 `公开入口/生产母体 / 维护层在研 / 本地任务/运行态 / 文档/方案 / 其他待人工判断` 分组提示，再给出 `status / stash / restore / 重新 clone` 指引；干净时再执行 `git pull --ff-only` 后重装，并补真实 provider/auth 探针 |
| 自检 | `%USERPROFILE%\.codex\self-check.cmd` | 完整验真 + 传令冒烟 + 真实 provider/auth 探针 |
| 回滚 | `%USERPROFILE%\.codex\rollback.cmd` | 从最近一次备份回滚受管文件 |

### 当前最短主线

1. 首次安装只用上表“安装”。
2. 日常开工优先回官方 `Codex` 面板，直接说：`传令：修一下登录页`。
3. 若当前版本在本机已经验过，后续任务默认跳过重复验真，直接建任务；若已有激活任务，也可直接说：`传令：继续` 或 `传令：继续当前任务`。
4. 若要升级、自检、回滚，直接回上表 4 个动作；普通用户不再单记底层 `.ps1`。

### 维护层补充口径（备用）

1. 当前统一入口链固定为：`VERSION.json` → `invoke-panel-command.ps1` → `render-panel-response.ps1 / start-panel-task.ps1`；其中 `传令：状态` 必须按 `status_bar_slots` 顺序渲染，`传令：升级` 必须按真源 3 行口径渲染，不能自行换序或改写边界。
2. 当前验板链固定为：`start-panel-acceptance.ps1` → `invoke-panel-command.ps1`；不再允许验板脚本绕过统一路由直接拼查询口径。
3. 跳过重复验真前仍会轻量复核固定轻检清单：`VERSION.json → config/cx-version.json`、`AGENTS.md`、`invoke-panel-command.ps1 → config/chancellor-mode/invoke-panel-command.ps1`、`start-panel-task.ps1 → config/chancellor-mode/start-panel-task.ps1`、`render-panel-response.ps1 → config/chancellor-mode/render-panel-response.ps1`；若不一致，自动回到验真流程。
4. 如需显式套用仓内模板 provider，再单独执行：`.\install.cmd -ApplyTemplateConfig`；默认安装与升级都不会替你切 provider / key。
5. 若当前 provider=`crs` 且统一 `/models` 探针返回 404，脚本会明确提示“需回官方 Codex 面板真人验证一次”；不再把这种情况当成静默通过。

### 当前对外感知

- 对外统一叫 `丞相`。
- 开场白、示例句、查询命令、状态栏 6 行、升级边界与固定边界提示，统一以 `VERSION.json` 为准；这里不再重复抄一整套对外口径。

### 当前次级材料（先不作为日常主路径）

- `install-to-home.ps1`、`verify-cutover.ps1`、`rollback-from-backup.ps1` 与 `run-managed-*`：都属于维护层底层脚本或编排层，不作为普通用户日常主路径。
- `start-panel-acceptance.ps1`、`new-panel-acceptance-result.ps1`、`verify-panel-acceptance-result.ps1` 与 `panel-acceptance-*` 文档：都属于验板补充材料，不作为当前自用 MVP 日常必经步骤。

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
