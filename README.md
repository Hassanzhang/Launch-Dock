# LaunchDock

原生 macOS Python 项目启动坞，通过按钮分别启动和停止项目的前端、后端服务。

## 当前状态

需求确认与设计文档已建立，应用尚未开发，尚无可运行的 `.app`、构建脚本或已发布版本。目标范围登记为“未发布”。本仓库当前不提供可执行的安装或启动命令。

首版采用 `SwiftUI + Foundation`，供用户自己的 Mac 使用。虚拟环境与依赖由用户提前准备；应用检测服务工作目录下的 `.venv` 或 `venv`，执行手动填写的命令并展示实时日志。

## 文档入口

| 文档 | 用途 |
| --- | --- |
| [PRODUCT.md](PRODUCT.md) | 已确认需求、首版边界与验收标准 |
| [DEVELOPMENT.md](DEVELOPMENT.md) | 技术设计、数据契约与待验证决策 |
| [TASKS.md](TASKS.md) | 开发顺序、任务依赖及完成证据 |
| [VALIDATION.md](VALIDATION.md) | 实际验证记录与待执行验收 |
| [CHANGELOG.md](CHANGELOG.md) | 未发布变化与后续发布记录 |
| [AGENTS.md](AGENTS.md) | 语言、SOP、实现和 Git 协作约定 |

## 后续开发入口

从 [TASKS.md](TASKS.md) 的 T-001 开始，先确认本机构建工具与最低系统版本，再实现配置和主界面。功能完成后更新本文件，补充实际构建、运行和使用方法。

本地仓库默认分支为 `main`。当前未建立远端仓库，未推送或发布。
