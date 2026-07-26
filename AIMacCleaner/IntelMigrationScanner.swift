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

    weak var localizer: Localizer?
    var needsAdaptCount: Int { intelOnlyCount }

    var needsAdaptItems: [IntelAppInfo] {
        items.filter { $0.architecture.isIntel }
    }

    var universalItems: [IntelAppInfo] {
        items.filter { $0.architecture == .universal }
    }

    var totalIntelSize: Int64 {
        needsAdaptItems.reduce(0) { $0 + $1.size }
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
                    let progressScanned = scanned
                    let detectingLabel = await MainActor.run { self.localizer?.detectingApp ?? "Detecting" }
                    await MainActor.run { self.scanProgress = "\(detectingLabel) \(app.displayName) (\(progressScanned)/\(appsCopy.count))..." }
                }

                var arch: IntelAppInfo.BinaryArchitecture
                let appType: IntelAppInfo.IntelAppType
                let size = app.totalSize

                if app.appPath.hasSuffix(".app") {
                    arch = self.detectAppArchitecture(appPath: app.appPath)
                    appType = .app
                } else if app.appPath.contains("Cellar") || app.appPath.contains("homebrew") || app.subCategory.contains("Package Manager") {
                    arch = self.detectBinaryArchitecture(binaryPath: app.appPath)
                    appType = .homebrew
                } else if app.subCategory.contains("CLI") || app.subCategory.contains("AI Agent") || app.appType == .other {
                    arch = self.detectBinaryArchitecture(binaryPath: app.appPath)
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

            let finalResults = results
            let finalIntelCount = iCount
            let finalUniversalCount = uCount
            let finalArmCount = aCount
            let finalScanned = scanned

            await MainActor.run {
                self.items = finalResults
                self.intelOnlyCount = finalIntelCount
                self.universalCount = finalUniversalCount
                self.armNativeCount = finalArmCount
                self.totalScanned = finalScanned
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

        guard let handle = FileHandle(forReadingAtPath: binaryPath) else { return .unknown }
        defer { try? handle.close() }

        let magicData = handle.readData(ofLength: 4)
        guard magicData.count == 4 else { return .unknown }

        let magic = magicData.withUnsafeBytes { $0.load(as: UInt32.self) }

        if magic == 0xcafebabe || magic == CFSwapInt32(0xcafebabe) {
            handle.seek(toFileOffset: 0)
            let headerData = handle.readData(ofLength: 8)
            guard headerData.count == 8 else { return .unknown }
            let ncmds = headerData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                ptr.load(fromByteOffset: 4, as: UInt32.self)
            }
            let swapped = CFSwapInt32(ncmds)
            let fatCount = magic == 0xcafebabe ? ncmds : swapped

            var hasX86 = false
            var hasArm = false
            for i in 0..<min(fatCount, 20) {
                handle.seek(toFileOffset: 8 + UInt64(i) * 20)
                let archData = handle.readData(ofLength: 4)
                guard archData.count == 4 else { break }
                let cpuType = archData.withUnsafeBytes { $0.load(as: UInt32.self) }
                let swappedCpu = CFSwapInt32(cpuType)
                let ct = magic == 0xcafebabe ? cpuType : swappedCpu
                if ct == 0x01000007 { hasX86 = true }
                if ct == 0x0100000c { hasArm = true }
            }

            if hasX86 && hasArm { return .universal }
            if hasX86 { return .x86_64 }
            if hasArm { return .arm64 }
            return .unknown
        }

        if magic == 0xfeedfacf {
            handle.seek(toFileOffset: 4)
            let cpuData = handle.readData(ofLength: 4)
            guard cpuData.count == 4 else { return .unknown }
            let cpuType = cpuData.withUnsafeBytes { $0.load(as: UInt32.self) }
            if cpuType == 0x01000007 { return .x86_64 }
            if cpuType == 0x0100000c { return .arm64 }
            return .unknown
        }

        if magic == CFSwapInt32(0xfeedfacf) {
            handle.seek(toFileOffset: 4)
            let cpuData = handle.readData(ofLength: 4)
            guard cpuData.count == 4 else { return .unknown }
            let cpuType = cpuData.withUnsafeBytes { $0.load(as: UInt32.self) }
            let swappedCpu = CFSwapInt32(cpuType)
            if swappedCpu == 0x01000007 { return .x86_64 }
            if swappedCpu == 0x0100000c { return .arm64 }
            return .unknown
        }

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
            return (nil, "search_link_gen_failed")
        }
        return (url.absoluteString, nil)
    }

    func openReplacementPage(for item: IntelAppInfo) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }

        items[idx].replaceState = .searchingReplacement
        items[idx].replaceProgress = 0.1

        let displayName = items[idx].displayName
        let appType = items[idx].appType
        let bundleId = items[idx].bundleId
        var downloadURL = items[idx].downloadURL
        let itemId = items[idx].id

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            if downloadURL == nil {
                let searchResult = Self.performSearchStatic(name: displayName, bundleId: bundleId, appType: appType)
                downloadURL = searchResult.0
            }

            await MainActor.run {
                guard let idx2 = self.items.firstIndex(where: { $0.id == itemId }) else { return }
                guard let urlString = downloadURL,
                      let url = URL(string: urlString),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "https" else {
                    self.items[idx2].replaceProgress = 1.0
                    self.items[idx2].replaceState = .failed
                    return
                }
                _ = NSWorkspace.shared.open(url)
                self.items[idx2].replaceProgress = 1.0
                // Opening a candidate download page is not proof that a native
                // replacement was installed. Keep the old item and wait for the
                // user to install and verify it before using Uninstall.
                self.items[idx2].replaceState = .awaitingVerification
            }
        }
    }

    func uninstallOnly(item: IntelAppInfo) -> Bool {
        do {
            switch item.appType {
            case .app, .framework:
                var resultURL: NSURL?
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &resultURL)
            case .cli:
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
            case .homebrew:
                break
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
