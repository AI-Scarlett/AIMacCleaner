import SwiftUI
import Foundation

@MainActor
class IntelMigrationScanner: ObservableObject {
    @Published var intelApps: [IntelAppInfo] = []
    @Published var isScanning = false
    @Published var scanProgress: String = ""
    @Published var intelCount: Int = 0
    @Published var universalCount: Int = 0
    @Published var armCount: Int = 0
    @Published var rosettaProcesses: [RosettaProcessInfo] = []

    struct RosettaProcessInfo: Identifiable {
        let id = UUID().uuidString
        let pid: Int32
        let name: String
        let path: String
    }

    private let fileManager = FileManager.default

    func scanAll() {
        guard !isScanning else { return }
        isScanning = true
        intelApps = []
        intelCount = 0
        universalCount = 0
        armCount = 0
        rosettaProcesses = []

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            var results: [IntelAppInfo] = []
            var iCount = 0
            var uCount = 0
            var aCount = 0

            await MainActor.run { self.scanProgress = "扫描应用程序..." }

            let appResults = self.scanApplications()
            results.append(contentsOf: appResults)

            await MainActor.run { self.scanProgress = "扫描命令行工具..." }

            let cliResults = self.scanCLITools()
            results.append(contentsOf: cliResults)

            await MainActor.run { self.scanProgress = "扫描 Homebrew 包..." }

            let brewResults = self.scanHomebrewPackages()
            results.append(contentsOf: brewResults)

            await MainActor.run { self.scanProgress = "检测 Rosetta 进程..." }

            let rosettaProcs = self.detectRosettaProcesses()

            for r in results {
                if r.architecture.isIntel { iCount += 1 }
                else if r.architecture == .universal { uCount += 1 }
                else if r.architecture == .arm64 { aCount += 1 }
            }

            await MainActor.run {
                self.intelApps = results
                self.intelCount = iCount
                self.universalCount = uCount
                self.armCount = aCount
                self.rosettaProcesses = rosettaProcs
                self.isScanning = false
                self.scanProgress = ""
            }
        }
    }

    nonisolated func scanApplications() -> [IntelAppInfo] {
        var results: [IntelAppInfo] = []
        let searchPaths = ["/Applications", NSHomeDirectory() + "/Applications"]

        for searchPath in searchPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: searchPath) else { continue }
            for item in contents {
                guard item.hasSuffix(".app") else { continue }
                let appPath = searchPath + "/" + item
                let arch = detectAppArchitecture(appPath: appPath)
                guard arch != .arm64 else { continue }

                let name = item.replacingOccurrences(of: ".app", with: "")
                let size = calculateSize(path: appPath)
                let version = getAppVersion(appPath: appPath)
                let bundleId = getBundleId(appPath: appPath)

                results.append(IntelAppInfo(
                    id: appPath,
                    name: name,
                    displayName: name,
                    path: appPath,
                    architecture: arch,
                    appType: .app,
                    size: size,
                    version: version,
                    bundleId: bundleId
                ))
            }
        }
        return results
    }

    nonisolated func scanCLITools() -> [IntelAppInfo] {
        var results: [IntelAppInfo] = []
        let cliPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/.cargo/bin",
            NSHomeDirectory() + "/go/bin",
        ]

        for dirPath in cliPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dirPath) else { continue }
            for item in contents {
                let fullPath = dirPath + "/" + item
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }

                let arch = detectBinaryArchitecture(binaryPath: fullPath)
                guard arch.isIntel || arch == .universal else { continue }

                let size = calculateSize(path: fullPath)

                results.append(IntelAppInfo(
                    id: fullPath,
                    name: item,
                    displayName: item,
                    path: fullPath,
                    architecture: arch,
                    appType: .cli,
                    size: size,
                    version: nil,
                    bundleId: nil
                ))
            }
        }
        return results
    }

    nonisolated func scanHomebrewPackages() -> [IntelAppInfo] {
        var results: [IntelAppInfo] = []
        let intelPrefix = "/usr/local/Cellar"
        let armPrefix = "/opt/homebrew/Cellar"

        if FileManager.default.fileExists(atPath: intelPrefix) {
            guard let packages = try? FileManager.default.contentsOfDirectory(atPath: intelPrefix) else { return results }
            for pkg in packages {
                let pkgPath = intelPrefix + "/" + pkg
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: pkgPath, isDirectory: &isDir), isDir.boolValue else { continue }

                let size = calculateSize(path: pkgPath)
                let hasARM = FileManager.default.fileExists(atPath: armPrefix + "/" + pkg)

                results.append(IntelAppInfo(
                    id: "brew_intel_\(pkg)",
                    name: pkg,
                    displayName: pkg,
                    path: pkgPath,
                    architecture: .x86_64,
                    appType: .homebrew,
                    size: size,
                    version: nil,
                    bundleId: nil,
                    homebrewARMName: hasARM ? nil : pkg
                ))
            }
        }

        return results
    }

    nonisolated func detectRosettaProcesses() -> [RosettaProcessInfo] {
        var results: [RosettaProcessInfo] = []
        let task = Process()
        task.launchPath = "/usr/bin/ps"
        task.arguments = ["-eo", "pid,comm,args"]

        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            for line in output.components(separatedBy: "\n").dropFirst() {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 2, let pid = Int32(parts[0]) else { continue }
                let comm = String(parts[1])

                if comm.hasSuffix(".app") || comm.contains("Rosetta") {
                    let path = parts.count >= 3 ? parts.suffix(from: 2).joined(separator: " ") : comm
                    results.append(RosettaProcessInfo(pid: pid, name: comm, path: path))
                }
            }
        } catch {}

        return results
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

    nonisolated private func calculateSize(path: String) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        if let enumerator = fm.enumerator(atPath: path) {
            for case let item as String in enumerator {
                let fullPath = path + "/" + item
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? Int64 {
                    total += size
                }
            }
        }
        return total
    }

    nonisolated private func getAppVersion(appPath: String) -> String? {
        let plistPath = appPath + "/Contents/Info.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)) else { return nil }
        var format: PropertyListSerialization.PropertyListFormat = .xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else { return nil }
        return plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String
    }

    nonisolated private func getBundleId(appPath: String) -> String? {
        let plistPath = appPath + "/Contents/Info.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)) else { return nil }
        var format: PropertyListSerialization.PropertyListFormat = .xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }

    func searchDownloadLink(for app: IntelAppInfo) async -> IntelAppInfo {
        guard let idx = intelApps.firstIndex(where: { $0.id == app.id }) else { return app }
        intelApps[idx].isSearching = true
        intelApps[idx].searchError = nil

        let result = await performSearch(name: app.displayName, bundleId: app.bundleId, appType: app.appType)

        if let idx2 = intelApps.firstIndex(where: { $0.id == app.id }) {
            intelApps[idx2].isSearching = false
            if let url = result.0 {
                intelApps[idx2].downloadURL = url
            } else if let err = result.1 {
                intelApps[idx2].searchError = err
            }
            return intelApps[idx2]
        }
        return app
    }

    nonisolated func performSearch(name: String, bundleId: String?, appType: IntelAppInfo.IntelAppType) async -> (String?, String?) {
        switch appType {
        case .homebrew:
            return ("brew reinstall \(name)", nil)
        case .cli:
            let brewCheck = checkBrewARM(name: name)
            if let brewName = brewCheck {
                return ("brew install \(brewName)", nil)
            }
            return await searchOnline(name: name)
        case .app:
            if let bid = bundleId {
                let macAppStoreURL = "macappstore://itunes.apple.com/app/id\(bid)"
                return (macAppStoreURL, nil)
            }
            return await searchOnline(name: name)
        case .framework:
            return await searchOnline(name: name)
        }
    }

    nonisolated func checkBrewARM(name: String) -> String? {
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/brew"
        task.arguments = ["search", name]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if output.contains(name) {
                return name
            }
        } catch {}

        return nil
    }

    nonisolated func searchOnline(name: String) async -> (String?, String?) {
        let query = "\(name) mac download arm64 apple silicon"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)") else {
            return (nil, "搜索链接生成失败")
        }
        return (url.absoluteString, nil)
    }

    func uninstallIntel(app: IntelAppInfo) -> Bool {
        do {
            switch app.appType {
            case .app:
                var resultURL: NSURL?
                try fileManager.trashItem(at: URL(fileURLWithPath: app.path), resultingItemURL: &resultURL)
            case .cli:
                try fileManager.removeItem(atPath: app.path)
            case .homebrew:
                let task = Process()
                task.launchPath = "/usr/local/bin/brew"
                task.arguments = ["uninstall", app.name]
                try task.run()
                task.waitUntilExit()
            case .framework:
                var resultURL: NSURL?
                try fileManager.trashItem(at: URL(fileURLWithPath: app.path), resultingItemURL: &resultURL)
            }
            intelApps.removeAll { $0.id == app.id }
            if app.architecture.isIntel { intelCount = max(0, intelCount - 1) }
            return true
        } catch {
            return false
        }
    }

    func reinstallWithARM(app: IntelAppInfo) -> Bool {
        switch app.appType {
        case .homebrew:
            let task = Process()
            task.launchPath = "/opt/homebrew/bin/brew"
            task.arguments = ["install", app.name]
            do {
                try task.run()
                return true
            } catch {
                return false
            }
        case .cli:
            if let brewName = app.homebrewARMName {
                let task = Process()
                task.launchPath = "/opt/homebrew/bin/brew"
                task.arguments = ["install", brewName]
                do {
                    try task.run()
                    return true
                } catch {
                    return false
                }
            }
            return false
        case .app:
            if let urlStr = app.downloadURL, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        case .framework:
            if let urlStr = app.downloadURL, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }

    var intelAppsOnly: [IntelAppInfo] {
        intelApps.filter { $0.architecture.isIntel }
    }

    var universalAppsOnly: [IntelAppInfo] {
        intelApps.filter { $0.architecture == .universal }
    }

    var totalIntelSize: Int64 {
        intelAppsOnly.reduce(0) { $0 + $1.size }
    }

    var totalIntelSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalIntelSize, countStyle: .file)
    }
}
