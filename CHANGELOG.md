# Changelog

All notable changes to AIMacCleaner will be documented in this file.

## [Unreleased] - 2026-07-26

### Security
- 清理规则只允许明确的缓存、日志和构建产物子目录；新增构建期规则校验与删除前二次路径护栏，拒绝用户资料根目录、整个应用容器、Docker 虚拟磁盘和越界 AI 建议。
- iOS Remote Pairing 改用带时间戳与 nonce 的 HMAC-SHA256 请求认证，拒绝重放、过期请求、公网来源、远程通用 shell 和旧 Bearer 认证；仅健康检查允许匿名访问。
- AI API Key、配对密钥与 Webhook secret 迁入 Keychain；只有安全写入成功后才删除旧明文，避免迁移失败导致配置丢失。
- Webhook 使用真实 HMAC 签名并限制为安全 HTTPS 目标；本地代理镜像移除通配 CORS、原始配置路由与代理凭据暴露。
- Hook socket 迁入权限为 0700 的用户 Application Support 目录，socket 权限收紧为 0600；Hook 配置解析失败时拒绝覆盖并保留首份备份。
- 直发构建入口统一走 Developer ID、Hardened Runtime、严格签名校验、公证与 staple 流程。

### Added
- Codex、Claude Code、OpenCode / MiniMax、OpenClaw / QClaw 本地用量洞察：Token 分项、180 天热力图、7 日对比、模型/会话排行和来源诊断。
- 菜单栏用量页，以及仅图标/单项/详细三档状态显示、已用/剩余切换和重置倒计时。
- 系统/UTC/固定 IANA 统计时区、扫描进度、结构化诊断、脱敏 JSON 导出与派生缓存清理。
- 主窗口置顶、启动自动检查更新开关、快捷键恢复默认和冲突/系统保留组合校验。

### Improved
- 重做菜单栏弹窗为 26pt 连续圆角的实时控制舱：增加玻璃卡片、弱网格背景、实时状态灯和更清晰的四入口导航。
- 取消信息稀疏的独立“用量”页，将本地 Token 快照、缓存/扫描状态与 Provider 额度、重置时间合并到“额度 / 用量”首页。
- Codex 官方额度严格按 300/10080 分钟识别；临时刷新失败时保留并标注上一次可信额度。
- 大型 JSONL 采用有界流式读取与文件指纹缓存，统计任务离开主线程，缓存不保存提示词或回复正文。
- “Token 统计”与“用量洞察”合并为单一“Token 与用量”入口；模型、会话、来源诊断共用同一规范化事件快照，项目排行和任务归入 Agent 监控。
- Agent 监控项目看板按标准化完整路径合并 7 天/全部时间 Token、API 等值、用量会话和任务，避免同名项目串联。
- 页面明确说明“明细补全”由 TraceFence 本机扫描器执行；应用运行时渐进续读，退出暂停，下次从本地缓存恢复。
- 当前会话产物优先显示最终答复链接名、HTML 标题或父目录语义名；原始文件名和短路径降为次级信息，旧自动命名收藏会安全升级且不覆盖手动改名。
- 用量补全显示本轮检查、实际读取、完整补全、剩余、跳过、失败、结束原因和完成时间，并区分响应额度结束与真正全部扫描完成。

### Fixed
- 官网版可只读复用本机 Claude Desktop 登录会话查询官方 5 小时与周额度；凭据仅在内存中用于 `claude.ai` 请求，不写入缓存或日志，App Store 包不启用该回退。
- iOS Remote Pairing 不再允许不同配对密钥的 TraceFence 进程共享同一监听端口，避免同一二维码随机命中旧密钥并在在线/断开之间跳变。
- iOS 客户端遇到单个旧端点返回 401/402 时会继续验证同一 Mac 的其余网关；重新配对时立即清空旧在线快照，避免假在线状态。
- 菜单栏 AppKit Panel 改为透明背景并对 Hosting View 做连续圆角裁切，消除原来四个直角。
- 修复主场景无法在首次启动时创建，以及关闭主窗口后 Dock 与菜单栏“打开 TraceFence”只能寻找旧窗口的问题；恢复启动场景、统一窗口重开动作，并清理失效窗口引用与重复窗口。
- 当前会话产物的任务目录不再把子 Agent 线程重复列为独立任务；传输别名按原生 thread ID 合并，长提示词型标题压缩为稳定短标题，同时保留同名的真实短任务。
- 修复普通授权目录被注入每一种 Agent 扫描根、同一批日志被重复归因并由旧缓存永久放大的问题；旧污染缓存与第二套 TokenScope 派生缓存会自动淘汰。
- 概览固定显示“全部可信 Agent · 全部时间 Token”，与 Token 与用量页面的同范围快照完全一致，切换页面筛选不会暗改概览数字。
- 全历史累计总量与已解析分项不再混画：聚合索引仅贡献总量，输入/输出分项保持真实明细，并单列“历史未拆分”、明细覆盖率与渐进补全状态。
- OpenCode 与 MiniMax 按原生 turn ID 去重，OpenClaw 与 QClaw 按原生事件 ID 去重；合法零用量记录静默忽略，不再误报为数据异常。
- Cursor、Trae、CodeBuddy、Qoder 等只在存在可信原生 Token 计数时进入汇总；否则继续在 Agent 监控显示活动，不按文件大小或活动次数猜算。
- 菜单栏弹窗可在不成为主窗口的前提下接收首次鼠标点击；用量 Tab 使用完整命中区，旧延迟刷新会被取消，不再需要反复点击才能切换。
- 补全收据不再把因时间或读取额度尚未尝试的会话同时计入“跳过”；未处理项只保留在“剩余”。
- 暖缓存读取预算不足时不再把未尝试会话批量误报为读取失败，结束原因正确显示为读取额度已到。

## [1.7.4] - 2026-05-15

### Removed
- **移除存储分析功能** - 删除侧边栏"存储分析" Tab、StorageAnalysisTab 视图及相关本地化

### Fixed
- **修复侧边栏版本号显示不一致** - 展开/收起状态下均从 `service.currentVersion` 读取，不再硬编码
- **修复 APP 管理执行操作后全量重扫** - 重置/卸载单条 APP 后仅移除该条记录，不再触发全量扫描

### Added
- **Agent 监控页面 AI 自学习开关** - 监控状态栏增加 AI 学习中标识和开关按钮
- **菜单栏 Agent 监控 Tab AI 开关** - 菜单栏弹出面板同样增加 AI 分析按钮和状态提示

## [1.7.3] - 2026-05-15

### Fixed
- **磁盘空间数据与系统设置不一致** - 使用 `URL.resourceValues` 的 `volumeTotalCapacityKey` + `volumeAvailableCapacityForImportantUsageKey` API 读取 APFS Container 级别数据，改用十进制GB（÷10^9）替代二进制GiB（÷2^30），现在显示数据与macOS系统设置完全一致
- **Agent监控无数据（根本性修复）** - 重写 OperationMonitor：lsof 从仅查 Agent PIDs 改为查所有用户进程（`lsof -u $UID`），建立全量文件→PID→进程名缓存映射，事件处理零等待直接命中
- **Agent监控假数据归因** - 重写进程识别算法，支持进程树追溯（子进程node/python等通过ppid归因到父Agent），新增 fileAgentCache 内存缓存（15s TTL / 5000条），过滤系统进程和Finder扩展
- **监控目录覆盖不全** - 扩展 watchPaths 自动发现用户主目录下的 Projects/Dev/Code/workspace 等常见开发目录
- **FSEvents 延迟优化** - latency 从 1.0s 降到 0.5s，进程轮询从 15s 降到 3s
- **存储分析扫描过慢** - 减少系统扫描路径（移除/usr, /sbin等不可访问目录），扫描深度从8降到5，maxFiles从5000降到3000
- **弹窗底部样式不统一** - 将版本号、网络状态、退出APP三个元素提取为弹窗公共外壳（`popoverFooter`），两个Tab共用统一底部布局

### Added
- **路径一键复制** - Agent 监控表格每条记录路径旁新增 📄 复制按钮，点击即复制完整路径，可粘贴到 Finder ⌘⇧G 直接跳转
- **OperationRecord新增字段** - `processName`（实际操作进程名）和 `toolInfo`（命令行信息），UI中Agent列下方小字显示processName，路径列下方小字显示toolInfo
- **全量lsof刷新机制** - `refreshAllProcessInfo()` 通过 `ps -eo` 获取所有进程，`refreshLsofData()` 对当前用户所有 PIDs 执行lsof建立文件→进程映射，不再仅限 Agent 进程
- **进程树追溯** - `resolveAgentNameForPid()` 向上追溯ppid链（最多10层），将子进程归因到父Agent

### Improved
- **Agent监控事件处理** - `processEvents` 中不再调用任何外部命令，只通过内存缓存匹配，性能从秒级降到毫秒级
- **Agent列UI优化** - 已识别agent显示紫色图标，未识别显示灰色，进程名支持tooltip查看，过滤内部标记字符
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
