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
