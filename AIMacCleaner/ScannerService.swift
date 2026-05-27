import Foundation
import Combine
@preconcurrency import UserNotifications
import AppKit
import IOKit
import IOKit.ps
import Security

private enum KeychainStore {
    private static let service = "com.aimaccleaner.app.ai"
    private static let account = "default-api-key"

    static func loadAPIKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static func saveAPIKey(_ key: String) {
        let data = Data(key.utf8)
        var query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static func deleteAPIKey() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

@MainActor
class ScannerService: ObservableObject {
    @Published var scanItems: [ScanItem] = []
    @Published var diskInfo: DiskInfo?
    @Published var hardwareInfo: HardwareInfo?
    @Published var isScanning = false
    @Published var isAiScanning = false
    @Published var isEnhancedScanning = false
    @Published var aiStatusMessage = ""
    @Published var errorMessage: String?
    @Published var aiConfig: AIConfig?
    @Published var installedApps: [AppInfo] = []
    @Published var isScanningApps = false

    private var ignoredIds: Set<String> = []
    private var ignoreFilePath: String { SandboxPaths.shared.ignoreListPath }
    private var aiConfigFilePath: String { SandboxPaths.shared.aiConfigPath }
    private var scanBookmarksPath: String { SandboxPaths.shared.scanBookmarksPath }
    private var authorizedScanRoots: Set<String> = []
    private var hasRestoredScanBookmarks = false

    init() {
        loadIgnores()
        loadAIConfigFromDisk()
        operationMonitor.guardFeature = guardFeature
        diskInfo = getDiskInfoNative()
        hardwareInfo = safeGetHardwareInfo()
    }

    // MARK: - Disk Info

    func getDiskInfoNative() -> DiskInfo? {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let values = try? url.resourceValues(forKeys: keys),
           let total = values.volumeTotalCapacity,
           let available = values.volumeAvailableCapacityForImportantUsage {
            let totalBytes = Int64(total)
            let freeBytes = Int64(available)
            let usedBytes = totalBytes - freeBytes
            let usedPct = totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100.0 : 0
            return DiskInfo(
                total: totalBytes, used: usedBytes, free: freeBytes,
                totalGb: Double(totalBytes) / 1_000_000_000.0,
                usedGb: Double(usedBytes) / 1_000_000_000.0,
                freeGb: Double(freeBytes) / 1_000_000_000.0,
                usedPct: usedPct
            )
        }
        return getDiskInfoFallback()
    }

    private func getDiskInfoFallback() -> DiskInfo? {
        for path in ["/System/Volumes/Data", SandboxPaths.realHomeDirectory, "/"] {
            let url = URL(fileURLWithPath: path)
            let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
            if let values = try? url.resourceValues(forKeys: keys),
               let total = values.volumeTotalCapacity,
               let available = values.volumeAvailableCapacityForImportantUsage {
                let totalBytes = Int64(total)
                let freeBytes = Int64(available)
                let usedBytes = totalBytes - freeBytes
                let usedPct = totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100.0 : 0
                return DiskInfo(
                    total: totalBytes, used: usedBytes, free: freeBytes,
                    totalGb: Double(totalBytes) / 1_000_000_000.0,
                    usedGb: Double(usedBytes) / 1_000_000_000.0,
                    freeGb: Double(freeBytes) / 1_000_000_000.0,
                    usedPct: usedPct
                )
            }
        }
        return nil
    }

    func refreshDiskInfo() {
        diskInfo = getDiskInfoNative()
    }

    func refreshHardwareInfo() {
        hardwareInfo = safeGetHardwareInfo()
    }

    private func safeGetHardwareInfo() -> HardwareInfo {
        var info = HardwareInfo(
            cpuUsage: 0, cpuCoreCount: 0, cpuTemperature: nil,
            memoryTotal: 0, memoryUsed: 0, memoryFree: 0, memoryPressure: 0, swapUsed: 0,
            batteryPercent: nil, batteryCharging: false, batteryTimeRemaining: nil,
            processCount: 0, threadCount: 0, uptimeSeconds: 0,
            networkInRate: 0, networkOutRate: 0
        )
        info.cpuCoreCount = getCPUCoreCount()
        info.cpuUsage = getCPUUsage()
        info.cpuTemperature = getCPUTemperature()
        getMemoryInfo(&info)
        getBatteryInfo(&info)
        getSystemStats(&info)
        safeGetNetworkInfo(&info)
        return info
    }

    private func getHardwareInfo() -> HardwareInfo {
        var info = HardwareInfo(
            cpuUsage: 0,
            cpuCoreCount: 0,
            cpuTemperature: nil,
            memoryTotal: 0,
            memoryUsed: 0,
            memoryFree: 0,
            memoryPressure: 0,
            swapUsed: 0,
            batteryPercent: nil,
            batteryCharging: false,
            batteryTimeRemaining: nil,
            processCount: 0,
            threadCount: 0,
            uptimeSeconds: 0,
            networkInRate: 0,
            networkOutRate: 0
        )

        info.cpuCoreCount = getCPUCoreCount()
        info.cpuUsage = getCPUUsage()
        info.cpuTemperature = getCPUTemperature()
        getMemoryInfo(&info)
        getBatteryInfo(&info)
        getSystemStats(&info)
        safeGetNetworkInfo(&info)

        return info
    }

    private func getCPUCoreCount() -> Int {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.ncpu", &count, &size, nil, 0)
        return Int(count)
    }

    private func getCPUUsage() -> Double {
        var numCPU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &cpuInfo, &numCPUInfo)

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else { return 0 }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCPUInfo) * 4) }

        var totalUser: Double = 0
        var totalSystem: Double = 0
        var totalIdle: Double = 0
        var totalNice: Double = 0

        for i in 0..<Int(numCPU) {
            let offset = i * Int(CPU_STATE_MAX)
            totalUser += Double(cpuInfo[offset + Int(CPU_STATE_USER)])
            totalSystem += Double(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += Double(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            totalNice += Double(cpuInfo[offset + Int(CPU_STATE_NICE)])
        }

        let total = totalUser + totalSystem + totalIdle + totalNice
        if total > 0 {
            return ((totalUser + totalSystem + totalNice) / total) * 100.0
        }
        return 0
    }

    private func getCPUTemperature() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        defer { IOObjectRelease(service) }
        guard service != 0 else { return nil }

        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return readTemperatureFromAppleARMIO()
        }

        for key in ["TC0P", "TC0c", "TC0d", "TC0e", "TCXC", "TCXc"] {
            if let tempData = dict[key] as? Data, tempData.count >= 2 {
                let bytes = [UInt8](tempData)
                let rawValue = Double(bytes[0])
                if rawValue > 0 && rawValue < 150 {
                    return rawValue
                }
            }
        }

        return readTemperatureFromAppleARMIO()
    }

    private func readTemperatureFromAppleARMIO() -> Double? {
        let matching = IOServiceMatching("AppleARMIODevice")
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service: io_object_t = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            var name = [CChar](repeating: 0, count: 256)
            IORegistryEntryGetName(service, &name)
            let nameStr = String(cString: name)

            if nameStr.contains("pmgr") || nameStr.contains("temp") || nameStr.contains("smc") {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = properties?.takeRetainedValue() as? [String: Any] {

                    for (key, value) in dict {
                        if key.lowercased().contains("temp") || key.lowercased().contains("temperature") {
                            if let num = value as? Int64, num > 0 && num < 150000 {
                                return num > 1000 ? Double(num) / 1000.0 : Double(num)
                            }
                            if let num = value as? Double, num > 0 && num < 150 {
                                return num
                            }
                            if let data = value as? Data, data.count >= 4 {
                                let rawValue = data.withUnsafeBytes { $0.load(as: UInt32.self) }
                                let temp = Double(rawValue) / 65536.0
                                if temp > 0 && temp < 150 { return temp }
                            }
                        }
                    }
                }
            }
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    private func getMemoryInfo(_ info: inout HardwareInfo) {
        var total: Int64 = 0
        var size = MemoryLayout<Int64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)
        info.memoryTotal = total

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = Int64(vm_kernel_page_size)
            let active = Int64(vmStats.active_count) * pageSize
            let inactive = Int64(vmStats.inactive_count) * pageSize
            let wired = Int64(vmStats.wire_count) * pageSize
            let compressed = Int64(vmStats.compressor_page_count) * pageSize
            let free = Int64(vmStats.free_count) * pageSize
            let speculative = Int64(vmStats.speculative_count) * pageSize

            info.memoryUsed = active + wired + compressed
            info.memoryFree = free + speculative + inactive
            info.swapUsed = Int64(vmStats.swapouts) * pageSize

            let usedPct = total > 0 ? Double(info.memoryUsed) / Double(total) * 100.0 : 0
            info.memoryPressure = usedPct
        }
    }

    private func getBatteryInfo(_ info: inout HardwareInfo) {
        guard let powerSourcesInfo = IOPSCopyPowerSourcesInfo() else { return }
        let powerSources = powerSourcesInfo.takeRetainedValue()
        guard let powerSourcesList = IOPSCopyPowerSourcesList(powerSources) else { return }
        let list = powerSourcesList.takeRetainedValue() as [CFTypeRef]

        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(powerSources, ps)?.takeUnretainedValue() as? [String: Any] else { continue }

            if let capacity = desc[kIOPSCurrentCapacityKey as String] as? Int {
                info.batteryPercent = Double(capacity)
            }
            if let charging = desc[kIOPSIsChargingKey as String] as? Bool {
                info.batteryCharging = charging
            }
            if let time = desc[kIOPSTimeToEmptyKey as String] as? Int, time > 0 {
                info.batteryTimeRemaining = time
            } else if let time = desc[kIOPSTimeToFullChargeKey as String] as? Int, time > 0 {
                info.batteryTimeRemaining = time
            }
            break
        }
    }

    private func getSystemStats(_ info: inout HardwareInfo) {
        var procCount: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.num_processes", &procCount, &size, nil, 0)
        info.processCount = Int(procCount)

        var threadCount: Int32 = 0
        size = MemoryLayout<Int32>.size
        sysctlbyname("kern.num_threads", &threadCount, &size, nil, 0)
        if threadCount > 0 {
            info.threadCount = Int(threadCount)
        }

        var tv = timeval()
        size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &tv, &size, nil, 0)
        let bootTime = Int64(tv.tv_sec)
        let now = Int64(Date().timeIntervalSince1970)
        info.uptimeSeconds = now - bootTime
    }

    private var lastNetInBytes: Int64 = 0
    private var lastNetOutBytes: Int64 = 0
    private var lastNetTime: Date = .distantPast

    private func safeGetNetworkInfo(_ info: inout HardwareInfo) {
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0, let firstAddr = interfaceAddresses else { return }

        var totalIn: Int64 = 0
        var totalOut: Int64 = 0

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let addr = current.pointee
            let ifaName = addr.ifa_name
            guard let namePtr = ifaName else { ptr = addr.ifa_next; continue }

            let name = String(cString: namePtr)

            if name != "lo0",
               let ifaAddr = addr.ifa_addr,
               ifaAddr.pointee.sa_family == UInt8(AF_LINK) {

                if let data = addr.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    totalIn += Int64(networkData.pointee.ifi_ibytes)
                    totalOut += Int64(networkData.pointee.ifi_obytes)
                }
            }
            ptr = addr.ifa_next
        }

        freeifaddrs(interfaceAddresses)

        let now = Date()
        let elapsed = now.timeIntervalSince(lastNetTime)

        if elapsed > 0.5 && lastNetTime != .distantPast {
            let inDiff = Double(max(totalIn - lastNetInBytes, 0))
            let outDiff = Double(max(totalOut - lastNetOutBytes, 0))
            info.networkInRate = inDiff / elapsed
            info.networkOutRate = outDiff / elapsed
        }

        lastNetInBytes = totalIn
        lastNetOutBytes = totalOut
        lastNetTime = now
    }

    // MARK: - Local Scan

    func scanLocal() async {
        isScanning = true
        errorMessage = nil
        restoreScanAccessFromBookmarks()

        if authorizedScanRoots.isEmpty, !requestLocalScanAccess() {
            errorMessage = localizer?.selectMonitorDirs ?? "Please select folders to scan"
            isScanning = false
            return
        }

        let savedIgnores = ignoredIds
        let roots = authorizedScanRoots
        let currentLocalizer = localizer

        let items = await Task.detached(priority: .userInitiated) {
            var results: [ScanItem] = []
            let fm = FileManager.default

            for rule in SCAN_RULES {
                var totalSize: Int64 = 0
                var totalFiles = 0
                var realPath = ""

                for path in rule.paths {
                    let expanded = Self.expandUserPath(path)
                    var isDir: ObjCBool = false

                    guard fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else { continue }
                    guard Self.isPathWithinAuthorizedRoots(expanded, roots: roots) else { continue }

                    realPath = expanded
                    let (size, count) = Self.calculateDirectorySizeStatic(at: expanded)
                    totalSize += size
                    totalFiles += count
                }

                guard totalSize > 0 else { continue }
                let localizedRule = currentLocalizer?.localizedScanRule(rule)

                results.append(ScanItem(
                    id: rule.id,
                    name: localizedRule?.name ?? rule.name,
                    category: localizedRule?.category ?? rule.category,
                    app: localizedRule?.app ?? rule.app,
                    risk: rule.risk,
                    riskDesc: localizedRule?.riskDesc ?? rule.riskDesc,
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
        refreshDiskInfo()
        isScanning = false
    }

    nonisolated private static func expandUserPath(_ path: String) -> String {
        if path == "~" { return SandboxPaths.realHomeDirectory }
        if path.hasPrefix("~/") {
            return SandboxPaths.realHomeDirectory + String(path.dropFirst())
        }
        return NSString(string: path).expandingTildeInPath
    }

    nonisolated private static func isPathWithinAuthorizedRoots(_ path: String, roots: Set<String>) -> Bool {
        guard !roots.isEmpty else { return false }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        for root in roots {
            let r = URL(fileURLWithPath: root).standardizedFileURL.path
            if normalized == r || normalized.hasPrefix(r + "/") { return true }
        }
        return false
    }

    private func restoreScanAccessFromBookmarks() {
        guard !hasRestoredScanBookmarks else { return }
        defer { hasRestoredScanBookmarks = true }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: scanBookmarksPath)),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else { return }

        var restored: Set<String> = []
        var refreshed = bookmarks

        for (path, bookmark) in bookmarks {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
                guard url.startAccessingSecurityScopedResource() else { continue }
                restored.insert(url.path)
                if stale, let newBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    refreshed.removeValue(forKey: path)
                    refreshed[url.path] = newBookmark
                }
            } catch {
                continue
            }
        }

        if let encoded = try? JSONEncoder().encode(refreshed) {
            try? encoded.write(to: URL(fileURLWithPath: scanBookmarksPath))
        }
        authorizedScanRoots = restored
    }

    private func requestLocalScanAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: SandboxPaths.realHomeDirectory)
        panel.prompt = localizer?.localScan ?? "Local Scan"
        panel.message = localizer?.selectMonitorDirs ?? "Select folders to scan (Home or Library is recommended)"

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return false }

        var bookmarks: [String: Data] = [:]
        for url in panel.urls {
            _ = url.startAccessingSecurityScopedResource()
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                bookmarks[url.path] = bookmark
                authorizedScanRoots.insert(url.path)
            } catch {
                print("[AIMacCleaner] Failed to create scan bookmark for \(url.path): \(error)")
            }
        }

        if !bookmarks.isEmpty, let encoded = try? JSONEncoder().encode(bookmarks) {
            try? encoded.write(to: URL(fileURLWithPath: scanBookmarksPath))
        }
        return !authorizedScanRoots.isEmpty
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

    func deleteItems(ids: [String], permanent: Bool = false) async -> DeleteResult {
        var deleteResults: [DeleteItemResult] = []
        var successCount = 0
        var failCount = 0

        let itemsToDelete = scanItems.filter { ids.contains($0.id) }

        for item in itemsToDelete {
            var pathsToDelete: [String] = []

            if let rule = SCAN_RULES.first(where: { $0.id == item.id }) {
                pathsToDelete = rule.paths.map { Self.expandUserPath($0) }
            } else if let realPath = item.realPath, !realPath.isEmpty {
                pathsToDelete = [realPath]
            } else {
                pathsToDelete = [Self.expandUserPath(item.path)]
            }

            for expanded in pathsToDelete {
                do {
                    if FileManager.default.fileExists(atPath: expanded) {
                        if permanent {
                            try FileManager.default.removeItem(atPath: expanded)
                        } else {
                            try moveToTrash(atPath: expanded)
                        }
                        successCount += 1
                        deleteResults.append(DeleteItemResult(id: item.id, path: expanded, success: true, message: permanent ? (localizer?.deleted ?? "Deleted") : (localizer?.movedToTrash ?? "Moved to Trash")))
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
        let storedKey = KeychainStore.loadAPIKey()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: aiConfigFilePath)),
              var config = try? JSONDecoder().decode(AIConfig.self, from: data) else {
            aiConfig = AIConfig(apiBase: "https://api.openai.com", apiKey: storedKey, model: "gpt-4o-mini", hasKey: storedKey?.isEmpty == false)
            return
        }

        if let legacyKey = config.apiKey, !legacyKey.isEmpty {
            KeychainStore.saveAPIKey(legacyKey)
            config = AIConfig(apiBase: config.apiBase, apiKey: nil, model: config.model, hasKey: true)
            saveAIConfigMetadata(config)
        }

        let apiKey = KeychainStore.loadAPIKey()
        aiConfig = AIConfig(
            apiBase: config.apiBase ?? "https://api.openai.com",
            apiKey: apiKey,
            model: config.model ?? "gpt-4o-mini",
            hasKey: apiKey?.isEmpty == false
        )
    }

    func saveAIConfig(apiBase: String, apiKey: String, model: String) {
        if apiKey.isEmpty {
            KeychainStore.deleteAPIKey()
        } else {
            KeychainStore.saveAPIKey(apiKey)
        }

        let config = AIConfig(apiBase: apiBase, apiKey: nil, model: model, hasKey: !apiKey.isEmpty)
        saveAIConfigMetadata(config)
        aiConfig = AIConfig(apiBase: apiBase, apiKey: apiKey.isEmpty ? nil : apiKey, model: model, hasKey: !apiKey.isEmpty)
    }

    private func saveAIConfigMetadata(_ config: AIConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: URL(fileURLWithPath: aiConfigFilePath))
    }

    // MARK: - AI Scan

    func startAiScan() async {
        guard let config = aiConfig, config.hasKey == true, let apiKey = config.apiKey, !apiKey.isEmpty else {
            errorMessage = localizer?.configureAPIKeyFirst ?? "Please configure LLM API Key first"
            return
        }

        isAiScanning = true
        aiStatusMessage = localizer?.collectingDirInfo ?? "Collecting directory info..."

        let dirInfo = collectDirInfo()
        aiStatusMessage = localizer?.callingAIAnalysis ?? "Calling AI for analysis..."

        let result = await callLLM(config: config, dirInfo: dirInfo)

        isAiScanning = false
        refreshDiskInfo()

        if result.success, let items = result.items {
            let localIds = Set(scanItems.map(\.id))
            let newItems = items.filter { !localIds.contains($0.id) }
            scanItems.append(contentsOf: newItems)
            scanItems.sort { $0.size > $1.size }
            aiStatusMessage = "\(localizer?.aiScanComplete ?? "AI scan complete, found") \(newItems.count) \(localizer?.itemsLabel ?? "items")"
        } else {
            errorMessage = "\(localizer?.aiScanFailed ?? "AI scan failed"): \(result.error ?? (localizer?.unknownError ?? "Unknown error"))\n\(localizer?.suggestLocalScan ?? "Suggest using local scan")"
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
        refreshDiskInfo()
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
                SandboxPaths.realHomeDirectory + "/Applications",
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

            let home = SandboxPaths.realHomeDirectory
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
            let home = SandboxPaths.realHomeDirectory
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
                desc: "\(appName) Application",
                bundleId: bundleId,
                appPath: appPath,
                iconPath: iconPath,
                version: version,
                appSize: appSize,
                cacheSize: cacheSize,
                dataSize: dataSize,
                totalSize: appSize + cacheSize + dataSize,
                appType: .app,
                subCategory: "Apps",
                risk: "safe",
                riskDesc: "Installed Application",
                canUninstall: true,
                canClean: cacheSize > 0,
                canReset: cacheSize > 0 || dataSize > 0
            ))
        }
    }

    nonisolated private func scanCLIAndAgents(fm: FileManager, results: inout [AppInfo], seen: inout Set<String>) {
        let home = SandboxPaths.realHomeDirectory

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
            CLITool(name: "Node.js / npm", displayName: "Node.js 运行环境", desc: "JavaScript 运行时和包管理器", id: "cli.nodejs", paths: ["\(home)/.nvm", "\(home)/.npm", "\(home)/.pnpm-store", "\(home)/.yarn", "\(home)/Library/pnpm", "/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules"], appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "卸载后Node.js项目将无法运行", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "Python (pyenv)", displayName: "Python 版本管理", desc: "Python 多版本管理工具和pip缓存", id: "cli.pyenv", paths: ["\(home)/.pyenv", "\(home)/.cache/pip", "\(home)/Library/Python", "\(home)/.local/pipx", "\(home)/.conda"], appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "卸载后Python项目将无法运行", canUninstall: true, canClean: true, canReset: true),
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
            CLITool(name: "Android SDK", displayName: "Android SDK", desc: "Android开发工具包", id: "dev.android", paths: ["\(home)/Library/Android", "\(home)/.android"], appType: .dependency, subCategory: "开发", risk: "caution", riskDesc: "卸载后Android项目将无法编译", canUninstall: true, canClean: true, canReset: false),
            CLITool(name: "Unity", displayName: "Unity 引擎", desc: "游戏开发引擎缓存", id: "dev.unity", paths: ["\(home)/Library/Unity"], appType: .dependency, subCategory: "开发", risk: "safe", riskDesc: "Unity编辑器缓存，可安全清理", canUninstall: false, canClean: true, canReset: true),
            CLITool(name: "Gradle", displayName: "Gradle 构建工具", desc: "Java/Android项目构建工具和缓存", id: "cli.gradle", paths: ["\(home)/.gradle"], appType: .dependency, subCategory: "包管理", risk: "safe", riskDesc: "构建缓存可安全清理，下次构建会重新下载", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "Maven", displayName: "Maven 构建工具", desc: "Java项目构建工具和本地仓库", id: "cli.maven", paths: ["\(home)/.m2"], appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "本地仓库删除后需重新下载所有依赖", canUninstall: true, canClean: true, canReset: true),
            CLITool(name: "CocoaPods", displayName: "CocoaPods 依赖管理", desc: "iOS/macOS依赖管理工具和仓库缓存", id: "cli.cocoapods", paths: ["\(home)/.cocoapods", "\(home)/Library/Caches/CocoaPods"], appType: .dependency, subCategory: "包管理", risk: "safe", riskDesc: "仓库缓存可安全清理", canUninstall: true, canClean: true, canReset: true),
        ]

        for tool in cliTools {
            guard !seen.contains(tool.id) else { continue }

            var totalSize: Int64 = 0
            var realPath = ""

            for path in tool.paths {
                let expanded = NSString(string: path).expandingTildeInPath
                let (s, _) = Self.calculateDirectorySizeStatic(at: expanded)
                if s > 0 || fm.fileExists(atPath: expanded) {
                    totalSize += s
                    if realPath.isEmpty { realPath = expanded }
                }
            }

            if realPath.isEmpty, let commandPath = Self.installedCommandPath(forToolId: tool.id) {
                realPath = commandPath
            }

            guard totalSize > 0 || !realPath.isEmpty else { continue }
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

    nonisolated private static func installedCommandPath(forToolId id: String) -> String? {
        let commandMap: [String: [String]] = [
            "cli.homebrew": ["brew"],
            "cli.nodejs": ["node", "npm", "pnpm", "yarn"],
            "cli.pyenv": ["pyenv", "python3", "pip3"],
            "cli.rustup": ["rustup", "cargo", "rustc"],
            "cli.go": ["go"],
            "cli.docker": ["docker"],
            "dev.xcode-dev": ["xcodebuild"],
            "dev.android": ["adb", "sdkmanager"],
            "dev.unity": ["unity"],
            "cli.gradle": ["gradle"],
            "cli.maven": ["mvn"],
            "cli.cocoapods": ["pod"],
        ]
        guard let names = commandMap[id] else { return nil }
        let dirs = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin", "/usr/bin", "/bin"]
        let fm = FileManager.default
        for name in names {
            for dir in dirs {
                let path = (dir as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }

    nonisolated private func scanDynamicAgents(fm: FileManager, results: inout [AppInfo], seen: inout Set<String>) {
        let home = SandboxPaths.realHomeDirectory

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
            ".aimaccleaner_operations_v2.json", ".aimaccleaner_curated.json", ".aimaccleaner_monitor.json",
            ".aimaccleaner_bookmarks.json", ".aimaccleaner_alerts.json", ".aimaccleaner_alert_rule.json",
            ".aimaccleaner_protected_dirs.json", ".aimaccleaner_lifecycle.json", ".aimaccleaner_hourly_stats.json",
            ".aimaccleaner_cmd_rules.json", ".aimaccleaner_custom_agents.json", ".aimaccleaner_snapshots.json",
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
            guard size > 1048576 || fm.isReadableFile(atPath: dirPath) else { continue }

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
                let dataSize: Int64 = size
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
        let home = SandboxPaths.realHomeDirectory

        let brewDirs = ["/opt/homebrew/Cellar", "/usr/local/Cellar"]
        for brewDir in brewDirs {
            guard let packages = try? fm.contentsOfDirectory(atPath: brewDir) else { continue }
            for pkg in packages {
                let id = "brew.\(pkg)"
                guard !seen.contains(id) else { continue }
                let pkgPath = (brewDir as NSString).appendingPathComponent(pkg)
                let (size, _) = Self.calculateDirectorySizeStatic(at: pkgPath)
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

        let pipPaths = [
            "\(home)/Library/Python",
            "\(home)/.pyenv/versions",
            "\(home)/.local/pipx/venvs",
            "\(home)/.conda/envs"
        ]
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
            let modPath = (path as NSString).appendingPathComponent(mod)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: modPath, isDirectory: &isDir), isDir.boolValue else { continue }

            if mod.hasPrefix("@"), let scoped = try? fm.contentsOfDirectory(atPath: modPath) {
                for child in scoped {
                    let childPath = (modPath as NSString).appendingPathComponent(child)
                    var childIsDir: ObjCBool = false
                    guard fm.fileExists(atPath: childPath, isDirectory: &childIsDir), childIsDir.boolValue else { continue }
                    let packageName = "\(mod)/\(child)"
                    let id = "npm.\(packageName)"
                    guard !seen.contains(id) else { continue }
                    let (size, _) = Self.calculateDirectorySizeStatic(at: childPath)
                    seen.insert(id)
                    results.append(AppInfo(
                        id: id, name: packageName, displayName: packageName, desc: "npm 全局安装的 \(packageName) 包",
                        bundleId: id,
                        appPath: childPath, iconPath: nil, version: nil,
                        appSize: size, cacheSize: 0, dataSize: 0, totalSize: size,
                        appType: .dependency, subCategory: "包管理", risk: "caution", riskDesc: "卸载后依赖此包的项目将无法运行",
                        canUninstall: true, canClean: false, canReset: false
                    ))
                }
                continue
            }

            let id = "npm.\(mod)"
            guard !seen.contains(id) else { continue }
            let (size, _) = Self.calculateDirectorySizeStatic(at: modPath)
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
        var sitePackagePaths = [path]
        if !fm.fileExists(atPath: path), let enumerator = fm.enumerator(atPath: (path as NSString).deletingLastPathComponent) {
            for case let rel as String in enumerator {
                if rel.hasSuffix("site-packages") {
                    sitePackagePaths.append(((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(rel))
                }
            }
        }

        for sitePath in Set(sitePackagePaths) {
            scanPipPackagesInSiteDirectory(at: sitePath, fm: fm, results: &results, seen: &seen)
        }
    }

    nonisolated private func scanPipPackagesInSiteDirectory(at path: String, fm: FileManager, results: inout [AppInfo], seen: inout Set<String>) {
        guard let packages = try? fm.contentsOfDirectory(atPath: path) else { return }
        for pkg in packages {
            guard !pkg.hasSuffix(".dist-info"), !pkg.hasSuffix(".egg-info"), pkg != "__pycache__" else { continue }
            let id = "pip.\(pkg)"
            guard !seen.contains(id) else { continue }
            let pkgPath = (path as NSString).appendingPathComponent(pkg)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: pkgPath, isDirectory: &isDir), isDir.boolValue {
                let (size, _) = Self.calculateDirectorySizeStatic(at: pkgPath)
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
    private var hardwareTimer: Timer?
    var isMonitoring: Bool { monitorTimer != nil }
    private var lastAlertTime: Date = .distantPast
    let operationMonitor = OperationMonitor()
    let guardFeature = AgentGuardFeature()
    @Published var isImportingAgentHistory = false

    weak var localizer: Localizer? {
        didSet {
            operationMonitor.localizer = localizer
            operationMonitor.guardFeature = guardFeature
            guardFeature.localizer = localizer
        }
    }

    @Published var operationRecords: [OperationRecord] = []
    private var processedOperationRecordIDs: Set<String> = []
    private var lastAgentHistoryImportTime: Date = .distantPast
    private var recordsClearCutoff: Date {
        if let d = UserDefaults.standard.object(forKey: "operationRecordsClearedAt") as? Date { return d }
        return .distantPast
    }

    func startOperationMonitor() {
        operationMonitor.start()
        operationRecords = operationMonitor.records
        processedOperationRecordIDs = Set(operationRecords.map(\.id))
        guardFeature.rebuildAnalytics(from: operationRecords)
        startOperationPolling()
    }

    func ensureAgentGuardDataPipeline() {
        if !operationMonitor.isMonitoring {
            startOperationMonitor()
            UserDefaults.standard.set(true, forKey: "operationMonitorEnabled")
        } else {
            operationRecords = operationMonitor.records
            guardFeature.rebuildAnalytics(from: operationRecords)
            startOperationPolling()
        }
        importKnownAgentHistory()
    }

    func stopOperationMonitor() {
        operationMonitor.saveRecords()
        guardFeature.saveHourlyStats()
        operationMonitor.stop()
        stopOperationPolling()
    }

    func clearOperationRecords() {
        UserDefaults.standard.set(Date(), forKey: "operationRecordsClearedAt")
        operationMonitor.clearRecords()
        operationRecords = []
        processedOperationRecordIDs.removeAll()
        lastAgentHistoryImportTime = Date()
        guardFeature.rebuildAnalytics(from: [])
    }

    func ingestAgentSessionRecords(_ records: [AgentOpRecord]) {
        let cutoff = recordsClearCutoff
        let converted = records
            .filter { $0.timestamp >= cutoff }
            .compactMap { convertAgentSessionRecord($0) }
        guard !converted.isEmpty else { return }
        operationMonitor.mergeHistoricalRecords(converted)
        operationRecords = operationMonitor.records
        processedOperationRecordIDs = Set(operationRecords.map(\.id))
        guardFeature.rebuildAnalytics(from: operationRecords)
    }

    func importKnownAgentHistory() {
        guard !isImportingAgentHistory else { return }
        guard Date().timeIntervalSince(lastAgentHistoryImportTime) > 600 else { return }
        lastAgentHistoryImportTime = Date()
        isImportingAgentHistory = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let scanner = AgentSessionScanner()
            let records = scanner.collectAllAgentOps(limit: 10000)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.ingestAgentSessionRecords(records)
                self.isImportingAgentHistory = false
            }
        }
    }

    private func convertAgentSessionRecord(_ record: AgentOpRecord) -> OperationRecord? {
        let target = record.targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = record.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty || !detail.isEmpty else { return nil }

        let opType = operationType(from: record.opType, toolName: record.toolName, detail: detail)
        let normalizedTarget = target.isEmpty ? detail : target
        return OperationRecord(
            id: "agent_session_\(record.id)",
            timestamp: record.timestamp,
            agentName: record.agentName,
            operationType: opType,
            targetPath: normalizedTarget,
            detail: detail.isEmpty ? normalizedTarget : detail,
            fileSize: 0,
            processName: record.toolName,
            toolInfo: record.sessionId
        )
    }

    private func operationType(from opType: String, toolName: String, detail: String) -> OperationRecord.OperationType {
        let combined = "\(opType) \(toolName) \(detail)".lowercased()
        if combined.contains("delete") || combined.contains("remove") || combined.contains("trash") || combined.contains("rm ") {
            return .delete
        }
        if combined.contains("write") || combined.contains("create") || combined.contains("new_file") || combined.contains("touch ") || combined.contains("mkdir ") {
            return .create
        }
        if combined.contains("edit") || combined.contains("modify") || combined.contains("update") || combined.contains("patch") {
            return .modify
        }
        if combined.contains("rename") {
            return .rename
        }
        if combined.contains("move") || combined.contains(" mv ") {
            return .move
        }
        if combined.contains("execute") || combined.contains("bash") || combined.contains("shell") || combined.contains("command") {
            return .execute
        }
        if combined.contains("read") || combined.contains("search") || combined.contains("grep") || combined.contains("glob") {
            return .read
        }
        return .modify
    }

    private var operationPollTimer: Timer?
    private var lastAutoSaveTime: Date = .distantPast

    private func startOperationPolling() {
        stopOperationPolling()
        operationPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let currentRecords = self.operationMonitor.records
                let newRecords = currentRecords.filter { !self.processedOperationRecordIDs.contains($0.id) }
                self.operationRecords = currentRecords
                self.processedOperationRecordIDs = Set(currentRecords.map(\.id))
                if !newRecords.isEmpty {
                    for record in newRecords {
                        self.guardFeature.checkBatchOperation(record: record)
                        self.guardFeature.checkSensitiveFile(record: record)
                        self.guardFeature.checkProtectedDir(record: record)
                        self.guardFeature.recordStats(record)
                    }
                }
                self.guardFeature.checkProcessLifecycle(
                    currentPids: Set(self.operationMonitor.allPidCommMap.keys),
                    pidCommMap: self.operationMonitor.allPidCommMap,
                    pidArgsMap: self.operationMonitor.allPidArgsMap,
                    ppidMap: self.operationMonitor.ppidMap,
                    agentKeywords: self.operationMonitor.agentKeywords
                )

                if Date().timeIntervalSince(self.lastAutoSaveTime) > 30 {
                    self.guardFeature.saveHourlyStats()
                    self.guardFeature.saveAlerts()
                    self.guardFeature.saveCommandRules()
                    self.lastAutoSaveTime = Date()
                }
            }
        }
    }

    private func stopOperationPolling() {
        operationPollTimer?.invalidate()
        operationPollTimer = nil
        aiLearningTimer?.invalidate()
        aiLearningTimer = nil
    }

    private var aiLearningTimer: Timer?

    func startAISelfLearning() {
        operationMonitor.aiSelfLearningEnabled = true
        aiLearningTimer?.invalidate()
        aiLearningTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.analyzeUnknownAgentsWithAI()
            }
        }
        aiLearningTimer?.fire()
    }

    func stopAISelfLearning() {
        operationMonitor.aiSelfLearningEnabled = false
        aiLearningTimer?.invalidate()
        aiLearningTimer = nil
    }

    func analyzeUnknownAgentsWithAI() async {
        guard let config = aiConfig, config.hasKey == true else { return }
        let samples = operationMonitor.getUnknownAgentSamples()
        guard !samples.isEmpty else { return }

        var pathSummary = ""
        for sample in samples.prefix(5) {
            pathSummary += "进程: \(sample.comm) (\(sample.pid))\n"
            pathSummary += "参数: \(sample.args.prefix(80))\n"
            pathSummary += "文件: \(sample.paths.prefix(5).joined(separator: ", "))\n\n"
        }

        let prompt = """
        你是一个Agent进程分析器。以下是未知进程及其打开的文件路径。请判断：
        1. 这个进程是否是一个自己的内部目录（而非修改用户文件）？
        2. 如果它是不同于已有的agent，请给出它的显示名称和关键字

        已知agent: Trae, Cursor, CodeBuddy, Claude, Windsurf, Copilot, Cline, Gemini, ChatGPT, DeepSeek, Kimi, Doubao, Hermes, Codex, Augment, CodeArts

        未知进程：
        \(pathSummary)

        请以JSON返回，格式：{"recognized":[],"new_agents":[{"name":"显示名","keywords":["kw1","kw2"],"dirs":["/path/to/dir"]}],"noise_dirs":["/path/to/skip"]}
        只返回JSON，不要其他内容。
        """

        guard let apiKey = config.apiKey, !apiKey.isEmpty, let apiBase = config.apiBase?.hasSuffix("/v1") == true ? config.apiBase : (config.apiBase ?? "") + "/v1" else { return }
        let requestBody: [String: Any] = [
            "model": config.model ?? "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.3, "max_tokens": 1000
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return }
        guard let url = URL(string: "\(apiBase)/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let content = msg["content"] as? String else { return }

            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let start = trimmed.firstIndex(of: "{"),
                  let end = trimmed.lastIndex(of: "}") else { return }
            let jsonStr = String(trimmed[start...end])
            guard let jsonData = jsonStr.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return }

            if let noiseDirs = result["noise_dirs"] as? [String] {
                for dir in noiseDirs {
                    operationMonitor.addDiscoveredAgentDir(dir)
                }
            }
            if let newAgents = result["new_agents"] as? [[String: Any]] {
                for agent in newAgents {
                    if let name = agent["name"] as? String,
                       let keywords = agent["keywords"] as? [String],
                       let dirs = agent["dirs"] as? [String] {
                        operationMonitor.learnAgentKeyword(displayName: name, keywords: keywords, dirs: dirs)
                    }
                }
            }
            print("[AIMacCleaner] AI self-learning: \(result)")
        } catch {
            print("[AIMacCleaner] AI self-learning failed: \(error)")
        }
    }

    private var curationTimer: Timer?

    func startAutoCuration() {
        stopAutoCuration()
        let interval = TimeInterval(operationMonitor.autoCurationInterval * 3600)
        curationTimer = Timer.scheduledTimer(withTimeInterval: max(interval, 300), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.curateWithAI()
            }
        }
    }

    func stopAutoCuration() {
        curationTimer?.invalidate()
        curationTimer = nil
    }

    func curateWithAI() async {
        operationMonitor.curationMessage = ""

        guard let config = aiConfig, config.hasKey == true else {
            operationMonitor.curationMessage = localizer?.configureAIModel ?? "Please configure AI model (Settings → AI Settings)"
            return
        }

        operationMonitor.isCurating = true
        operationMonitor.curationMessage = localizer?.collectingRawData ?? "Collecting raw data..."
        operationMonitor.discoverAgentSelfDirs()

        let (events, snapshots) = operationMonitor.getRawDataForCuration()
        print("[AIMacCleaner] curateWithAI: got \(events.count) events, \(snapshots.count) snapshots")

        guard events.count >= 3 else {
            operationMonitor.isCurating = false
            operationMonitor.curationMessage = events.isEmpty
                ? (localizer?.noMonitorData ?? "No monitoring data, please enable Agent monitoring and wait for file operations")
                : "\(localizer?.insufficientDataPrefix ?? "Insufficient data (only") \(events.count) \(localizer?.continueMonitorRetry ?? "records), continue monitoring and retry")"
            return
        }

        operationMonitor.curationMessage = localizer?.callingAIAnalysis ?? "Calling AI for analysis..."

        let recentSnaps = snapshots.filter { s in
            if let first = events.first?.timestamp, let last = events.last?.timestamp {
                let range = first.timeIntervalSince1970 ... last.timeIntervalSince1970 + 60
                return range.contains(s.timestamp.timeIntervalSince1970)
            }
            return false
        }

        let selfDirs = operationMonitor.agentSelfDirs
        let knownAgentParentDirs = Set(selfDirs.map { ($0 as NSString).deletingLastPathComponent }).union(selfDirs)

        var eventSummary = ""
        var externalCount = 0
        for e in events {
            let path = e.targetPath
            if path.contains("/.git/") || path.hasSuffix("/.git") || path.hasSuffix(".DS_Store") { continue }
            if path.contains("/node_modules/") || path.contains("/.vite/") || path.contains("/.turbo/") { continue }
            if path.contains("/Library/Caches/") || path.contains("/Library/Containers/") || path.contains("/tmp/") { continue }
            if path.contains("/dist/") || path.contains("/build/") || path.contains("/.next/") { continue }
            if knownAgentParentDirs.contains(where: { path.hasPrefix($0) }) { continue }
            externalCount += 1
            eventSummary += "\(formattedTime(e.timestamp)) | \(e.operationType.rawValue) | \(path)\n"
        }
        let lines = eventSummary.components(separatedBy: "\n").filter { !$0.isEmpty }
        eventSummary = lines.suffix(60).joined(separator: "\n")

        if eventSummary.isEmpty {
            operationMonitor.isCurating = false
            operationMonitor.curationMessage = "\(localizer?.curationComplete ?? "Curation complete: ")\(events.count) \(localizer?.allInternalOps ?? "events are all within the agent's own project directory, no external file operations")"
            return
        }

        var procSummary = ""
        let systemComms: Set<String> = ["kernel_task", "launchd", "WindowServer", "Dock", "Finder", "SystemUIServer",
            "cfprefsd", "distnoted", "logd", "syslogd", "securityd", "trustd", "sysmond", "mds", "mdworker",
            "corespeechd", "coreaudiod", "WiFi", "bluetoothd", "airportd", "iconservicesagent", "coreduetd",
            "locationd", "timed", "chronod", "powerd", "configd", "diskarbitrationd", "fseventsd", "sandboxd"]
        let nonSystemProcs = recentSnaps.filter { snap in
            let c = snap.comm.lowercased()
            if systemComms.contains(snap.comm) { return false }
            if c.hasPrefix("com.apple.") || c.hasPrefix("com.apple") { return false }
            return true
        }
        print("[AIMacCleaner] curateWithAI: \(recentSnaps.count) recent snaps, \(nonSystemProcs.count) non-system")
        if nonSystemProcs.isEmpty {
            procSummary = "（\(localizer?.noProcessSnapshot ?? "No process snapshots—ensure Agent monitoring is enabled, or re-enable and wait 30 seconds")）"
        } else {
            let grouped = Dictionary(grouping: nonSystemProcs.prefix(200), by: { $0.comm })
            for (comm, procs) in grouped.sorted(by: { $0.1.count > $1.1.count }) {
                let pids = Set(procs.map { String($0.pid) }).sorted().joined(separator: ",")
                let ppids = Set(procs.filter { $0.ppid != 0 }.map { String($0.ppid) }).sorted().joined(separator: ",")
                let ppidStr = ppids.isEmpty ? "" : " PPIDs[\(ppids)]"
                procSummary += "\(comm)(x\(procs.count)) PIDs[\(pids)]\(ppidStr)\n"
            }
        }

        let prompt = """
            你是文件操作归因分析器。判断每个文件事件是哪个 Agent 进程操作的。

            【关键】只能用进程PID/PPID数据判断！禁止用目录名猜测（例如文件在 codebuddy 文件夹 ≠ CodeBuddy 的操作）！

            进程快照:
            \(procSummary)

            文件操作事件（仅外部文件，共\(externalCount)条，取最近60条）:
            \(eventSummary)

            进程归因方法：找到每个文件对应的进程PID，查看该进程的comm和PPID链，确定属于哪个Agent。
            例：node(PID=1240, PPID=1234) → trae-cn(PID=1234) → 归因Trae

            返回JSON数组。每条格式：
            {"path":"/完整路径","op":"修改|创建|删除","agent":"Agent名","confidence":0.8,"evidence":"PID xxxx 进程 xxx 操作"}
            只返回JSON数组。
            """

        guard let apiKey = config.apiKey, !apiKey.isEmpty,
              let apiBase = config.apiBase else {
            operationMonitor.isCurating = false
            operationMonitor.curationMessage = localizer?.aiConfigIncomplete ?? "AI configuration incomplete"
            return
        }
        let base = apiBase.hasSuffix("/v1") ? apiBase : apiBase + "/v1"
        let requestBody: [String: Any] = [
            "model": config.model ?? "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.1, "max_tokens": 4000
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: "\(base)/chat/completions") else {
            operationMonitor.isCurating = false
            operationMonitor.curationMessage = localizer?.requestBuildFailed ?? "Request build failed"
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 60

        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            guard let httpResp = resp as? HTTPURLResponse else {
                operationMonitor.isCurating = false
                operationMonitor.curationMessage = localizer?.networkError ?? "Network error"
                return
            }
            guard httpResp.statusCode == 200 else {
                operationMonitor.isCurating = false
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[AIMacCleaner] API error \(httpResp.statusCode): \(body.prefix(200))")
                operationMonitor.curationMessage = "\(localizer?.apiError ?? "API error") (\(httpResp.statusCode))"
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let content = msg["content"] as? String else {
                operationMonitor.isCurating = false
                operationMonitor.curationMessage = localizer?.aiResponseFormatError ?? "AI response format error"
                return
            }

            let raw = content.trimmingCharacters(in: .whitespacesAndNewlines)
            operationMonitor.curationRawResponse = raw
            print("[AIMacCleaner] AI raw response (\(raw.count) chars)")

            let curated = parseCurationResponse(raw: raw, events: events)
            if curated == nil {
                operationMonitor.isCurating = false
                return
            }

            if curated!.isEmpty {
                operationMonitor.isCurating = false
                operationMonitor.curationMessage = "\(localizer?.curationComplete ?? "Curation complete: ")\(localizer?.allSystemOps ?? "All are internal system operations, no external file changes detected")"
                operationMonitor.saveCuratedRecords([])
            } else {
                operationMonitor.saveCuratedRecords(curated!)
                operationMonitor.curationMessage = "\(localizer?.curationComplete ?? "Curation complete: ")\(localizer?.identifiedAgentOps ?? "Identified") \(curated!.count) \(localizer?.agentOpsRecords ?? "Agent operations")"
                operationMonitor.curationRawResponse = ""
                print("[AIMacCleaner] Curation done: \(curated!.count) records from \(events.count) events")
            }
        } catch {
            operationMonitor.isCurating = false
            operationMonitor.curationMessage = "\(localizer?.networkRequestFailed ?? "Network request failed"): \(error.localizedDescription)"
            print("[AIMacCleaner] Curation failed: \(error)")
        }
    }

    private func parseCurationResponse(raw: String, events: [OperationRecord]) -> [CuratedRecord]? {
        var body = raw
            .replacingOccurrences(of: "`json\n", with: "\n")
            .replacingOccurrences(of: "`json \n", with: "\n")

        if let results = tryJSONParse(body) { return buildCurated(from: results, events: events) }

        while let start = body.range(of: "```"), let end = body.range(of: "```", options: [], range: body.index(after: start.lowerBound)..<body.endIndex) {
            var inner = String(body[body.index(after: start.lowerBound)..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.hasPrefix("json") { inner = String(inner.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines) }
            body.replaceSubrange(start.lowerBound...end.upperBound, with: "\n\(inner)\n")
        }

        if let results = tryJSONParse(body) { return buildCurated(from: results, events: events) }

        // Try extracting array
        if let start = body.firstIndex(of: "["), let end = body.lastIndex(of: "]"), start < end {
            if let results = tryJSONParse(String(body[start...end])) { return buildCurated(from: results, events: events) }
        }

        // Try extracting object with results key
        if let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}"), start < end {
            let objStr = String(body[start...end])
            if let obj = try? JSONSerialization.jsonObject(with: objStr.data(using: .utf8)!) as? [String: Any],
               let results = obj["results"] as? [[String: Any]] {
                return buildCurated(from: results, events: events)
            }
            if let obj = try? JSONSerialization.jsonObject(with: objStr.data(using: .utf8)!) as? [String: Any],
               let items = obj["items"] as? [[String: Any]] {
                return buildCurated(from: items, events: events)
            }
        }

        operationMonitor.curationMessage = localizer?.aiNoJsonArray ?? "AI did not return JSON array or object"
        print("[AIMacCleaner] --- AI RAW RESPONSE (\(raw.count) chars) ---")
        print(raw)
        print("[AIMacCleaner] --- END RAW RESPONSE ---")
        return nil
    }

    private func tryJSONParse(_ text: String) -> [[String: Any]]? {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: "`json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        if let data = cleaned.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            if let arr = obj as? [[String: Any]] { return arr }
            if let dict = obj as? [String: Any], let arr = dict["results"] as? [[String: Any]] { return arr }
            if let dict = obj as? [String: Any], let arr = dict["items"] as? [[String: Any]] { return arr }
            if let arr = obj as? [Any] {
                return arr.compactMap { $0 as? [String: Any] }
            }
        }
        return nil
    }

    private func buildCurated(from results: [[String: Any]], events: [OperationRecord]) -> [CuratedRecord] {
        var curated: [CuratedRecord] = []
        for item in results {
            guard let path = item["path"] as? String,
                  let agent = item["agent"] as? String,
                  let op = item["op"] as? String else { continue }
            if agent.hasPrefix("系统") || agent.hasPrefix(localizer?.systemPrefix ?? "system") || agent.hasPrefix("IDE") { continue }
            let conf = (item["confidence"] as? NSNumber)?.doubleValue ?? 0.5
            let ev = (item["evidence"] as? String) ?? ""
            let matchedEv = events.first { $0.targetPath == path }
            let detail = matchedEv?.detail ?? "\(op): \((path as NSString).lastPathComponent)"
            let size = matchedEv?.fileSize ?? 0
            curated.append(CuratedRecord(
                id: UUID().uuidString, timestamp: matchedEv?.timestamp ?? Date(),
                agentName: agent, operationType: op, targetPath: path,
                detail: detail, fileSize: size, confidence: conf, evidence: ev
            ))
        }
        return curated
    }
    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        stopMonitoring()
        refreshDiskInfo()
        refreshHardwareInfo()
        checkAndAlert()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDiskInfo()
                self?.checkAndAlert()
            }
        }
        hardwareTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHardwareInfo()
            }
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        hardwareTimer?.invalidate()
        hardwareTimer = nil
    }

    private func checkAndAlert() {
        guard let disk = diskInfo else { return }
        let freePct = 100.0 - disk.usedPct
        guard freePct <= alertThreshold else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAlertTime) > 3600 else { return }
        lastAlertTime = now

        let content = UNMutableNotificationContent()
        content.title = localizer?.storageWarningTitle ?? "⚠️ Low Storage"
        content.body = "\(localizer?.storageWarningBody ?? "Disk remaining") \(String(format: "%.1f", disk.freeGb)) GB（\(String(format: "%.0f", freePct))%），\(localizer?.suggestCleanNow ?? "Clean up recommended")"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "aimaccleaner.storage.alert",
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request) { error in
                    if let error = error {
                        print("Notification error: \(error.localizedDescription)")
                    }
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error = error {
                        print("Notification authorization error: \(error.localizedDescription)")
                    }
                    guard granted else { return }
                    center.add(request) { error in
                        if let error = error {
                            print("Notification error: \(error.localizedDescription)")
                        }
                    }
                }
            default:
                break
            }
        }
    }

    let currentVersion: String = {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let version = dict["CFBundleShortVersionString"] as? String {
            return version
        }
        return "unknown"
    }()

    func analyzeImpactWithAI(apps: [AppInfo]) async {
        guard let config = aiConfig, config.hasKey == true, let apiKey = config.apiKey, !apiKey.isEmpty else {
            for app in apps { aiAnalysisMap[app.id] = localizer?.pleaseConfigureAPIKey ?? "⚠️ Please configure LLM API Key first" }
            return
        }

        isAnalyzingImpact = true
        for app in apps { aiAnalysisMap[app.id] = localizer?.analyzingDots ?? "🔄 Analyzing..." }

        let itemsDesc = apps.map { app in
            """
            - Name: \(app.displayName)
              Type: \(app.appType.localizedLabel(localizer ?? Localizer())) / \(localizer?.localizedSubCategory(app.subCategory) ?? app.subCategory)
              Size: \(formatSize(app.totalSize))
              Path: \(app.appPath)
              Risk: \(app.risk) - \(app.riskDesc)
            """
        }.joined(separator: "\n")

        let prompt = """
        You are a macOS system management expert. The user wants to delete/clean the following items. Please analyze the impact of deleting each item.

        For each item, provide a one-sentence description (no more than 30 words) of the main impact after deletion.

        Please strictly return the result in the following JSON format, without any other text:
        [
          {
            "name": "item name",
            "impact": "one-sentence impact description"
          }
        ]
        Only return the JSON array, do not include markdown code block markers.
        The items to analyze:
        \(itemsDesc)
        """

        let apiBase = (config.apiBase ?? "https://api.openai.com").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(apiBase)/v1/chat/completions") else {
            for app in apps { aiAnalysisMap[app.id] = localizer?.invalidAPIUrl ?? "❌ Invalid API URL" }
            isAnalyzingImpact = false
            return
        }

        let body: [String: Any] = [
            "model": config.model ?? "gpt-4o-mini",
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
                for app in apps { aiAnalysisMap[app.id] = localizer?.invalidHttpResponse ?? "❌ Invalid HTTP response" }
                isAnalyzingImpact = false
                return
            }

            if http.statusCode != 200 {
                for app in apps { aiAnalysisMap[app.id] = "❌ \(localizer?.apiError ?? "API error") (\(http.statusCode))" }
                isAnalyzingImpact = false
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else {
                for app in apps { aiAnalysisMap[app.id] = localizer?.aiModelFormatError ?? "❌ AI model response format error" }
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
                        aiAnalysisMap[app.id] = localizer?.analysisComplete ?? "🤖 Analysis complete (see original description)"
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

    func emptyTrashIfAllowed() {
        guard trashInsteadOfDelete && !preventAutoEmptyTrash else { return }
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
    }

    private enum ManagedAppAction {
        case reset
        case basicUninstall
        case fullUninstall
    }

    private func existingPaths(_ paths: [String]) -> [String] {
        let fm = FileManager.default
        var seen = Set<String>()
        return paths.compactMap { path in
            let expanded = Self.expandUserPath(path)
            guard !expanded.isEmpty, !seen.contains(expanded), fm.fileExists(atPath: expanded) else { return nil }
            seen.insert(expanded)
            return expanded
        }
    }

    private func standardAppSupportPaths(for app: AppInfo) -> (cache: [String], data: [String], install: [String]) {
        let install = app.appPath.isEmpty ? [] : [app.appPath]
        return (app.cachePaths, app.dataPaths, install)
    }

    private func managedPaths(for app: AppInfo, action: ManagedAppAction) -> [String] {
        let home = SandboxPaths.realHomeDirectory
        let standard = standardAppSupportPaths(for: app)
        let id = app.id.lowercased()
        let bundle = app.bundleId.lowercased()
        let name = (app.name + " " + app.displayName).lowercased()

        func candidates(install: [String] = [], cache: [String] = [], data: [String] = []) -> [String] {
            switch action {
            case .reset:
                return existingPaths(cache + data)
            case .basicUninstall:
                return existingPaths(install.isEmpty ? standard.install : install)
            case .fullUninstall:
                return existingPaths(install + cache + data + standard.install + standard.cache + standard.data)
            }
        }

        if id.contains("cli.nodejs") {
            return candidates(
                install: ["\(home)/.nvm", "/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules"],
                cache: ["\(home)/.npm", "\(home)/.pnpm-store", "\(home)/.yarn", "\(home)/Library/pnpm"],
                data: ["\(home)/Library/Caches/node-gyp", "\(home)/Library/Caches/npm"]
            )
        }
        if id.contains("cli.pyenv") {
            return candidates(
                install: ["\(home)/.pyenv", "\(home)/.local/pipx", "\(home)/.conda"],
                cache: ["\(home)/.cache/pip"],
                data: ["\(home)/Library/Python"]
            )
        }
        if id.contains("cli.rustup") {
            return candidates(install: ["\(home)/.rustup", "\(home)/.cargo"], cache: ["\(home)/.cargo/registry/cache", "\(home)/.cargo/git/checkouts"])
        }
        if id.contains("cli.go") {
            return candidates(install: ["\(home)/go"], cache: ["\(home)/.cache/go-build"])
        }
        if id.contains("cli.docker") {
            return candidates(install: ["\(home)/Library/Containers/com.docker.docker"], cache: ["\(home)/Library/Caches/com.docker.docker"], data: ["\(home)/.docker"])
        }
        if id.contains("cli.gradle") || id.contains("dotdir..gradle") {
            return candidates(install: ["\(home)/.gradle"], cache: ["\(home)/.gradle/caches"])
        }
        if id.contains("cli.maven") || id.contains("dotdir..m2") {
            return candidates(install: ["\(home)/.m2"], cache: ["\(home)/.m2/repository"])
        }
        if id.contains("cli.cocoapods") {
            return candidates(install: ["\(home)/.cocoapods"], cache: ["\(home)/Library/Caches/CocoaPods"])
        }
        if id.contains("dev.xcode-dev") {
            return candidates(cache: ["\(home)/Library/Developer/Xcode/DerivedData", "\(home)/Library/Developer/Xcode/Archives"], data: ["\(home)/Library/Developer"])
        }
        if id.contains("dev.android") {
            return candidates(install: ["\(home)/Library/Android"], cache: ["\(home)/.gradle/caches"], data: ["\(home)/.android"])
        }
        if id.contains("dev.unity") {
            return candidates(cache: ["\(home)/Library/Unity/cache"], data: ["\(home)/Library/Unity"])
        }

        if id.contains("agent.trae") || name.contains("trae") || bundle.contains("trae") {
            return candidates(
                install: ["/Applications/Trae.app", "/Applications/Trae CN.app", "\(home)/Applications/Trae.app"],
                cache: ["\(home)/Library/Caches/Trae", "\(home)/Library/Caches/TraeCN", "\(home)/Library/Caches/com.trae"],
                data: ["\(home)/Library/Application Support/Trae", "\(home)/Library/Application Support/TraeCN", "\(home)/Library/Preferences/com.trae.plist", "\(home)/Library/Saved Application State/com.trae.savedState"]
            )
        }
        if id.contains("agent.codebuddy") || name.contains("codebuddy") || bundle.contains("codebuddy") {
            return candidates(
                install: ["/Applications/CodeBuddy.app", "\(home)/Applications/CodeBuddy.app"],
                cache: ["\(home)/Library/Caches/CodeBuddy", "\(home)/Library/Caches/CodeBuddyCN", "\(home)/Library/Caches/com.tencent.codebuddy"],
                data: ["\(home)/Library/Application Support/CodeBuddy", "\(home)/Library/Application Support/CodeBuddyCN", "\(home)/Library/Preferences/com.tencent.codebuddy.plist"]
            )
        }
        if id.contains("agent.claude") || name.contains("claude") || bundle.contains("claude") {
            return candidates(
                install: ["/Applications/Claude.app", "\(home)/Applications/Claude.app"],
                cache: ["\(home)/Library/Caches/Claude", "\(home)/Library/Caches/com.anthropic.claude"],
                data: ["\(home)/.claude", "\(home)/.config/claude", "\(home)/Library/Application Support/Claude", "\(home)/Library/Application Support/Claude-3p", "\(home)/Library/Preferences/com.anthropic.claude.plist"]
            )
        }
        if id.contains("agent.openclaw") || name.contains("openclaw") || bundle.contains("openclaw") {
            return candidates(
                install: ["/Applications/OpenClaw.app", "\(home)/Applications/OpenClaw.app"],
                cache: ["\(home)/Library/Caches/OpenClaw", "\(home)/Library/Caches/openclaw"],
                data: ["\(home)/.openclaw", "\(home)/Library/Application Support/OpenClaw", "\(home)/Library/Preferences/openclaw.plist"]
            )
        }
        if id.contains("agent.hermes") || name.contains("hermes") || bundle.contains("hermes") {
            return candidates(
                install: ["/Applications/Hermes.app", "\(home)/Applications/Hermes.app"],
                cache: ["\(home)/Library/Caches/Hermes", "\(home)/Library/Caches/hermes"],
                data: ["\(home)/.hermes", "\(home)/Library/Application Support/Hermes", "\(home)/Library/Preferences/hermes.plist"]
            )
        }

        return candidates(install: standard.install, cache: standard.cache, data: standard.data)
    }

    func basicUninstall(app: AppInfo) async -> Bool {
        do {
            let paths = managedPaths(for: app, action: .basicUninstall)
            guard !paths.isEmpty else { return false }
            for path in paths { try moveToTrash(atPath: path) }
            return true
        } catch {
            errorMessage = "\(localizer?.uninstallFailed ?? "Uninstall failed"): \(error.localizedDescription)"
            return false
        }
    }

    func fullUninstall(app: AppInfo) async -> Bool {
        do {
            let paths = managedPaths(for: app, action: .fullUninstall)
            guard !paths.isEmpty else { return false }
            for path in paths { try moveToTrash(atPath: path) }
            return true
        } catch {
            errorMessage = "\(localizer?.uninstallFailed ?? "Uninstall failed"): \(error.localizedDescription)"
            return false
        }
    }

    func resetApp(app: AppInfo) async -> Bool {
        do {
            let paths = managedPaths(for: app, action: .reset)
            guard !paths.isEmpty else { return false }
            for path in paths { try moveToTrash(atPath: path) }
            return true
        } catch {
            errorMessage = "\(localizer?.resetAction ?? "Reset failed"): \(error.localizedDescription)"
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
        let apiBase = (config.apiBase ?? "https://api.openai.com").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(apiBase)/v1/chat/completions"

        guard let url = URL(string: urlString) else {
            return (success: false, items: nil, error: localizer?.invalidAPIUrl ?? "❌ Invalid API URL")
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
            "model": config.model ?? "gpt-4o-mini",
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
                return (success: false, items: nil, error: localizer?.invalidHttpResponse ?? "❌ Invalid HTTP response")
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
                return (success: false, items: nil, error: localizer?.aiModelFormatError ?? "❌ AI model response format error")
            }

            var content = message["content"] as? String ?? ""
            let reasoningContent = message["reasoning_content"] as? String ?? ""

            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let retryBody: [String: Any] = [
                        "model": config.model ?? "gpt-4o-mini",
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
            let logPath = SandboxPaths.shared.lastResponsePath
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
            let path = (item["path"] as? String ?? "").replacingOccurrences(of: "~", with: SandboxPaths.realHomeDirectory)
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
