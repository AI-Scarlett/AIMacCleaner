# AIMacCleaner

<p align="center">
  <img src="build/AppIcon.icns" width="128" height="128" alt="AIMacCleaner Icon">
</p>

<p align="center">
  <strong>智能 Mac 存储空间清理工具</strong>
</p>

<p align="center">
  <a href="#功能特性">功能</a> •
  <a href="#安装">安装</a> •
  <a href="#使用方法">使用</a> •
  <a href="#从源码构建">构建</a> •
  <a href="#技术架构">架构</a>
</p>

---

## 功能特性

### 🔍 本地扫描
- 内置 35+ 条扫描规则，覆盖浏览器、办公、AI Agent、开发、系统、社交等分类
- 精确计算每个目录的占用大小和文件数量
- 三级风险标识：安全（可放心删除）、注意（可能需重新登录）、危险（可能丢失数据）

### 🤖 AI 扫描
- 接入大模型（DeepSeek / OpenAI / 智谱 GLM / 通义千问等）智能分析可清理目录
- AI 自动识别本地规则未覆盖的清理项
- 返回的风险评估和清理建议更贴近实际使用场景

### ✨ 智能清理
- 一键清理所有「安全」级别的项目
- 清理完成后显示释放的存储空间大小

### 🎯 精细筛选
- 按分类筛选（浏览器 / 办公 / AI Agent / 开发 / 系统 / 社交）
- 按应用筛选（Google Chrome / 飞书 / Trae / CodeBuddy 等）
- 按风险等级筛选（安全 / 注意 / 危险）
- 关键词搜索

### 📊 磁盘信息
- 实时显示磁盘使用率、总容量、已用、可用空间
- 显示当前可释放的存储空间大小

## 安装

### 方式一：下载 DMG（推荐）

1. 从 [Releases](https://github.com/AI-Scarlett/AIMacCleaner/releases) 下载最新版 `AIMacCleaner-arm64.dmg`
2. 双击打开 DMG 文件
3. 将 AIMacCleaner 拖入 Applications 文件夹
4. 首次打开时，右键点击应用 → 选择「打开」（需绕过 Gatekeeper 验证）

### 方式二：从源码构建

```bash
# 克隆仓库
git clone https://github.com/AI-Scarlett/AIMacCleaner.git
cd AIMacCleaner

# 构建
bash build_native.sh

# 安装
cp -r /tmp/AIMacCleaner_build/build/AIMacCleaner.app /Applications/
```

## 使用方法

### 基本流程

1. **启动应用** — 打开 AIMacCleaner，首页显示磁盘空间概览
2. **本地扫描** — 点击「本地扫描」卡片，扫描内置规则覆盖的可清理项
3. **AI 扫描**（可选）— 点击「AI 扫描」卡片，首次使用需配置大模型 API
4. **查看结果** — 在扫描结果列表中查看每项的大小、风险等级和说明
5. **筛选** — 使用搜索栏、风险筛选按钮或侧边栏分类筛选
6. **选择清理** — 勾选要清理的项目，或使用「智能清理」一键清理安全项
7. **确认删除** — 删除前会弹出确认对话框，显示将释放的空间大小

### AI 扫描配置

点击右上角「AI 设置」按钮，配置大模型 API：

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
- Xcode Command Line Tools (`xcode-select --install`)
- Apple Silicon (arm64) 或 Intel (x86_64)

### 构建步骤

```bash
# 构建 .app
bash build_native.sh

# 构建 DMG 安装包
mkdir -p dist
DMG_DIR="/tmp/AIMacCleaner_dmg"
rm -rf "$DMG_DIR" && mkdir -p "$DMG_DIR"
cp -R /tmp/AIMacCleaner_build/build/AIMacCleaner.app "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
hdiutil create -volname "AIMacCleaner" -srcfolder "$DMG_DIR" -ov -format UDZO dist/AIMacCleaner-arm64.dmg
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
│   ├── ContentView.swift        # 主界面（侧边栏 + 详情视图）
│   ├── ScannerService.swift     # 核心服务（扫描、删除、AI 调用）
│   ├── ScanRules.swift          # 35+ 条本地扫描规则
│   ├── Models.swift             # 数据模型定义
│   ├── AIConfigView.swift       # AI 配置弹窗
│   └── Assets.xcassets/         # 图标和资源
├── build/
│   ├── build_native.sh          # 构建脚本
│   └── create_icon.py           # 图标生成脚本
├── dist/                        # DMG 输出目录
├── README.md
└── LICENSE
```

### 扫描规则覆盖

| 分类 | 覆盖应用 |
|------|----------|
| 浏览器 | Google Chrome, 夸克 |
| 办公 | 飞书/Lark, 钉钉, WPS Office, XMind |
| AI Agent | Trae CN, CodeBuddy CN, Claude Code, 豆包, 通义千问, Crebee, CodeArts Agent, Master Desktop, QClaw |
| 开发 | Electron, Python/pip, Homebrew, npm, pnpm, Huawei, HarmonyOS |
| 系统 | macOS 照片分析, 系统日志, 地理位置服务 |
| 社交 | 微信, QQ |

### 风险等级说明

| 等级 | 含义 | 示例 |
|------|------|------|
| 🟢 安全 | 纯缓存/日志，删除后无影响 | 浏览器缓存、pip 缓存、运行日志 |
| 🟠 注意 | 删除后可能需重新登录/配置 | Chrome Session Storage、微信缓存 |
| 🔴 危险 | 可能丢失数据 | （需用户确认的重要数据目录） |

## 常见问题

<details>
<summary>首次打开提示"无法验证开发者"</summary>

右键点击应用 → 选择「打开」→ 在弹出的对话框中再次点击「打开」即可。或在系统设置 → 隐私与安全性 → 点击「仍要打开」。
</details>

<details>
<summary>AI 扫描返回"无法解析大模型返回的 JSON"</summary>

这是大模型返回格式不稳定导致的。建议：
1. 更换为 DeepSeek 或 GLM 等中文能力更强的模型
2. 重新点击 AI 扫描重试
3. 本地扫描结果不受影响，可正常使用
</details>

<details>
<summary>扫描结果为空</summary>

可能原因：
1. Mac 存储空间充足，没有大的可清理项
2. 对应应用的缓存目录不存在（说明该应用未安装或未产生缓存）
3. 需要授予「完全磁盘访问」权限：系统设置 → 隐私与安全性 → 完全磁盘访问 → 添加 AIMacCleaner
</details>

## 许可证

MIT License
