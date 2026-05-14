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
}
