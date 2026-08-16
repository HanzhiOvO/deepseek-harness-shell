# DeepSeek Harness Shell（跨平台桌面版）

> 当前版本：2.0.0 · Electron + React + TypeScript + Tailwind CSS

一个把 **DeepSeek Harness**（官方 `@deepseek-ai/dsh`）包装成现代桌面应用的跨平台壳，支持 **Windows / macOS / Linux**。

v2.0 从 SwiftUI 壳重构为 Web 技术栈：界面更现代、可深度定制，并且三平台共用同一套 UI 与主进程逻辑。

```
┌──────────────────────────────────────────────────────────────┐
│ DeepSeek Harness Shell（Electron 主进程）                     │
│                                                              │
│  对话        ← WebContentsView（内嵌官方 dsh Web UI）         │
│  插件中心    ← dsh plugin --profile <name> add/remove/update  │
│  运行日志    ← stdout/stderr 按行流式回传                      │
│  环境与设置  ← dsh / node / npm / pnpm / git / brew 自检安装  │
│                                                              │
│  Renderer（React + Tailwind）：侧边栏 / 命令面板 / 卡片 UI    │
└───────────────────────────┬──────────────────────────────────┘
                            │ spawn + Pipe，无轮询
                            ▼
                   @deepseek-ai/dsh CLI（内核不改）
```

## 为什么是 Electron

- **真三平台**：一套代码在 Windows（WebView2 内核）、macOS、Linux 上运行；
- **内嵌官方 Web UI**：用 `WebContentsView` 把 dsh 页面嵌入应用窗口，还能跨源注入会话恢复脚本，这是 iframe 方案做不到的；
- **同生态**：主进程是 Node，与 dsh CLI / npm / pnpm 天然同构，环境与插件管理最稳；
- **可定制 UI**：React + Tailwind，彻底解决「原生控件难美化」的问题。

代价是应用包比 SwiftUI 壳更大（Electron 运行时约 200+ MB）。如果未来追求更小体积，可以在保留本前端代码的前提下迁移到 Tauri，主进程逻辑也按服务模块拆好，迁移成本可控。

## 功能

- **自动环境检测**：探测 `dsh`、`node`、`npm`、`pnpm`、`git`、`brew`，覆盖 Homebrew、nvm、volta、asdf、fnm、mise、Windows npm/Volta/Program Files 目录。
- **一键配置**：无 dsh 自动 `npm install -g @deepseek-ai/dsh`；无 Node 时 Homebrew 安装或引导下载；pnpm 优先 Corepack，自动生成 shim。
- **ChatGPT 式工作区**：
  - 服务状态胶囊、⌘R 启动、⌘. 停止；
  - Web 工具栏：后退/前进/刷新、缩放（⌘+ / ⌘− / ⌘0）、复制地址、系统浏览器打开；
  - 未启动时显示品牌占位页与最近会话。
- **本地历史会话**：
  - 只读同步 `$DSH_HOME/sessions`，支持 zstd CLI 早停读取与 Node 内置 zstd 回退；
  - 侧边栏最近会话、收藏（pin）、搜索、按更新/创建时间排序；
  - 点击会话通过 React fiber 脚本在官方 Web UI 内恢复。
- **插件中心**：
  - GitHub 地址 / ZIP 压缩包 / 本地文件夹 / npm 包名四种安装方式；
  - **直接把 .zip 或插件文件夹拖进窗口**即可安装；
  - 更新到最新、移除、打开 GitHub/npm 主页、定位本地源码、搜索过滤。
- **运行日志**：环境 / Web / 插件 / 会话四路日志，按级别筛选、全文搜索、导出 txt。
- **设置**：外观（跟随系统/浅色/深色）、自动启动/停止、端口、profile、DSH_HOME、API Key、dsh 升级、工具链定位、重置。
- **全局体验**：⌘K 命令面板、菜单栏/托盘状态组件、最近会话快捷入口、跨平台快捷键。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌘/Ctrl + R` | 启动服务 |
| `⌘/Ctrl + .` | 停止服务 |
| `⌘/Ctrl + K` | 命令面板 |
| `⌘/Ctrl + Shift + P` | 插件中心 |
| `⌘/Ctrl + Shift + H` | 历史会话 |
| `⌘/Ctrl + + / - / 0` | Web UI 缩放 |

## 开发

要求：Node.js 22.19+（推荐 24+）。

```bash
npm install
npm run dev        # 开发模式（HMR）
npm run typecheck  # 主进程 + 渲染进程类型检查
npm test           # 解析器单元测试
npm run build      # 构建 out/main、out/preload、out/renderer
```

### 冒烟测试

不创建窗口、自动执行：环境检测 → 插件清单 → 会话同步 → 启动 dsh web → HTTP 200 → 停止：

```bash
DSH_SHELL_USER_DATA=$(mktemp -d) DSH_SHELL_SMOKE=1 npx electron .
```

附带在临时 DSH_HOME 中验证插件安装/更新/移除：

```bash
ROOT=$(mktemp -d)
mkdir -p "$ROOT/userdata" "$ROOT/dshhome"
printf '{"autoStartWeb":false,"dshHome":"%s/dshhome"}' "$ROOT" > "$ROOT/userdata/settings.json"
DSH_SHELL_USER_DATA="$ROOT/userdata" DSH_SHELL_SMOKE=1 DSH_SHELL_PLUGIN_SMOKE=1 npx electron .
```

验证渲染层真实加载与 IPC 数据：

```bash
DSH_SHELL_USER_DATA=$(mktemp -d) DSH_SHELL_GUI_SMOKE=1 npx electron .
```

## 打包

```bash
npm run pack:mac     # macOS：dmg + zip
npm run pack:win     # Windows：nsis + zip（建议在 Windows 或 CI 上执行）
npm run pack:linux   # Linux：AppImage + deb
```

产物在 `release/`。`resources/icon.png` 是应用图标源，Windows/Linux 发布前建议补一张多尺寸 `.ico`。

> `DSH_SHELL_USER_DATA` 可用于便携模式：把所有壳设置重定向到指定目录。

## 目录结构

```text
src/
├── main/                    # Electron 主进程（Node）
│   ├── core/                # 日志总线、进程运行器
│   ├── services/            # 环境/Web/插件/会话/设置/内嵌 WebContents
│   └── index.ts             # 窗口、菜单、托盘、IPC、冒烟模式
├── preload/                 # contextBridge 安全桥
├── renderer/                # React + Tailwind UI
│   ├── components/          # 侧边栏、命令面板、安装弹窗…
│   └── views/               # 对话/历史/插件/日志/设置
└── shared/                  # 三端共享类型与解析器
tests/                       # Vitest 单元测试
resources/                   # 图标与品牌资源
```

## 数据归属与安全

- 壳设置：Electron `userData/settings.json`（0600）。
- ZIP 插件源码：`userData/PluginSources/`。
- Harness 数据仍在 `$DSH_HOME`（默认 `~/.dsh`），壳只读同步会话，不迁移不复制。
- 渲染进程启用 `contextIsolation`；主进程只向 dsh 子进程传 `DSH_HOME`、`DEEPSEEK_API_KEY`、`DSH_TELEMETRY_DISABLED` 与 PATH。
- 内嵌 dsh Web UI 使用独立 WebContents，`nodeIntegration` 关闭、`sandbox` 开启；外部链接一律交给系统浏览器。

## 已知限制

- dsh 为 developer preview，CLI/插件格式变化时需同步 `src/shared/parsers.ts` 与主进程解析器。
- 无 zstd CLI 的机器上，`.jsonl.zstd` 会话只可能显示目录名/时间（Node 内置 zstd 可解析单帧文件）。
- Electron 包体积大于原生壳；后续如需更小体积，可保留前端迁移到 Tauri。

## License

MIT
