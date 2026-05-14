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
    var searchingApps: String { t("正在扫描...", en: "Scanning...") }

    var agentMonitorTitle: String { t("Agent 监控", en: "Agent Monitor") }
    var agentMonitorSubtitle: String { t("监控 AI Agent 的文件操作", en: "Monitor AI Agent file operations") }
    var monitoring: String { t("监控中", en: "Monitoring") }
    var startMonitoring: String { t("开始监控", en: "Start Monitoring") }
    var clear: String { t("清空", en: "Clear") }
    var records: String { t("条记录", en: "records") }
    var noRecords: String { t("暂无操作记录", en: "No operation records yet") }
    var noRecordsHint: String { t("启动监控后将自动记录 AI Agent 的文件操作", en: "AI Agent file operations will be recorded once monitoring starts") }

    var settings: String { t("设置", en: "Settings") }
    var collapseSidebar: String { t("收起侧边栏", en: "Collapse sidebar") }
    var expandSidebar: String { t("展开侧边栏", en: "Expand sidebar") }
    var features: String { t("功能", en: "Features") }

    var settingsTabAI: String { t("AI", en: "AI") }
    var settingsTabFeatures: String { t("功能", en: "Features") }
    var settingsTabMonitor: String { t("监控", en: "Monitor") }
    var settingsTabLanguage: String { t("语言", en: "Language") }
    var settingsTabVersion: String { t("版本", en: "Version") }

    var navCleaner: String { t("Mac 清理", en: "Mac Clean") }
    var navStorage: String { t("存储分析", en: "Storage Analysis") }
    var navApp: String { t("APP 管理", en: "App Manager") }
    var navDependency: String { t("依赖管理", en: "Dependency") }
    var navOther: String { t("其它工具", en: "Other Tools") }
    var navOperations: String { t("Agent 监控", en: "Agent Monitor") }

    var subCleaner: String { t("扫描并清理存储空间", en: "Scan and clean storage") }
    var subStorage: String { t("存储空间分析与AI建议", en: "Storage analysis with AI") }
    var subApp: String { t("管理已安装的应用", en: "Manage installed apps") }
    var subDependency: String { t("管理开发依赖", en: "Manage dev dependencies") }
    var subOther: String { t("管理命令行工具", en: "Manage CLI tools") }
    var subOperations: String { t("监控 AI Agent 的文件操作", en: "Monitor AI Agent file operations") }

    var searching: String { t("正在扫描...", en: "Scanning...") }
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
    var startScanBtn: String { t("开始扫描", en: "Start Scan") }
    var storageCats: String { t("存储分类", en: "Storage Categories") }
}
