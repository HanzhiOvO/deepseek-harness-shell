# DeepSeek Harness Shell（轻量跨平台桌面壳）

> 当前版本：2.1.0 · Tauri 2 + React + TypeScript + Tailwind CSS

一个把 **DeepSeek Harness**（官方 `@deepseek-ai/dsh`）包装成现代桌面应用的跨平台壳，支持 **Windows / macOS / Linux**。

v2.1 从 Electron 迁移到 **Tauri 2**：前端 UI 完全复用，后端改为 Rust，应用体积和内存占用大幅下降。

| 指标 | Electron v2.0 | **Tauri v2.1** |
| --- | --- | --- |
| macOS .app | 230 MB | **12 MB** |
| 安装包 DMG | 103 MB | **4.6 MB** |
| 主进程运行方式 | Chromium + Node | **系统 WebView + Rust** |
| 空闲内存 | 高（多进程） | **低（共享系统 WebView）** |

## 架构

```
┌──────────────────────────────────────────────────────────────┐
│ Tauri Rust 后端（单二进制，约 11 MB）                         │
│                                                              │
│  环境检测/安装 · dsh web 生命周期 · 插件管理 · 会话同步       │
│  设置持久化 · 日志事件 · 系统对话框 · 外部打开                │
└───────────────────────────┬──────────────────────────────────┘
                            │ Tauri IPC / Event
┌───────────────────────────▼──────────────────────────────────┐
│ React 渲染层（系统 WebView，不捆绑 Chromium）                 │
│  侧边栏 / 命令面板 / 历史会话 / 插件中心 / 日志 / 设置         │
│  对话区 iframe 内嵌官方 dsh Web UI                            │
└──────────────────────────────────────────────────────────────┘
```

## 功能

- **自动环境检测**：探测 dsh / node / npm / pnpm / git / brew，覆盖 Homebrew、nvm、volta、asdf、fnm、mise、Windows npm/Volta 目录。
- **一键配置**：无 dsh 自动 npm 安装；无 Node 时 Homebrew 安装或引导下载；pnpm 优先 Corepack，自动生成 shim。
- **对话工作区**：
  - iframe 内嵌官方 dsh Web UI（无额外浏览器进程）；
  - 「独立窗口」按钮创建原生 WebView 窗口，**点击历史会话会打开带注入脚本的窗口并自动定位到该会话**。
- **本地历史会话**：只读同步 `$DSH_HOME/sessions`，zstd CLI 早停读取；搜索、排序、收藏、复制、Finder/资源管理器定位。
- **插件中心**：GitHub / ZIP / 本地文件夹 / npm 四种安装方式，**拖文件进窗口安装**、更新、移除、打开主页与源码。
- **运行日志**：环境 / Web / 插件 / 会话四路日志，按级别筛选、搜索、导出 txt。
- **设置**：外观、自动启动/停止、端口、profile、DSH_HOME、API Key、升级 dsh、重置。
- **全局体验**：⌘K 命令面板、拖拽安装、Toast、深色/浅色主题。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌘/Ctrl + K` | 命令面板 |
| `Esc` | 关闭面板 |

> 启动/停止由顶栏按钮控制。Tauri 默认使用系统窗口标题栏。

## 开发

要求：Node.js 22.19+，Rust 1.85+（`brew install rust` 或 rustup）。

```bash
npm install
npm run dev          # tauri dev（前端 HMR）
npm run typecheck    # 前端类型检查
npm test             # 解析器单元测试
npm run build        # 构建 dist
npm run build:tauri  # 完整打包
```

### 冒烟测试

Rust 服务链冒烟（检测→插件清单→会话→启动 dsh web→HTTP 200→停止）：

```bash
DSH_SHELL_USER_DATA=$(mktemp -d) DSH_SHELL_SMOKE=1 cargo run -p deepseek-harness-shell
```

`DSH_SHELL_USER_DATA` 可指向任意目录，实现便携设置。

## 打包

```bash
npm run pack:mac     # macOS：app + dmg
npm run pack:win     # Windows：nsis
npm run pack:linux   # Linux：deb + AppImage
```

产物在 `src-tauri/target/release/bundle/`。macOS 需本机构建；Windows/Linux 建议在对应系统或 CI 上构建（仓库已带 GitHub Actions 三平台工作流）。

## 目录结构

```text
src/
├── renderer/           # React + Tailwind UI（Electron 版原样复用）
│   ├── components/
│   ├── views/
│   └── lib/tauriApi.ts # Tauri IPC 桥
├── shared/             # 类型与解析器
└── (已移除 Electron 主进程)
src-tauri/
├── src/
│   ├── services.rs     # 环境/Web/插件/会话/设置
│   ├── commands.rs     # Tauri 命令
│   ├── models.rs       # 序列化模型
│   └── lib.rs          # 应用装配
├── capabilities/       # 权限
└── tauri.conf.json
tests/                  # Vitest
```

## 数据与安全

- 壳设置：系统应用数据目录 `settings.json`。
- ZIP 插件源码：应用数据目录 `PluginSources/`。
- Harness 数据仍在 `$DSH_HOME`（默认 `~/.dsh`），壳只读同步会话。
- 渲染层无 Node 能力；子进程只传 `DSH_HOME`、`DEEPSEEK_API_KEY`、`DSH_TELEMETRY_DISABLED` 与 PATH。
- 独立 Harness 窗口使用 Tauri initialization script 自动选择会话；iframe 中的官方页面无法注入脚本，因此自动恢复会话统一走独立窗口。

## 已知限制

- dsh 为 developer preview，CLI/插件格式变化时需同步 `src/shared/parsers.ts` 与 Rust 解析器。
- 主窗口内的官方 Web UI 通过 iframe 展示，跨源限制下不能自动点击会话；点击侧边栏会话会自动打开独立窗口恢复。
- 无 zstd CLI 的机器上，`.jsonl.zstd` 会话只显示目录名与时间。

## 版本历史

- `swift-1.1.0`：SwiftUI 原生版（git tag）。
- `8c9beb7`：Electron v2.0（git commit）。
- 当前：Tauri v2.1。

## License

MIT
