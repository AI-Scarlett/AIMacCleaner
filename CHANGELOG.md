# Changelog

All notable changes to AIMacCleaner will be documented in this file.

## [1.3.0] - 2025-05-13

### Added
- **操作记录 Tab** - 新增第5个 Tab，记录 AI Agent 的自动操作（创建/删除文件等）
- **操作监控** - 每3秒轮询检测 Agent 目录变更，记录文件创建和删除操作
- **筛选功能** - 按 Agent 名称、操作类型（创建/修改/删除/移动/重命名）、时间范围筛选
- **删除移入回收站** - 所有删除操作默认移入回收站而非永久删除，可手动开关
- **禁止自动清空回收站** - 可手动开关，防止自动清理回收站
- **操作监控开关** - 操作监控需手动开启，默认关闭
- **菜单栏安全设置** - 菜单栏面板新增操作监控、回收站设置开关
- 支持 20+ 种 Agent 目录监控（Hermes/Claude/CodeBuddy/Codex/Cline/Trae/Cursor 等）

## [1.2.0] - 2025-05-13

### Added
- **菜单栏常驻监控** - 应用运行时在菜单栏实时显示磁盘剩余百分比
- **存储空间警报** - 磁盘剩余低于阈值（默认10%）时发送系统通知提醒
- **警报阈值设置** - 可在菜单栏下拉面板中调整警报阈值（5%~30%）
- **检测更新** - 菜单栏面板中可手动检查 GitHub 最新版本，有更新时一键下载
- **监控开关** - 可开启/关闭定时磁盘监控（每5分钟检查一次）

### Fixed
- 修复菜单栏显示百分比与实际不一致的问题

## [1.1.1] - 2025-05-13

### Added
- AI 影响分析：勾选项后点击"AI 分析"按钮，调用大模型分析删除影响，结果直接显示在列表中
- 全面扫描用户主目录 dotdir，智能分类（AI Agent/CLI/包管理/开发/其它）
- 30+ 种 AI Agent 关键词匹配（Hermes/yi-code/Cline/MiniMax/CodeArts 等）
- 25+ 种开发工具 dotdir 分类（.nvm/.pyenv/.conda/.android/.ohos 等）
- 未识别的 dotdir 归入"其它"分类，标注风险提示
- 所有 Agent/工具均支持卸载操作（包括无 .app 包的 dotdir 类型）

### Fixed
- 修复 Hermes/OpenClaw 等无 .app 包的 Agent 无法卸载的问题
- 修复 dotdir 类型 Agent 的 relatedPaths/dataPaths 不包含实际路径的问题
- 移除 scanDynamicCLITools 中与 scanDynamicAgents 重复的 dotdir 扫描

## [1.1.0] - 2025-05-13

### Added
- APP管理 tab 纯粹只显示 .app 应用，缓存/数据类条目不再出现
- 其它工具 tab 添加分类筛选（AI Agent / CLI / 包管理 / 开发）
- 分类标签带颜色标识，点击可切换筛选
- AI Agent 类 .app 应用自动从 APP管理 移至其它工具，避免重复
- 其它工具中的 .app 应用自动计算缓存和数据大小，支持重置和完全卸载
- 动态扫描 Homebrew、npm、pip 安装的包
- 扫描 dotfiles 配置目录（.nvm, .pyenv, .cargo, .conda 等）
- 每项添加影响说明，描述删除/清理后的后果

### Fixed
- 修复 scanNpmModules/scanPipPackages 缺少 subCategory 参数的编译错误
- 修复 ScanRules.swift 未加入 Xcode 项目编译源的问题
- 修复 AI Agent 应用在 APP管理和其它工具中重复显示的问题

## [1.0.0] - 2025-05-13

### Added
- Native SwiftUI macOS application
- Local scanning engine with 35+ built-in rules
- AI-powered scanning with LLM integration (DeepSeek, OpenAI, GLM, Qwen)
- Smart clean - one-click cleanup of all safe items
- Risk level classification (safe / caution / dangerous)
- Category and application-based filtering
- Search functionality
- Disk space overview with usage statistics
- Ignore list persistence
- AI configuration with preset providers
- DMG installer for Apple Silicon (arm64)
