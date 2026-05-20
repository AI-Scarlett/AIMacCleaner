import SwiftUI
import Foundation

@MainActor
class IntelMigrationScanner: ObservableObject {
    @Published var items: [IntelAppInfo] = []
    @Published var isScanning = false
    @Published var scanProgress: String = ""
    @Published var intelOnlyCount: Int = 0
    @Published var universalCount: Int = 0
    @Published var armNativeCount: Int = 0
    @Published var totalScanned: Int = 0

    private let fileManager = FileManager.default

    var needsMigrationCount: Int { intelOnlyCount }

    var needsMigrationItems: [IntelAppInfo] {
        items.filter { $0.architecture.isIntel }
    }

    var universalItems: [IntelAppInfo] {
        items.filter { $0.architecture == .universal }
    }

    var totalIntelSize: Int64 {
        needsMigrationItems.reduce(0) { $0 + $1.size }
    }

    var totalIntelSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalIntelSize, countStyle: .file)
    }

    var totalUniversalSize: Int64 {
        universalItems.reduce(0) { $0 + $1.size }
    }

    var totalUniversalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalUniversalSize, countStyle: .file)
    }

    func scanFromInstalledApps(_ apps: [AppInfo]) {
        guard !isScanning else { return }
        isScanning = true
        items = []
        intelOnlyCount = 0
        universalCount = 0
        armNativeCount = 0
        totalScanned = 0

        let appsCopy = apps

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            var results: [IntelAppInfo] = []
            var iCount = 0
            var uCount = 0
            var aCount = 0
            var scanned = 0

            for app in appsCopy {
                scanned += 1
                if scanned % 20 == 0 {
                    await MainActor.run { self.scanProgress = "检测 \(app.displayName) (\(scanned)/\(appsCopy.count))..." }
                }

                var arch: IntelAppInfo.BinaryArchitecture
                let appType: IntelAppInfo.IntelAppType
                let size = app.totalSize

                if app.appPath.hasSuffix(".app") {
                    arch = self.detectAppArchitecture(appPath: app.appPath)
                    appType = .app
                } else if app.appPath.contains("Cellar") || app.appPath.contains("homebrew") || app.subCategory.contains("包管理") {
                    if app.appPath.contains("/usr/local/Cellar") || app.appPath.contains("/usr/local/Homebrew") {
                        arch = .x86_64
                    } else if app.appPath.contains("/opt/homebrew/Cellar") || app.appPath.contains("/opt/homebrew") {
                        arch = .arm64
                    } else {
                        arch = self.detectBinaryArchitecture(binaryPath: app.appPath)
                    }
                    appType = .homebrew
                } else if app.subCategory.contains("CLI") || app.subCategory.contains("AI Agent") || app.appType == .other {
                    if app.appPath.hasPrefix("/usr/local/") {
                        arch = self.detectBinaryArchitecture(binaryPath: app.appPath)
                        if arch == .unknown { arch = .x86_64 }
                    } else if app.appPath.hasPrefix("/opt/homebrew/") {
                        arch = self.detectBinaryArchitecture(binaryPath: app.appPath)
                        if arch == .unknown { arch = .arm64 }
                    } else {
                        arch = self.detectBinaryArchitecture(binaryPath: app.appPath)
                    }
                    appType = .cli
                } else {
                    arch = self.detectBinaryArchitecture(binaryPath: app.appPath)
                    appType = app.appPath.hasSuffix(".app") ? .app : .cli
                }

                if arch.isIntel { iCount += 1 }
                else if arch == .universal { uCount += 1 }
                else if arch == .arm64 { aCount += 1 }

                let brewARMName: String? = (appType == .homebrew && arch.isIntel) ? app.name : nil

                results.append(IntelAppInfo(
                    id: app.id,
                    name: app.name,
                    displayName: app.displayName,
                    path: app.appPath,
                    architecture: arch,
                    appType: appType,
                    size: size,
                    version: app.version,
                    bundleId: app.bundleId,
                    homebrewARMName: brewARMName
                ))
            }

            await MainActor.run {
                self.items = results
                self.intelOnlyCount = iCount
                self.universalCount = uCount
                self.armNativeCount = aCount
                self.totalScanned = scanned
                self.isScanning = false
                self.scanProgress = ""
            }
        }
    }

    nonisolated func detectAppArchitecture(appPath: String) -> IntelAppInfo.BinaryArchitecture {
        let fm = FileManager.default
        let contentsDir = appPath + "/Contents/MacOS/"
        guard let contents = try? fm.contentsOfDirectory(atPath: contentsDir) else {
            return .unknown
        }

        for executable in contents {
            let execPath = contentsDir + executable
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: execPath, isDirectory: &isDir), !isDir.boolValue {
                let arch = detectBinaryArchitecture(binaryPath: execPath)
                if arch != .unknown { return arch }
            }
        }

        return .unknown
    }

    nonisolated func detectBinaryArchitecture(binaryPath: String) -> IntelAppInfo.BinaryArchitecture {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: binaryPath, isDirectory: &isDir), !isDir.boolValue else {
            return .unknown
        }

        let task = Process()
        task.launchPath = "/usr/bin/lipo"
        task.arguments = ["-info", binaryPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if output.contains("x86_64") && output.contains("arm64") {
                return .universal
            }
            if output.contains("x86_64") {
                return .x86_64
            }
            if output.contains("arm64") {
                return .arm64
            }
        } catch {}

        let task2 = Process()
        task2.launchPath = "/usr/bin/file"
        task2.arguments = [binaryPath]

        let pipe2 = Pipe()
        task2.standardOutput = pipe2

        do {
            try task2.run()
            task2.waitUntilExit()
            let data = pipe2.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if output.contains("universal") || (output.contains("x86_64") && output.contains("arm64")) {
                return .universal
            }
            if output.contains("x86_64") {
                return .x86_64
            }
            if output.contains("arm64") {
                return .arm64
            }
        } catch {}

        return .unknown
    }

    func searchDownloadLink(for item: IntelAppInfo) async {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isSearching = true
        items[idx].searchError = nil

        let name = item.displayName
        let bundleId = item.bundleId
        let appType = item.appType

        let result = await Task.detached(priority: .userInitiated) {
            return Self.performSearchStatic(name: name, bundleId: bundleId, appType: appType)
        }.value

        if let idx2 = items.firstIndex(where: { $0.id == item.id }) {
            items[idx2].isSearching = false
            if let url = result.0 {
                items[idx2].downloadURL = url
            } else if let err = result.1 {
                items[idx2].searchError = err
            }
        }
    }

    nonisolated static func performSearchStatic(name: String, bundleId: String?, appType: IntelAppInfo.IntelAppType) -> (String?, String?) {
        switch appType {
        case .homebrew:
            return ("brew install \(name)", nil)
        case .cli:
            if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
                let task = Process()
                task.launchPath = "/opt/homebrew/bin/brew"
                task.arguments = ["search", name]
                let pipe = Pipe()
                task.standardOutput = pipe
                if let _ = try? task.run() {
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    if output.contains(name) {
                        return ("brew install \(name)", nil)
                    }
                }
            }
            let ghResult = searchGitHubRepos(query: name)
            if let url = ghResult {
                return (url, nil)
            }
            return searchDuckDuckGo(name: name, appType: appType)
        case .app:
            let ghResult = searchGitHubRepos(query: name)
            if let url = ghResult {
                return (url, nil)
            }
            if let bid = bundleId {
                let itunesResult = searchITunesLookup(bundleId: bid)
                if let url = itunesResult {
                    return (url, nil)
                }
            }
            return searchDuckDuckGo(name: name, appType: appType)
        case .framework:
            let ghResult = searchGitHubRepos(query: name)
            if let url = ghResult {
                return (url, nil)
            }
            return searchDuckDuckGo(name: name, appType: appType)
        }
    }

    nonisolated static func searchGitHubRepos(query: String) -> String? {
        let searchTerms = query
            .replacingOccurrences(of: " ", with: "+")
            .lowercased()
        guard let url = URL(string: "https://api.github.com/search/repositories?q=\(searchTerms)+mac+arm64&sort=stars&per_page=3"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return nil
        }
        for item in items {
            if let htmlUrl = item["html_url"] as? String {
                return htmlUrl
            }
        }
        return nil
    }

    nonisolated static func searchITunesLookup(bundleId: String) -> String? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let trackViewUrl = first["trackViewUrl"] as? String else {
            return nil
        }
        return trackViewUrl
    }

    nonisolated static func searchDuckDuckGo(name: String, appType: IntelAppInfo.IntelAppType) -> (String?, String?) {
        let typeHint: String
        switch appType {
        case .app: typeHint = "mac app download"
        case .cli: typeHint = "mac cli install arm64"
        case .homebrew: typeHint = "homebrew install"
        case .framework: typeHint = "mac framework download arm64"
        }
        let query = "\(name) \(typeHint) apple silicon"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://duckduckgo.com/?q=\(encodedQuery)") else {
            return (nil, "搜索链接生成失败")
        }
        return (url.absoluteString, nil)
    }

    func uninstallAndReplace(item: IntelAppInfo) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }

        items[idx].replaceState = .uninstalling
        items[idx].replaceProgress = 0.1

        let appPath = items[idx].path
        let appName = items[idx].name
        let displayName = items[idx].displayName
        let appType = items[idx].appType
        let bundleId = items[idx].bundleId
        var downloadURL = items[idx].downloadURL
        let itemId = items[idx].id

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            var success = false

            if downloadURL == nil {
                let searchResult = Self.performSearchStatic(name: displayName, bundleId: bundleId, appType: appType)
                downloadURL = searchResult.0
            }

            switch appType {
            case .homebrew:
                let uninstall = Process()
                uninstall.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
                uninstall.arguments = ["uninstall", appName]
                try? uninstall.run()
                uninstall.waitUntilExit()

                await MainActor.run {
                    if let idx2 = self.items.firstIndex(where: { $0.id == itemId }) {
                        self.items[idx2].replaceProgress = 0.5
                        self.items[idx2].replaceState = .installing
                    }
                }

                let install = Process()
                install.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
                install.arguments = ["install", appName]
                try? install.run()
                install.waitUntilExit()
                success = true

            case .app:
                await MainActor.run {
                    if let idx2 = self.items.firstIndex(where: { $0.id == itemId }) {
                        self.items[idx2].replaceProgress = 0.3
                    }
                }

                if let urlStr = downloadURL, let url = URL(string: urlStr) {
                    await MainActor.run { NSWorkspace.shared.open(url) }
                }

                await MainActor.run {
                    if let idx2 = self.items.firstIndex(where: { $0.id == itemId }) {
                        self.items[idx2].replaceProgress = 0.5
                    }
                }

                var resultURL: NSURL?
                try? self.fileManager.trashItem(at: URL(fileURLWithPath: appPath), resultingItemURL: &resultURL)

                await MainActor.run {
                    if let idx2 = self.items.firstIndex(where: { $0.id == itemId }) {
                        self.items[idx2].replaceProgress = 0.8
                        self.items[idx2].replaceState = .installing
                    }
                }

                success = downloadURL != nil

            case .cli:
                try? self.fileManager.removeItem(atPath: appPath)

                await MainActor.run {
                    if let idx2 = self.items.firstIndex(where: { $0.id == itemId }) {
                        self.items[idx2].replaceProgress = 0.5
                        self.items[idx2].replaceState = .installing
                    }
                }

                let brewPath = "/opt/homebrew/bin/brew"
                if self.fileManager.fileExists(atPath: brewPath) {
                    let install = Process()
                    install.executableURL = URL(fileURLWithPath: brewPath)
                    install.arguments = ["install", appName]
                    try? install.run()
                    install.waitUntilExit()
                    success = true
                } else if let urlStr = downloadURL, let url = URL(string: urlStr) {
                    await MainActor.run { NSWorkspace.shared.open(url) }
                    success = true
                } else {
                    success = false
                }

            case .framework:
                await MainActor.run {
                    if let idx2 = self.items.firstIndex(where: { $0.id == itemId }) {
                        self.items[idx2].replaceProgress = 0.3
                    }
                }

                if let urlStr = downloadURL, let url = URL(string: urlStr) {
                    await MainActor.run { NSWorkspace.shared.open(url) }
                }

                await MainActor.run {
                    if let idx2 = self.items.firstIndex(where: { $0.id == itemId }) {
                        self.items[idx2].replaceProgress = 0.5
                    }
                }

                var resultURL: NSURL?
                try? self.fileManager.trashItem(at: URL(fileURLWithPath: appPath), resultingItemURL: &resultURL)

                await MainActor.run {
                    if let idx2 = self.items.firstIndex(where: { $0.id == itemId }) {
                        self.items[idx2].replaceProgress = 0.8
                        self.items[idx2].replaceState = .installing
                    }
                }

                success = downloadURL != nil
            }

            await MainActor.run {
                if let idx2 = self.items.firstIndex(where: { $0.id == itemId }) {
                    self.items[idx2].replaceProgress = 1.0
                    self.items[idx2].replaceState = success ? .completed : .failed
                    if success {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.items.removeAll { $0.id == itemId }
                            self.intelOnlyCount = max(0, self.intelOnlyCount - 1)
                        }
                    }
                }
            }
        }
    }

    func uninstallOnly(item: IntelAppInfo) -> Bool {
        do {
            switch item.appType {
            case .app, .framework:
                var resultURL: NSURL?
                try fileManager.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &resultURL)
            case .cli:
                try fileManager.removeItem(atPath: item.path)
            case .homebrew:
                let task = Process()
                task.launchPath = "/usr/local/bin/brew"
                task.arguments = ["uninstall", item.name]
                try task.run()
                task.waitUntilExit()
            }
            items.removeAll { $0.id == item.id }
            if item.architecture.isIntel { intelOnlyCount = max(0, intelOnlyCount - 1) }
            else if item.architecture == .universal { universalCount = max(0, universalCount - 1) }
            return true
        } catch {
            return false
        }
    }
}
