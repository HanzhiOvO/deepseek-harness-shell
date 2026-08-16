# DeepSeek Harness Shell

> 🧩 **dsh 社区桌面壳** · 轻量 · 跨平台 · 当前版本 1.1.0

一个把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`@deepseek-ai/dsh`）包装成现代桌面应用的社区项目，支持 **Windows / macOS / Linux**。

---

> ## ⚠️ 社区项目声明
>
> **本项目是社区开发者的个人作品，与 DeepSeek 公司及 DeepSeek Harness 官方团队无关。**
>
> - 本项目不代表 DeepSeek 官方立场，也不是官方作品；
> - 项目没有获得官方的背书、认证或任何形式的支持；
> - 所有与 DeepSeek 相关的名称、商标、图标权利归其权利人所有，本项目仅用于技术学习和社区交流；
> - 上游官方项目地址：<https://github.com/deepseek-ai/deepseek-harness>，使用前请阅读并遵守上游项目的许可协议与使用条款。
>
> 本应用不修改上游 dsh 内核，只在其外部提供桌面体验。

---

## 为什么是 Tauri

本项目目前使用 **Tauri 2 + React + TypeScript + Tailwind CSS**：前端 UI 用 Web 技术构建，后端用 Rust，运行时复用系统 WebView。

| 指标 | Electron 实现 | **当前 Tauri 实现** |
| --- | --- | --- |
| macOS `.app` | 230 MB | **约 12 MB** |
| 安装包 DMG | 103 MB | **约 4 MB** |
| 运行时 | Chromium + Node | **系统 WebView + Rust** |
| 空闲占用 | 高（多进程） | **低（共享系统 WebView）** |

## 功能

- **环境检测与一键配置**：自动探测 `dsh`、`node`、`npm`、`pnpm`、`git`、`brew`，无 dsh 时可用 npm 用户级前缀自动安装，无 Node 时引导安装，pnpm 优先 Corepack。
- **对话工作区**：主窗口 iframe 内嵌 dsh Web UI；点击历史会话会打开带自动定位脚本的独立窗口。
- **历史会话**：只读同步 `$DSH_HOME/sessions`，支持 zstd 早停读取、搜索、排序、收藏、复制与 Finder/资源管理器定位。
- **插件中心**：GitHub / ZIP / 本地文件夹 / npm 四种安装方式，支持拖拽安装、更新、移除、打开主页与源码。
- **运行日志**：环境 / Web / 插件 / 会话四路日志，实时留存，可筛选、搜索、导出和按来源清空。
- **设置**：外观模式、自动启动/停止、端口、profile、DSH_HOME、API Key、升级 dsh、重置。
- **全局体验**：⌘K 命令面板、深色/浅色主题、Toast 通知、单实例锁、托盘驻留与异常启动重试。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌘/Ctrl + K` | 打开命令面板 |
| `Esc` | 关闭命令面板 |

## 安装与使用

### 从发布包安装

在 [Releases](../../releases) 下载对应平台产物，当前稳定版为 **v1.1.0**：

- Windows：`nsis` 安装包或 zip；
- macOS：`dmg` 或 `.app`；
- Linux：`deb` 或 `AppImage`。

### 从源码运行

要求：

- Node.js 22.19+（推荐 24+）
- Rust 1.85+（`brew install rust` 或 rustup）

```bash
npm install
npm run dev          # 开发模式
npm run build:tauri  # 构建当前平台应用
```

打包：

```bash
npm run pack:mac     # macOS：app + dmg
npm run pack:win     # Windows：nsis
npm run pack:linux   # Linux：deb + AppImage
```

> `DSH_SHELL_USER_DATA` 环境变量可把应用设置重定向到任意目录，便于便携使用和测试。

### 测试

```bash
npm run typecheck    # 前端类型检查
npm test             # 解析器单元测试

# Rust 检查
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets --all-features -- -D warnings

# Rust 服务链冒烟：检测 → 插件清单 → 会话 → 启动 dsh web → HTTP 200 → 停止
DSH_SHELL_USER_DATA=$(mktemp -d) DSH_SHELL_SMOKE=1 cargo run --manifest-path src-tauri/Cargo.toml
```

## 架构

```text
src/renderer/             React + Tailwind 界面（侧边栏/命令面板/各页面）
src/shared/               类型与解析器
src-tauri/src/
  commands.rs             Tauri 命令
  services.rs             环境/Web/插件/会话/设置服务
  models.rs               序列化模型
  lib.rs                  应用装配与冒烟模式
```

主进程负责管理 `dsh web` 子进程、调用 `dsh plugin`、同步本地会话元数据、持久化应用设置以及托盘生命周期。**上游 dsh 内核与官方 Web UI 不被修改。**

## 数据归属与安全

- 应用设置：应用数据目录 `settings.json`；可用 `DSH_SHELL_USER_DATA` 重定向，Unix 下以 `0600` 权限保存。
- ZIP 插件源码：同一应用数据目录的 `PluginSources/`。
- Harness 数据仍在上游默认位置 `~/.dsh`（或你配置的 `DSH_HOME`），本应用只读同步会话，不迁移、不复制。
- 渲染层没有 Node 能力；子进程只接收 `DSH_HOME`、`DEEPSEEK_API_KEY`、`DSH_TELEMETRY_DISABLED` 与 `PATH`。
- 插件是本地代码，以当前用户权限运行；profile 名称会限制为安全路径片段，请只安装可信来源。

## 已知限制

- 上游 dsh 处于 developer preview，CLI / 插件格式可能变化，需要同步更新解析器。
- 主窗口内的 Web UI 通过 iframe 展示，受跨源限制不能自动点击会话；点击侧边栏会话会打开独立窗口并注入定位脚本。
- 没有 zstd CLI 的机器上，`.jsonl.zstd` 会话只能显示目录名和时间。
- 本社区项目不提供官方客服、账号或模型服务支持。

## 参与贡献

欢迎通过 Issue / Pull Request 参与，但请先阅读本文件顶部的社区声明：本仓库是一个独立社区项目，请勿将其内容误解为官方信息。

## 版本历史

- 当前：**1.1.0**（Tauri 跨平台版）
- `1.1.0`：修复 Web/插件进程生命周期、设置与 profile 同步、日志留存、数据目录和插件回滚；增加托盘驻留、自动安装 dsh、启动失败重试、响应式界面、可访问性改进和放大的统一应用图标。
- `1.0.1`：修复启动白屏、dsh 升级卡死、图标边距和社区项目声明，增加单实例锁。
- 历史：`swift-1.1.0` SwiftUI 原型、Electron 原型保留在 git 历史中

## License

本项目代码按 [MIT](LICENSE) 协议发布。上游 DeepSeek Harness 的代码、图标与商标归其各自权利人所有。
