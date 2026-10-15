# 技术设计与实现

## 当前状态

未发布 MVP 已实现；需求见 [PRODUCT.md](PRODUCT.md)，界面基线见 [DESIGN.md](DESIGN.md)，任务及未完成验收见 [TASKS.md](TASKS.md)。应用采用原生 SwiftUI、Foundation、AppKit 与 Darwin/POSIX，无第三方运行依赖。

工程使用 Swift Package，最低目标 macOS 13，Swift tools version 5.9。本机实际工具链为 Swift 6.2.3，macOS 26.2（25C56）、arm64、Command Line Tools SDK；未做最低目标系统和 Intel 实机验证。

## 模块

| 位置 | 职责 | 需求/任务 |
| --- | --- | --- |
| `Sources/LaunchDock/LaunchDockApp.swift` | 单窗口 SwiftUI 入口、窗口捕获、添加项目菜单 | F-007、F-009 / T-001、T-004 |
| `Sources/LaunchDock/ContentView.swift` | 侧栏、拖拽排序、卡片、日志、删除确认 | F-003、F-005、F-009 / T-001、T-003、T-004 |
| `Sources/LaunchDock/LogOutputView.swift` | 仅负责日志文本布局、原生双向滚动和跟随位置 | F-005、F-009 / T-010 |
| `Sources/LaunchDock/ProjectEditor.swift` | 配置表单、目录选择、即时校验 | F-001、F-002 / T-001 |
| `Sources/LaunchDock/AppModel.swift` | 配置操作、编辑删除约束、正常退出清理与 Dock 重开 | F-007、F-008 / T-001、T-004 |
| `Sources/LaunchDockCore/Configuration.swift` | Codable 模型、原子存储、环境检测 | F-001、F-002、F-004、F-008 / T-001、T-002 |
| `Sources/LaunchDockCore/FrontendURL.swift` | 本地访问 URL 解析 | F-010 / T-009 |
| `Sources/LaunchDockCore/ServiceRunner.swift` | 进程所有权、状态、停止、UTF-8 日志与容量限制 | F-003、F-005、F-006、F-007 / T-002、T-003、T-004 |
| `Sources/ProcessSupport/ProcessSupport.c` | posix_spawn、独立进程组、工作目录与管道描述符 | F-003、F-007 / T-002、T-004 |

以上为小规模直接实现，不引入数据库、Web 服务或额外架构框架。

## 配置契约

使用系统 Application Support 路径下的 `LaunchDock/projects.json`，UTF-8 JSON 原子替换写入。可通过开发用环境变量 `LAUNCHDOCK_CONFIG_PATH` 隔离文件。

| 对象 | 字段 | 持久化 |
| --- | --- | --- |
| Configuration | `schemaVersion`（当前 1）、`projects`（数组顺序即手动排序） | 是 |
| Project | `id`（UUID）、`name`、`directory`、`services` | 是 |
| Service | `id`（UUID）、`role`（frontend/backend）、`workingDirectory`、`command` | 是 |
| ServiceSnapshot / Job | 状态、PID、环境路径、错误、前端访问 URL、日志、描述符与清理期限 | 否 |

保存及读取时验证项目/服务 ID 不重复、名称非空、路径为绝对路径、角色唯一且至少一个服务、命令非空。目录无需隶属于项目目录；启动前重新检查其存在性。

读取损坏文件、未知 schemaVersion 或权限失败时，不覆盖原文件；界面本次禁止修改配置。保存失败保持内存中的旧配置。重新打开恢复配置，运行状态从停止开始。命令本身按明文保存，宿主环境与日志不写入配置。

## Python 环境与命令

1. 先查找服务工作目录的 `.venv`、`venv`，都不存在时再查找配置的项目根目录的 `.venv`、`venv`；同目录去重，不向任意上级目录递归搜索。首个命中环境的 `bin/python` 必须可执行；损坏时不继续回退。命令仍在服务工作目录执行。
2. 继承应用进程环境，将环境 `bin` 放在 PATH 首位，设置 VIRTUAL_ENV 和 PYTHONUNBUFFERED=1，移除 PYTHONHOME。继承 PATH 后补充 `/opt/homebrew/bin`、`/opt/homebrew/sbin`、`/usr/local/bin`、`/usr/local/sbin` 与系统命令目录，覆盖 Finder 最小 PATH 下的 Homebrew npm/node；不修改 Shell 初始化文件。
3. 通过固定 `/bin/zsh -f -c` 执行用户命令；工作目录由 spawn file action 设置，目录不拼接进 shell 命令。
4. stdin 指向 `/dev/null`，stdout/stderr 合并进入同一非阻塞管道；不提供 PTY 或交互输入。

`-f` 禁用普通用户 shell 启动配置，不承诺与交互终端一致。支持前台非交互 Python 命令；不支持 `&`、nohup、daemon 或主动脱离受管进程组的程序。绝对解释器路径和命令内覆盖变量可绕过虚拟环境设置，用户需自行保证命令使用选定环境。

启动入口 `ServiceRunner.start(_:projectDirectory:)` 将配置的项目根目录传给环境解析器；该参数不修改服务工作目录，也不增加配置字段或迁移。查找失败列出全部候选路径，便于检查项目根目录配置。

## 进程所有权、状态与退出

采用 `posix_spawn` 是因为普通 Foundation Process 不能提供这里所需的原子独立进程组创建契约。C 封装通过 `POSIX_SPAWN_SETPGROUP`、pgroup=0 在启动时建立以子 PID 为组号的独立进程组，同时设置目录、信号默认值、信号掩码和描述符继承边界。

运行管理器在 MainActor 上维护每个服务唯一 Job；定时器每 100ms 检查非阻塞管道和 `waitpid(WNOHANG)`，不会同步等待子进程。启动/停止状态锁定重复操作；旧 Job 完全回收前不允许启动新实例。

- 内部状态：stopped、starting、running、stopping、failed；运行中只表示受管命令进程启动成功。
- 正常零退出为已停止；非零或意外信号退出为异常退出；主动停止不显示异常。
- 停止向受管进程组发送 SIGTERM，5 秒仍存在则 SIGKILL，再等待清理；只操作本次启动并跟踪的有效组，拒绝自身组和非法组号。
- 组长已退出而子进程仍存在时保留 Job 并清理子进程；组长回收、进程组消失且输出管道 EOF 后才最终结束，避免丢失尾部日志。
- 清理超时保留记录并提示错误，禁止声称已停止；退出清理失败时取消应用退出。

关闭窗口不退出应用；捕获的 NSWindow 保留供 Dock 重开。正常应用退出返回 terminateLater，清理成功后回复系统继续退出。强制退出、崩溃、断电不保证清理；不支持接管遗留进程。

## 日志与性能边界

UTF-8 分块解码保留末尾不完整码点。每服务最多保留最近 2,000 行及 1 MiB（包括无换行长行），新启动清空旧缓冲；停止后可继续查看本次日志。

stdout/stderr 在管道入口合并，不标注输出流来源；显示内核读到的合并顺序。每轮每服务最多读取 64 KiB，100ms 批次更新；这是 MVP 的有界主线程读取方案，很多高输出服务并发时仍需性能测量，出现明显卡顿再迁移 I/O。

## 前端访问地址（T-009）

`FrontendURL.swift` 从完整日志行提取 HTTP/HTTPS 本地地址，剥离 ANSI 控制序列；仅接受 localhost、127.0.0.1、IPv6 回环与通配监听地址，拒绝外站 URL、含凭据 URL 和无效端口。通配地址转换为 localhost。不在收到半个端口号时提前记录链接。

受管进程仅为 frontend 角色且处于 running 时，将首次识别的地址存入本次 ServiceSnapshot.browserURL。清空日志不清除此地址；开始停止、进程结束或新一轮启动清除。服务卡片通过 SwiftUI Link 使用系统默认浏览器打开，不自动打开或发起健康检查。启动程序未输出适配地址时不展示链接。

原 exitDetail 字段及 Signal/Exit code 格式化和展示已删除；异常退出只给出通用错误与原始程序日志。waitpid 状态仍用于正确回收、判定 stopped/failed，不作为可见退出码展示。

## 界面与配置操作

按 DESIGN.md 使用 NavigationSplitView、原生控件、SF Symbols、系统字体与语义颜色。卡片空间不足纵向排列；错误保留原文和中文解释；日志支持服务切换、跟随暂停、复制及清空。

运行中的项目暂时禁止编辑整个配置；删除需确认，先清理该项目服务再保存配置删除，不删除项目文件。排序使用原生 List onMove 持久化数组顺序，同时提供右键上移/下移供键盘操作。真实界面操作、浅深色及布局验收因自动化连接失败尚未完成。

## 日志呈现（T-010）

日志面板局部使用 NSViewRepresentable 包装 NSScrollView/NSTextView。关闭宽度跟踪和折行，以 glyph usedRect 与额外空行测量文档大小；文档至少与视口等宽等高，文字原点固定为 (16, 12)。使用指定的 12pt 常规等宽字体链，段落最小/最大行高均为 19.2pt，8 空格 tab 间隔。输出不改变原字符串，不改 ServiceRunner、LogBuffer 或服务配置。

日志更新及视口布局时保存原滚动原点；跟随启用则只滚至底部，保留横向位置；暂停则保留可用范围内的横纵位置。服务切换替换文本，暂停时从左上角显示新服务；空日志显示占位文本。工具栏仍在 SwiftUI VStack 顶部，独立于 NSScrollView。

原生控件布局检查可通过 `swiftc Sources/LaunchDock/LogOutputView.swift Tests/LogOutputChecks.swift -o .build/log-output-checks` 编译后运行，不要求 XCTest；它验证控件尺寸与滚动，不代替真实窗口截图和鼠标操作验收。

## 独立状态与卡片占位（T-011）

ContentView 的 ServiceStatusPresentation 仅负责状态文字/颜色：stopped 灰“已停止”、starting 黄“正在启动”、running 绿“运行中”、failed 红“启动失败”、stopping 黄“正在停止”。侧栏按每个配置服务 ID 读取快照，显示圆点与角色；卡片使用同一个映射，不再对项目状态做汇总，也不改变底层状态含义。

T-011 保留原项目标题、编辑/删除与 LogPanel；T-012 已将灰色 GroupBox 替换为内部标题的服务卡片。仅用真实内容高度替换原卡片 ScrollView 的弹性 240pt 占位，GeometryReader 按实际宽度选择横排/纵排，并用 PreferenceKey 同步卡片实际高度。页边距 20pt、区块 16pt 不变，LogPanel 填满余下空间。T-011 未修改 LogOutputView 或工具栏；T-012 的局部样式调整见下。

`./scripts/check-project-detail.sh` 在隔离配置、未展示的 NSWindow/NSHostingView 中检查真实详情布局、超长路径、缩放和各状态文字；不启动用户服务，不替代实际参考图视觉验收。

## 构建与验证入口

- `swift build`：debug 编译。
- `./scripts/build-app.sh`：release 构建，生成 `dist/LaunchDock.app` 并本地 ad-hoc 签名；不设置正式发布版本。
- `swift run LaunchDockChecks`：无 XCTest 依赖的可执行行为检查，使用临时目录中的真实 Python 环境与进程。
- 可选 uvicorn 集成检查入口和前置环境见 [README.md](README.md)。

实际测试结果、失败修复及未覆盖项见 [VALIDATION.md](VALIDATION.md)。


## 卡片与日志工具栏精修（T-012）

ContentView 的 ServiceCardSurface 共用原生语义背景、0.5pt 分割线边框和 12pt 内边距，供服务及缺省卡片使用。卡片内部标题添加角色图标，PID 先转 String 防止 SwiftUI 本地化插入千分位；路径采用 12pt tertiary 样式。

LogPanel 保留原 selection/following 绑定、复制与清空闭包；仅隐藏 picker 标签并缩短选项文案，使用带无障碍标签/提示的原生图标按钮和 button toggle。LogOutputView 与服务层不变。窗口最小内容尺寸改为 980×600，最大侧栏宽 320 时仍有空间横排两张卡；更窄的嵌入视口继续纵排兜底。
