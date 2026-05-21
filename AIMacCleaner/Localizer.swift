import SwiftUI
import Foundation

enum AppLanguage: String, CaseIterable {
    case chinese = "zh-CN"
    case english = "en"
    var label: String {
        switch self {
        case .chinese: "简体中文"
        case .english: "English"
        }
    }
    var flag: String {
        switch self { case .chinese: "🇨🇳"; case .english: "🇺🇸" }
    }
}

class Localizer: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            objectWillChange.send()
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-CN"
        language = AppLanguage(rawValue: saved) ?? .chinese
    }

    func t(_ zh: String, en: String) -> String {
        language == .chinese ? zh : en
    }
}

extension Localizer {
    var settingsTitle: String { t("设置", en: "Settings") }
    var aiSettings: String { t("AI 设置", en: "AI Settings") }
    var aiSettingsDesc: String { t("配置大模型 API，用于智能分析目录结构和识别可清理项", en: "Configure LLM API for intelligent directory analysis") }
    var apiBase: String { t("API Base", en: "API Base") }
    var apiKey: String { t("API Key", en: "API Key") }
    var modelName: String { t("模型名称", en: "Model Name") }
    var recommendedConfig: String { t("推荐配置（点击自动填入）", en: "Recommended presets (click to auto-fill)") }

    var featureToggles: String { t("功能开关", en: "Feature Toggles") }
    var menuBarMonitor: String { t("菜单栏监控", en: "Menu Bar Monitor") }
    var menuBarMonitorDesc: String { t("在菜单栏显示系统资源监控", en: "Show system resource monitoring in menu bar") }
    var sensorMonitor: String { t("设备监控", en: "Device Monitor") }
    var sensorMonitorDesc: String { t("监控摄像头和麦克风调用", en: "Monitor camera and microphone usage") }
    var operationMonitor: String { t("操作记录", en: "Operation Monitor") }
    var operationMonitorDesc: String { t("监控 AI Agent 的文件操作", en: "Monitor AI Agent file operations") }

    var monitorSettings: String { t("监控设置", en: "Monitor Settings") }
    var storageAlertThreshold: String { t("存储警告阈值", en: "Storage Alert Threshold") }
    var trashInsteadOfDelete: String { t("使用回收站", en: "Use Trash") }
    var trashInsteadOfDeleteDesc: String { t("删除文件时移入回收站而非直接删除", en: "Move files to Trash instead of permanent delete") }

    var versionUpdate: String { t("版本与更新", en: "Version & Updates") }
    var currentVersion: String { t("当前版本", en: "Current Version") }
    var checkUpdate: String { t("检查更新", en: "Check Update") }
    var downloadingUpdate: String { t("正在检查更新...", en: "Checking for updates...") }
    var newVersionAvailable: String { t("发现新版本 v", en: "New version available v") }
    var downloadUpdate: String { t("下载更新", en: "Download Update") }

    var cancel: String { t("取消", en: "Cancel") }
    var save: String { t("保存设置", en: "Save Settings") }

    var languageLabel: String { t("语言", en: "Language") }

    var macCleanerTitle: String { t("Mac 清理", en: "Mac Cleaner") }
    var macCleanerSubtitle: String { t("扫描并清理存储空间", en: "Scan and clean up storage space") }
    var localScan: String { t("本地扫描", en: "Local Scan") }
    var aiScan: String { t("AI 扫描", en: "AI Scan") }
    var enhancedScan: String { t("增强扫描", en: "Enhanced Scan") }
    var diskSpace: String { t("磁盘空间", en: "Disk Space") }
    var used: String { t("已使用", en: "Used") }
    var scanning: String { t("正在扫描存储空间...", en: "Scanning storage space...") }
    var scanningSubtitle: String { t("请稍候，正在分析可清理的文件", en: "Please wait, analyzing cleanable files") }
    var searchFiles: String { t("搜索文件...", en: "Search files...") }
    var allCategories: String { t("全部分类", en: "All Categories") }
    var allApps: String { t("全部应用", en: "All Apps") }
    var riskLabel: String { t("风险", en: "Risk") }
    var smartClean: String { t("智能清理", en: "Smart Clean") }
    var selectAll: String { t("全选", en: "Select All") }
    var safeOnly: String { t("仅安全", en: "Safe Only") }
    var cancelSelection: String { t("取消选择", en: "Deselect") }
    var ignoreSelected: String { t("忽略选中", en: "Ignore Selected") }
    var deleteSelected: String { t("删除选中", en: "Delete Selected") }
    var noMatches: String { t("当前筛选条件下没有匹配项", en: "No matches under current filters") }
    var clearRiskFilter: String { t("清除风险筛选", en: "Clear risk filter") }
    var clearCategoryFilter: String { t("清除分类筛选", en: "Clear category filter") }
    var clearSearch: String { t("清除搜索", en: "Clear search") }
    var cleanComplete: String { t("🎉 清理完成", en: "🎉 Clean Complete") }
    var cleanCompleteMsg: String { t("本次清理释放了", en: "This cleanup freed up") }
    var confirmDelete: String { t("确认删除", en: "Confirm Delete") }
    var deleteBtn: String { t("删除", en: "Delete") }
    var ok: String { t("确定", en: "OK") }

    var storageAnalysisTitle: String { t("存储分析", en: "Storage Analysis") }
    var storageAnalysisSubtitle: String { t("存储空间分析与AI建议", en: "Storage analysis with AI recommendations") }
    var startScan: String { t("开始扫描", en: "Start Scan") }
    var aiAnalysis: String { t("AI 分析", en: "AI Analysis") }
    var aiAnalysisResult: String { t("AI 分析结果", en: "AI Analysis Result") }
    var storageCategories: String { t("存储分类", en: "Storage Categories") }
    var usedLabel: String { t("已使用", en: "Used") }
    var noLargeFiles: String { t("无大文件（>1MB）", en: "No large files (>1MB)") }
    var selectCatView: String { t("选择左侧分类查看文件列表", en: "Select a category on the left to view files") }

    var opCreate: String { t("创建", en: "Create") }
    var opModify: String { t("修改", en: "Modify") }
    var opDelete: String { t("删除", en: "Delete") }
    var opMove: String { t("移动", en: "Move") }
    var opRename: String { t("重命名", en: "Rename") }
    var opRead: String { t("读取", en: "Read") }

    var riskSafe: String { t("安全", en: "Safe") }
    var riskCaution: String { t("注意", en: "Caution") }
    var riskDangerous: String { t("危险", en: "Dangerous") }

    var sourceAI: String { t("AI", en: "AI") }
    var sourceLocal: String { t("本地", en: "Local") }

    var typeApp: String { t("应用", en: "Apps") }
    var typeDependency: String { t("依赖", en: "Dependencies") }
    var typeOther: String { t("其它", en: "Other Tools") }

    var timeAll: String { t("全部", en: "All") }
    var timeToday: String { t("今天", en: "Today") }
    var time1h: String { t("1小时", en: "1 Hour") }
    var time6h: String { t("6小时", en: "6 Hours") }
    var time24h: String { t("24小时", en: "24 Hours") }
    var time7d: String { t("7天", en: "7 Days") }

    var hardwareMonitor: String { t("硬件监控", en: "Hardware Monitor") }
    var diskSpaceLabel: String { t("磁盘空间", en: "Disk Space") }
    var usedPct: String { t("已使用", en: "Used") }
    var totalCapacity: String { t("总容量", en: "Total") }
    var available: String { t("可用", en: "Available") }
    var storageWarning: String { t("存储空间不足！建议立即清理", en: "Low storage! Clean up recommended") }
    var alertThreshold: String { t("警报阈值", en: "Alert Threshold") }
    var remainingPct: String { t("剩余", en: "Remaining") }

    var operationSettings: String { t("操作监控", en: "Operation Monitor") }
    var moveToTrash: String { t("删除移入回收站", en: "Move to Trash") }
    var preventAutoEmptyTrash: String { t("禁止自动清空回收站", en: "Prevent Auto Empty Trash") }
    var pauseMonitoring: String { t("暂停监控", en: "Pause Monitoring") }
    var startMonitoringBtn: String { t("开始监控", en: "Start Monitoring") }
    var clearRecords: String { t("清空", en: "Clear") }
    var clearResults: String { t("清除结果", en: "Clear Results") }
    var viewFullLog: String { t("查看完整记录", en: "View Full Log") }
    var quitApp: String { t("退出", en: "Quit") }
    var openAIMacCleaner: String { t("打开 AIMacCleaner", en: "Open AIMacCleaner") }
    var checkForUpdate: String { t("检查更新", en: "Check for Updates") }
    var checkingUpdate: String { t("检查中...", en: "Checking...") }
    var running: String { t("运行中", en: "Running") }
    var notEnabled: String { t("未启用", en: "Not Enabled") }
    var noData: String { t("暂无数据", en: "No Data") }
    var noOpRecords: String { t("暂无操作记录", en: "No Operation Records") }
    var startMonitorHint: String { t("开启监控后将自动记录 Agent 操作", en: "Agent operations will be recorded once monitoring starts") }
    var totalOps: String { t("总操作", en: "Total Ops") }
    var todayOps: String { t("今日", en: "Today") }
    var hourOps: String { t("1小时", en: "1 Hour") }
    var agentActivity: String { t("Agent 活跃度", en: "Agent Activity") }
    var noOpRecordsShort: String { t("暂无操作记录", en: "No Records") }
    var opTypeDist: String { t("操作类型分布", en: "Operation Types") }
    var recentOps: String { t("最近操作", en: "Recent Operations") }

    var cpuLabel: String { t("CPU", en: "CPU") }
    var memoryLabel: String { t("内存", en: "Memory") }
    var cpuTempLabel: String { t("CPU 温度", en: "CPU Temp") }
    var batteryLabel: String { t("电池", en: "Battery") }
    var networkLabel: String { t("网络", en: "Network") }
    var coresLabel: String { t("核", en: "Cores") }
    var processesLabel: String { t("进程", en: "Processes") }
    var threadsLabel: String { t("线程", en: "Threads") }
    var runtimeLabel: String { t("运行", en: "Running") }
    var overheating: String { t("过热", en: "Overheating") }
    var high: String { t("偏高", en: "High") }
    var normal: String { t("正常", en: "Normal") }
    var charging: String { t("充电中", en: "Charging") }
    var inUse: String { t("使用中", en: "In Use") }

    var sortSize: String { t("大小", en: "Size") }
    var sortCreated: String { t("添加日期", en: "Date Added") }
    var sortModified: String { t("修改日期", en: "Modified") }
    var sortName: String { t("名称", en: "Name") }

    var sort: String { t("排序", en: "Sort") }
    var analyze: String { t("分析", en: "Analyze") }
    var copyPath: String { t("复制路径", en: "Copy path") }

    var appManagerTitle: String { t("APP 管理", en: "App Manager") }
    var appManagerSubtitle: String { t("管理已安装的应用", en: "Manage installed applications") }
    var dependencyTitle: String { t("依赖管理", en: "Dependency Manager") }
    var dependencySubtitle: String { t("管理开发依赖", en: "Manage development dependencies") }
    var otherToolsTitle: String { t("其它工具", en: "Other Tools") }
    var otherToolsSubtitle: String { t("管理命令行工具", en: "Manage command line tools") }
    var refresh: String { t("刷新", en: "Refresh") }
    var all: String { t("全部", en: "All") }
    var actionConfirm: String { t("确认操作", en: "Confirm Action") }
    var actionComplete: String { t("操作完成", en: "Action Complete") }
    var searchingApps: String { t("搜索应用...", en: "Search apps...") }
    var searchingScanning: String { t("正在扫描...", en: "Scanning...") }

    var agentMonitorTitle: String { t("Agent 监控", en: "Agent Monitor") }
    var agentMonitorSubtitle: String { t("监控 AI Agent 的文件操作", en: "Monitor AI Agent file operations") }
    var monitoring: String { t("监控中", en: "Monitoring") }
    var startMonitoring: String { t("开始监控", en: "Start Monitoring") }
    var clear: String { t("清空", en: "Clear") }
    var records: String { t("条记录", en: "records") }
    var noRecords: String { t("暂无操作记录", en: "No operation records yet") }
    var noRecordsHint: String { t("启动监控后将自动记录 AI Agent 的文件操作", en: "AI Agent file operations will be recorded once monitoring starts") }

    var settings: String { t("设置", en: "Settings") }
    var collapseSidebar: String { t("收起", en: "Collapse") }
    var expandSidebar: String { t("展开侧边栏", en: "Expand sidebar") }
    var features: String { t("功能", en: "Features") }

    var settingsTabAI: String { t("AI", en: "AI") }
    var settingsTabFeatures: String { t("功能", en: "Features") }
    var settingsTabMonitor: String { t("监控", en: "Monitor") }
    var settingsTabLanguage: String { t("语言", en: "Language") }
    var settingsTabVersion: String { t("版本", en: "Version") }

    var navCleaner: String { t("Mac 清理", en: "Mac Cleaner") }
    var navApp: String { t("APP 管理", en: "App Manager") }
    var navDependency: String { t("依赖管理", en: "Dependency") }
    var navOther: String { t("其它工具", en: "Other Tools") }
    var navOperations: String { t("Agent 监控", en: "Agent Monitor") }

    var subCleaner: String { t("扫描并清理存储空间", en: "Scan and clean storage") }
    var subApp: String { t("管理已安装的应用", en: "Manage installed apps") }
    var subDependency: String { t("管理开发依赖", en: "Manage dev dependencies") }
    var subOther: String { t("管理命令行工具", en: "Manage CLI tools") }
    var subOperations: String { t("监控 AI Agent 的文件操作", en: "Monitor AI Agent file operations") }

    var searching: String { t("搜索...", en: "Search...") }
    var notFound: String { t("未发现", en: "Not found") }
    var selected: String { t("已选", en: "Selected") }
    var selectAllBtn: String { t("全选", en: "Select All") }
    var cancelBtn: String { t("取消", en: "Cancel") }
    var resetAction: String { t("重置", en: "Reset") }
    var basicUninstall: String { t("基础卸载", en: "Basic Uninstall") }
    var fullUninstall: String { t("完全卸载", en: "Full Uninstall") }
    var resetDesc: String { t("清除缓存和历史数据，恢复为全新安装状态（APP本身保留）", en: "Clear cache and data, restore to fresh install state") }
    var basicUninstallDesc: String { t("仅卸载安装文件，保留缓存和历史数据（重新安装后可恢复）", en: "Uninstall only, keep cache and data") }
    var fullUninstallDesc: String { t("卸载并清除所有缓存、历史数据和配置（彻底清除，不可恢复）", en: "Uninstall and clear all data (permanent)") }
    var confirmAction: String { t("确认操作", en: "Confirm Action") }
    var actionDone: String { t("操作完成", en: "Action Done") }
    var confirmBtn: String { t("确认", en: "Confirm") }
    var willAction: String { t("将", en: "Will") }
    var total: String { t("共", en: "Total") }

    var nameCol: String { t("名称", en: "Name") }
    var riskCol: String { t("风险", en: "Risk") }
    var impactCol: String { t("影响说明", en: "Impact") }
    var sizeCol: String { t("大小", en: "Size") }
    var actionCol: String { t("操作", en: "Action") }
    var safe: String { t("安全", en: "Safe") }
    var dangerous: String { t("危险", en: "Dangerous") }
    var warning: String { t("注意", en: "Warning") }

    var timeCol: String { t("时间", en: "Time") }
    var agentCol: String { t("Agent", en: "Agent") }
    var opCol: String { t("操作", en: "Operation") }
    var pathCol: String { t("目标路径", en: "Target Path") }
    var fileSizeCol: String { t("大小", en: "Size") }
    var allAgents: String { t("全部 Agent", en: "All Agents") }
    var allTypes: String { t("全部类型", en: "All Types") }
    var timeRange: String { t("时间范围", en: "Time Range") }
    var opTypeLabel: String { t("操作类型", en: "Operation Type") }
    var agentLabel: String { t("Agent", en: "Agent") }
    var recordsCount: String { t("条", en: "records") }

    var allCats: String { t("全部分类", en: "All Categories") }

    var internetStatus: String { t("互联网", en: "Internet") }
    var offlineStatus: String { t("离线", en: "Offline") }

    var quitBehaviorTitle: String { t("退出行为", en: "Quit Behavior") }
    var quitBehaviorDesc: String { t("控制点击 Dock 退出按钮或 Cmd+Q 时的行为", en: "Control behavior when clicking Dock quit or pressing Cmd+Q") }
    var quitAppAndMenu: String { t("退出应用和菜单栏（默认）", en: "Quit App & Menu Bar (Default)") }
    var quitAppKeepMenu: String { t("仅退出应用，保留菜单栏监控", en: "Quit App Only, Keep Menu Bar")}

    var liveMonitor: String { t("实时监控", en: "Live Monitor") }
    var audit: String { t("审计", en: "Audit") }
    var auditColon: String { t("审计: ", en: "Audit: ") }
    var auditRecordCount: String { t("条记录", en: "records") }
    var back: String { t("返回", en: "Back") }
    var aiAnalyzing: String { t("分析中...", en: "Analyzing...") }
    var aiSummaryTitle: String { t("AI 分析总结", en: "AI Analysis Summary") }
    var aiLearning: String { t("AI 学习中", en: "AI Learning") }
    var closeAI: String { t("关闭 AI", en: "Close AI") }
    var noCuratedData: String { t("暂无梳理数据", en: "No curated data") }
    var noCuratedHint: String { t("点击\"立即梳理\"通过 AI 分析原始监控数据", en: "Click \"Curate Now\" to analyze raw data with AI") }
    var agentOpAudit: String { t("Agent 操作审计", en: "Agent Operation Audit") }
    var scanToDiscover: String { t("点击\"刷新扫描\"发现本机的 Agent 会话记录", en: "Click \"Scan\" to discover Agent sessions") }
    var supportedAgents: String { t("支持 Claude Code、Codex、Trae、Cursor、CodeBuddy、Aider、Cline 等 20+ 种 Agent", en: "Supports Claude Code, Codex, Trae, Cursor, CodeBuddy, Aider, Cline and 20+ agents") }
    var scanRefresh: String { t("刷新扫描", en: "Refresh Scan") }
    var customBadge: String { t("自定义", en: "Custom") }
    var addCustomAgent: String { t("添加自定义 Agent", en: "Add Custom Agent") }
    var selectFromInstalled: String { t("从已安装的 APP/依赖/工具中选择", en: "Select from installed apps/deps/tools") }
    var customAgentName: String { t("名称", en: "Name") }
    var sessionPathHint: String { t("会话目录路径 (如 ~/.trae/sessions)", en: "Session directory path (e.g. ~/.trae/sessions)") }
    var removeCustomAgent: String { t("移除自定义 Agent", en: "Remove Custom Agent") }
    var highFreqFiles: String { t("高频文件:", en: "Top Files:") }
    var filterColon: String { t("筛选: ", en: "Filter: ") }
    var scanAgentSession: String { t("正在扫描 Agent 会话...", en: "Scanning Agent sessions...") }
    var parsingAgentOps: String { t("正在解析", en: "Parsing") }
    var operationsRecord: String { t("的操作记录...", en: "operations...") }
    var monitoringStarted: String { t("监控已启动，等待文件操作事件...", en: "Monitoring started, waiting for file events...") }
    var monitoringHint: String { t("请在其他应用中创建、修改或删除文件以产生记录", en: "Create, modify or delete files in other apps to generate records") }
    var searchingLabel: String { t("搜索", en: "Search") }
    var searchingPlaceholder: String { t("搜索...", en: "Search...") }
    var checkUpdates: String { t("检查更新", en: "Check Updates") }

    var deviceMonitor: String { t("设备监控", en: "Device Monitor") }
    var deviceMonitorSubtitle: String { t("摄像头与麦克风使用监控", en: "Camera & Microphone Monitor") }
    var camera: String { t("摄像头", en: "Camera") }
    var microphone: String { t("麦克风", en: "Microphone") }
    var stopMonitor: String { t("停止监控", en: "Stop Monitor") }
    var deviceMonitorStopped: String { t("设备监控未启动", en: "Device Monitor Stopped") }
    var deviceMonitorHint: String { t("启动后将监控摄像头和麦克风的使用情况", en: "Monitor camera and microphone usage after start") }
    var noDeviceCall: String { t("未检测到设备调用", en: "No Device Call Detected") }
    var noDeviceCallHint: String { t("摄像头和麦克风均未被使用", en: "Camera and microphone are not in use") }

    var scanningStorage: String { t("正在扫描存储空间...", en: "Scanning storage...") }
    var scanningStorageHint: String { t("请稍候，正在分析可清理的文件", en: "Please wait, analyzing cleanable files") }
    var noMatchesHint: String { t("当前筛选条件下没有匹配项", en: "No matches under current filters") }
    var smartCleanDesc: String { t("智能清理 Mac 存储空间", en: "Intelligently clean Mac storage") }

    var installingUpdate: String { t("正在安装更新，应用即将重启...", en: "Installing update, app will restart...") }
    var updateDownloaded: String { t("更新已下载完成", en: "Update download complete") }
    var quitAndInstall: String { t("退出并安装", en: "Quit & Install") }
    var retryDownload: String { t("重试下载", en: "Retry Download") }
    var updateToVersion: String { t("更新到", en: "Update to") }
    var scanningAppList: String { t("正在扫描已安装应用列表...", en: "Scanning installed app list...") }
    var confirmUninstallMsg: String { t("确定要卸载", en: "Are you sure you want to uninstall") }
    var irreversibleMsg: String { t("此操作不可撤销。", en: "This action is irreversible.") }
    var willUninstallIntel: String { t("将卸载", en: "Will uninstall") }
    var intelVersionMsg: String { t("的 Intel 版本，并尝试安装 ARM 原生版本。", en: "Intel version and try to install ARM native version.") }
    var scannedCount: String { t("已扫描", en: "Scanned") }
    var itemsLabel: String { t("项", en: "items") }
    var clickScanToDetect: String { t("点击\"扫描\"开始检测", en: "Click \"Scan\" to start detection") }
    var scanDesc1: String { t("将扫描所有已安装的APP、依赖和CLI工具的CPU架构", en: "Scan CPU architecture of all installed apps, deps and CLI tools") }
    var scanDesc2: String { t("检测哪些需要适配当前 Apple Silicon 芯片", en: "Detect which need adaptation for current Apple Silicon chip") }
    var firstScanHint: String { t("请稍候，首次扫描需要获取所有应用信息", en: "Please wait, first scan needs to fetch all app info") }
    var detectingArch: String { t("正在检测CPU架构...", en: "Detecting CPU architecture...") }
    var allAdapted: String { t("所有应用均已适配 Apple Silicon", en: "All apps are adapted for Apple Silicon") }
    var noIntelApps: String { t("您的 Mac 上没有需要适配的 Intel 应用", en: "No Intel apps need adaptation on your Mac") }
    var needAdapt: String { t("需适配", en: "Needs Adaptation") }
    var replaceBtn: String { t("替换", en: "Replace") }
    var confirmUninstall: String { t("确认卸载", en: "Confirm Uninstall") }
    var replaceARMVersion: String { t("替换为 ARM 版本", en: "Replace with ARM Version") }
    var uninstallBtn: String { t("卸载", en: "Uninstall") }
    var confidence: String { t("置信度", en: "Confidence") }
    var unitAgent: String { t("个 Agent", en: " agents") }
    var unitSession: String { t("个会话", en: " sessions") }
    var recentLabel: String { t("最近", en: "Recent") }
    var addAndScan: String { t("添加并扫描", en: "Add & Scan") }
    var selectAgentToAdd: String { t("选择要添加的 Agent / APP / 工具", en: "Select Agent / App / Tool to add") }
    var noMatchingApp: String { t("没有找到匹配的 APP", en: "No matching app found") }
    var alreadyAdded: String { t("已添加", en: "Already added") }
    var selectAppFromList: String { t("点击列表选择一个 APP", en: "Click list to select an app") }
    var confirmDeleteMsg: String { t("确定删除", en: "Confirm delete") }
    var releasable: String { t("可释放", en: "Releasable") }
    var operationCol: String { t("操作", en: "Operation") }
    var instructionCol: String { t("指令", en: "Instruction") }
    var targetPathCol: String { t("目标路径", en: "Target Path") }
    var projectCol: String { t("项目", en: "Project") }
    var detailCol: String { t("详情", en: "Detail") }
    var localScanSubtitle: String { t("扫描系统缓存、日志等已知可清理目录", en: "Scan known cleanable dirs like system caches, logs") }
    var aiScanSubtitle: String { t("大模型补充发现本地规则遗漏的清理项", en: "AI supplements local rules to find missed items") }
    var enhancedScanSubtitle: String { t("本地 + AI 双重检测，覆盖最全面", en: "Local + AI dual detection, most comprehensive coverage") }

    var navMigration: String { t("适配检测", en: "Adaptation Check") }
    var subMigration: String { t("Apple Silicon 架构适配", en: "Apple Silicon Architecture Adaptation") }
    var processHelp: String { t("进程: ", en: "Process: ") }
    var openInFinder: String { t("在 Finder 中打开", en: "Open in Finder") }
    var opWrite: String { t("写入", en: "Write") }
    var opEdit: String { t("编辑", en: "Edit") }
    var opRead2: String { t("读取", en: "Read") }
    var opDelete2: String { t("删除", en: "Delete") }
    var opExec: String { t("执行命令", en: "Execute") }
    var opSearch: String { t("搜索", en: "Search") }
    var opOpen: String { t("打开", en: "Open") }
    var opClose: String { t("关闭", en: "Close") }
    var opDialogue: String { t("对话", en: "Chat") }
    var opAction: String { t("操作", en: "Action") }
    var opNew: String { t("新增", en: "New") }
    var opSave: String { t("保存", en: "Save") }
    var unknownAgent: String { t("未知", en: "Unknown") }
    var timesUnit: String { t("次", en: "times") }
    var unitItems: String { t("个", en: "items") }
    var apiConfigInvalid: String { t("API 配置无效", en: "Invalid API configuration") }
    var apiRequestFailed: String { t("API 请求失败", en: "API request failed") }
    var aiFormatError: String { t("AI 返回格式异常", en: "AI response format error") }
    var requestFailed: String { t("请求失败", en: "Request failed") }
    var successCount: String { t("成功", en: "Success") }
    var failCount: String { t("失败", en: "Failed") }
    var scanningDisk: String { t("正在扫描磁盘...", en: "Scanning disk...") }
    var scanningApps: String { t("扫描应用程序...", en: "Scanning applications...") }
    var scanningDocs: String { t("扫描文稿...", en: "Scanning documents...") }
    var calcSystemData: String { t("计算系统数据...", en: "Calculating system data...") }
    var scanningOther: String { t("扫描其它...", en: "Scanning other...") }
    var appNameApps: String { t("应用程序", en: "Applications") }
    var appNameDocs: String { t("文稿", en: "Documents") }
    var appNameSystem: String { t("系统数据", en: "System Data") }
    var appNameOther: String { t("其它", en: "Other") }
    var gettingHardwareInfo: String { t("正在获取硬件信息...", en: "Getting hardware info...") }
    var downloadingUpdateFmt: String { t("正在下载更新", en: "Downloading update") }
    var storageAlert: String { t("存储警报", en: "Storage Alert") }
    var alertThresholdLabel: String { t("警报阈值", en: "Alert Threshold") }
    var remainingLabel: String { t("剩余", en: "Remaining") }
    var thresholdLabel: String { t("阈值", en: "Threshold") }
    var opMonitorLabel: String { t("操作监控", en: "Operation Monitor") }
    var opStatsLabel: String { t("操作统计", en: "Operation Stats") }
    var monitoringLabel: String { t("监控中", en: "Monitoring") }
    var notEnabledLabel: String { t("未启用", en: "Not Enabled") }
    var totalOpsLabel: String { t("总操作", en: "Total Ops") }
    var todayLabel: String { t("今日", en: "Today") }
    var hourLabel: String { t("1小时", en: "1 Hour") }
    var agentActivityLabel: String { t("Agent 活跃度", en: "Agent Activity") }
    var noOpRecordsLabel: String { t("暂无操作记录", en: "No Operation Records") }
    var opTypeDistLabel: String { t("操作类型分布", en: "Operation Types") }
    var recentOpsLabel: String { t("最近操作", en: "Recent Operations") }
    var recordsUnit: String { t("条", en: "records") }
    var startMonitorHint2: String { t("开启监控后将自动记录 Agent 操作", en: "Agent operations will be recorded once monitoring starts") }
    var pauseMonitorLabel: String { t("暂停监控", en: "Pause Monitoring") }
    var startMonitorLabel: String { t("开始监控", en: "Start Monitoring") }
    var closeAILabel: String { t("关闭 AI", en: "Close AI") }
    var aiAnalysisLabel: String { t("AI分析", en: "AI Analysis") }
    var aiSelfLearning: String { t("AI 自学习 Agent 识别", en: "AI Self-Learning Agent Detection") }
    var aiSelfLearningDesc: String { t("调用 AI 自动分析未知进程和目录，持续优化 Agent 监控准确性", en: "Auto-analyze unknown processes and directories with AI to improve monitoring accuracy") }
    var aiSelfLearningStatus: String { t("AI 自学习中...", en: "AI Self-Learning...") }
    var viewFullLogLabel: String { t("查看完整记录", en: "View Full Log") }
    var cleanableRisk: String { t("可清理", en: "Cleanable") }
    var cautionRisk: String { t("谨慎清理", en: "Clean with Caution") }
    var keepRisk: String { t("保留", en: "Keep") }
    var unknownRisk: String { t("未知", en: "Unknown") }
    var localSource: String { t("本地", en: "Local") }
    var dirType: String { t("目录", en: "Directory") }
    var fileType: String { t("文件", en: "File") }
    var catPackageManager: String { t("包管理", en: "Package Manager") }
    var catDev: String { t("开发", en: "Development") }
    var catApp: String { t("应用", en: "Apps") }
    var catOther: String { t("其它", en: "Other") }
    var catBrowser: String { t("浏览器", en: "Browser") }
    var catOffice: String { t("办公", en: "Office") }
    var catAIAgent: String { t("AI Agent", en: "AI Agent") }
    var catSystem: String { t("系统", en: "System") }
    var catSocial: String { t("社交", en: "Social") }
    var catCLI: String { t("CLI", en: "CLI") }
    var uninstalling: String { t("正在卸载...", en: "Uninstalling...") }
    var installing: String { t("正在安装...", en: "Installing...") }
    var completed: String { t("已完成", en: "Completed") }
    var failed: String { t("失败", en: "Failed") }
    var unknownArch: String { t("未知", en: "Unknown") }
    var rosettaTrans: String { t("Rosetta 转译", en: "Rosetta Translation") }
    var universalBinary: String { t("通用", en: "Universal") }
    var translated: String { t("转译", en: "Translated") }
    var highConf: String { t("高", en: "High") }
    var medConf: String { t("中", en: "Medium") }
    var lowConf: String { t("低", en: "Low") }
    var needAdaptLabel: String { t("需适配", en: "Needs Adaptation") }
    var universalBinLabel: String { t("通用二进制", en: "Universal Binary") }
    var armNative: String { t("ARM 原生", en: "ARM Native") }
    var releasableSpace: String { t("可释放空间", en: "Releasable Space") }
    var showIntelOnly: String { t("仅显示需适配", en: "Show Intel Only") }
    var uninstallIntelAndInstallARM: String { t("卸载 Intel 版本并安装 ARM 版本", en: "Uninstall Intel version and install ARM version") }
    var searchARMDownload: String { t("搜索 ARM 版本下载链接", en: "Search ARM version download link") }
    var searchPureARM: String { t("搜索纯 ARM 版本", en: "Search pure ARM version") }
    var openDownloadLink: String { t("打开下载链接", en: "Open download link") }
    var uninstallLabel: String { t("卸载", en: "Uninstall") }
    var detectingArchWithLipo: String { t("使用 lipo/file 命令检测每个应用的二进制架构", en: "Detecting binary architecture of each app using lipo/file commands") }
    var appTypeApp: String { t("应用程序", en: "Application") }
    var appTypeCLI: String { t("命令行工具", en: "CLI Tool") }
    var appTypeHomebrew: String { t("Homebrew 包", en: "Homebrew Package") }
    var appTypeFramework: String { t("框架/库", en: "Framework/Library") }
    var minuteUnit: String { t("分钟", en: "min") }
    var networkModeTitle: String { t("网络模式", en: "Network Mode") }
    var networkModeDesc: String { t("选择更新检查和 AI 功能的网络模式", en: "Choose network mode for update checking and AI features") }
    var internetMode: String { t("互联网模式", en: "Internet Mode") }
    var internetModeDesc: String { t("完整互联网访问，支持更新、AI 扫描和版本检查", en: "Full internet access for updates, AI scanning, and version checking") }
    var intranetMode: String { t("内网模式（离线）", en: "Intranet Mode (Offline)") }
    var intranetModeDesc: String { t("无互联网访问，仅支持本地扫描，不检查更新", en: "No internet access. Local scanning only, no update checks") }
    var updateChecking: String { t("更新检查", en: "Update Checking") }
    var updateCheckingDesc: String { t("互联网模式下，可以检查已安装应用、AI Agent、CLI 工具和依赖的更新", en: "In internet mode, the app can check for updates of installed apps, AI agents, CLI tools, and dependencies.") }
    var movedToTrash: String { t("已移入回收站", en: "Moved to Trash") }
    var configureAPIKeyFirst: String { t("请先配置大模型 API Key", en: "Please configure LLM API Key first") }
    var collectingDirInfo: String { t("正在收集目录信息...", en: "Collecting directory info...") }
    var callingAIAnalysis: String { t("正在调用大模型分析...", en: "Calling AI for analysis...") }
    var aiScanComplete: String { t("AI 扫描完成，发现", en: "AI scan complete, found") }
    var aiScanFailed: String { t("AI 扫描失败", en: "AI scan failed") }
    var suggestLocalScan: String { t("建议使用本地扫描", en: "Suggest using local scan") }
    var unknownError: String { t("未知错误", en: "Unknown error") }
    var userDir: String { t("用户目录", en: "User Directory") }
    var unknownDir: String { t("未知目录，删除前请确认其用途", en: "Unknown directory, confirm its purpose before deletion") }
    var menuBarMonitorClosed: String { t("菜单栏监控已关闭", en: "Menu bar monitor closed") }
    var searchLinkGenFailed: String { t("搜索链接生成失败", en: "Search link generation failed") }
    var systemProcess: String { t("系统进程", en: "System Process") }
    var processNotFound: String { t("未找到相关的运行中进程，请确认该程序正在运行", en: "No running process found, please confirm the program is running") }
    var fileDeleted: String { t("文件已删除", en: "File deleted") }
    var fileRead: String { t("文件已读取", en: "File read") }
    var fileCreated: String { t("文件已创建", en: "File created") }
    var contentChanged: String { t("内容已更改", en: "Content changed") }
    var fileModified: String { t("文件已修改", en: "File modified") }
    var fileTruncated: String { t("截断", en: "Truncated") }
    var fileChangeCount: String { t("个文件变更", en: "files changed") }
    var allowedPaths: String { t("允许访问", en: "Allowed access") }
    var pathsCount: String { t("个路径", en: "paths") }
    var currentSession: String { t("当前活跃会话", en: "Current active session") }
    var historySession: String { t("历史会话", en: "History session") }
    var parsingOps: String { t("正在解析", en: "Parsing") }
    var opsRecord: String { t("的操作记录...", en: "operations...") }
    var colType: String { t("类型", en: "Type") }
    var colProcess: String { t("进程", en: "Process") }
    var colPath: String { t("路径", en: "Path") }
    var colSize: String { t("大小", en: "Size") }
    var colName: String { t("名称", en: "Name") }
    var colSource: String { t("来源", en: "Source") }
    var colApp: String { t("应用", en: "App") }
    var colRisk: String { t("风险", en: "Risk") }
    var colDesc: String { t("说明", en: "Description") }
    var colAction: String { t("操作", en: "Action") }
    var detectingApp: String { t("检测", en: "Detecting") }
    var invalidDownloadLink: String { t("下载链接无效", en: "Invalid download link") }
    var saveDownloadFailed: String { t("保存下载文件失败", en: "Failed to save download file") }
    var downloadFailed: String { t("下载失败", en: "Download failed") }
    var installFileNotFound: String { t("安装文件不存在，请重新下载", en: "Install file not found, please re-download") }
    var storageWarningTitle: String { t("⚠️ 存储空间不足", en: "⚠️ Low Storage") }
    var storageWarningBody: String { t("磁盘剩余", en: "Disk remaining") }
    var suggestCleanNow: String { t("建议立即清理", en: "Clean up recommended") }
    var configureAIModel: String { t("请先配置 AI 模型（设置 → AI 设置）", en: "Please configure AI model (Settings → AI Settings)") }
    var collectingRawData: String { t("正在收集原始数据...", en: "Collecting raw data...") }
    var noMonitorData: String { t("暂无监控数据，请先启用 Agent 监控并等待文件操作产生", en: "No monitoring data, please enable Agent monitoring and wait for file operations") }
    var insufficientDataPrefix: String { t("监控数据不足（仅有", en: "Insufficient data (only") }
    var continueMonitorRetry: String { t("条），继续监控后重试", en: "records), continue monitoring and retry") }
    var curationComplete: String { t("梳理完成：", en: "Curation complete: ") }
    var allInternalOps: String { t("条事件均在 agent 自身项目目录内，无对外部文件的操作", en: "events are all within the agent's own project directory, no external file operations") }
    var allSystemOps: String { t("均为系统内部操作，未发现对外部文件的改动", en: "All are internal system operations, no external file changes detected") }
    var identifiedAgentOps: String { t("识别到", en: "Identified") }
    var agentOpsRecords: String { t("条 Agent 操作", en: "Agent operations") }
    var noProcessSnapshot: String { t("无进程快照——请确保 Agent 监控已启用，或重新启用后等待 30 秒再试", en: "No process snapshots—ensure Agent monitoring is enabled, or re-enable and wait 30 seconds") }
    var aiConfigIncomplete: String { t("AI 配置不完整", en: "AI configuration incomplete") }
    var requestBuildFailed: String { t("请求构建失败", en: "Request build failed") }
    var networkError: String { t("网络错误", en: "Network error") }
    var apiError: String { t("API 错误", en: "API error") }
    var aiResponseFormatError: String { t("AI 响应格式错误", en: "AI response format error") }
    var networkRequestFailed: String { t("网络请求失败", en: "Network request failed") }
    var aiNoJsonArray: String { t("AI 未返回 JSON 数组或对象", en: "AI did not return JSON array or object") }
    var updateInstallFailedMount: String { t("更新安装失败：无法挂载安装包", en: "Update install failed: cannot mount installer") }
    var updateInstallFailedApp: String { t("更新安装失败：安装包中未找到应用", en: "Update install failed: app not found in installer") }
    var updateInstallFailedCopy: String { t("更新安装失败：无法复制应用", en: "Update install failed: cannot copy app") }
    var updateSuccess: String { t("已成功更新到最新版本", en: "Successfully updated to latest version") }
    var pleaseConfigureAPIKey: String { t("⚠️ 请先配置大模型 API Key", en: "⚠️ Please configure LLM API Key first") }
    var analyzingDots: String { t("🔄 分析中...", en: "🔄 Analyzing...") }
    var invalidAPIUrl: String { t("❌ 无效的 API 地址", en: "❌ Invalid API URL") }
    var invalidHttpResponse: String { t("❌ 无效的 HTTP 响应", en: "❌ Invalid HTTP response") }
    var aiModelFormatError: String { t("❌ 大模型返回格式错误", en: "❌ AI model response format error") }
    var analysisComplete: String { t("🤖 分析完成（详见原说明）", en: "🤖 Analysis complete (see original description)") }
    var uninstallFailed: String { t("卸载失败", en: "Uninstall failed") }
    var systemPrefix: String { t("系统", en: "system") }
}
