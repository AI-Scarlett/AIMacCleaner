# AIMacCleaner

<p align="center">
  <strong>智能 Mac 存储空间清理 & 应用管理工具</strong>
</p>

<p align="center">
  <a href="#功能特性">功能</a> •
  <a href="#安装">安装</a> •
  <a href="#使用方法">使用</a> •
  <a href="#从源码构建">构建</a> •
  <a href="#技术架构">架构</a> •
  <a href="#更新日志">更新</a>
</p>

---

## 功能特性

### 🧹 Mac 清理
- 内置 35+ 条本地扫描规则，覆盖浏览器、办公、AI Agent、开发、系统、社交等分类
- AI 扫描：接入大模型（DeepSeek / OpenAI / 智谱 GLM / 通义千问等）智能发现更多可清理项
- 智能清理：一键清理所有「安全」级别的项目
- 三级风险标识：安全 / 注意 / 危险
- 按分类、应用、风险等级筛选 + 关键词搜索

### 📱 APP 管理
- 自动扫描本机所有 .app 应用
- 显示应用大小、缓存大小、数据大小
- 三种操作：重置（清缓存/数据）、基础卸载（保留数据）、完全卸载（彻底清除）
- 批量选择 + 批量操作
- AI Agent 类应用自动归入「其它工具」，避免重复

### 📦 依赖管理
- 自动扫描 Homebrew、npm、pip 安装的包
- 显示包大小和依赖关系说明
- 支持卸载和缓存清理

### 🔧 其它工具
- **全面扫描用户主目录 dotdir**（~/.xxx），排除系统目录
- **30+ 种 AI Agent 自动识别**：Hermes、yi-code、Cline、MiniMax、CodeArts、Cherry Studio、LM Studio、Codex、OpenClaw、QClaw、Kimi、DeepSeek 等
- **25+ 种开发工具自动分类**：.nvm、.pyenv、.conda、.cargo、.android、.ohos、.harmony 等
- **分类筛选**：AI Agent / CLI / 包管理 / 开发 / 其它
- **AI 影响分析**：勾选项后点击「AI 分析」，调用大模型分析删除影响，结果直接显示在列表中
- 未识别的 dotdir 归入「其它」分类，标注风险提示

### 🛡️ Agent 审计
- **50+ 种 AI Agent 内置支持**：自动发现本机 Agent 会话数据，审计其对本地文件的操作记录
- **多种存储格式解析**：JSONL、SQLite (state.vscdb)、JSON (file-changes)、MD、数据库
- **VSCode 类 Agent 智能识别**：Trae、Cursor、CodeBuddy、Windsurf 等自动解析 vscdb + file-changes
- **CLI 类 Agent 深度解析**：Claude Code、Codex、Kimi、OpenClaw、Hermes 等专用解析器
- **多 Agent 框架支持**：CrewAI、AutoGen、OpenHands、MetaGPT、CAMEL、DeerFlow 等
- **自定义 Agent 添加**：支持从已安装 App 中选择或手动指定路径添加
- **防重复添加**：内置 Agent 不可重复添加
- **操作记录分类**：写入、编辑、读取、删除、执行命令、搜索、对话等

### 🖥️ Agent 监控
- **真实进程追踪** - 通过 `ps` + `lsof` 批量查询追踪真正操作文件的进程，支持进程树追溯（子进程如 node/python 自动归因到父 Agent）
- **智能 Agent 识别** - 15 种主流 AI 工具 + 20 种开发工具自动识别
  - **AI 工具识别**：Claude、Trae、Cursor、Windsurf、Doubao、Kimi、DeepSeek、ChatGPT、Gemini、Copilot 等
  - **开发工具识别**：Node.js、Python、Cargo、Go、Xcode、npm、Yarn、pnpm、Deno、Bun 等
  - **多级检测策略**：lsof精确匹配 → 前缀匹配 → 路径关键词匹配
- **进程详情显示** - 每条记录显示 Agent 名称、实际进程名、命令行信息
- **筛选功能** - 按 Agent 名称、操作类型筛选
- 操作记录自动保存，最多保留 2000 条

### ⚙️ 设置

在菜单栏底部点击「设置」按钮，打开统一设置页面：
- **AI 设置**：配置大模型 API（DeepSeek / OpenAI / 智谱 GLM / 通义千问等）
- **功能开关**：菜单栏监控、设备监控、操作记录的开关控制
- **监控设置**：存储警告阈值（5%~30%）、回收站删除模式
- **退出行为**：控制点击 Dock 退出按钮或 Cmd+Q 时的行为
  - **退出应用和菜单栏（默认）** - 传统行为，完全关闭应用
  - **仅退出应用，保留菜单栏** - 菜单栏常驻模式，继续后台监控 Agent 操作
- **版本与更新**：查看当前版本、手动检查更新、下载更新

### 📊 磁盘信息 & 菜单栏监控
- 实时显示磁盘使用率、总容量、已用、可用空间（数据与macOS系统设置完全一致）
- **菜单栏常驻图标**：实时显示磁盘剩余百分比
- **存储空间警报**：磁盘剩余低于阈值（默认10%）时发送系统通知
- **警报阈值设置**：5%~30% 可调
- **检测更新**：手动检查 GitHub 最新版本，有更新时一键下载

## 安装

### 方式一：下载 DMG（推荐）

1. 从 [Releases](https://github.com/AI-Scarlett/AIMacCleaner/releases) 下载最新版 `AIMacCleaner-v1.7.8-arm64.dmg`
2. 双击打开 DMG 文件
3. 将 AIMacCleaner 拖入 Applications 文件夹
4. 首次打开时，右键点击应用 → 选择「打开」（需绕过 Gatekeeper 验证）

### 方式二：从源码构建

```bash
git clone https://github.com/AI-Scarlett/AIMacCleaner.git
cd AIMacCleaner
bash build_native.sh
cp -r /tmp/AIMacCleaner_build/build/AIMacCleaner.app /Applications/
```

## 使用方法

### 六大功能 Tab

| Tab | 功能 | 说明 |
|-----|------|------|
| 🧹 Mac 清理 | 扫描可清理的缓存/日志/临时文件 | 本地扫描 + AI 扫描 |
| 📱 APP 管理 | 管理本机 .app 应用 | 卸载/清理缓存/重置 |
| 📦 依赖管理 | 管理 Homebrew/npm/pip 包 | 卸载/清理 |
| 🛡️ Agent 审计 | 审计 AI Agent 对本地文件的操作 | 50+ 种 Agent 内置 |
| 🖥️ Agent 监控 | 记录 AI Agent 自动操作 | 筛选 + 监控 |
| ⚙️ 设置 | AI配置/功能开关/监控/版本更新 | 集中设置面板 |

### 🛡️ 安全设置

在菜单栏面板中可配置：
- **删除移入回收站**：开启后所有删除操作移入回收站而非永久删除（默认开启）
- **禁止自动清空回收站**：防止自动清理回收站（默认开启）
- **操作监控**：开启后记录 AI Agent 的文件操作（默认关闭）

### AI 影响分析

在「依赖管理」或「其它工具」tab 中：
1. 勾选想要删除的项目
2. 点击操作栏的「✨ AI 分析」按钮
3. 大模型分析每个项目删除后的影响
4. 分析结果直接显示在列表的「影响说明」列中（紫色 🤖 标识）

### AI 扫描配置

点击 Mac 清理页面右上角「AI 设置」按钮：

| 预设 | API Base | 模型 |
|------|----------|------|
| DeepSeek | https://api.deepseek.com | deepseek-chat |
| OpenAI | https://api.openai.com | gpt-4o-mini |
| 智谱 GLM | https://open.bigmodel.cn/api/paas | glm-4-flash |
| 通义千问 | https://dashscope.aliyuncs.com/compatible-mode | qwen-turbo |

也可自定义任意兼容 OpenAI 接口的大模型服务。

## 从源码构建

### 环境要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 15+ (`xcode-select --install`)
- Apple Silicon (arm64) 或 Intel (x86_64)

### 构建步骤

```bash
# 构建 .app
bash build_native.sh

# 构建 DMG 安装包
xcodebuild -project AIMacCleaner.xcodeproj -scheme AIMacCleaner \
  -configuration Release -derivedDataPath build build

APP_PATH="build/Build/Products/Release/AIMacCleaner.app"
DMG_STAGING="/tmp/AIMacCleaner-dmg-staging"
rm -rf "$DMG_STAGING" && mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -sf /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "AIMacCleaner" -srcfolder "$DMG_STAGING" \
  -ov -format UDZO AIMacCleaner-arm64.dmg
rm -rf "$DMG_STAGING"
```

## 技术架构

### 技术栈

- **UI 框架**: SwiftUI (原生 macOS 应用)
- **最低版本**: macOS 13.0
- **架构**: arm64 (Apple Silicon)
- **语言**: Swift 5.9+

### 项目结构

```
AIMacCleaner/
├── AIMacCleaner/
│   ├── AIMacCleanerApp.swift         # 应用入口
│   ├── ContentView.swift             # 主界面（左侧导航 + 右侧内容）
│   ├── MenuBarMonitor.swift          # 菜单栏常驻监控视图
│   ├── AgentSessionScanner.swift     # Agent 审计：50+ 种 Agent 会话数据扫描与解析
│   ├── OperationMonitor.swift        # AI Agent 操作监控服务
│   ├── ScannerService.swift          # 核心服务（扫描、删除、AI、监控、更新）
│   ├── ScanRules.swift               # 35+ 条本地扫描规则
│   ├── Models.swift                  # 数据模型
│   ├── SettingsView.swift            # 统一设置页面
│   ├── SensorMonitor.swift           # 摄像头/麦克风监控
│   ├── AIConfigView.swift            # AI 配置弹窗
│   └── Assets.xcassets/              # 图标和资源
├── AIMacCleaner.xcodeproj/          # Xcode 项目
├── build_native.sh                   # 构建脚本
├── upload_dmg.py                     # DMG 上传脚本
├── CHANGELOG.md                      # 更新日志
├── README.md
└── LICENSE
```

### 扫描覆盖

| 分类 | 覆盖内容 |
|------|----------|
| 浏览器 | Google Chrome, 夸克 |
| 办公 | 飞书/Lark |
| AI Agent | Trae, CodeBuddy, Claude, Codex, Hermes, yi-code, Cline, MiniMax, Cherry Studio, LM Studio, OpenClaw, QClaw, CodeArts, Kimi, DeepSeek, 豆包, 通义千问, Augment, Copilot, Aider, Cody, Tabby, Warp, ChatGPT, Gemini, 智谱AI, 讯飞星火, 通义灵码, Whitzard, Cursor, Windsurf, Roo Code, Continue, Amazon Q, Tabnine, Lingma, OpenHands, CrewAI, AutoGen, MetaGPT, CAMEL, DeerFlow, Dify, BrowserUse, Huginn, AgentGPT, LobeHub, LangGraph, Swarm, AgentScope, UI-TARS 等 50+ |
| 开发 | Electron, Python/pip, Homebrew, npm, pnpm, CocoaPods, Gradle, Maven, Cargo, Go, Conda, Julia, pyenv, NVM, Android SDK, OpenHarmony SDK, HarmonyOS SDK, VS Code, IntelliJ 等 |
| 系统 | macOS 照片分析, 系统日志, 地理位置服务 |

### 风险等级说明

| 等级 | 含义 | 示例 |
|------|------|------|
| 🟢 安全 | 纯缓存/日志，删除后无影响 | 浏览器缓存、pip 缓存、运行日志 |
| 🟠 注意 | 删除后可能需重新登录/配置 | Chrome Session、Maven 仓库、pyenv |
| 🔴 危险 | 可能丢失数据 | （需用户确认的重要数据目录） |

## 更新日志

### v1.2.4 (2026-08-15)
- 每个插件独立声明是否可显示在概览、桌面“我的插件”Tab、菜单栏“插件”Tab
- 概览新增经过目录许可的已安装插件快捷入口，复杂工具仍留在完整工作区
- 全部插件统一标记“免费/收费”；订阅用户对收费插件同时看到“订阅已包含”
- 目录导入和校验新增位置冲突检查，为未来新增插件保留稳定的 UI 与 UX 规则
- 新增“Codex 媒体整理”v1.0.0，在桌面插件工作区安全扫描、去重和修复 Codex 会话图片引用
- 45 个存量插件完成 TraceFence 品牌、发布包与权限体验统一，并各自提升独立补丁版本供商城更新
- 插件只声明所需系统能力，辅助功能、屏幕录制、输入监控等权限由 TraceFence 主应用统一授权和复用

### v1.2.3 (2026-08-14)
- 修复插件工作区顶部、底部被窗口裁切，改为固定标题栏与单一内容滚动区
- 数据型插件默认打开数据面板，完整工具默认进入工作区，高频动作默认显示快捷按钮
- 菜单栏只承载固定插件的快捷控制或状态摘要，完整图表和复杂操作留在桌面端
- 新增从菜单栏状态摘要一键打开桌面完整内容，并为未来插件建立独立展示契约

### v1.2.2 (2026-08-14)
- 新增“我的插件”主工作区，商城不再承担插件日常启动职责
- 菜单栏新增可固定的快捷插件页，风扇控制可直接在菜单栏使用
- 修复插件运行器嵌套在设置里且无法明确关闭的问题
- 插件主面板补齐可见性生命周期，实时状态刷新与资源占用更合理

详见 [CHANGELOG.md](CHANGELOG.md)

### v1.7.8 (2026-05-19)
- 🛡️ **新增 Agent 审计功能**：50+ 种 AI Agent 内置支持，审计其对本地文件的操作记录
- **新增 10+ 种 Agent 内置注册**：OpenClaw、Hermes、CrewAI、AutoGen、OpenHands、Dify、MetaGPT、CAMEL、DeerFlow、Huginn、BrowserUse 等
- **OpenClaw 专用解析器**：解析 ~/.openclaw/agents/ 下 JSONL 会话中的 tool_use/tool_call 操作
- **Hermes 专用解析器**：解析 ~/.hermes/sessions/ 下 JSON 会话 + SQLite state.db
- **CrewAI/AutoGen SQLite 解析**：自动发现表结构并提取操作记录
- **OpenHands 事件解析**：解析轨迹文件中的 action/tool 事件
- **VSCode 类 Agent 智能分发**：Trae/Cursor/CodeBuddy 等自动识别 .vscdb 和 file-changes JSON
- **修复 Trae/CodeBuddy 审计无记录**：智能解析器根据文件扩展名自动分发到正确解析方法
- **修复内置 Agent 可被重复添加**
- **修复菜单栏退出按钮导致应用卡死**
- **文件发现增强**：支持 .db、.sqlite、session/events/conversation/trajectory JSON 文件
- **UI 更新**：所有新增 Agent 均有专属图标和颜色

### v1.7.7 (2026-05-18)
- Agent 审计功能基础框架
- SQLite3 解析支持 (state.vscdb)
- file-changes JSON 解析支持
- Kimi 会话路径修复
- 调试日志增强

### v1.7.3 (2026-05-15)
- 修复磁盘空间数据与macOS系统设置不一致：使用 `URL.resourceValues` API + 十进制GB，数据完全对齐
- 修复Agent监控无数据：移除per-event的lsof调用，改为批量lsof + 缓存匹配架构
- 重写Agent进程识别：支持进程树追溯（子进程node/python等通过ppid归因到父Agent）
- 新增processName和toolInfo字段，显示真实操作进程名和命令行信息
- 过滤系统进程和Finder扩展，消除假数据归因
- 存储分析扫描优化：减少不可访问路径扫描，扫描深度从8降到5
- 弹窗底部样式统一：版本号、网络状态、退出APP作为弹窗公共外壳

### v1.7.2 (2026-05-15)
- 修复存储分析重复计算导致统计1TB
- 修复AI分析按钮无响应
- 修复英文模式下APP管理/依赖/其它工具中文残留
- 修复网络状态显示异常
- 优化Agent监控识别算法
- 新增Dock退出时菜单栏常驻选项

### v1.7.1 (2026-05-15)
- 修复存储空间显示与macOS系统设置不一致
- 修复操作监控完全失效（路径字符串插值错误）

### v1.6.6 (2026-05-14)
- 中英文切换全面生效：SettingsView/Agent监控/Mac清理 全面接入 Localizer
- 语言 Tab 点击布局修复：固定按钮宽度，消除切换动画
- 操作记录正式更名为 Agent 监控：侧边栏/页面标题/菜单栏统一更名
- 菜单栏 Tab 优化："监控"→"硬件监控"，"操作"→"Agent监控"
- 存储扫描优化：移除 /System，新增 /Users/Shared、/private/var、/private/tmp
- Agent 检测精确匹配：仅在 Agent 新启动时生成记录，避免误报
- FSEventStream 线程安全修复
- 废弃 Process API 修复

### v1.6.5 (2026-05-14)
- 设置页整合：AI设置/功能开关/监控/版本更新检测
- 存储分析全面升级：全盘扫描系统文件、应用程序、文稿等
- 存储分析新增"目录"列：显示完整路径，可一键复制
- 修复闪退问题
- 修复权限持久化问题
- 新增功能开关：菜单栏监控、设备监控、操作记录均可在设置中控制

### v1.6.1 (2025-05-13)
- 修复 getNetworkInfo 中强制解包导致的启动崩溃
- 修复菜单栏 popover 内容不显示（高度自适应）
- 桌面端 UI 重构：左侧导航栏 + 右侧内容区
- 统一各功能页面布局（PageHeader + FilterBar + Content）
- 修复操作记录筛选框宽度问题
- 修复代码签名缺失导致"已损坏"提示
- 修复图标丢失问题（使用 xcodebuild 编译 Assets.xcassets）

### v1.6.0 (2025-05-13)
- 菜单栏硬件监控：CPU、内存、温度、电池、网络
- 自动操作监控 Tab
- 操作记录筛选和统计

### v1.3.0 (2025-05-13)
- 操作记录 Tab：记录 AI Agent 自动操作
- 删除移入回收站（可手动开关）
- 禁止自动清空回收站（可手动开关）
- 操作监控需手动开启（默认关闭）
- 20+ 种 Agent 目录监控

### v1.2.0 (2025-05-13)
- 菜单栏常驻监控：实时显示磁盘剩余百分比
- 存储空间警报：磁盘剩余低于阈值时发送系统通知
- 检测更新：手动检查 GitHub 最新版本
- 警报阈值设置（5%~30%）

### v1.1.1 (2025-05-13)
- AI 影响分析：勾选项后调用大模型分析删除影响，结果直接显示在列表中
- 全面扫描用户主目录 dotdir，智能分类
- 30+ 种 AI Agent 自动识别
- 修复无 .app 包的 Agent 无法卸载的问题

### v1.1.0 (2025-05-13)
- APP 管理纯净化：只显示 .app 应用
- 其它工具分类筛选（AI Agent / CLI / 包管理 / 开发）
- 动态扫描 Homebrew/npm/pip 包
- 应用图标支持

### v1.0.0 (2025-05-13)
- 首个正式版本
- 本地扫描 + AI 扫描
- 原生 SwiftUI macOS 应用

## 常见问题

<details>
<summary>首次打开提示"无法验证开发者"</summary>

右键点击应用 → 选择「打开」→ 在弹出的对话框中再次点击「打开」即可。或在系统设置 → 隐私与安全性 → 点击「仍要打开」。
</details>

<details>
<summary>AI 扫描返回"无法解析大模型返回的 JSON"</summary>

建议：
1. 更换为 DeepSeek 或 GLM 等中文能力更强的模型
2. 重新点击 AI 扫描重试
3. 本地扫描结果不受影响，可正常使用
</details>

<details>
<summary>某些 Agent 没有被扫描到</summary>

应用会自动扫描用户主目录的所有 dotdir（~/.xxx），通过关键词匹配识别 AI Agent。如果某个 Agent 没有被识别，它会出现在「其它工具」tab 的「其它」分类中，标注为"未知目录"。
</details>

<details>
<summary>AI 分析按钮是灰色的</summary>

需要先勾选至少一个项目，且已配置大模型 API Key。API Key 在 Mac 清理页面的「AI 设置」中配置。
</details>

<details>
<summary>扫描结果为空</summary>

可能原因：
1. Mac 存储空间充足，没有大的可清理项
2. 对应应用的缓存目录不存在
3. 需要授予「完全磁盘访问」权限：系统设置 → 隐私与安全性 → 完全磁盘访问 → 添加 AIMacCleaner
</details>

## 许可证

MIT License
