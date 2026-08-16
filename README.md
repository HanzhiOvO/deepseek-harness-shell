# DeepSeek Harness Shell（macOS 原生版）

> 当前版本：1.1.0

一个把 **DeepSeek Harness**（官方 `@deepseek-ai/dsh`）包装成 macOS 桌面应用的**原生 SwiftUI 壳**。

它不重新实现 Agent / Session / Tool / Sandbox / Cordis，只负责让内核更好用：

- **自动检测并配置环境**：没有 `dsh` 时自动通过 npm 安装；没有 Node.js 时自动走 Homebrew 或引导下载。
- **ChatGPT 桌面应用式体验**：侧边栏 + 主工作区 + 工具栏状态胶囊 + 设置场景 + 快捷键。
- **全局快捷与菜单栏**：⌘K 快速跳转面板；⌘R/⌘. 启动停止服务；⌘+/-/0 缩放网页；菜单栏常驻状态组件（窗口关闭不退出时仍可控制服务与恢复会话）。
- **应用级图形界面**：插件中心、运行日志、环境与设置都是原生窗口，不塞在网页里；运行日志可按来源/级别筛选、全文搜索并导出为文本。
- **本地历史会话读取与同步**：侧边栏直接列出 `$DSH_HOME/sessions` 下的历史会话，显示标题、工作区、project 与时间，只读不改；支持收藏（pin）、搜索、排序、复制 ID/路径与 Finder 定位；回到前台自动刷新；点击任意会话会直接在官方 Web UI 中恢复该对话。
- **三种插件安装方式**：输入 GitHub 仓库地址、上传 ZIP 压缩包、选择本地文件夹（另附 npm 包名方式）。
- **低资源消耗**：不用 Electron / Chromium，应用包约 **4.6 MB**（zip 2.1 MB）；空闲无定时器；服务停止即释放内存。

> 内核仍是官方 `@deepseek-ai/dsh`。目前 DeepSeek Harness 处于 developer preview，接口可能变化。

---

## 架构

```
┌──────────────────────────────────────────────────────────────┐
│ DeepSeek Harness Shell.app（原生 SwiftUI + AppKit）            │
│                                                              │
│  对话        ← WKWebView（系统 WebKit，按需创建/释放）          │
│  插件中心    ← dsh plugin --profile <name> add/remove ...      │
│  运行日志    ← stdout/stderr 按行流式回传                       │
│  环境与设置  ← dsh / node / npm / pnpm / git / brew 自检与安装  │
│                                                              │
│  EnvironmentManager · WebServerManager · PluginManager        │
│  （不捆绑 dsh / Node / pnpm / Chromium）                       │
└───────────────────────────┬──────────────────────────────────┘
                            │ Process + Pipe，无轮询
                            ▼
                   @deepseek-ai/dsh CLI（内核不改）
                            │
              DSH profile（Cordis patch 层叠）
              ├── @deepseek-ai/dsh-base
              ├── @deepseek-ai/dsh-web-app   → 官方浏览器 UI
              └── 你安装的 dsh 插件（bundle）
```

### 和 Electron 版的关键区别

| 维度 | 本原生壳 | 典型 Electron 壳 |
| --- | --- | --- |
| 运行时 | SwiftUI/AppKit + 系统 WKWebView | 捆绑 Chromium + Node |
| 应用体积 | ~4.6 MB（zip 2.1 MB） | 常 >100 MB |
| 空闲进程 | 关闭窗口即退出，无驻留 | 常有主/渲染/GPU 多个进程 |
| GPU | 仅绘制可见内容，支持 App Nap | Chromium 合成器常驻 |
| 数据 | 复用系统全局 dsh，不复制依赖 | 常把 dsh 打进 asar |

---

## 功能

### 1. 环境自动检测与配置

启动时按以下顺序探测，并把结果显示在侧边栏和「环境与设置」：

```
PATH → ~/.local/bin → ~/.npm-global/bin → ~/Library/pnpm
     → /opt/homebrew/bin（含 node@18/20/22/24 多版本公式）
     → /usr/local/bin → /usr/bin
     → nvm / volta / asdf / fnm / mise / MacPorts / conda 目录
```

| 检测结果 | 处理 |
| --- | --- |
| 已有 dsh | 直接显示版本并启动 |
| 只有 dsh 缺失 | **自动**执行 `npm install --global @deepseek-ai/dsh`（优先当前 npm 前缀，不可写时退回 `~/.local`，无需 sudo） |
| 没有 Node.js，但有 Homebrew | 提供一键 `brew install node` |
| 两者都没有 | 引导打开 nodejs.org 下载页，安装后点击重新检测 |
| 没有 pnpm | 安装插件前自动准备：优先 Corepack，并在应用目录生成 pnpm shim；失败时 `npm i -g pnpm` |

已安装的 dsh 也可作为临时回退：只有 npm 时，启动服务会使用
`npm exec --package=@deepseek-ai/dsh -- dsh web ...`。

### 2. 对话工作区（参考 ChatGPT 桌面应用）

- `dsh web --host 127.0.0.1 --port 0`：让 OS 分配空闲端口，解析 stdout 中的 URL，加载进 WKWebView。
- 窗口工具栏显示运行状态胶囊（灰/橙/绿/红），可 `⌘R` 启动、`⌘.` 停止。
- Web 工具栏提供后退/前进/刷新/在浏览器打开、页面缩放（⌘+ / ⌘− / ⌘0）、复制服务地址与加载进度。
- 菜单栏状态组件可快速启动/停止、恢复最近会话，配合「关闭窗口不退出」实现后台驻留。
- 未启动时显示美观的占位页和「一键配置 / 一键启动」卡片。
- 官方 Web UI 的会话、模型、审批策略全部保留，登录态由 WebKit 持久化。

### 3. 插件中心

内部等价于官方 `dsh plugin --profile <name> add/remove ...`，安装后由 dsh 自动 reconcile `dsh.profile.bundles`。

| 安装方式 | 内部处理 |
| --- | --- |
| **GitHub 地址** | 支持 `owner/repo`、`https://github.com/owner/repo(.git)#ref`、`git+https`、`git@`。规范化为 pnpm 的 `github:owner/repo#ref`，**不需要本机 git** |
| **ZIP 压缩包** | `/usr/bin/ditto` 解压 → 自动定位 `package.json`（根目录或唯一顶层目录）→ `file:<path>` 安装。源码持久保存到 `~/Library/Application Support/DeepSeekHarnessShell/PluginSources`（pnpm 后续操作仍需解析该路径） |
| **本地文件夹** | 校验 `package.json` → `file:<path>` 直接安装，不复制源码以省磁盘 |
| **npm 包名** | 直接 `pnpm add <package>` |

插件卡片显示包名、spec、版本、来源（GitHub/归档/本地/npm）和 **BUNDLE** 徽章，可一键移除；支持**更新到最新**、打开 GitHub/npm 主页、在 Finder 中定位本地源码、复制包名/spec 与名称搜索。也可以把 `.zip` 或含 `package.json` 的文件夹**直接拖进插件中心**开始安装。

### 4. 本地历史会话读取与同步

- 数据源：`$DSH_HOME/sessions/<project>/<session>/session.jsonl(.zstd)`，与 Harness Web UI 完全同一份，壳只读不写。
- 侧边栏「历史会话」实时列出标题、工作区、更新时间，并可 pin 收藏；详情页支持搜索、排序（更新时间/创建时间）、收藏筛选、复制会话 ID/文件路径/工作区路径、在 Finder 中定位文件。
- **恢复会话**：点击历史会话后，壳会确保 Web UI 运行，并定位到会话列表中同 ID 的节点触发打开（找不到时按标题回退），对话内容由 Harness 自行加载，壳不复制会话数据。
- 同步策略（低能耗）：
  1. 先扫描目录与文件的 mtime/size；
  2. 只有新增/变化才读取内容，缓存未变会话；
  3. 内容读取优先 `zstd -dc | node(stdin)`，找到 `session/title` 后立即停止，不解压整段长会话；
  4. 没有 zstd CLI 时回退 Node 读取首帧头部（仍可显示工作区和时间）。
- 自动同步时机：应用启动、Web 服务启动、窗口回到前台（内部 5 秒节流）、手动点击同步按钮。

### 4.5 全局快捷键与命令面板

| 快捷键 | 功能 |
| --- | --- |
| `⌘R` | 启动服务 |
| `⌘.` | 停止服务 |
| `⌘K` | 打开快速跳转面板（搜索会话/功能） |
| `⌘⇧P` | 打开插件中心 |
| `⌘+` / `⌘−` / `⌘0` | Web UI 放大 / 缩小 / 实际大小 |

菜单栏组件与命令面板均无轮询定时器，窗口隐藏时不会增加 CPU 占用。

### 5. 设置

- 启动时自动连接、缺失 dsh 自动安装、关闭窗口时停止服务、关闭遥测。
- 外观模式：跟随系统 / 浅色 / 深色，即时生效。
- Web 端口（0 = 自动）、默认 profile、`DSH_HOME`、自定义 dsh 路径。
- `DEEPSEEK_API_KEY`（可选；仅作为环境变量传给子进程，设置文件权限 0600）。
- 一键升级 dsh 到 npm 最新版；工具链版本与路径可逐项在 Finder 定位；支持重置全部偏好。

---

## 构建

要求：macOS 13+，Xcode Command Line Tools（`xcode-select --install`）。

```bash
cd DeepSeekHarnessShell
./Scripts/build-app.sh
open "build/DeepSeek Harness Shell.app"
```

产物：

- `build/DeepSeek Harness Shell.app`：已 ad-hoc 签名，可直接双击运行。
- `build/DeepSeek Harness Shell.zip`：约 2.1 MB。

开发运行：

```bash
swift run DeepSeekHarnessShell
```

### 测试

```bash
swift run DeepSeekHarnessCoreSelfTests    # 解析器/定位器/URL 解析单元自检
swift run DeepSeekHarnessSmoke            # 检测环境、同步历史会话、真实启动 dsh web
swift run DeepSeekHarnessPluginSmoke      # 临时 DSH_HOME 下：安装 pnpm → 文件夹插件 → ZIP 插件 → 移除
```

> 插件冒烟测试会验证应用目录中的 pnpm shim；不会修改 `~/.dsh` 的真实 profile。

### 资源采样

```bash
./Scripts/measure-resources.sh
```

---

## 资源设计（低能耗 / 低占用）

1. **不捆绑运行时**：不打包 Electron、Chromium、Node、dsh，应用包约 4.6 MB（SwiftUI 二进制 3.3 MB + 官方 Harness 鲸鱼图标 1.3 MB）。
2. **系统 WebKit 复用**：仅当 Web 服务运行时创建 WKWebView，停止/退出后释放，WebKit 内容进程随之退出。
3. **零轮询**：所有子进程通过 Pipe + readabilityHandler 按行回传；没有周期性 Timer 刷新 UI。
4. **空闲即停**：默认关闭最后一个窗口就退出并停止 Node 服务；支持 App Nap。
5. **日志环形缓冲**：每个来源最多 500–700 行，避免日志无限增长。
6. **磁盘策略**：
   - dsh / pnpm 使用系统全局目录与内容寻址 store（pnpm 默认硬链接去重）；
   - 文件夹插件直接引用源目录，不复制；
   - ZIP 源只保留一份在应用数据目录，安装阶段临时目录自动清理。
7. **UI 流畅**：插件清单按需加载；`LazyVStack` / `List` 虚拟化；文件系统操作在后台队列，主线程只做 UI。

本机实测（arm64，运行官方 Web UI 时）：

| 项目 | 实测 |
| --- | --- |
| `.app` 体积 | 4.6 MB（含官方图标 1024px icns） |
| zip 体积 | 2.1 MB |
| 壳主进程 RSS | 约 85–100 MB |
| dsh web 子进程 RSS | 约 135–190 MB（取决于模型/插件，属内核本身） |
| 空闲 CPU | 加载完成后 <1% |
| 退出后 | 子进程全部清理，内存归零 |

> 注：dsh web 进程本身是 Node.js 应用，其内存由内核决定；壳额外增加的部分只有 SwiftUI + 一个 WebKit 页面。

---

## 目录结构

```text
DeepSeekHarnessShell/
├── Package.swift
├── Sources/
│   ├── DeepSeekHarnessCore/          # 无 UI 内核适配层
│   │   ├── EnvironmentManager.swift  # 工具链探测与一键安装
│   │   ├── WebServerManager.swift    # dsh web 生命周期与 URL 解析
│   │   ├── PluginManager.swift       # dsh plugin 包装、三种安装方式
│   │   ├── PluginSpec.swift          # GitHub 地址 / ZIP 定位
│   │   ├── ProcessRunner.swift       # 短命令 + 流式长任务
│   │   ├── AppSettings.swift         # 设置持久化（0600）
│   │   └── Logging.swift
│   └── DeepSeekHarnessShell/         # SwiftUI 应用
│       ├── App/
│       ├── Support/                  # WKWebView 宿主
│       └── Views/                    # 对话/插件/日志/设置/安装表单
├── Resources/Info.plist
├── Scripts/
│   ├── build-app.sh
│   ├── make-icon.swift
│   └── measure-resources.sh
└── Tests/                            # 单元自检 + 两个冒烟测试
```

---

## 数据归属与安全

- 壳设置：`~/Library/Application Support/DeepSeekHarnessShell/settings.json`（0600）。
- ZIP 插件源：`~/Library/Application Support/DeepSeekHarnessShell/PluginSources/`。
- Harness 数据仍在 `$DSH_HOME`（默认 `~/.dsh`），包括 profile、会话、凭证、storage，壳不迁移不复制。
- 壳只向 dsh 子进程传递 `DSH_HOME`、`DEEPSEEK_API_KEY`、`DSH_TELEMETRY_DISABLED` 和 PATH。
- WKWebView 不注入任何 Node/原生桥接；插件是本地代码，以当前用户权限运行，只安装信任的来源。
- 应用未沙箱化（ad-hoc 签名），分发前可用 Developer ID 签名并公证。

## 已知限制

- `dsh plugin` 依赖 pnpm；GitHub 插件若带构建脚本，pnpm 可能要求 `allowBuilds` 白名单，应用会把官方提示完整展示在日志中。
- 文件夹方式直接引用源目录，使用期间请勿移动/删除该文件夹。
- DeepSeek Harness 为 developer preview，后续 CLI/插件格式变化时需同步更新解析器。

## License

MIT
