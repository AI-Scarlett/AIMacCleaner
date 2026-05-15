# Changelog

All notable changes to AIMacCleaner will be documented in this file.

## [1.7.3] - 2026-05-15

### Fixed
- **磁盘空间数据与系统设置不一致** - 使用 `URL.resourceValues` 的 `volumeTotalCapacityKey` + `volumeAvailableCapacityForImportantUsageKey` API 读取 APFS Container 级别数据，改用十进制GB（÷10^9）替代二进制GiB（÷2^30），现在显示数据与macOS系统设置完全一致
- **Agent监控无数据** - 移除per-event的 `lsof` 调用（每次800ms+导致事件处理完全阻塞），改为批量lsof + 缓存匹配架构：每15秒对所有已知Agent PIDs执行一次lsof，事件处理时只查缓存
- **Agent监控显示"System"或"Unknown"** - 重写进程识别算法，支持进程树追溯（子进程node/python等通过ppid归因到父Agent），新增processName和toolInfo字段显示真实操作进程和命令行
- **Agent监控假数据归因** - 过滤系统进程（kernel, launchd, mds, fseventsd）和Finder扩展（.appex, FinderSyncExtension），不再将后台进程误报为AI Agent
- **存储分析扫描过慢** - 减少系统扫描路径（移除/usr, /sbin等不可访问目录），扫描深度从8降到5，maxFiles从5000降到3000
- **弹窗底部样式不统一** - 将版本号、网络状态、退出APP三个元素提取为弹窗公共外壳（`popoverFooter`），两个Tab共用统一底部布局

### Added
- **OperationRecord新增字段** - `processName`（实际操作进程名）和 `toolInfo`（命令行信息），UI中Agent列下方小字显示processName，路径列下方小字显示toolInfo
- **批量lsof刷新机制** - `detectActiveAgents()` 通过 `ps -eo pid,ppid=,comm=,args=` 一次性获取所有进程，`refreshLsofData()` 对Agent PIDs执行lsof建立PID→文件集映射
- **进程树追溯** - `resolveFromTree()` 向上追溯ppid链（最多10层），将子进程归因到父Agent

### Improved
- **Agent监控事件处理** - `processEvents` 中不再调用任何外部命令，只通过内存缓存匹配，性能从秒级降到毫秒级
- **弹窗底部统一** - `[🟢 Internet] [v1.7.3] [⏻ 退出]` 水平排列，两个Tab样式一致

## [1.7.2] - 2026-05-15

### Fixed
- **存储分析重复计算导致统计1TB** - 修复多个存储分类路径重叠导致的重复计算问题，使用 `scannedRootPaths` 全局跟踪已扫描目录，避免同一文件被多次计算
- **AI分析按钮无反应** - 修复存储分析页面点击 AI 分析按钮无任何响应的问题，添加配置检查提示和结果弹窗显示
- **英文模式下中文硬编码** - 修复 APP管理/依赖/其它工具 三个 Tab 在英文模式下仍显示26处中文硬编码的问题，全面接入 Localizer 国际化
- **网络状态显示异常** - 修复左侧 Tab 菜单栏未缩小时不显示网络状态，以及设置页面网络状态始终显示英文的问题
- **Agent监控数据不准确** - 优化 Agent 名称识别算法，新增基于路径特征的智能匹配（支持15种主流AI工具 + 20种开发工具），替代简单的 `agents.first` 逻辑
- **左下角布局优化** - 将左下角功能区域调整为两列布局（设置+网络状态 / 收起侧边栏+版本号），提升视觉美观度

### Added
- **Dock退出时菜单栏常驻选项** - 新增"退出行为"设置选项，支持"仅退出应用，保留菜单栏监控"模式，满足常驻监控需求

### Improved
- **OperationMonitor 监控路径扩展** - 从5个目录扩展到7个，新增 ~/Projects 和用户主目录 ~ 的监控
- **AppAction 枚举重构** - 改用方法调用支持国际化，消除硬编码中文字符串

## [1.7.1] - 2026-05-15

### Fixed
- **存储空间显示不一致** - 修复 AIMacCleaner 显示的剩余空间（29GB）与 macOS 系统设置（67GB）不符的问题，改用 `FileManager.attributesOfFileSystem(forPath:)` 获取 APFS 容器级别的准确存储信息
- **操作监控完全失效** - 修复 OperationMonitor 监控路径字符串插值语法错误（`$(home)` → `\(home)`），导致 Documents/Downloads/Caches/Application Support 等目录无法被监控
- **扩展监控范围** - 新增 `~/Projects` 和用户主目录 `~` 到监控路径，覆盖更多文件操作场景

## [1.6.6] - 2026-05-14

### Fixed
- 修复中英文切换没有效果：SettingsView/CopyLogTab/MacCleanerTab 全面接入 Localizer
- 修复语言 Tab 点击后整体布局右移：固定语言切换按钮宽度，消除切换动画
- 操作记录改名为 "Agent 监控"：侧边栏 Tab、页面标题、菜单栏 Tab 统一更名
- 菜单栏 Tab 名称优化："监控" → "硬件监控"，"操作" → "Agent监控"
- 存储扫描优化：移除不可访问的 /System，新增 /Users/Shared、/private/var、/private/tmp
- 操作记录 Agent 检测修复：使用精确进程名匹配，仅在 Agent 新启动时生成记录
- FSEventStream 线程安全修复：使用 CFRunLoopGetMain() 替代 CFRunLoopGetCurrent()
- 废弃 API 修复：Process 使用 executableURL + run() 替代 launchPath + launch()
- 版本号统一更新为 v1.6.6

## [1.6.5] - 2026-05-14

### Fixed
- 修复闪退问题
- 移除设备监控 Tab（已整合到设置页面）
- 修复操作记录误报 doubao（移除通用进程名匹配）
- 优化左侧 Tab 栏收缩按钮（更优雅的设计）
- 设置页面语言 Tab 更名为"语言"
- 存储分析改进：扫描深度提升到 6 层，最大文件数到 3000，降低文件阈值到 100KB，可扫描更多文件

## [1.6.4] - 2026-05-14

### Added
- **操作记录改进** - 使用 FSEvents 监控用户目录（Desktop/Documents/Downloads/Projects 等），直接显示 Agent 对文件的增删改查操作，小白用户也能看懂
- **操作记录详情** - 每条记录包含：创建/修改/删除的完整文件名、路径、大小变化、活跃 Agent 名称
- **设置页分Tab** - 设置页面按 AI/功能/监控/通用/版本 分 Tab 切换，结构更清晰
- **设备监控开关** - 摄像头/麦克风监控开关移到设置页面统一管理
- **侧边栏收缩** - 左侧 Tab 栏支持收缩，收缩后只显示图标和简称
- **中英文切换** - 设置页面支持简体中文/English 切换
- **文件风险等级** - 存储分析文件列表新增"风险"列，自动标注：可清理/谨慎清理/保留/未知
- **扫描进度指示** - 存储分析扫描时自动隐藏开始按钮，显示进度指示器

### Fixed
- 操作记录只显示 Agent 日志文件的问题：改为使用 FSEvents 监控真实文件变更
- 存储分析只扫描 50G 的问题：增加扫描深度到 5 层，最大文件数到 500

## [1.6.3] - 2026-05-14

### Added
- **设置页整合** - 将 AI 设置、功能开关、监控设置、版本更新检测整合到统一的设置页面
- **功能开关** - 菜单栏监控、设备监控、操作记录均可在设置中一键开关
- **监控设置** - 存储警告阈值可调、回收站删除模式开关
- **版本检测** - 设置页内置版本更新检测功能，显示当前版本号
- **全盘扫描** - 存储分析全面升级，扫描整个磁盘包括系统文件、应用程序、应用数据、文稿、Agent、依赖、日志缓存等
- **目录复制** - 存储分析文件列表新增"目录"列，显示完整路径，点击复制按钮可直接复制路径
- **应用数据分类** - 存储分析新增"应用数据"和"日志与缓存"分类

### Fixed
- 修复闪退问题：安全处理网络接口遍历和文件句柄关闭操作
- 修复权限持久化：添加系统权限描述，重启后无需重新授权
- 修复存储分析不准确：扫描范围从用户目录扩展到整个磁盘

## [1.6.0] - 2025-05-13

### Added
- **硬件监控** - 菜单栏监控 Tab 新增硬件监控区域，实时显示系统状态
- **CPU 使用率** - 实时显示 CPU 使用百分比和核心数，颜色随负载变化
- **内存使用** - 显示内存压力百分比和已用/总量，含进度条
- **CPU 温度** - 通过 AppleSMC/IORegistry 读取 CPU 温度，标注状态（正常/偏高/过热）
- **电池状态** - 显示电池百分比、充电状态和剩余时间
- **网络速率** - 实时计算并显示上传/下载速率
- **系统信息** - 显示进程数、线程数、系统运行时间
- **3秒刷新** - 硬件数据每 3 秒自动刷新，网络速率通过差值计算

## [1.5.0] - 2025-05-13

### Added
- **菜单栏 Tab 切换** - 菜单栏面板新增"监控"和"操作"两个 Tab 页
- **操作统计概览** - 显示总操作数、今日操作数、1小时内操作数三个统计卡片
- **Agent 活跃度排行** - 按 Agent 分组统计操作数量，横向条形图展示 Top 5
- **操作类型分布** - 按创建/修改/删除/移动/重命名分类统计，图标+数字展示
- **最近操作列表** - 显示最近 5 条操作记录，包含 Agent、操作类型、路径和时间
- **操作监控控制** - 操作 Tab 底部可开始/暂停监控、清空记录、查看完整记录
- **ScannerService 桥接** - 通过 ScannerService 桥接 OperationMonitor 数据到菜单栏

## [1.4.0] - 2025-05-13

### Added
- **自动更新安装** - 检测到新版本后自动下载 DMG，无需手动打开浏览器下载
- **下载进度显示** - 菜单栏面板实时显示更新下载进度百分比
- **退出并安装提示** - 下载完成后提示"退出并安装"，应用退出后自动替换并重启
- **启动时自动检查更新** - 应用启动时自动检查 GitHub 最新版本，有更新时弹窗提醒
- **下载取消** - 下载过程中可随时取消下载
- **下载失败重试** - 下载失败时显示错误信息和重试按钮
- **安装脚本** - 自动生成安装脚本，等待应用退出后执行替换、清理和重启

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
