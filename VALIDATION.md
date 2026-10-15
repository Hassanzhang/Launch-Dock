# 验证记录

## 2026-10-15 · T-006 · 未发布文档基线

范围：本轮仅交付设计文档；功能尚未实现。

### 已执行的环境检查

- `git status --short --branch`：文档修改前位于 `main`，工作区干净。
- `sw_vers`：macOS 26.2，BuildVersion 25C56。
- `uname -m`：arm64。
- `xcode-select -p`：`/Library/Developer/CommandLineTools`。
- 本次未检查 Swift/SDK 版本，未验证完整 Xcode 或 `.app` 构建能力。

### 文档检查

状态：通过。

- 使用 `python3` 内联检查脚本读取仓库根目录的 Markdown 文件，检查本地链接目标存在、编号定义唯一、F/T 引用可解析以及全部需求被 T-001 至 T-005 覆盖。
- 实际输出：`PASS: 7 Markdown files; local links valid; 9 unique requirements; 6 unique tasks; all references resolved; all requirements covered by implementation tasks.`
- `git diff --check` 与暂存后的 `git diff --cached --check`：均通过，无空白错误，后者覆盖全部新增文档。
- 人工对照已确认问答：首版为 Python，不再包含 Node.js/Java；原生技术栈、本地使用与服务生命周期均已同步；实施默认值单独标记。

文档提交通过 T-006 提交信息检索，不在本提交中循环回填自身 hash。

### 未覆盖

未编写或运行应用代码、单元测试、构建和真实应用交互；未验证 Python 环境解析、进程清理、日志性能或 `.app`。本记录不作为应用功能验收通过的证据。

## MVP 初始验收计划（建档时全部待执行）

以下为建档时的验证计划，不是执行结果；本轮实际覆盖情况见下方 MVP 开发记录。执行时分别记录环境、真实项目或合成样本、命令/步骤、结果、证据及清理情况。

| 场景 | 重点 | 任务 |
| --- | --- | --- |
| 本机构建与启动 | 明确 Swift/SDK 和系统版本，构建并打开 `.app` | T-001、T-005 |
| 项目配置 | 单服务/双服务、字段校验、编辑删除、空状态 | T-001 |
| 路径与持久化 | 中文/空格路径、重开恢复、配置损坏不覆盖 | T-001 |
| 环境解析 | `.venv`、`venv`、同时存在、缺失、不可执行 Python | T-002 |
| 环境实际使用 | 运行命令输出解释器路径及环境标识，核对所选环境 | T-002 |
| 多项目并发 | 重复点击、同时运行、互不影响、快速启停 | T-002、T-004 |
| 进程状态 | 零退出、非零退出、启动失败、信号终止、主动停止 | T-003、T-004 |
| 实时日志 | stdout/stderr、中文分块、长行、大量输出、切换、清空及新一轮运行 | T-003 |
| 子进程清理 | Python 父子进程、真实 `uvicorn --reload`、组长先退出、忽略 SIGTERM | T-004 |
| 所有权边界 | 无关进程不受影响，不因端口冲突杀进程 | T-004 |
| 窗口与退出 | 关闭/重开窗口、正常退出清理、重开应用不自动启动 | T-004、T-005 |
| 原生界面操作 | 键盘焦点、浅深色、错误反馈、长日志滚动与窗口缩放 | T-005 |
| 完整真实流程 | 用户自己的 Python 项目完成配置至退出 | T-005 |

强制退出、崩溃和断电不承诺执行退出清理；不将这些情况误记为正常退出已覆盖。首版不要求跨机器分发或固定时长的连续使用验收。


## 2026-10-15 · T-001、T-002、T-003、T-004、T-005 · MVP 开发

### 环境与样本

- macOS 26.2（25C56）、arm64；Swift 6.2.3；SDK 位于 CommandLineTools，工程目标 macOS 13。
- 核心样本由 `Tests/LaunchDockChecks/Checks.swift` 创建：真实临时 Python venv、中文/空格目录、持续运行、非零退出、信号退出、父子进程、忽略 SIGTERM 和大日志程序；不是用户业务项目。
- Python 3.9.6；uvicorn 0.39.0 安装于隔离的 `.build/ui-fixture/.venv`，用于真实 ASGI/reload 机制检查；不加入应用依赖。

### 实际执行与结果

| 检查 | 实际入口 | 结果 |
| --- | --- | --- |
| Swift 编译 | `swift build` | 通过 |
| 核心行为检查 | `swift run LaunchDockChecks` | 通过 |
| 真实 uvicorn 重载 | `LAUNCHDOCK_UVICORN_FIXTURE="$PWD/.build/ui-fixture" swift run LaunchDockChecks` | 通过，最终输出 `PASS all behavioral checks` |
| 本地 release 打包 | `./scripts/build-app.sh` | 通过，生成 dist/LaunchDock.app |
| 签名完整性 | `codesign --verify --deep --strict dist/LaunchDock.app` | 通过；仅本地 ad-hoc 签名，不代表公证 |
| Bundle 配置 | `plutil -lint dist/LaunchDock.app/Contents/Info.plist` | 通过 |
| 启动冒烟 | `open dist/LaunchDock.app` 后检查对应进程 | 成功启动且进程存在；不作为窗口视觉或交互通过证据 |
| 脚本语法 | `bash -n scripts/build-app.sh`、Python ast.parse | 通过 |
| 文档一致性 | Python 内联检查 Markdown 链接、编号和需求覆盖；Git diff 空白检查 | 8 份 Markdown、9 项需求、6 项任务，检查通过 |

行为检查覆盖：

- 配置顺序和字段往返、空服务/重复 ID/重复角色、未知 schemaVersion、损坏 JSON 保留。
- `.venv`/venv、优先级、缺失目录/环境及损坏环境不回退；核对真实 sys.executable 和 VIRTUAL_ENV。
- stdout/stderr、中文/emoji 跨字节解码、2,000 行和 1 MiB 上限、超过 2 MB 的输出与尾部日志。
- 零退出、非零退出、信号终止、并发服务、重复启动保护、新一轮日志隔离及 stopAll。
- 独立进程组、忽略 SIGTERM 后强制清理、组长先退出后的子进程清理、无关 sleep 进程保持运行。
- 真实 `uvicorn --reload` 启动，修改 ASGI 文件后工作进程替换，停止后组长与工作进程均不存在。

### 遇到的失败与处理

- 初始 `swift test` 返回 `error: no such module 'XCTest'`；当前 CLT 缺少该模块，改用无测试框架依赖的可执行检查程序，保留同类真实行为检查。
- UTF-8 分块检查暴露 Data.removeFirst 后索引不从零开始的越界，改为数组待解码缓冲后通过；结束运行前等待管道 EOF，避免关闭时截断尾部输出。
- 首次 reload 变更检查未等待 StatReload 建立初始 mtime 基线，导致测试未触发重载；修正测试等待条件后，实际新旧 worker 与清理检查通过。

### 未完成的真实界面与人工验收

通过原生自动化工具按 `.app` 路径和 bundle ID 分别连接，两次均返回原文：`Sky Computer Use native pipe closed before response`。原生自动化通道未连接成功，因此未取得可用的辅助功能树或截图。

以下保持待验收，不以代码存在、编译通过或应用进程存在代替：

- 配置 Sheet 的目录选择、校验、保存、取消，列表拖拽与键盘排序。
- 卡片启停按钮、日志 Tab/跟随/复制/清空、错误横幅、空态与窄窗口布局。
- 浅色/深色、键盘焦点与无障碍、视觉截图。
- 关闭窗口后服务继续运行、点击 Dock 重开、Cmd-Q 清理及退出失败反馈的真实 UI 路径。
- 用户自己的真实项目完整验收；macOS 13 或 Intel 机器兼容性；大量高输出服务的并发 UI 性能。

本轮没有发布版本、创建标签或推送。开发任务标为代码完成，T-005 的本机人工验收仍未勾选。


## 2026-10-15 · T-007 · 项目根目录虚拟环境回退

- 复现与原因：只读检查用户提供的目录结构，服务目录存在但没有 `.venv`/`venv`，配置所指项目根目录存在 `.venv/bin/python`；旧环境解析器仅接收工作目录，启动调用未传入项目根目录，因此无法命中共享环境。
- 修复：启动入口传入项目目录；按服务 `.venv`、服务 `venv`、项目 `.venv`、项目 `venv` 的顺序查找，环境损坏不回退，命令工作目录不变；全缺失时列出全部候选路径。不更改持久化格式或用户配置。
- 回归：在中文/空格路径创建真实 venv 与 frontend/backend 子目录，分别运行命令并核对解释器、VIRTUAL_ENV 和 cwd；覆盖服务环境优先、损坏不回退、根目录 venv、候选全缺失及未配置根目录时不搜索任意祖先。
- 实际命令：`swift run LaunchDockChecks`，结果通过，最终输出 `PASS all behavioral checks`。本轮未设置可选 uvicorn 检查环境变量，该专项跳过；进程管理实现未变更，其余核心检查通过。
- 构建：`swift build -c release --product LaunchDock` 通过；以临时可执行文件复制后原子替换 dist/LaunchDock.app 的二进制，避免截断运行中的旧二进制；本地 ad-hoc 重签名与 `codesign --verify --deep --strict`、`plutil -lint` 通过。
- 未覆盖：未启动用户的真实前端命令、未重启当前应用或其受管服务、未执行界面按钮验收。当前运行实例需要用户正常退出并重新打开新 .app 才使用新逻辑。
- 本轮为未发布修复；提交以 T-007 检索，不创建发布版本或标签。


## 2026-10-15 · T-008 · Homebrew npm 命令查找

- 原始错误：`zsh:1: command not found: npm`。只读登录及交互 Shell 探测均找到 `/opt/homebrew/bin/npm` 和 `/opt/homebrew/bin/node`；应用原先只继承启动环境，Finder 的最小 PATH 未覆盖这些目录。
- 修复：Python 虚拟环境 bin 优先，其后保留继承 PATH，再补充 Apple Silicon/Intel 常见 Homebrew 与系统命令目录。不执行用户 Shell 初始化文件，不新增工具安装或版本管理，不改变既有 Python 环境查找规则。
- 防回归：新增真实 npm/node 调用检查；修复前执行 `PATH=/usr/bin:/bin .build/debug/LaunchDockChecks` 失败（npm 不可解析），修复后同一命令全部通过，最终输出 `PASS all behavioral checks`。检查包含 `command -v npm`、`npm --version`、`node --version` 与虚拟环境 Python 解释器路径；同时运行原有配置、日志和进程清理回归。
- 构建与产物：`swift build -c release --product LaunchDock` 通过；原子替换本地 dist/LaunchDock.app 可执行文件并进行 ad-hoc 重签名，`codesign --verify --deep --strict` 和 `plutil -lint` 通过。
- 未覆盖：未运行用户的 npm 项目启动脚本、未安装依赖、未重启当前应用或服务，原生 UI 操作仍待人工验收；本轮没有运行可选 uvicorn 专项。nvm/fnm/asdf 等依赖初始化脚本的环境不在本次 Homebrew 路径修复覆盖范围。
- 本轮为未发布修复，提交以 T-008 检索，无版本或标签操作。


## 2026-10-15 · T-009 · 删除运行详情与前端浏览器链接

- 删除：ServiceSnapshot.exitDetail、退出码/信号的格式化与独立展示、就绪说明文案。保留 waitpid 回收与失败判定，不移除受管进程清理。
- 新增：从前端本次完整日志行提取本地 HTTP/HTTPS URL，在运行中的前端卡片使用原生 SwiftUI Link 调用默认浏览器；不自动打开、不新增健康检查。
- 自动检查：`swift run LaunchDockChecks` 通过，最终输出 `PASS all behavioral checks`；URL 样本覆盖 Vite 彩色输出、跨批次端口、IPv4、IPv6、通配地址、外站/凭据/无效端口拒绝。真实临时 Python 进程输出 Vite 格式样本（不是实际 Vite 应用），验证仅前端记录链接、清空日志保留、停止/重启/异常退出清除地址；其余配置、环境与进程清理回归通过。
- 编译与打包：`swift build --product LaunchDock`、`swift build -c release --product LaunchDock` 通过；原子替换本地 dist/LaunchDock.app 二进制并重签名，codesign 严格校验及 Info.plist 检查通过。
- 静态核对：Sources/Tests 中不再有 exitDetail、Signal:/Exit code: 展示字符串和旧免责声明；Markdown 链接、需求/任务 ID 与 Git 空白检查通过。
- UI 限制：原生自动化再次返回 `Sky Computer Use native pipe closed before response`，无法操作新 Link 或取得截图；真实默认浏览器打开、浅深色和布局效果待人工验收。用户提供的截图作为修改前参照，未冒充修改后结果。
- 本轮未启动或停止用户业务服务、未重启当前应用；需用户正常退出并打开新 .app 生效。启动程序未输出完整、受支持的本地地址时不展示链接。
- Impeccable context 与 craft-floor 用于保留现有原生界面风格；本轮为 SwiftUI 原生界面，不执行仅针对 Web 的机械检测，不迁移无关设计文档 schema。
- 本轮为未发布变更，无标签、推送或发布；提交以 T-009 检索。
