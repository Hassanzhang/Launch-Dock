# LaunchDock

原生 macOS Python 项目启动坞，通过按钮分别启动和停止项目的前端、后端服务。

## 当前状态

当前构建版本 **0.1.1**（build 2），DMG 已完成打包及安装启动检查，真实鼠标拖拽验收待完成；最新已登记标签仍为 `v0.1.0`。MVP 已实现，使用 `SwiftUI + Foundation` 与少量 Darwin/POSIX 进程启动代码，无第三方应用依赖。已通过本机构建、核心行为检查及部分隔离窗口交互/截图验证；用户真实项目完整验收仍待完成，详见 [VALIDATION.md](VALIDATION.md)。

最低构建目标为 macOS 13；目前仅在 macOS 26.2 / Apple Silicon 验证，不声称已测试其他系统或架构。供用户自己的 Mac 使用；已提供本机 arm64 的 DMG，不包含 Developer ID 签名、公证或公开分发。

## DMG 安装

当前产物：`dist/LaunchDock-0.1.1-arm64.dmg`（Apple Silicon）。打开镜像，将 `LaunchDock.app` 拖入其中的 `Applications` 入口；复制完成后卸载镜像，从应用程序目录启动。替换已有应用前先正常退出，避免影响运行中的服务。

只提供本地 ad-hoc 签名，尚未验证下载后 Gatekeeper 的放行行为；DMG 不代表 Apple 公证。其他系统/架构仍需单独验证。

构建并自动校验 DMG：

```bash
./scripts/build-dmg.sh
```

脚本复用下方应用构建入口，按 VERSION 和实际二进制架构命名产物；镜像完整性、只读挂载内容、应用版本、图标、架构与签名全部通过后才替换已有 DMG。脚本不会自动安装应用或发布到 GitHub。

## 构建与打开

需要可用的 Swift 5.9+ 工具链及 macOS SDK。当前机器的 Command Line Tools / Swift 6.2.3 可完成构建，无需安装额外框架。

在仓库根目录执行：

```bash
./scripts/build-app.sh
open dist/LaunchDock.app
```

脚本读取 `VERSION`，进行 release 构建，将用户提供的 `Assets/AppIcon.png` 转为多尺寸 `.icns`，生成带版本与图标的 `.app` 并进行本地 ad-hoc 签名。输出目录 `dist/` 和构建目录 `.build/` 不进入 Git；脚本不安装应用、不更改系统工具链、不发布版本。

## 使用

1. 先在 Python 服务目录或项目根目录准备 `.venv` 或 `venv`，并安装项目依赖。
2. 点击“添加项目”，填写名称、选择项目目录。
3. 开启前端或后端配置，选择各自工作目录，填写命令，例如 `python app.py` 或 `python -m uvicorn main:app --reload`。
4. 保存后，点击对应服务的“启动”；日志在下方面板查看，可切换、暂停跟随、复制和清空。前端日志输出本地访问地址后，点击卡片上的「打开前端」链接即可在默认浏览器打开。
5. 点击“停止”清理对应服务；关闭窗口后继续运行，点击 Dock 可重新打开窗口；正常退出应用会先清理全部受管服务。

前端、后端是角色名称，首版均要求 Python 环境。至少配置一个服务；多个项目可同时运行。列表可拖拽排序，也可通过项目右键菜单上移/下移。编辑前需要停止该项目服务；删除只删除 LaunchDock 配置，不删除项目目录。

配置保存在 `~/Library/Application Support/LaunchDock/projects.json`；重开应用恢复列表和顺序，但不自动启动服务。配置读取失败时保留原文件并禁止本次修改，请修复后重新打开。

## 行为与限制

- 查找顺序为：服务目录 `.venv` → 服务目录 `venv` → 项目根目录 `.venv` → 项目根目录 `venv`。前后端可共享根目录环境；命令仍在各自工作目录运行。首个命中环境损坏时提示，不回退到其他环境或系统 Python。环境在启动时检测。
- 使用非交互 `/bin/zsh -f -c` 执行命令；不读取交互式终端环境；PATH 补充 Apple Silicon/Intel 常见 Homebrew 和系统目录，可调用已安装的 npm/node。不自动加载 nvm/fnm/asdf 初始化脚本，不支持需要输入的程序、`&`、`nohup` 或自行 daemonize/脱离进程组的服务。
- 虚拟环境路径、`PATH`、`VIRTUAL_ENV` 与 Python 无缓冲输出由应用设置，查找优先级为虚拟环境 bin → 继承 PATH → 常见 Homebrew/系统目录；绝对解释器路径或命令内覆盖环境可能绕过该设置。
- 状态依据进程生命周期更新，不执行端口或健康检查。前端链接从本次日志识别，仅支持 HTTP/HTTPS 本地地址；无适配地址时不显示，停止或重启清除。
- 停止先发送 SIGTERM，5 秒后仍存在则发送 SIGKILL。强制退出应用、崩溃、断电无法保证清理，首版不接管遗留进程。
- 每服务保留最近 2,000 行且不超过 1 MiB 的本次日志；不写日志文件。程序自身缓冲可能影响输出及时性。
- 项目命令是本机明文配置，不建议在命令中填写凭据。

## 开发验证

```bash
swift build
swift run LaunchDockChecks
```

检查程序使用真实临时 Python 环境和进程，覆盖配置、异常环境、解释器、日志、并发、退出和父子进程清理。依赖系统 `/usr/bin/python3` 的 `venv` 能力；不依赖 XCTest，适用于本机仅有 Command Line Tools 的环境。

日志布局专项检查（实际 AppKit 控件，覆盖排版、跟随和视口缩放）：

```bash
swiftc Sources/LaunchDock/LogOutputView.swift Tests/LogOutputChecks.swift -o .build/log-output-checks
.build/log-output-checks
```

详情布局专项检查（隔离配置，不启动服务）：

```bash
./scripts/check-project-detail.sh
```

可选的真实 uvicorn 重载检查（只向 `.build/check-project/.venv` 安装测试依赖，不是应用依赖）：

```bash
python3 scripts/prepare-check-project.py
LAUNCHDOCK_UVICORN_FIXTURE="$PWD/.build/check-project" swift run LaunchDockChecks
```

测试环境变量 `LAUNCHDOCK_CONFIG_PATH` 可将配置隔离到指定文件，避免测试改动日常项目；正常使用无需设置。

## 文档入口

| 文档 | 用途 |
| --- | --- |
| [PRODUCT.md](PRODUCT.md) | 已确认需求、首版边界与验收标准 |
| [DESIGN.md](DESIGN.md) | 用户提供的原生界面设计基线 |
| [DEVELOPMENT.md](DEVELOPMENT.md) | 实际架构、数据契约与实现决策 |
| [TASKS.md](TASKS.md) | 任务进度、依赖及完成证据 |
| [VALIDATION.md](VALIDATION.md) | 实际验证记录与未覆盖项 |
| [CHANGELOG.md](CHANGELOG.md) | 未发布变化与后续发布记录 |
| [AGENTS.md](AGENTS.md) | 语言、SOP 和 Git 协作约定 |

本地仓库默认分支为 `main`；当前构建为 `0.1.1`，真实鼠标拖拽验收完成前不建立 `v0.1.1`；最新注释标签仍为 `v0.1.0`。未创建 GitHub Release，不含公开分发或公证。
