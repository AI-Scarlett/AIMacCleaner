import Foundation
import Combine
import UserNotifications
import AppKit

@MainActor
class ScannerService: ObservableObject {
    @Published var scanItems: [ScanItem] = []
    @Published var diskInfo: DiskInfo?
    @Published var isScanning = false
    @Published var isAiScanning = false
    @Published var isEnhancedScanning = false
    @Published var aiStatusMessage = ""
    @Published var errorMessage: String?
    @Published var aiConfig: AIConfig?
    @Published var installedApps: [AppInfo] = []
    @Published var isScanningApps = false

    private var ignoredIds: Set<String> = []
    private let ignoreFilePath = NSHomeDirectory() + "/.aimaccleaner_ignore.json"
    private let aiConfigFilePath = NSHomeDirectory() + "/.aimaccleaner_ai.json"

    init() {
        loadIgnores()
        loadAIConfigFromDisk()
        diskInfo = getDiskInfoNative()
    }

    // MARK: - Disk Info

    func getDiskInfoNative() -> DiskInfo? {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return nil }

        let total = Int64(UInt64(fs.f_blocks) * UInt64(fs.f_bsize))
        let free = Int64(UInt64(fs.f_bavail) * UInt64(fs.f_bsize))
        let used = total - free
        let usedPct = total > 0 ? Double(used) / Double(total) * 100.0 : 0

        return DiskInfo(
            total: total, used: used, free: free,
            totalGb: Double(total) / 1073741824.0,
            usedGb: Double(used) / 1073741824.0,
            freeGb: Double(free) / 1073741824.0,
            usedPct: usedPct
        )
    }

    func refreshDiskInfo() {
        diskInfo = getDiskInfoNative()
    }

    // MARK: - Local Scan

    func scanLocal() async {
        isScanning = true
        errorMessage = nil

        let savedIgnores = ignoredIds

        let items = await Task.detached(priority: .userInitiated) {
            var results: [ScanItem] = []
            let fm = FileManager.default

            for rule in SCAN_RULES {
                var totalSize: Int64 = 0
                var totalFiles = 0
                var realPath = ""

                for path in rule.paths {
                    let expanded = NSString(string: path).expandingTildeInPath
                    var isDir: ObjCBool = false

                    guard fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else { continue }

                    realPath = expanded
                    let (size, count) = Self.calculateDirectorySizeStatic(at: expanded)
                    totalSize += size
                    totalFiles += count
                }

                guard totalSize > 0 else { continue }

                results.append(ScanItem(
                    id: rule.id,
                    name: rule.name,
                    category: rule.category,
                    app: rule.app,
                    risk: rule.risk,
                    riskDesc: rule.riskDesc,
                    path: rule.paths.first ?? "",
                    realPath: realPath,
                    size: totalSize,
                    fileCount: totalFiles,
                    ignored: savedIgnores.contains(rule.id),
                    reason: nil,
                    source: "local"
                ))
            }

            results.sort { $0.size > $1.size }
            return results
        }.value

        scanItems = items
        isScanning = false
    }

    nonisolated private static func calculateDirectorySizeStatic(at path: String) -> (Int64, Int) {
        let fm = FileManager.default
        var totalSize: Int64 = 0
        var fileCount = 0

        guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: path),
                                              includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                              options: [.skipsHiddenFiles],
                                              errorHandler: nil) else {
            return (0, 0)
        }

        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values.isRegularFile == true, let size = values.fileSize {
                    totalSize += Int64(size)
                    fileCount += 1
                }
            } catch {
                continue
            }
        }

        return (totalSize, fileCount)
    }

    // MARK: - Delete

    func deleteItems(ids: [String]) async -> DeleteResult {
        var deleteResults: [DeleteItemResult] = []
        var successCount = 0
        var failCount = 0

        let itemsToDelete = scanItems.filter { ids.contains($0.id) }

        for item in itemsToDelete {
            var pathsToDelete: [String] = []

            if let rule = SCAN_RULES.first(where: { $0.id == item.id }) {
                pathsToDelete = rule.paths.map { NSString(string: $0).expandingTildeInPath }
            } else if let realPath = item.realPath, !realPath.isEmpty {
                pathsToDelete = [realPath]
            } else {
                pathsToDelete = [NSString(string: item.path).expandingTildeInPath]
            }

            for expanded in pathsToDelete {
                do {
                    if FileManager.default.fileExists(atPath: expanded) {
                        try moveToTrash(atPath: expanded)
                        successCount += 1
                        deleteResults.append(DeleteItemResult(id: item.id, path: expanded, success: true, message: "已移入回收站"))
                    }
                } catch {
                    failCount += 1
                    deleteResults.append(DeleteItemResult(id: item.id, path: expanded, success: false, message: error.localizedDescription))
                }
            }
        }

        return DeleteResult(success: true, results: deleteResults, deleted: successCount, failed: failCount)
    }

    func removeScannedItems(ids: [String]) {
        scanItems.removeAll { ids.contains($0.id) }
    }

    // MARK: - Ignore

    func ignoreItems(ids: [String]) {
        ignoredIds.formUnion(ids)
        saveIgnores()
        for i in scanItems.indices {
            if ids.contains(scanItems[i].id) {
                scanItems[i].ignored = true
            }
        }
    }

    func unignoreItems(ids: [String]) {
        ignoredIds.subtract(ids)
        saveIgnores()
        for i in scanItems.indices {
            if ids.contains(scanItems[i].id) {
                scanItems[i].ignored = false
            }
        }
    }

    private func loadIgnores() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: ignoreFilePath)),
              let array = try? JSONDecoder().decode([String].self, from: data) else { return }
        ignoredIds = Set(array)
    }

    private func saveIgnores() {
        let array = Array(ignoredIds)
        guard let data = try? JSONEncoder().encode(array) else { return }
        try? data.write(to: URL(fileURLWithPath: ignoreFilePath))
    }

    // MARK: - AI Config

    func loadAIConfigFromDisk() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: aiConfigFilePath)),
              let config = try? JSONDecoder().decode(AIConfig.self, from: data) else {
            aiConfig = AIConfig(apiBase: "https://api.deepseek.com", apiKey: nil, model: "deepseek-chat", hasKey: false)
            return
        }
        aiConfig = config
    }

    func saveAIConfig(apiBase: String, apiKey: String, model: String) {
        let config = AIConfig(apiBase: apiBase, apiKey: apiKey, model: model, hasKey: !apiKey.isEmpty)
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: URL(fileURLWithPath: aiConfigFilePath))
        aiConfig = config
    }

    // MARK: - AI Scan

    func startAiScan() async {
        guard let config = aiConfig, config.hasKey == true, let apiKey = config.apiKey, !apiKey.isEmpty else {
            errorMessage = "请先配置大模型 API Key"
            return
        }

        isAiScanning = true
        aiStatusMessage = "正在收集目录信息..."

        let dirInfo = collectDirInfo()
        aiStatusMessage = "正在调用大模型分析..."

        let result = await callLLM(config: config, dirInfo: dirInfo)

        isAiScanning = false

        if result.success, let items = result.items {
            let localIds = Set(scanItems.map(\.id))
            let newItems = items.filter { !localIds.contains($0.id) }
            scanItems.append(contentsOf: newItems)
            scanItems.sort { $0.size > $1.size }
            aiStatusMessage = "AI 扫描完成，发现 \(newItems.count) 项"
        } else {
            errorMessage = "AI 扫描失败: \(result.error ?? "未知错误")\n建议使用本地扫描。"
        }
    }

    // MARK: - Enhanced Scan

    func startEnhancedScan() async {
        isEnhancedScanning = true
        await scanLocal()
        if aiConfig?.hasKey == true, let apiKey = aiConfig?.apiKey, !apiKey.isEmpty {
            await startAiScan()
        }
        isEnhancedScanning = false
    }

    // MARK: - App Management

    func scanInstalledApps() async {
        isScanningApps = true
        let apps = await Task.detached(priority: .userInitiated) {
            var results: [AppInfo] = []
            let fm = FileManager.default
            var seenIds = Set<String>()

            let appDirs = [
                "/Applications",
                "/Applications/Utilities",
                NSHomeDirectory() + "/Applications",
            ]

            for appDir in appDirs {
                self.scanAppDir(appDir, fm: fm, results: &results, seen: &seenIds)
                guard let contents = try? fm.contentsOfDirectory(atPath: appDir) else { continue }
                for name in contents {
                    let subPath = (appDir as NSString).appendingPathComponent(name)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue, !name.hasSuffix(".app") && !name.hasPrefix(".") {
                        self.scanAppDir(subPath, fm: fm, results: &results, seen: &seenIds)
                    }
                }
            }

            self.scanCLIAndAgents(fm: fm, results: &results, seen: &seenIds)
            self.scanDynamicCLITools(fm: fm, results: &results, seen: &seenIds)

            let home = NSHomeDirectory()
            for i in results.indices where results[i].appType == .other && results[i].appPath.hasSuffix(".app") {
                let plistPath = (results[i].appPath as NSString).appendingPathComponent("Contents/Info.plist")
                guard let plistData = fm.contents(atPath: plistPath),
                      let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
                      let bundleId = plist["CFBundleIdentifier"] as? String else { continue }

                var cacheSize: Int64 = 0
                var dataSize: Int64 = 0
                let cp = [
                    "\(home)/Library/Caches/\(bundleId)",
                    "\(home)/Library/HTTPStorages/\(bundleId)",
                    "\(home)/Library/WebKit/\(bundleId)",
                ]
                for p in cp { let (s, _) = Self.calculateDirectorySizeStatic(at: p); cacheSize += s }
                let dp = [
                    "\(home)/Library/Application Support/\(bundleId)",
                    "\(home)/Library/Preferences/\(bundleId).plist",
                    "\(home)/Library/Saved Application State/\(bundleId).savedState",
                    "\(home)/Library/Containers/\(bundleId)",
                    "\(home)/Library/Logs/\(bundleId)",
                    "\(home)/Library/Cookies/\(bundleId).binarycookies",
                    "\(home)/Library/Group Containers/\(bundleId)",
                ]
                for p in dp { let (s, _) = Self.calculateDirectorySizeStatic(at: p); dataSize += s }

                let appSize = results[i].appSize
                results[i] = AppInfo(
                    id: results[i].id, name: results[i].name, displayName: results[i].displayName,
                    desc: results[i].desc, bundleId: bundleId,
                    appPath: results[i].appPath, iconPath: results[i].iconPath, version: results[i].version,
                    appSize: appSize, cacheSize: cacheSize, dataSize: dataSize,
                    totalSize: appSize + cacheSize + dataSize,
                    appType: results[i].appType, subCategory: results[i].subCategory,
                    risk: results[i].risk, riskDesc: results[i].riskDesc,
                    canUninstall: results[i].canUninstall,
                    canClean: results[i].canClean || cacheSize > 0,
                    canReset: results[i].canReset || dataSize > 0
                )
            }

            let otherAppPaths = Set(results.filter { $0.appType == .other && $0.appPath.hasSuffix(".app") }.map(\.appPath))
            results.removeAll { $0.appType == .app && otherAppPaths.contains($0.appPath) }

            results.sort { $0.name.lowercased() < $1.name.lowercased() }
            return results
        }.value

        installedApps = apps
        isScanningApps = false
    }

    nonisolated private func scanAppDir(_ dir: String, fm: FileManager, results: inout [AppInfo], seen: inout Set<String>) {
        guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { return }

        for name in contents where name.hasSuffix(".app") {
            let appPath = (dir as NSString).appendingPathComponent(name)
            let plistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")

            guard let plistData = fm.contents(atPath: plistPath),
                  let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else { continue }

            let bundleId = plist["CFBundleIdentifier"] as? String ?? ""
            guard !bundleId.isEmpty, !seen.contains(bundleId) else { continue }
            seen.insert(bundleId)

            let appName = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? name.replacingOccurrences(of: ".app", with: "")
            let version = plist["CFBundleShortVersionString"] as? String

            var iconPath: String? = nil
            if let iconFile = plist["CFBundleIconFile"] as? String {
                let candidate = (appPath as NSString).appendingPathComponent("Contents/Resources/\(iconFile)")
                if fm.fileExists(atPath: candidate) { iconPath = candidate }
            } else if let iconDicts = plist["CFBundleIconFiles"] as? [String], let first = iconDicts.first {
                let candidate = (appPath as NSString).appendingPathComponent("Contents/Resources/\(first)")
                if fm.fileExists(atPath: candidate) { iconPath = candidate }
            }
            if iconPath == nil {
                let icns = (appPath as NSString).appendingPathComponent("Contents/Resources/AppIcon.icns")
                if fm.fileExists(atPath: icns) { iconPath = icns }
            }

            let (appSize, _) = Self.calculateDirectorySizeStatic(at: appPath)
            let home = NSHomeDirectory()
            var cacheSize: Int64 = 0
            var dataSize: Int64 = 0

            let cachePaths = [
                "\(home)/Library/Caches/\(bundleId)",
                "\(home)/Library/HTTPStorages/\(bundleId)",
                "\(home)/Library/WebKit/\(bundleId)",
            ]
            for p in cachePaths { let (s, _) = Self.calculateDirectorySizeStatic(at: p); cacheSize += s }

            let dataPaths = [
                "\(home)/Library/Application Support/\(bundleId)",
                "\(home)/Library/Preferences/\(bundleId).plist",
                "\(home)/Library/Saved Application State/\(bundleId).savedState",
                "\(home)/Library/Containers/\(bundleId)",
                "\(home)/Library/Logs/\(bundleId)",
                "\(home)/Library/Cookies/\(bundleId).binarycookies",
                "\(home)/Library/Group Containers/\(bundleId)",
            ]
            for p in dataPaths { let (s, _) = Self.calculateDirectorySizeStatic(at: p); dataSize += s }

            results.append(AppInfo(
                id: bundleId,
                name: appName,
                displayName: appName,
                desc: "\(appName) 应用程序",
                bundleId: bundleId,
                appPath: appPath,
                iconPath: iconPath,
                version: version,
                appSize: appSize,
                cacheSize: cacheSize,
                dataSize: dataSize,
                totalSize: appSize + cacheSize + dataSize,
                appType: .app,
                subCategory: "应用",
                risk: "safe",
                riskDesc: "已安装的应用程序",
                canUninstall: true,
                canClean: cacheSize > 0,
                canReset: cacheSize > 0 || dataSize > 0
            ))
        }
    }

    nonisolated private func scanCLIAndAgents(fm: FileManager, results: inout [AppInfo], seen: inout Set<String>) {
        let home = NSHomeDirectory()

        struct CLITool {
            let name: String
            let displayName: String
            let desc: String
            let id: String
            let paths: [String]
            let appType: AppInfo.AppType
            let subCategory: String
            let risk: String
            let riskDesc: String
            let canUninstall: Bool
            let canClean: Bool
            let canReset: Bool
        }

        let cliTools: [CLITool] = [
            CLITool(name: "Homebrew", displayName: "Homebrew 包管理器", desc: "macOS/Linux 包管理工具，通过终端安装软件", id: "cli.homebrew", paths: ["/opt/homebrew", "/usr/local/Cellar"], appType: .other, subCategory: "CLI", risk: "caution", riskDesc: "卸载后所有通过brew安装的工具将不可用", canUninstall: true, canClean: true, canReset: false),
            CLITool(name: "Node.js / npm", displayName: "Node.js 运行环境", desc: "JavaScript 运行时和包管理器", id: "cli.nodejs", paths: ["\(home)/.nvm", "\(home)/.npm", "\(home)/.pnpm-store", "\(home)/.yarn"], appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "卸载后Node.js项目将无法运行", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "Python (pyenv)", displayName: "Python 版本管理", desc: "Python 多版本管理工具和pip缓存", id: "cli.pyenv", paths: ["\(home)/.pyenv", "\(home)/.cache/pip"], appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "卸载后Python项目将无法运行", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "Rust (rustup)", displayName: "Rust 工具链", desc: "Rust 编程语言和Cargo包管理器", id: "cli.rustup", paths: ["\(home)/.rustup", "\(home)/.cargo"], appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "卸载后Rust项目将无法编译", canUninstall: true, canClean: true, canReset: false),
            CLITool(name: "Go", displayName: "Go 语言环境", desc: "Go 编程语言和构建缓存", id: "cli.go", paths: ["\(home)/go", "\(home)/.cache/go-build"], appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "卸载后Go项目将无法编译", canUninstall: true, canClean: true, canReset: false),
            CLITool(name: "Docker", displayName: "Docker 容器", desc: "容器化平台，包含镜像和容器数据", id: "cli.docker", paths: ["\(home)/Library/Containers/com.docker.docker", "\(home)/.docker"], appType: .other, subCategory: "CLI", risk: "caution", riskDesc: "卸载后所有Docker容器和镜像将丢失", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "Trae", displayName: "Trae AI 编程助手", desc: "字节跳动AI编程IDE", id: "agent.trae", paths: ["/Applications/Trae.app", "\(home)/Library/Application Support/TraeCN"], appType: .other, subCategory: "AI Agent", risk: "safe", riskDesc: "可安全卸载，重新安装后需重新配置", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "CodeBuddy", displayName: "CodeBuddy 编程助手", desc: "AI编程助手", id: "agent.codebuddy", paths: ["/Applications/CodeBuddy.app", "\(home)/Library/Application Support/CodeBuddyCN"], appType: .other, subCategory: "AI Agent", risk: "safe", riskDesc: "可安全卸载", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "Claude Code", displayName: "Claude Code", desc: "Anthropic AI编程助手", id: "agent.claude", paths: ["/Applications/Claude.app", "\(home)/Library/Application Support/Claude-3p", "\(home)/.claude"], appType: .other, subCategory: "AI Agent", risk: "safe", riskDesc: "可安全卸载", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "Cursor", displayName: "Cursor AI 编辑器", desc: "AI代码编辑器", id: "agent.cursor", paths: ["/Applications/Cursor.app", "\(home)/Library/Application Support/Cursor"], appType: .other, subCategory: "AI Agent", risk: "safe", riskDesc: "可安全卸载", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "Windsurf", displayName: "Windsurf 编辑器", desc: "AI代码编辑器", id: "agent.windsurf", paths: ["/Applications/Windsurf.app", "\(home)/Library/Application Support/Windsurf"], appType: .other, subCategory: "AI Agent", risk: "safe", riskDesc: "可安全卸载", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "豆包", displayName: "豆包 AI 助手", desc: "字节跳动AI助手", id: "agent.doubao", paths: ["/Applications/豆包.app"], appType: .other, subCategory: "AI Agent", risk: "safe", riskDesc: "可安全卸载", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "通义千问", displayName: "通义千问 AI", desc: "阿里云AI助手", id: "agent.qwen", paths: ["/Applications/通义千问.app"], appType: .other, subCategory: "AI Agent", risk: "safe", riskDesc: "可安全卸载", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "Xcode Developer", displayName: "Xcode 开发者数据", desc: "Xcode编译缓存、派生数据和归档", id: "dev.xcode-dev", paths: ["\(home)/Library/Developer"], appType: .dependency, subCategory: "开发", risk: "caution", riskDesc: "删除后Xcode需重新编译项目", canUninstall: false, canClean: true, canReset: true),
            CLITool(name: "Android SDK", displayName: "Android SDK", desc: "Android开发工具包", id: "dev.android", paths: ["\(home)/Library/Android"], appType: .dependency, subCategory: "开发", risk: "caution", riskDesc: "卸载后Android项目将无法编译", canUninstall: true, canClean: true, canReset: false),
            CLITool(name: "Unity", displayName: "Unity 引擎", desc: "游戏开发引擎缓存", id: "dev.unity", paths: ["\(home)/Library/Unity"], appType: .dependency, subCategory: "开发", risk: "safe", riskDesc: "Unity编辑器缓存，可安全清理", canUninstall: false, canClean: true, canReset: true),
            CLITool(name: "Gradle", displayName: "Gradle 构建工具", desc: "Java/Android项目构建工具和缓存", id: "cli.gradle", paths: ["\(home)/.gradle"], appType: .dependency, subCategory: "包管理", risk: "safe", riskDesc: "构建缓存可安全清理，下次构建会重新下载", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "Maven", displayName: "Maven 构建工具", desc: "Java项目构建工具和本地仓库", id: "cli.maven", paths: ["\(home)/.m2"], appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "本地仓库删除后需重新下载所有依赖", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "CocoaPods", displayName: "CocoaPods 依赖管理", desc: "iOS/macOS依赖管理工具和仓库缓存", id: "cli.cocoapods", paths: ["\(home)/.cocoapods"], appType: .dependency, subCategory: "包管理", risk: "safe", riskDesc: "仓库缓存可安全清理", canUninstall: true, canClean: true, canReset: true),
        ]

        for tool in cliTools {
            guard !seen.contains(tool.id) else { continue }

            var totalSize: Int64 = 0
            var realPath = ""

            for path in tool.paths {
                let expanded = NSString(string: path).expandingTildeInPath
                let (s, _) = Self.calculateDirectorySizeStatic(at: expanded)
                if s > 0 {
                    totalSize += s
                    if realPath.isEmpty { realPath = expanded }
                }
            }

            guard totalSize > 0 else { continue }
            seen.insert(tool.id)

            results.append(AppInfo(
                id: tool.id,
                name: tool.name,
                displayName: tool.displayName,
                desc: tool.desc,
                bundleId: tool.id,
                appPath: realPath,
                iconPath: nil,
                version: nil,
                appSize: totalSize,
                cacheSize: 0,
                dataSize: 0,
                totalSize: totalSize,
                appType: tool.appType,
                subCategory: tool.subCategory,
                risk: tool.risk,
                riskDesc: tool.riskDesc,
                canUninstall: tool.canUninstall,
                canClean: tool.canClean,
                canReset: tool.canReset
            ))
        }

        self.scanDynamicAgents(fm: fm, results: &results, seen: &seen)
    }

    nonisolated private func scanDynamicAgents(fm: FileManager, results: inout [AppInfo], seen: inout Set<String>) {
        let home = NSHomeDirectory()

        let agentKeywords: [(String, String, String)] = [
            ("trae", "Trae AI 编程助手", "字节跳动AI编程IDE"),
            ("codebuddy", "CodeBuddy 编程助手", "AI编程助手"),
            ("claude", "Claude Code", "Anthropic AI编程助手"),
            ("cursor", "Cursor AI 编辑器", "AI代码编辑器"),
            ("windsurf", "Windsurf 编辑器", "AI代码编辑器"),
            ("codex", "Codex", "OpenAI AI编程助手"),
            ("codearts", "CodeArts Agent", "华为AI编程助手"),
            ("yi-code", "yi-code", "零一万物AI编程助手"),
            ("yi.agent", "yi-agent", "零一万物AI Agent"),
            ("hermes", "Hermes", "AI编程助手"),
            ("cherrystudio", "Cherry Studio", "AI大模型客户端"),
            ("lmstudio", "LM Studio", "本地大模型运行环境"),
            ("openclaw", "OpenClaw", "AI编程助手"),
            ("qclaw", "QClaw", "AI编程助手"),
            ("doubao", "豆包 AI 助手", "字节跳动AI助手"),
            ("qwen", "通义千问 AI", "阿里云AI助手"),
            ("augment", "Augment Code", "AI编程助手"),
            ("copilot", "GitHub Copilot", "GitHub AI编程助手"),
            ("aider", "Aider", "AI终端编程助手"),
            ("continue", "Continue", "AI代码补全扩展"),
            ("cody", "Cody", "Sourcegraph AI编程助手"),
            ("tabby", "Tabby", "AI代码补全"),
            ("warp", "Warp", "AI终端"),
            ("chatgpt", "ChatGPT", "OpenAI AI助手"),
            ("gemini", "Gemini", "Google AI助手"),
            ("deepseek", "DeepSeek", "深度求索AI助手"),
            ("kimi", "Kimi", "月之暗面AI助手"),
            ("zhipu", "智谱AI", "智谱清言AI助手"),
            ("spark", "讯飞星火", "科大讯飞AI助手"),
            ("tongyi", "通义灵码", "阿里云AI编程助手"),
            ("cline", "Cline", "AI编程助手"),
            ("minimax", "MiniMax Agent", "MiniMax AI编程助手"),
            ("stepfun", "阶跃星辰", "阶跃星辰AI助手"),
            ("whitzard", "Whitzard", "AI编程助手"),
            ("ai_completion", "AI Completion", "AI代码补全工具"),
            ("agent-browser", "Agent Browser", "AI浏览器自动化"),
            ("evomorph", "EvoMorph", "易衍编程系统"),
            ("skillhub", "SkillHub", "AI技能平台"),
            ("cloudbase-mcp", "CloudBase MCP", "腾讯云MCP工具"),
        ]

        let systemDotdirs: Set<String> = [
            ".DS_Store", ".Trash", ".bash_history", ".bash_profile", ".bash_sessions",
            ".CFUserTextEncoding", ".cups", ".gitconfig", ".gitignore", ".profile",
            ".ssh", ".viminfo", ".zsh_history", ".zshrc", ".npmrc",
            ".bash_profile.swk", ".bash_profile.swl", ".bash_profile.swm",
            ".bash_profile.swn", ".bash_profile.swo", ".bash_profile.swp",
            ".swiftpm", ".mono", ".gem", ".config", ".cups", ".EventSDK",
            ".aimaccleaner_ai.json", ".aimaccleaner_ignore.json", ".aimaccleaner_last_response.txt",
            ".maccleaner_ai.json", ".pcr-stats.json", ".claude.json",
        ]

        let devToolDotdirs: [String: (String, String, String)] = [
            ".nvm": ("NVM (Node版本管理)", "包管理", "Node.js多版本管理工具，删除后Node.js版本切换将不可用"),
            ".npm": ("npm 全局缓存", "包管理", "npm包缓存，删除后下次安装包时会重新下载"),
            ".pnpm-store": ("pnpm 存储", "包管理", "pnpm包管理器的存储目录，删除后需重新安装依赖"),
            ".yarn": ("Yarn", "包管理", "Yarn包管理器缓存，删除后需重新下载"),
            ".pyenv": ("pyenv (Python版本管理)", "包管理", "Python多版本管理工具，删除后Python版本切换将不可用"),
            ".rustup": ("rustup (Rust工具链)", "包管理", "Rust编程语言工具链，删除后Rust项目将无法编译"),
            ".cargo": ("Cargo (Rust包管理)", "包管理", "Rust包管理器和编译缓存，删除后Rust项目需重新编译"),
            ".gradle": ("Gradle 构建工具", "包管理", "Java/Android项目构建缓存，删除后下次构建会重新下载"),
            ".m2": ("Maven 构建工具", "包管理", "Java项目本地仓库，删除后需重新下载所有依赖"),
            ".cocoapods": ("CocoaPods 依赖管理", "包管理", "iOS/macOS依赖仓库缓存，删除后下次pod install会重新下载"),
            ".conda": ("Conda (Python环境)", "包管理", "Python环境和包管理器，删除后所有Conda环境将丢失"),
            ".julia": ("Julia", "包管理", "Julia编程语言和包，删除后Julia项目将无法运行"),
            ".local": ("用户本地安装", "CLI", "用户本地安装的工具和库，删除后相关工具将不可用"),
            ".cache": ("用户缓存目录", "CLI", "各种工具的缓存数据，删除后工具需重新生成缓存"),
            ".docker": ("Docker 配置", "CLI", "Docker容器平台配置，删除后Docker需重新配置"),
            ".android": ("Android SDK 配置", "开发", "Android开发配置和AVD，删除后Android模拟器数据将丢失"),
            ".idea": ("IntelliJ IDEA 配置", "开发", "JetBrains IDE配置和缓存，删除后IDE需重新配置"),
            ".ohos": ("OpenHarmony SDK", "开发", "鸿蒙/OpenHarmony开发工具配置，删除后鸿蒙项目将无法编译"),
            ".ohpm": ("ohpm 包管理", "包管理", "鸿蒙包管理器缓存，删除后需重新下载依赖"),
            ".hvigor": ("Hvigor 构建工具", "包管理", "鸿蒙项目构建工具缓存，删除后需重新构建"),
            ".harmony": ("HarmonyOS SDK", "开发", "HarmonyOS开发工具配置，删除后鸿蒙项目将无法编译"),
            ".vscode": ("VS Code 配置", "开发", "VS Code编辑器扩展和数据，删除后需重新安装扩展"),
            ".pm2": ("PM2 进程管理", "CLI", "Node.js进程管理器，删除后PM2管理的进程配置将丢失"),
            ".Huawei": ("华为开发工具", "开发", "华为开发工具配置，删除后相关开发工具需重新配置"),
            ".sogouinput": ("搜狗输入法", "应用", "搜狗输入法用户词库和配置，删除后需重新配置输入法"),
            ".downloader": ("下载器", "应用", "下载工具缓存，删除后下载记录将丢失"),
            ".chromium-browser-snapshots": ("Chromium 快照", "开发", "Chromium浏览器测试快照，删除后需重新下载"),
        ]

        guard let homeDirs = try? fm.contentsOfDirectory(atPath: home) else { return }

        for dirName in homeDirs {
            guard dirName.hasPrefix(".") else { continue }
            guard !systemDotdirs.contains(dirName) else { continue }

            let dirPath = (home as NSString).appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let (size, _) = Self.calculateDirectorySizeStatic(at: dirPath)
            guard size > 1048576 else { continue }

            let dirLower = dirName.lowercased().replacingOccurrences(of: ".", with: "")

            if let (name, subCat, riskDesc) = devToolDotdirs[dirName] {
                let id = "dotdir.\(dirName)"
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                let risk = subCat == "包管理" ? "caution" : "safe"
                results.append(AppInfo(
                    id: id, name: name, displayName: name, desc: riskDesc,
                    bundleId: id, appPath: dirPath, iconPath: nil, version: nil,
                    appSize: size, cacheSize: 0, dataSize: 0, totalSize: size,
                    appType: subCat == "应用" ? .other : (subCat == "开发" ? .dependency : .dependency),
                    subCategory: subCat, risk: risk, riskDesc: riskDesc,
                    canUninstall: true, canClean: true, canReset: true
                ))
                continue
            }

            var matchedAgent = false
            var agentName = dirName.replacingOccurrences(of: ".", with: "")
            var agentDesc = "AI编程助手"
            var agentId = "agent.dotdir.\(dirLower)"

            for (keyword, name, desc) in agentKeywords {
                if dirLower.contains(keyword) {
                    agentName = name
                    agentDesc = desc
                    agentId = "agent.\(keyword.replacingOccurrences(of: " ", with: "-"))"
                    matchedAgent = true
                    break
                }
            }

            if matchedAgent {
                guard !seen.contains(agentId) else { continue }
                seen.insert(agentId)

                var appPath = dirPath
                var iconPath: String? = nil
                var appSize: Int64 = 0
                var cacheSize: Int64 = 0
                var dataSize: Int64 = size
                var bundleId = agentId

                let knownAppPaths = Set(results.filter { $0.appType == .other && $0.appPath.hasSuffix(".app") }.map { $0.appPath.lowercased() })
                let possibleAppNames = ["\(agentName).app", "\(dirName).app"]
                let appDirs = ["/Applications", "\(home)/Applications"]
                outerLoop: for appDir in appDirs {
                    for appName in possibleAppNames {
                        let candidate = (appDir as NSString).appendingPathComponent(appName)
                        if fm.fileExists(atPath: candidate) && !knownAppPaths.contains(candidate.lowercased()) {
                            appPath = candidate
                            appSize = Self.calculateDirectorySizeStatic(at: candidate).0
                            let plistPath = (candidate as NSString).appendingPathComponent("Contents/Info.plist")
                            if let plistData = fm.contents(atPath: plistPath),
                               let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
                                bundleId = plist["CFBundleIdentifier"] as? String ?? agentId
                                if let iconFile = plist["CFBundleIconFile"] as? String {
                                    let ic = (candidate as NSString).appendingPathComponent("Contents/Resources/\(iconFile)")
                                    if fm.fileExists(atPath: ic) { iconPath = ic }
                                }
                                if iconPath == nil {
                                    let icns = (candidate as NSString).appendingPathComponent("Contents/Resources/AppIcon.icns")
                                    if fm.fileExists(atPath: icns) { iconPath = icns }
                                }
                            }
                            let cp = ["\(home)/Library/Caches/\(bundleId)", "\(home)/Library/HTTPStorages/\(bundleId)", "\(home)/Library/WebKit/\(bundleId)"]
                            for p in cp { cacheSize += Self.calculateDirectorySizeStatic(at: p).0 }
                            break outerLoop
                        }
                    }
                }

                let totalSize = appSize + cacheSize + dataSize
                results.append(AppInfo(
                    id: agentId, name: agentName, displayName: agentName, desc: agentDesc,
                    bundleId: bundleId, appPath: appPath, iconPath: iconPath, version: nil,
                    appSize: appSize, cacheSize: cacheSize, dataSize: dataSize, totalSize: totalSize,
                    appType: .other, subCategory: "AI Agent", risk: "safe",
                    riskDesc: "可安全卸载，重新安装后需重新配置",
                    canUninstall: true, canClean: cacheSize > 0, canReset: dataSize > 0
                ))
                continue
            }

            let id = "dotdir.unknown.\(dirLower)"
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            results.append(AppInfo(
                id: id, name: dirName, displayName: dirName, desc: "用户目录 \(dirName)",
                bundleId: id, appPath: dirPath, iconPath: nil, version: nil,
                appSize: size, cacheSize: 0, dataSize: 0, totalSize: size,
                appType: .other, subCategory: "其它", risk: "caution",
                riskDesc: "未知目录，删除前请确认其用途",
                canUninstall: true, canClean: false, canReset: false
            ))
        }

        let allApps = results.filter { $0.appType == .app }
        for app in allApps {
            let nameLower = app.displayName.lowercased()
            let bundleLower = app.bundleId.lowercased()
            var isAgent = false
            var agentDesc = "AI编程助手"

            for (keyword, _, desc) in agentKeywords {
                if nameLower.contains(keyword) || bundleLower.contains(keyword) {
                    isAgent = true
                    agentDesc = desc
                    break
                }
            }

            if isAgent && !seen.contains("agent.fromapp.\(app.bundleId)") {
                seen.insert("agent.fromapp.\(app.bundleId)")
                results.append(AppInfo(
                    id: "agent.fromapp.\(app.bundleId)",
                    name: app.displayName, displayName: app.displayName, desc: agentDesc,
                    bundleId: app.bundleId, appPath: app.appPath, iconPath: app.iconPath, version: app.version,
                    appSize: app.appSize, cacheSize: app.cacheSize, dataSize: app.dataSize, totalSize: app.totalSize,
                    appType: .other, subCategory: "AI Agent", risk: "safe",
                    riskDesc: "可安全卸载，重新安装后需重新配置",
                    canUninstall: true, canClean: app.cacheSize > 0, canReset: app.dataSize > 0
                ))
            }
        }
    }

    nonisolated private func scanDynamicCLITools(fm: FileManager, results: inout [AppInfo], seen: inout Set<String>) {
        let home = NSHomeDirectory()

        let brewDirs = ["/opt/homebrew/Cellar", "/usr/local/Cellar"]
        for brewDir in brewDirs {
            guard let packages = try? fm.contentsOfDirectory(atPath: brewDir) else { continue }
            for pkg in packages {
                let id = "brew.\(pkg)"
                guard !seen.contains(id) else { continue }
                let pkgPath = (brewDir as NSString).appendingPathComponent(pkg)
                let (size, _) = Self.calculateDirectorySizeStatic(at: pkgPath)
                guard size > 0 else { continue }
                seen.insert(id)
                results.append(AppInfo(
                    id: id, name: pkg, displayName: pkg, desc: "通过 Homebrew 安装的 \(pkg)",
                    bundleId: id,
                    appPath: pkgPath, iconPath: nil, version: nil,
                    appSize: size, cacheSize: 0, dataSize: 0, totalSize: size,
                    appType: .other, subCategory: "CLI", risk: "caution", riskDesc: "卸载后通过brew安装的\(pkg)将不可用",
                    canUninstall: true, canClean: false, canReset: false
                ))
            }
        }

        let npmGlobalPaths = [
            "\(home)/.nvm/versions/node",
            "/opt/homebrew/lib/node_modules",
            "/usr/local/lib/node_modules",
        ]
        for npmBase in npmGlobalPaths {
            let expanded = NSString(string: npmBase).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else { continue }

            if npmBase.contains("/node") {
                guard let nodeVersions = try? fm.contentsOfDirectory(atPath: expanded) else { continue }
                for nodeVer in nodeVersions {
                    let libPath = (expanded as NSString).appendingPathComponent(nodeVer + "/lib/node_modules")
                    self.scanNpmModules(at: libPath, fm: fm, results: &results, seen: &seen)
                }
            } else {
                self.scanNpmModules(at: expanded, fm: fm, results: &results, seen: &seen)
            }
        }

        let pipPaths = ["\(home)/Library/Python"]
        for pipBase in pipPaths {
            let expanded = NSString(string: pipBase).expandingTildeInPath
            guard let versions = try? fm.contentsOfDirectory(atPath: expanded) else { continue }
            for ver in versions {
                let sitePackages = (expanded as NSString).appendingPathComponent(ver + "/lib/python/site-packages")
                self.scanPipPackages(at: sitePackages, fm: fm, results: &results, seen: &seen)
            }
        }
    }

    nonisolated private func scanNpmModules(at path: String, fm: FileManager, results: inout [AppInfo], seen: inout Set<String>) {
        guard let modules = try? fm.contentsOfDirectory(atPath: path) else { return }
        for mod in modules {
            let id = "npm.\(mod)"
            guard !seen.contains(id) else { continue }
            let modPath = (path as NSString).appendingPathComponent(mod)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: modPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let (size, _) = Self.calculateDirectorySizeStatic(at: modPath)
            guard size > 0 else { continue }
            seen.insert(id)
            results.append(AppInfo(
                id: id, name: mod, displayName: mod, desc: "npm 全局安装的 \(mod) 包",
                bundleId: id,
                appPath: modPath, iconPath: nil, version: nil,
                appSize: size, cacheSize: 0, dataSize: 0, totalSize: size,
                appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "卸载后依赖此包的项目将无法运行",
                canUninstall: true, canClean: false, canReset: false
            ))
        }
    }

    nonisolated private func scanPipPackages(at path: String, fm: FileManager, results: inout [AppInfo], seen: inout Set<String>) {
        guard let packages = try? fm.contentsOfDirectory(atPath: path) else { return }
        for pkg in packages {
            let id = "pip.\(pkg)"
            guard !seen.contains(id) else { continue }
            let pkgPath = (path as NSString).appendingPathComponent(pkg)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: pkgPath, isDirectory: &isDir), isDir.boolValue {
                let (size, _) = Self.calculateDirectorySizeStatic(at: pkgPath)
                guard size > 0 else { continue }
                seen.insert(id)
                results.append(AppInfo(
                    id: id, name: pkg, displayName: pkg, desc: "pip 安装的 \(pkg) 包",
                    bundleId: id,
                    appPath: pkgPath, iconPath: nil, version: nil,
                    appSize: size, cacheSize: 0, dataSize: 0, totalSize: size,
                    appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "卸载后依赖此包的Python项目将无法运行",
                    canUninstall: true, canClean: false, canReset: false
                ))
            }
        }
    }

    @Published var aiAnalysisResult: String = ""
    @Published var isAnalyzingImpact: Bool = false
    @Published var aiAnalysisMap: [String: String] = [:]

    var alertThreshold: Double = 10.0
    var trashInsteadOfDelete: Bool = true
    var preventAutoEmptyTrash: Bool = true
    private var monitorTimer: Timer?
    private var lastAlertTime: Date = .distantPast

    func startMonitoring() {
        stopMonitoring()
        refreshDiskInfo()
        checkAndAlert()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDiskInfo()
                self?.checkAndAlert()
            }
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func checkAndAlert() {
        guard let disk = diskInfo else { return }
        let freePct = 100.0 - disk.usedPct
        guard freePct <= alertThreshold else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAlertTime) > 3600 else { return }
        lastAlertTime = now

        let content = UNMutableNotificationContent()
        content.title = "⚠️ 存储空间不足"
        content.body = "磁盘剩余 \(String(format: "%.1f", disk.freeGb)) GB（\(String(format: "%.0f", freePct))%），建议立即清理"
        content.sound = .defaultCritical

        let request = UNNotificationRequest(
            identifier: "aimaccleaner.storage.alert",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error.localizedDescription)")
            }
        }
    }

    @Published var latestVersion: String = ""
    @Published var isCheckingUpdate: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var updateDownloadURL: String = ""

    let currentVersion = "1.3.0"

    func checkForUpdates() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }

        guard let url = URL(string: "https://api.github.com/repos/AI-Scarlett/AIMacCleaner/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            latestVersion = remoteVersion

            if compareVersions(remoteVersion, currentVersion) > 0 {
                updateAvailable = true
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String, name.hasSuffix("-arm64.dmg"),
                           let downloadURL = asset["browser_download_url"] as? String {
                            updateDownloadURL = downloadURL
                            break
                        }
                    }
                }
            } else {
                updateAvailable = false
            }
        } catch {
            return
        }
    }

    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return 1 }
            if p1 < p2 { return -1 }
        }
        return 0
    }

    func openDownloadPage() {
        if !updateDownloadURL.isEmpty {
            if let url = URL(string: updateDownloadURL) { NSWorkspace.shared.open(url) }
        } else {
            if let url = URL(string: "https://github.com/AI-Scarlett/AIMacCleaner/releases") { NSWorkspace.shared.open(url) }
        }
    }

    func analyzeImpactWithAI(apps: [AppInfo]) async {
        guard let config = aiConfig, config.hasKey == true, let apiKey = config.apiKey, !apiKey.isEmpty else {
            for app in apps { aiAnalysisMap[app.id] = "⚠️ 请先配置大模型 API Key" }
            return
        }

        isAnalyzingImpact = true
        for app in apps { aiAnalysisMap[app.id] = "🔄 分析中..." }

        let itemsDesc = apps.map { app in
            """
            - 名称: \(app.displayName)
              类型: \(app.appType.label) / \(app.subCategory)
              大小: \(formatSize(app.totalSize))
              路径: \(app.appPath)
              当前风险: \(app.risk) - \(app.riskDesc)
            """
        }.joined(separator: "\n")

        let prompt = """
        你是一个 macOS 系统管理专家。用户想要删除/清理以下项目，请分析每个项目删除后的影响。

        对于每个项目，请用一句话（不超过30字）说明删除后的主要影响。

        请严格按照以下 JSON 格式返回结果，不要包含任何其他文字：
        [
          {
            "name": "项目名称",
            "impact": "一句话影响说明"
          }
        ]
        只返回JSON数组，不要包含markdown代码块标记。
        以下是要分析的项目：
        \(itemsDesc)
        """

        let apiBase = (config.apiBase ?? "https://api.deepseek.com").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(apiBase)/v1/chat/completions") else {
            for app in apps { aiAnalysisMap[app.id] = "❌ 无效的 API 地址" }
            isAnalyzingImpact = false
            return
        }

        let body: [String: Any] = [
            "model": config.model ?? "deepseek-chat",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 4096,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                for app in apps { aiAnalysisMap[app.id] = "❌ 无效的 HTTP 响应" }
                isAnalyzingImpact = false
                return
            }

            if http.statusCode != 200 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                for app in apps { aiAnalysisMap[app.id] = "❌ API 错误 (\(http.statusCode))" }
                isAnalyzingImpact = false
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else {
                for app in apps { aiAnalysisMap[app.id] = "❌ 大模型返回格式错误" }
                isAnalyzingImpact = false
                return
            }

            var content = message["content"] as? String ?? ""
            if content.isEmpty {
                content = message["reasoning_content"] as? String ?? ""
            }

            if content.hasPrefix("```") {
                if let start = content.range(of: "["), let end = content.range(of: "]", options: .backwards) {
                    content = String(content[start.lowerBound...end.upperBound])
                }
            }

            if let jsonData = content.data(using: .utf8),
               let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] {
                for item in items {
                    let name = item["name"] ?? ""
                    let impact = item["impact"] ?? ""
                    for app in apps {
                        if app.displayName == name || name.contains(app.displayName) || app.displayName.contains(name) {
                            aiAnalysisMap[app.id] = "🤖 \(impact)"
                        }
                    }
                }
                for app in apps {
                    if aiAnalysisMap[app.id]?.hasPrefix("🤖") != true {
                        aiAnalysisMap[app.id] = "🤖 分析完成（详见原说明）"
                    }
                }
            } else {
                let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                for (i, app) in apps.enumerated() {
                    if i < lines.count {
                        aiAnalysisMap[app.id] = "🤖 \(lines[i].trimmingCharacters(in: .whitespacesAndNewlines))"
                    }
                }
            }
        } catch {
            for app in apps { aiAnalysisMap[app.id] = "❌ 网络错误" }
        }

        isAnalyzingImpact = false
    }

    private func moveToTrash(atPath path: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        if trashInsteadOfDelete {
            let url = URL(fileURLWithPath: path)
            var resultURL: NSURL?
            try fm.trashItem(at: url, resultingItemURL: &resultURL)
        } else {
            try fm.removeItem(atPath: path)
        }
    }

    func basicUninstall(app: AppInfo) async -> Bool {
        do {
            if FileManager.default.fileExists(atPath: app.appPath) {
                try moveToTrash(atPath: app.appPath)
            }
            return true
        } catch {
            errorMessage = "卸载失败: \(error.localizedDescription)"
            return false
        }
    }

    func fullUninstall(app: AppInfo) async -> Bool {
        do {
            if FileManager.default.fileExists(atPath: app.appPath) {
                try moveToTrash(atPath: app.appPath)
            }
            for path in app.relatedPaths {
                if FileManager.default.fileExists(atPath: path) {
                    try moveToTrash(atPath: path)
                }
            }
            return true
        } catch {
            errorMessage = "卸载失败: \(error.localizedDescription)"
            return false
        }
    }

    func resetApp(app: AppInfo) async -> Bool {
        do {
            for path in app.cachePaths + app.dataPaths {
                if FileManager.default.fileExists(atPath: path) {
                    try moveToTrash(atPath: path)
                }
            }
            return true
        } catch {
            errorMessage = "重置失败: \(error.localizedDescription)"
            return false
        }
    }

    private func collectDirInfo() -> String {
        var lines: [String] = []
        let scanDirs: [(String, String, Int)] = [
            ("~/Library/Caches", "User Caches", 100),
            ("~/Library/Application Support", "App Support", 80),
            ("~/Library/Logs", "User Logs", 50),
            ("~/Library/Containers", "App Containers", 50),
            ("~/Library/Developer", "Developer", 50),
            ("~/.cache", "Dot Cache", 50),
            ("~/.npm", "npm", 20),
            ("~/Library/Application Support/Google/Chrome/Default", "Chrome Default Profile", 30),
            ("~/Library/Application Support/LarkShell", "Lark/飞书", 20),
            ("~/Library/Application Support/Claude-3p", "Claude Code", 20),
        ]

        let fm = FileManager.default

        for (dirPath, label, maxEntries) in scanDirs {
            let expanded = NSString(string: dirPath).expandingTildeInPath
            lines.append("\n## \(label) (\(dirPath))")

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            guard let contents = try? fm.contentsOfDirectory(atPath: expanded) else {
                lines.append("  [无法访问]")
                continue
            }

            var entries: [(String, Int64)] = []
            for name in contents.prefix(maxEntries) {
                let fullPath = (expanded as NSString).appendingPathComponent(name)
                let (size, _) = Self.calculateDirectorySizeStatic(at: fullPath)
                if size > 0 {
                    entries.append((name, size))
                }
            }
            entries.sort { $0.1 > $1.1 }

            for (name, size) in entries {
                lines.append("  \(formatSize(size))  \(name)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func callLLM(config: AIConfig, dirInfo: String) async -> (success: Bool, items: [ScanItem]?, error: String?) {
        let apiBase = (config.apiBase ?? "https://api.deepseek.com").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(apiBase)/v1/chat/completions"

        guard let url = URL(string: urlString) else {
            return (success: false, items: nil, error: "无效的 API 地址")
        }

        let systemPrompt = """
        你是一个 macOS 存储空间清理专家。根据用户提供的目录列表和大小信息，分析哪些目录可以安全清理。

        请严格按照以下 JSON 格式返回结果，不要包含任何其他文字：
        [
          {
            "name": "清理项名称",
            "category": "分类（浏览器/办公/AI Agent/开发/系统/社交/其他）",
            "app": "所属应用",
            "risk": "safe 或 caution 或 dangerous",
            "risk_desc": "删除后的风险和后果说明",
            "path": "目录路径（用 ~ 表示用户目录）",
            "reason": "为什么可以清理"
          }
        ]

        风险等级：safe=纯缓存可安全删除; caution=删除后可能需重新登录/配置; dangerous=可能丢失数据。
        只返回确定可以清理的项目，按大小从大到小排序。
        只返回JSON数组，不要包含markdown代码块标记。
        """

        let body: [String: Any] = [
            "model": config.model ?? "deepseek-chat",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "以下是我的 Mac 目录结构和大小说明，请分析哪些可以清理：\n\(dirInfo)"],
            ],
            "temperature": 0.1,
            "max_tokens": 16384,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey ?? "")", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return (success: false, items: nil, error: "无效的 HTTP 响应")
            }

            if http.statusCode != 200 {
                if let body = String(data: data, encoding: .utf8) {
                    return (success: false, items: nil, error: "HTTP \(http.statusCode): \(body.prefix(200))")
                }
                return (success: false, items: nil, error: "HTTP \(http.statusCode)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else {
                return (success: false, items: nil, error: "大模型返回格式错误")
            }

            var content = message["content"] as? String ?? ""
            let reasoningContent = message["reasoning_content"] as? String ?? ""

            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let retryBody: [String: Any] = [
                        "model": config.model ?? "deepseek-chat",
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": "以下是我的 Mac 目录结构和大小说明，请分析哪些可以清理：\n\(dirInfo)"],
                            ["role": "assistant", "content": reasoningContent],
                            ["role": "user", "content": "请根据以上分析，直接输出JSON数组结果，不要包含任何其他文字。"]
                        ],
                        "temperature": 0.1,
                        "max_tokens": 8192
                    ]

                    var retryRequest = URLRequest(url: url)
                    retryRequest.httpMethod = "POST"
                    retryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    retryRequest.setValue("Bearer \(config.apiKey ?? "")", forHTTPHeaderField: "Authorization")
                    retryRequest.timeoutInterval = 120
                    retryRequest.httpBody = try? JSONSerialization.data(withJSONObject: retryBody)

                    do {
                        let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
                        if let retryHttp = retryResponse as? HTTPURLResponse, retryHttp.statusCode == 200,
                           let retryJson = try? JSONSerialization.jsonObject(with: retryData) as? [String: Any],
                           let retryChoices = retryJson["choices"] as? [[String: Any]],
                           let retryMessage = retryChoices.first?["message"] as? [String: Any] {
                            let retryContent = retryMessage["content"] as? String ?? ""
                            if !retryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                content = retryContent
                            }
                        }
                    } catch {}
                }

                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (success: false, items: nil, error: "大模型返回内容为空，推理模型思考过程消耗了所有token。请在AI设置中将模型改为 deepseek-chat 后重试。")
                }
            }

            let rawContent = content
            let logPath = NSHomeDirectory() + "/.aimaccleaner_last_response.txt"
            try? rawContent.write(toFile: logPath, atomically: true, encoding: .utf8)

            let jsonStr = extractJSON(from: rawContent)

            if let jsonData = jsonStr.data(using: .utf8),
               let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                return buildScanItems(from: items)
            }

            if let fixed = tryFixJSON(jsonStr),
               let jsonData = fixed.data(using: .utf8),
               let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                return buildScanItems(from: items)
            }

            if let fixed = tryFixTruncatedJSON(jsonStr),
               let jsonData = fixed.data(using: .utf8),
               let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                return buildScanItems(from: items)
            }

            if let fixed = tryFixJSON(jsonStr),
               let jsonData = fixed.data(using: .utf8),
               let wrapper = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                for key in ["items", "data", "results", "list"] {
                    if let items = wrapper[key] as? [[String: Any]] {
                        return buildScanItems(from: items)
                    }
                }
            }

            let preview = String(rawContent.prefix(300))
            return (success: false, items: nil, error: "无法解析大模型返回的 JSON\n原始返回已保存到: \(logPath)\n预览: \(preview)")

        } catch {
            return (success: false, items: nil, error: error.localizedDescription)
        }
    }

    private func extractJSON(from content: String) -> String {
        var str = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = str.range(of: "```json") {
            str = String(str[range.upperBound...])
        } else if let range = str.range(of: "```") {
            str = String(str[range.upperBound...])
        }

        if let range = str.range(of: "```", options: .backwards) {
            str = String(str[..<range.lowerBound])
        }

        str = str.trimmingCharacters(in: .whitespacesAndNewlines)

        if let startIdx = str.range(of: "[") {
            let remaining = String(str[startIdx.lowerBound...])
            if let endIdx = remaining.lastIndex(of: "]") {
                return String(remaining[...endIdx])
            }
        }

        return str
    }

    private func tryFixJSON(_ str: String) -> String? {
        var fixed = str

        fixed = fixed.replacingOccurrences(of: "\u{201C}", with: "\"")
        fixed = fixed.replacingOccurrences(of: "\u{201D}", with: "\"")
        fixed = fixed.replacingOccurrences(of: "\u{2018}", with: "'")
        fixed = fixed.replacingOccurrences(of: "\u{2019}", with: "'")

        fixed = fixed.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
        fixed = fixed.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)

        fixed = fixed.replacingOccurrences(of: "//[^\n]*", with: "", options: .regularExpression)

        if fixed.contains("\"") || fixed.contains("[") {
            return fixed
        }

        return nil
    }

    private func tryFixTruncatedJSON(_ str: String) -> String? {
        var fixed = str.trimmingCharacters(in: .whitespacesAndNewlines)

        guard fixed.hasPrefix("[") else { return nil }

        var openBraces = 0
        var openBrackets = 1
        var inString = false
        var escape = false

        for char in fixed {
            if escape { escape = false; continue }
            if char == "\\" { escape = true; continue }
            if char == "\"" { inString = !inString; continue }
            if inString { continue }
            if char == "{" { openBraces += 1 }
            if char == "}" { openBraces -= 1 }
            if char == "[" { openBrackets += 1 }
            if char == "]" { openBrackets -= 1 }
        }

        if inString {
            fixed += "\""
        }

        let lastCompleteObj = fixed.lastIndex(of: "}")
        if let lastIdx = lastCompleteObj {
            fixed = String(fixed[...lastIdx])
        }

        for _ in 0..<openBraces {
            fixed += "}"
        }
        fixed += "]"

        return fixed
    }

    private func buildScanItems(from items: [[String: Any]]) -> (success: Bool, items: [ScanItem]?, error: String?) {
        var results: [ScanItem] = []
        let fm = FileManager.default

        for (i, item) in items.enumerated() {
            let path = (item["path"] as? String ?? "").replacingOccurrences(of: "~", with: NSHomeDirectory())
            let expanded = NSString(string: path).expandingTildeInPath
            var size: Int64 = 0
            var fileCount = 0

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                (size, fileCount) = Self.calculateDirectorySizeStatic(at: expanded)
            }

            results.append(ScanItem(
                id: "ai_\(i)",
                name: item["name"] as? String ?? "Unknown",
                category: item["category"] as? String ?? "其他",
                app: item["app"] as? String ?? "Unknown",
                risk: item["risk"] as? String ?? "caution",
                riskDesc: item["risk_desc"] as? String ?? "",
                path: item["path"] as? String ?? "",
                realPath: expanded,
                size: size,
                fileCount: fileCount,
                ignored: false,
                reason: item["reason"] as? String,
                source: "ai"
            ))
        }

        results.sort { $0.size > $1.size }
        return (success: true, items: results, error: nil)
    }

    // MARK: - Utility

    func formatSize(_ bytes: Int64) -> String {
        if bytes >= 1073741824 { return String(format: "%.1f GB", Double(bytes) / 1073741824.0) }
        if bytes >= 1048576 { return String(format: "%.1f MB", Double(bytes) / 1048576.0) }
        if bytes >= 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return "\(bytes) B"
    }
}
