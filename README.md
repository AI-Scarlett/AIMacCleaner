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

### 🕐 操作记录
- **自动操作监控** - 记录 AI Agent 的文件操作（创建/删除等），需手动开启
- **筛选功能** - 按 Agent 名称、操作类型、时间范围筛选
- **20+ 种 Agent 监控** - Hermes/Claude/CodeBuddy/Codex/Cline/Trae/Cursor 等
- 操作记录自动保存，最多保留 5000 条

### 🛡️ 安全设置（菜单栏面板）
- **删除移入回收站** - 所有删除操作默认移入回收站，可手动开关
- **禁止自动清空回收站** - 可手动开关，防止自动清理回收站
- **操作监控开关** - 操作监控需手动开启，默认关闭

### 📊 磁盘信息 & 菜单栏监控
- 实时显示磁盘使用率、总容量、已用、可用空间
- **菜单栏常驻图标**：实时显示磁盘剩余百分比
- **存储空间警报**：磁盘剩余低于阈值（默认10%）时发送系统通知
- **警报阈值设置**：5%~30% 可调
- **检测更新**：手动检查 GitHub 最新版本，有更新时一键下载

## 安装

### 方式一：下载 DMG（推荐）

1. 从 [Releases](https://github.com/AI-Scarlett/AIMacCleaner/releases) 下载最新版 `AIMacCleaner.dmg`
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

### 四大功能 Tab

| Tab | 功能 | 说明 |
|-----|------|------|
| 🧹 Mac 清理 | 扫描可清理的缓存/日志/临时文件 | 本地扫描 + AI 扫描 |
| 📱 APP 管理 | 管理本机 .app 应用 | 卸载/清理缓存/重置 |
| 📦 依赖管理 | 管理 Homebrew/npm/pip 包 | 卸载/清理 |
| 🕐 操作记录 | 记录 AI Agent 自动操作 | 筛选 + 监控 |

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
│   ├── AIMacCleanerApp.swift    # 应用入口
│   ├── ContentView.swift        # 主界面（5 Tab + 分类筛选 + AI 分析）
│   ├── MenuBarMonitor.swift     # 菜单栏常驻监控视图
│   ├── OperationMonitor.swift   # AI Agent 操作监控服务
│   ├── ScannerService.swift     # 核心服务（扫描、删除、AI 调用、监控、更新检测）
│   ├── ScanRules.swift          # 35+ 条本地扫描规则
│   ├── Models.swift             # 数据模型（AppInfo/ScanItem/AIConfig）
│   ├── AIConfigView.swift       # AI 配置弹窗
│   └── Assets.xcassets/         # 图标和资源
├── AIMacCleaner.xcodeproj/     # Xcode 项目
├── build_native.sh              # 构建脚本
├── CHANGELOG.md                 # 更新日志
├── README.md
└── LICENSE
```

### 扫描覆盖

| 分类 | 覆盖内容 |
|------|----------|
| 浏览器 | Google Chrome, 夸克 |
| 办公 | 飞书/Lark, 钉钉, WPS Office, XMind |
| AI Agent | Trae, CodeBuddy, Claude, Codex, Hermes, yi-code, Cline, MiniMax, Cherry Studio, LM Studio, OpenClaw, QClaw, CodeArts, Kimi, DeepSeek, 豆包, 通义千问, Augment, Copilot, Aider, Cody, Tabby, Warp, ChatGPT, Gemini, 智谱AI, 讯飞星火, 通义灵码, Whitzard 等 30+ |
| 开发 | Electron, Python/pip, Homebrew, npm, pnpm, CocoaPods, Gradle, Maven, Cargo, Go, Conda, Julia, pyenv, NVM, Android SDK, OpenHarmony SDK, HarmonyOS SDK, VS Code, IntelliJ 等 |
| 系统 | macOS 照片分析, 系统日志, 地理位置服务 |
| 社交 | 微信, QQ |

### 风险等级说明

| 等级 | 含义 | 示例 |
|------|------|------|
| 🟢 安全 | 纯缓存/日志，删除后无影响 | 浏览器缓存、pip 缓存、运行日志 |
| 🟠 注意 | 删除后可能需重新登录/配置 | Chrome Session、Maven 仓库、pyenv |
| 🔴 危险 | 可能丢失数据 | （需用户确认的重要数据目录） |

## 更新日志

详见 [CHANGELOG.md](CHANGELOG.md)

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
