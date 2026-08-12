import SwiftUI
import Foundation
import QuickLookUI

enum DiskAdvisorRecommendation: String, Codable, CaseIterable, Sendable {
    case clean
    case review
    case keep

    func label(_ localizer: Localizer) -> String {
        switch self {
        case .clean: return localizer.t("建议清理", en: "Clean")
        case .review: return localizer.t("需要确认", en: "Review")
        case .keep: return localizer.t("建议保留", en: "Keep")
        }
    }

    var color: Color {
        switch self {
        case .clean: return Theme.Colors.success
        case .review: return Theme.Colors.warning
        case .keep: return Theme.Colors.textSecondary
        }
    }
}

enum DiskAdvisorRisk: String, Codable, CaseIterable, Sendable {
    case safe
    case caution
    case danger
    case unknown

    func label(_ localizer: Localizer) -> String {
        switch self {
        case .safe: return localizer.riskSafe
        case .caution: return localizer.riskCaution
        case .danger: return localizer.riskDangerous
        case .unknown: return localizer.t("未知", en: "Unknown")
        }
    }

    var color: Color {
        switch self {
        case .safe: return Theme.Colors.success
        case .caution: return Theme.Colors.warning
        case .danger: return Theme.Colors.danger
        case .unknown: return Theme.Colors.textSecondary
        }
    }
}

enum DiskAdvisorRationale: String, Codable, Sendable, CaseIterable {
    case credentials
    case personalFiles
    case projectData
    case aiAgentData
    case agentDuplicateMedia
    case hiddenAppData
    case simulatorDevices
    case simulatorDyldCache
    case temporaryFiles
    case generatedTaskData
    case generatedMedia
    case appUpdateCache
    case xcodeArchives
    case cacheOrLogs
    case buildArtifact
    case historicalBuild
    case installerArtifact
    case downloadArchive
    case unknownLargeItem
}

struct DiskAdvisorCandidate: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let path: String
    let size: Int64
    let fileCount: Int
    let isDirectory: Bool
    let modifiedDate: Date?
    let category: String
    let localHint: String
    var recommendation: DiskAdvisorRecommendation
    var risk: DiskAdvisorRisk
    var reason: String
    var impact: String
    var confidence: Double
    var source: String
    var analyzedAt: Date?
    var rationale: DiskAdvisorRationale?

    var displayPath: String {
        path.replacingOccurrences(of: SandboxPaths.realHomeDirectory, with: "~")
    }

    var isAISafeClean: Bool {
        recommendation == .clean && risk == .safe
    }
}

private struct DiskAdvisorLLMResult: Codable {
    let id: String
    let recommendation: DiskAdvisorRecommendation?
    let risk: DiskAdvisorRisk?
    let reason: String?
    let impact: String?
    let confidence: Double?
}

@MainActor
final class DiskAdvisorLabStore: ObservableObject {
    static let shared = DiskAdvisorLabStore()

    @Published var candidates: [DiskAdvisorCandidate] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var isAnalyzing = false
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var cleanedSize: Int64 = 0
    @Published var cleanedCount = 0
    @Published var optimizationSummary: StorageOptimizationSummary?
    @Published var fileInventory: [DiskFileRecord] = [] {
        didSet { rebuildFileInventoryIndexes() }
    }
    @Published var fileInventorySummary: DiskFileInventorySummary?
    @Published var selectedFileIDs: Set<String> = []
    @Published private(set) var hasCompletedScan = false

    private struct FileActivityStats {
        var count = 0
        var bytes: Int64 = 0
    }

    private struct InventoryFilterKey: Equatable {
        let inventoryRevision: Int
        let query: String
        let category: DiskFileCategory?
        let ageFilter: DiskFileAgeFilter
        let sort: DiskFileSort
        let dayBucket: Int
    }

    // Keep only an index into the canonical inventory. Storing every path-rich
    // record a second time in a dictionary made consecutive scans briefly retain
    // both complete generations and substantially raised the memory peak.
    private var fileIndexByID: [String: Int] = [:]
    private var activityStats: [DiskFileActivityMarker: FileActivityStats] = [:]
    private var inventoryRevision = 0
    private var inventoryFilterKey: InventoryFilterKey?
    private var inventoryFilterResults: [DiskFileRecord] = []
    private var activityStatsDayBucket = 0

    var selectedCandidates: [DiskAdvisorCandidate] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    var selectedSize: Int64 {
        selectedCandidates.reduce(Int64(0)) { $0 + $1.size }
    }

    var suggestedCleanSize: Int64 {
        candidates.filter(\.isAISafeClean).reduce(Int64(0)) { $0 + $1.size }
    }

    var suggestedCleanCount: Int {
        candidates.filter(\.isAISafeClean).count
    }

    var selectedFiles: [DiskFileRecord] {
        selectedFileIDs.compactMap { id in
            guard let index = fileIndexByID[id], fileInventory.indices.contains(index) else { return nil }
            return fileInventory[index]
        }
    }

    var selectedFileSize: Int64 {
        selectedFileIDs.reduce(Int64(0)) { total, id in
            guard let index = fileIndexByID[id], fileInventory.indices.contains(index) else { return total }
            return total + fileInventory[index].size
        }
    }

    fileprivate func filteredInventoryFiles(
        query rawQuery: String,
        category: DiskFileCategory?,
        ageFilter: DiskFileAgeFilter,
        sort: DiskFileSort,
        now: Date
    ) -> [DiskFileRecord] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let key = InventoryFilterKey(
            inventoryRevision: inventoryRevision,
            query: query,
            category: category,
            ageFilter: ageFilter,
            sort: sort,
            dayBucket: Int(now.timeIntervalSince1970 / 86_400)
        )
        if inventoryFilterKey == key { return inventoryFilterResults }

        var files = fileInventory.filter { file in
            let matchesCategory = category == nil || file.category == category
            let matchesAge = ageFilter.includes(file.activityMarker(at: now))
            let matchesSearch = query.isEmpty
                || file.name.lowercased().contains(query)
                || file.path.lowercased().contains(query)
                || file.fileExtension.lowercased().contains(query)
            return matchesCategory && matchesAge && matchesSearch
        }
        switch sort {
        case .sizeDescending:
            break
        case .oldestActivity:
            files.sort { ($0.lastActivityDate ?? .distantPast) < ($1.lastActivityDate ?? .distantPast) }
        case .newestActivity:
            files.sort { ($0.lastActivityDate ?? .distantPast) > ($1.lastActivityDate ?? .distantPast) }
        case .name:
            files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        inventoryFilterKey = key
        inventoryFilterResults = files
        return files
    }

    func inactiveFileStats(minimumDays: Int) -> (count: Int, bytes: Int64) {
        rebuildActivityStatsIfNeeded()
        let markers: [DiskFileActivityMarker]
        switch minimumDays {
        case 90...:
            markers = [.days90]
        case 30...:
            markers = [.days30, .days90]
        case 7...:
            markers = [.days7, .days30, .days90]
        default:
            markers = [.recent, .days7, .days30, .days90]
        }
        return markers.reduce(into: (count: 0, bytes: Int64(0))) { total, marker in
            let stats = activityStats[marker] ?? FileActivityStats()
            total.count += stats.count
            total.bytes += stats.bytes
        }
    }

    private func rebuildFileInventoryIndexes() {
        inventoryRevision &+= 1
        inventoryFilterKey = nil
        inventoryFilterResults.removeAll(keepingCapacity: false)
        fileIndexByID.removeAll(keepingCapacity: false)
        fileIndexByID.reserveCapacity(fileInventory.count)
        for (index, file) in fileInventory.enumerated() {
            fileIndexByID[file.id] = index
        }
        rebuildActivityStats()
    }

    private func rebuildActivityStatsIfNeeded() {
        let dayBucket = Int(Date().timeIntervalSince1970 / 86_400)
        if activityStatsDayBucket != dayBucket { rebuildActivityStats() }
    }

    private func rebuildActivityStats() {
        let now = Date()
        activityStatsDayBucket = Int(now.timeIntervalSince1970 / 86_400)
        activityStats = fileInventory.reduce(into: [:]) { result, file in
            let marker = file.activityMarker(at: now)
            var stats = result[marker] ?? FileActivityStats()
            stats.count += 1
            stats.bytes += file.size
            result[marker] = stats
        }
    }

    func scan(authorizedRoots: Set<String>? = nil, localizer: Localizer) async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        statusMessage = localizer.t("正在盘点常见缓存和大型目录...", en: "Inventorying common caches and large folders...")
        defer { isScanning = false }

        let roots = authorizedRoots
        let genericCandidates = await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                DiskAdvisorScanner.scan(authorizedRoots: roots)
            }
        }.value

        statusMessage = localizer.t(
            "正在分析 Agent 会话重复媒体和历史构建；首次扫描会读取原始文件，之后使用指纹缓存...",
            en: "Analyzing duplicate Agent media and build history. The first scan reads source files; later scans use the fingerprint cache..."
        )
        let home = SandboxPaths.realHomeDirectory
        let cacheURL = URL(fileURLWithPath: SandboxPaths.shared.storageOptimizerCachePath)
        let optimization = await Task.detached(priority: .utility) {
            autoreleasepool {
                StorageOptimizationCore.scan(
                    homeDirectory: home,
                    authorizedRoots: roots,
                    isSandboxed: SandboxPaths.isSandboxed,
                    cacheURL: cacheURL,
                    retainBuildCount: 3
                )
            }
        }.value

        statusMessage = localizer.t(
            "正在建立文件分类并读取最后打开、访问和修改时间...",
            en: "Building the file inventory and reading last-opened, accessed, and modified dates..."
        )
        let inventoryCacheURL = URL(fileURLWithPath: SandboxPaths.shared.diskFileInventoryCachePath)
        let inventory = await Task.detached(priority: .utility) {
            autoreleasepool {
                DiskFileInventoryCore.scan(
                    homeDirectory: home,
                    authorizedRoots: roots,
                    isSandboxed: SandboxPaths.isSandboxed,
                    cacheURL: inventoryCacheURL
                )
            }
        }.value
        let found = merge(genericCandidates: genericCandidates, optimization: optimization)

        candidates = found
        optimizationSummary = optimization.summary
        fileInventory = inventory.files
        fileInventorySummary = inventory.summary
        hasCompletedScan = true
        selectedIDs.removeAll()
        selectedFileIDs.removeAll()
        let fingerprintedSize = ByteCountFormatter.string(
            fromByteCount: optimization.summary.fingerprintedBytes,
            countStyle: .file
        )
        let inventoryNote = localizer.t(
            "文件索引 \(inventory.summary.returnedFileCount) 项，元数据缓存命中 \(inventory.summary.cacheHitCount) 项",
            en: "\(inventory.summary.returnedFileCount) files indexed with \(inventory.summary.cacheHitCount) metadata cache hits"
        )
        if found.isEmpty {
            statusMessage = localizer.t(
                "扫描完成，没有发现目录级清理候选；\(inventoryNote)。Agent 原始会话未修改。",
                en: "Scan complete. No directory-level cleanup candidates were found; \(inventoryNote). Original Agent sessions were not modified."
            )
        } else {
            statusMessage = localizer.t(
                "扫描完成：\(found.count) 个候选；\(inventoryNote)；Agent 指纹缓存命中 \(optimization.summary.cacheHitCount) 个，本次增量读取 \(optimization.summary.hashedFileCount) 个 / \(fingerprintedSize)。原始会话未修改。",
                en: "Scan complete: \(found.count) candidates; \(inventoryNote); \(optimization.summary.cacheHitCount) Agent fingerprint cache hits and \(optimization.summary.hashedFileCount) files / \(fingerprintedSize) read incrementally. Original sessions were not modified."
            )
        }
    }

    private func merge(
        genericCandidates: [DiskAdvisorCandidate],
        optimization: StorageOptimizationScanResult
    ) -> [DiskAdvisorCandidate] {
        let specialized = optimization.cleanupItems.map { item -> DiskAdvisorCandidate in
            let rationale: DiskAdvisorRationale = item.kind == .historicalBuild
                ? .historicalBuild
                : .installerArtifact
            return DiskAdvisorCandidate(
                id: item.path,
                name: item.name,
                path: item.path,
                size: item.size,
                fileCount: item.fileCount,
                isDirectory: item.isDirectory,
                modifiedDate: item.modifiedDate,
                category: item.kind == .historicalBuild ? "Historical Build" : "Installer Artifact",
                localHint: rationale.rawValue,
                recommendation: .review,
                risk: .caution,
                reason: item.detail,
                impact: "",
                confidence: item.kind == .historicalBuild ? 0.94 : 0.97,
                source: "TraceFence Storage",
                analyzedAt: optimization.summary.completedAt,
                rationale: rationale
            )
        }

        let specializedPaths = specialized.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }
        let filteredGeneric = genericCandidates.filter { candidate in
            let path = URL(fileURLWithPath: candidate.path).standardizedFileURL.path
            return !specializedPaths.contains { specializedPath in
                path == specializedPath
                    || specializedPath.hasPrefix(path + "/")
                    || path.hasPrefix(specializedPath + "/")
            }
        }
        var seen = Set<String>()
        return (specialized + filteredGeneric)
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.size > $1.size }
    }

    func analyze(config: AIConfig?, localizer: Localizer) async {
        guard !isAnalyzing else { return }
        if candidates.isEmpty {
            await scan(localizer: localizer)
        }
        guard !candidates.isEmpty else { return }

        isAnalyzing = true
        errorMessage = nil
        statusMessage = localizer.t("正在调用 AI 生成清理建议...", en: "Asking AI for cleanup recommendations...")
        defer { isAnalyzing = false }

        do {
            let response = try await DiskAdvisorAIClient.analyze(candidates: Array(candidates.prefix(60)), config: config)
            apply(results: response.results, source: response.source, localizer: localizer)
            statusMessage = localizer.t("AI 已完成分析。", en: "AI analysis complete.")
        } catch {
            let nsError = error as NSError
            statusMessage = localizer.t("AI 分析失败，已保留本地规则建议。", en: "AI analysis failed; local rule suggestions are still available.")
            if nsError.domain == "DiskAdvisor", nsError.code == 5 {
                statusMessage = localizer.t("AI 返回格式不完整，已保留本地规则建议。", en: "AI returned an incomplete format; local rule suggestions are still available.")
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectSuggestedClean() {
        selectedIDs = Set(candidates.filter(\.isAISafeClean).map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func clearFileSelection() {
        selectedFileIDs.removeAll()
    }

    func removeCleaned(ids: Set<String>, cleanedSize: Int64) {
        candidates.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        self.cleanedSize = cleanedSize
        cleanedCount = ids.count
    }

    func removeCleanedFiles(ids: Set<String>, cleanedSize: Int64) {
        let removedFiles = fileInventory.filter { ids.contains($0.id) }
        let removedCount = removedFiles.count
        fileInventory.removeAll { ids.contains($0.id) }
        selectedFileIDs.subtract(ids)
        self.cleanedSize = cleanedSize
        cleanedCount = removedCount
        if let summary = fileInventorySummary {
            let removedByCategory = Dictionary(grouping: removedFiles, by: \.category)
                .mapValues { files in
                    (count: files.count, bytes: files.reduce(Int64(0)) { $0 + $1.size })
                }
            let breakdown = summary.categoryBreakdown.compactMap { item -> DiskFileCategoryBreakdown? in
                let removed = removedByCategory[item.category] ?? (count: 0, bytes: 0)
                let count = max(item.fileCount - removed.count, 0)
                let bytes = max(item.totalBytes - removed.bytes, 0)
                guard count > 0 else { return nil }
                return DiskFileCategoryBreakdown(
                    category: item.category,
                    fileCount: count,
                    totalBytes: bytes
                )
            }
                .sorted { $0.totalBytes > $1.totalBytes }
            fileInventorySummary = DiskFileInventorySummary(
                eligibleFileCount: max(summary.eligibleFileCount - removedCount, 0),
                eligibleBytes: max(summary.eligibleBytes - cleanedSize, 0),
                returnedFileCount: fileInventory.count,
                returnedBytes: fileInventory.reduce(Int64(0)) { $0 + $1.size },
                visitedEntryCount: summary.visitedEntryCount,
                cacheHitCount: summary.cacheHitCount,
                metadataReadCount: summary.metadataReadCount,
                unreadableEntryCount: summary.unreadableEntryCount,
                wasTruncated: summary.wasTruncated,
                minimumFileSize: summary.minimumFileSize,
                scanDuration: summary.scanDuration,
                completedAt: summary.completedAt,
                categoryBreakdown: breakdown
            )
        }
    }

    private func apply(results: [DiskAdvisorLLMResult], source: String, localizer: Localizer) {
        let mapped = results.reduce(into: [String: DiskAdvisorLLMResult]()) { partial, result in
            partial[result.id] = result
        }
        let now = Date()
        candidates = candidates.map { item in
            var updated = item
            guard let result = mapped[item.id] else { return updated }
            let requiresManualSelection = item.category == "Historical Build"
                || item.category == "Installer Artifact"
            if !requiresManualSelection, let recommendation = result.recommendation {
                updated.recommendation = recommendation
            }
            if !requiresManualSelection, let risk = result.risk {
                updated.risk = risk
            }
            let reason = result.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            let impact = result.impact?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasReason = reason?.isEmpty == false
            let hasImpact = impact?.isEmpty == false
            if !requiresManualSelection, hasReason || hasImpact {
                updated.rationale = nil
                updated.reason = hasReason ? (reason ?? "") : ""
                updated.impact = hasImpact ? (impact ?? "") : ""
            }
            updated.confidence = min(max(result.confidence ?? updated.confidence, 0), 1)
            updated.source = source
            updated.analyzedAt = now
            return updated
        }
    }
}

private enum DiskAdvisorSection: String, CaseIterable {
    case cleanup
    case files
}

private enum DiskFileAgeFilter: String, CaseIterable {
    case all
    case days7
    case days30
    case days90
    case unknown

    func includes(_ marker: DiskFileActivityMarker) -> Bool {
        switch self {
        case .all:
            return true
        case .days7:
            return marker == .days7 || marker == .days30 || marker == .days90
        case .days30:
            return marker == .days30 || marker == .days90
        case .days90:
            return marker == .days90
        case .unknown:
            return marker == .unknown
        }
    }
}

private enum DiskFileSort: String, CaseIterable {
    case sizeDescending
    case oldestActivity
    case newestActivity
    case name
}

private enum DiskAdvisorDeleteScope {
    case cleanupCandidates
    case inventoryFiles
}

private enum DiskCleanupCandidateFilter: String, CaseIterable {
    case all
    case installerArtifact
    case historicalBuild

    var category: String? {
        switch self {
        case .all: return nil
        case .installerArtifact: return "Installer Artifact"
        case .historicalBuild: return "Historical Build"
        }
    }
}

private enum DiskAdvisorScrollTarget: Hashable {
    case cleanupCandidates
}

struct DiskAdvisorLabView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @StateObject private var store = DiskAdvisorLabStore.shared
    @StateObject private var licenseService = DirectLicenseService.shared
    @State private var searchText = ""
    @State private var inventorySearchText = ""
    @State private var inventorySearchTask: Task<Void, Never>?
    @State private var showAISettings = false
    @State private var showSubscriptionSettings = false
    @State private var showDeleteConfirm = false
    @State private var showExternalAIConsent = false
    @State private var showCleanResult = false
    @State private var paywallMessage = ""
    @State private var section: DiskAdvisorSection = .cleanup
    @State private var selectedFileCategory: DiskFileCategory?
    @State private var fileAgeFilter: DiskFileAgeFilter = .all
    @State private var fileSort: DiskFileSort = .sizeDescending
    @State private var inventoryVisibleLimit = 300
    @State private var previewFile: DiskFileRecord?
    @State private var deleteScope: DiskAdvisorDeleteScope = .cleanupCandidates
    @State private var cleanupCandidateFilter: DiskCleanupCandidateFilter = .all
    @State private var cleanupCandidateFocusRequest = 0
    @State private var showDuplicateMediaInfo = false

    private var filteredCandidates: [DiskAdvisorCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let categoryFiltered = store.candidates.filter { candidate in
            guard let category = cleanupCandidateFilter.category else { return true }
            return candidate.category == category
        }
        guard !query.isEmpty else { return categoryFiltered }
        return categoryFiltered.filter {
            $0.name.lowercased().contains(query)
                || $0.displayPath.lowercased().contains(query)
                || $0.category.lowercased().contains(query)
                || displayReason(for: $0).lowercased().contains(query)
        }
    }

    private var filteredInventoryFiles: [DiskFileRecord] {
        store.filteredInventoryFiles(
            query: inventorySearchText,
            category: selectedFileCategory,
            ageFilter: fileAgeFilter,
            sort: fileSort,
            now: Date()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: section == .files ? "doc.text.magnifyingglass" : "sparkles",
                title: localizer.t("磁盘分析与清理", en: "Disk Analysis & Cleanup"),
                subtitle: section == .files
                    ? localizer.t("按格式、大小和最后活动时间分析用户文件", en: "Analyze user files by type, size, and last activity")
                    : (SandboxPaths.isSandboxed
                        ? localizer.t("扫描用户授权目录，并用 AI 判断可清理项", en: "Scan user-authorized folders and review cleanup candidates with AI")
                        : localizer.t("用 Apple Intelligence 或自定义模型判断可清理项", en: "Use Apple Intelligence or your model to review cleanup candidates")),
                color: Theme.Colors.purple
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    if section == .cleanup {
                        Button {
                            showAISettings = true
                        } label: {
                            Label(localizer.t("AI 设置", en: "AI Settings"), systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .secondary, minHeight: 34))
                    }

                    Button {
                        Task { await scanWithAuthorization(promptForAccess: true) }
                    } label: {
                        Label(store.isScanning ? localizer.tokenScopeScanning : scanButtonTitle, systemImage: "magnifyingglass")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 34))
                    .disabled(store.isScanning || store.isAnalyzing)

                    if section == .cleanup {
                        Button {
                            requestAIAnalysis()
                        } label: {
                            Label(store.isAnalyzing ? localizer.t("分析中", en: "Analyzing") : localizer.t("AI 分析", en: "AI Analyze"), systemImage: "sparkles")
                        }
                        .buttonStyle(BrandButtonStyle(color: Theme.Colors.purple, variant: .primary, minHeight: 34))
                        .disabled(store.isScanning || store.isAnalyzing)
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        statusStrip
                        sectionSelector
                        if section == .cleanup {
                            if let summary = store.optimizationSummary {
                                storageOptimizationOverview(summary)
                            }
                            summaryGrid
                            actionBar
                                .id(DiskAdvisorScrollTarget.cleanupCandidates)
                            candidateList
                        } else {
                            if let summary = store.fileInventorySummary {
                                fileInventoryOverview(summary)
                            }
                            fileInventoryContent
                        }
                    }
                    .padding(Theme.Spacing.xl)
                }
                .onChange(of: cleanupCandidateFocusRequest) { _ in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(DiskAdvisorScrollTarget.cleanupCandidates, anchor: .top)
                    }
                }
            }
        }
        .sheet(isPresented: $showAISettings) {
            AIConfigView()
                .environmentObject(service)
                .environmentObject(localizer)
        }
        .sheet(isPresented: $showSubscriptionSettings) {
            SettingsView(initialTab: .license)
                .environmentObject(service)
                .environmentObject(localizer)
                .environmentObject(licenseService)
        }
        .alert(localizer.t("需要 TraceFence Standard", en: "TraceFence Standard required"), isPresented: Binding(
            get: { !paywallMessage.isEmpty },
            set: { if !$0 { paywallMessage = "" } }
        )) {
            if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                Button(localizer.t("管理订阅", en: "Manage Subscription")) {
                    showSubscriptionSettings = true
                    paywallMessage = ""
                }
            } else {
                Button(localizer.t("订阅 Standard", en: "Subscribe Standard")) {
                    licenseService.openPurchasePage()
                    paywallMessage = ""
                }
            }
            Button(localizer.cancelBtn, role: .cancel) {
                paywallMessage = ""
            }
        } message: {
            Text(paywallMessage)
        }
        .alert(localizer.confirmDelete, isPresented: $showDeleteConfirm) {
            Button(localizer.cancelBtn, role: .cancel) {}
            Button(localizer.deleteBtn, role: .destructive) {
                performDelete()
            }
        } message: {
            Text(localizer.t(
                "将 \(pendingDeleteCount) 个项目移到废纸篓，预计释放 \(service.formatSize(pendingDeleteSize))。请确认这些项目不再需要。",
                en: "Move \(pendingDeleteCount) items to Trash, estimated \(service.formatSize(pendingDeleteSize)). Confirm these items are no longer needed."
            ))
        }
        .alert(localizer.t("提示", en: "Notice"), isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button(localizer.ok, role: .cancel) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert(localizer.t("确认发送元数据", en: "Confirm Metadata Sharing"), isPresented: $showExternalAIConsent) {
            Button(localizer.cancelBtn, role: .cancel) {}
            Button(localizer.t("继续分析", en: "Continue")) {
                Task { await analyzeWithCurrentModel() }
            }
        } message: {
            Text(localizer.t(
                "如果需要使用第三方模型，TraceFence 会把候选项的路径、名称、大小、文件数、修改时间和本地规则提示发送到你配置的外部模型服务。不发送文件内容。",
                en: "If an external model is needed, TraceFence will send candidate paths, names, sizes, file counts, modification dates, and local rule hints to your configured external model provider. File contents are not sent."
            ))
        }
        .alert(localizer.t("重复媒体不能直接删除", en: "Duplicate Media Cannot Be Deleted In Place"), isPresented: $showDuplicateMediaInfo) {
            Button(localizer.ok, role: .cancel) {}
        } message: {
            Text(localizer.t(
                "这些重复图片、视频和音频是嵌在 Agent 会话文件里的内容，不是独立副本。直接删除会破坏原始对话。安全清理必须先把已结束的旧会话做成可还原冷归档，逐字节校验恢复结果后，才能把原会话移到废纸篓；当前版本只分析，不会改写或删除会话。",
                en: "These duplicate images, videos, and audio clips are embedded inside Agent session files rather than stored as independent copies. Deleting bytes in place would corrupt the original conversations. Safe cleanup requires a restorable cold archive for closed, inactive sessions and byte-for-byte restore verification before originals can be moved to Trash. This version analyzes only and never rewrites or deletes sessions."
            ))
        }
        .sheet(isPresented: $showCleanResult) {
            cleanResultSheet
        }
        .sheet(item: $previewFile) { file in
            diskFilePreviewSheet(file)
        }
        .onAppear {
            licenseService.refreshTrialState()
            if !store.hasCompletedScan, !store.isScanning {
                Task { await scanWithAuthorization(promptForAccess: false) }
            }
        }
        .onChange(of: searchText) { value in
            guard section == .files else { return }
            inventoryVisibleLimit = 300
            inventorySearchTask?.cancel()
            inventorySearchTask = Task {
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                inventorySearchText = value
            }
        }
        .onDisappear {
            inventorySearchTask?.cancel()
        }
    }

    private var statusStrip: some View {
        CardView(padding: Theme.Spacing.lg, cornerRadius: Theme.Radius.lg) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    if diskAdvisorIsBusy {
                        RadarScanGlyph(color: diskAdvisorActivityColor)
                            .scaleEffect(1.35)
                    } else {
                        Circle()
                            .fill(Theme.Colors.purple.opacity(0.12))
                        Image(systemName: section == .files ? "doc.text.magnifyingglass" : "brain.head.profile")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Colors.purple)
                    }
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(section == .files
                        ? localizer.t("本地文件元数据分析", en: "Local File Metadata Analysis")
                        : activeModelText)
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(store.statusMessage.isEmpty ? AppleIntelligenceService.availabilitySummary() : store.statusMessage)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if diskAdvisorIsBusy {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                        ScanningStatusPill(title: diskAdvisorActivityTitle, color: diskAdvisorActivityColor)
                        ScanningProgressCaption(detail: diskAdvisorActivityDetail, color: diskAdvisorActivityColor)
                    }
                    .frame(minWidth: 220, maxWidth: 340, alignment: .trailing)
                }
            }
        }
    }

    private var sectionSelector: some View {
        CardView(padding: 6, cornerRadius: Theme.Radius.lg, showShadow: false) {
            HStack(spacing: 6) {
                sectionButton(
                    .cleanup,
                    title: localizer.t("清理建议", en: "Cleanup Advice"),
                    icon: "sparkles"
                )
                sectionButton(
                    .files,
                    title: localizer.t("文件分析", en: "File Analysis"),
                    icon: "doc.text.magnifyingglass"
                )
            }
        }
    }

    private func sectionButton(_ target: DiskAdvisorSection, title: String, icon: String) -> some View {
        Button {
            section = target
            searchText = ""
            inventorySearchText = ""
            inventorySearchTask?.cancel()
            inventoryVisibleLimit = 300
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.Font.subheadlineMedium)
                .foregroundStyle(section == target ? Color.white : Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(section == target ? Theme.Colors.purple : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func fileInventoryOverview(_ summary: DiskFileInventorySummary) -> some View {
        let inactive90 = inventoryStats(minimumDays: 90)
        return CardView(padding: Theme.Spacing.lg, cornerRadius: Theme.Radius.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.info)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizer.t("文件活动分析", en: "File Activity Analysis"))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.t(
                            "活动时间取最后打开、文件系统访问和修改时间中的最新值；只读取元数据，不读取文件内容。",
                            en: "Activity uses the newest last-opened, filesystem-accessed, or modified date. Only metadata is read, never file contents."
                        ))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Text(shortDateTime(summary.completedAt))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Divider().overlay(Theme.Colors.separator)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 4),
                    spacing: Theme.Spacing.md
                ) {
                    optimizationMetric(
                        icon: "doc.on.doc.fill",
                        color: Theme.Colors.info,
                        title: localizer.t("已索引文件", en: "Indexed Files"),
                        value: "\(summary.returnedFileCount)",
                        subtitle: service.formatSize(summary.returnedBytes)
                    )
                    optimizationMetric(
                        icon: "calendar.badge.exclamationmark",
                        color: Theme.Colors.warning,
                        title: localizer.t("90 天未活动", en: "Inactive 90+ Days"),
                        value: "\(inactive90.count)",
                        subtitle: service.formatSize(inactive90.bytes)
                    )
                    optimizationMetric(
                        icon: "bolt.horizontal.circle.fill",
                        color: Theme.Colors.success,
                        title: localizer.t("元数据缓存", en: "Metadata Cache"),
                        value: "\(summary.cacheHitCount)",
                        subtitle: localizer.t("本次命中", en: "hits this scan")
                    )
                    optimizationMetric(
                        icon: "timer",
                        color: Theme.Colors.purple,
                        title: localizer.t("扫描耗时", en: "Scan Time"),
                        value: formatDuration(summary.scanDuration),
                        subtitle: localizer.t("访问 \(summary.visitedEntryCount) 项", en: "\(summary.visitedEntryCount) entries visited")
                    )
                }

                if !summary.categoryBreakdown.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(summary.categoryBreakdown, id: \.category) { item in
                                Button {
                                    selectedFileCategory = selectedFileCategory == item.category ? nil : item.category
                                    inventoryVisibleLimit = 300
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: fileCategoryIcon(item.category))
                                        Text(fileCategoryLabel(item.category))
                                        Text("\(item.fileCount)")
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                        Text(service.formatSize(item.totalBytes))
                                            .fontWeight(.semibold)
                                    }
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(selectedFileCategory == item.category ? Color.white : fileCategoryColor(item.category))
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .padding(.vertical, 7)
                                    .background(selectedFileCategory == item.category ? fileCategoryColor(item.category) : fileCategoryColor(item.category).opacity(0.08))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "scope")
                        .foregroundStyle(Theme.Colors.info)
                    Text(localizer.t(
                        "为聚焦可释放空间，文件清单只索引 \(service.formatSize(summary.minimumFileSize)) 以上的普通文件；隐藏文件、Agent 历史、系统目录、依赖缓存和符号链接不会列入。",
                        en: "To focus on reclaimable space, the inventory includes regular files of at least \(service.formatSize(summary.minimumFileSize)). Hidden files, Agent history, system folders, dependency caches, and symbolic links are excluded."
                    ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }

                if summary.wasTruncated || summary.unreadableEntryCount > 0 {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Theme.Colors.warning)
                        Text(inventoryCoverageMessage(summary))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
    }

    private var fileInventoryContent: some View {
        let filtered = filteredInventoryFiles
        let visible = Array(filtered.prefix(inventoryVisibleLimit))
        return VStack(spacing: Theme.Spacing.md) {
            fileInventoryActionBar(filtered: filtered, visible: visible)
            fileInventoryList(filtered: filtered, visible: visible)
        }
    }

    private func fileInventoryActionBar(
        filtered: [DiskFileRecord],
        visible: [DiskFileRecord]
    ) -> some View {
        CardView(padding: Theme.Spacing.md, cornerRadius: Theme.Radius.lg, showShadow: false) {
            VStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    FilterSearchBar(
                        placeholder: localizer.t("搜索文件名、路径或扩展名", en: "Search name, path, or extension"),
                        text: $searchText
                    )
                    .frame(maxWidth: 360)

                    inventoryFilterMenu(
                        title: selectedFileCategory.map(fileCategoryLabel) ?? localizer.t("全部格式", en: "All Types"),
                        icon: "square.grid.2x2"
                    ) {
                        Button(localizer.t("全部格式", en: "All Types")) {
                            selectedFileCategory = nil
                            inventoryVisibleLimit = 300
                        }
                        ForEach(DiskFileCategory.allCases, id: \.self) { category in
                            Button(fileCategoryLabel(category)) {
                                selectedFileCategory = category
                                inventoryVisibleLimit = 300
                            }
                        }
                    }

                    inventoryFilterMenu(title: fileAgeFilterLabel(fileAgeFilter), icon: "calendar") {
                        ForEach(DiskFileAgeFilter.allCases, id: \.self) { filter in
                            Button(fileAgeFilterLabel(filter)) {
                                fileAgeFilter = filter
                                inventoryVisibleLimit = 300
                            }
                        }
                    }

                    inventoryFilterMenu(title: fileSortLabel(fileSort), icon: "arrow.up.arrow.down") {
                        ForEach(DiskFileSort.allCases, id: \.self) { sort in
                            Button(fileSortLabel(sort)) {
                                fileSort = sort
                                inventoryVisibleLimit = 300
                            }
                        }
                    }

                    Spacer()
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Text(localizer.t(
                        "筛选结果 \(filtered.count) 项 · 已显示 \(visible.count) 项",
                        en: "\(filtered.count) results · \(visible.count) shown"
                    ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                    Spacer()

                    Button {
                        store.selectedFileIDs.formUnion(visible.map(\.id))
                    } label: {
                        Label(localizer.t("选择当前页", en: "Select Page"), systemImage: "checkmark.square")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 32))
                    .disabled(visible.isEmpty)

                    Button {
                        store.clearFileSelection()
                    } label: {
                        Label(localizer.t("清空选择", en: "Clear"), systemImage: "xmark.circle")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 32))
                    .disabled(store.selectedFileIDs.isEmpty)

                    Button {
                        deleteScope = .inventoryFiles
                        confirmDelete()
                    } label: {
                        Label(
                            localizer.t("清理所选 \(store.selectedFileIDs.count)", en: "Clean Selected \(store.selectedFileIDs.count)"),
                            systemImage: "trash"
                        )
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .primary, minHeight: 32))
                    .disabled(store.selectedFileIDs.isEmpty)
                }
            }
        }
    }

    private func inventoryFilterMenu<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu(content: content) {
            Label(title, systemImage: icon)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .stroke(Theme.Colors.separator, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func fileInventoryList(
        filtered: [DiskFileRecord],
        visible: [DiskFileRecord]
    ) -> some View {
        LazyVStack(spacing: Theme.Spacing.md) {
            if visible.isEmpty {
                CardView(padding: Theme.Spacing.xl, cornerRadius: Theme.Radius.lg) {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(localizer.t("没有符合筛选条件的文件", en: "No files match these filters"))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.t("调整格式、未活动时间或搜索条件。", en: "Change the type, inactivity, or search filters."))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(visible) { file in
                    fileInventoryRow(file)
                }

                if visible.count < filtered.count {
                    Button {
                        inventoryVisibleLimit += 300
                    } label: {
                        Label(localizer.t("再显示 300 项", en: "Show 300 More"), systemImage: "chevron.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 38))
                }
            }
        }
    }

    private func fileInventoryRow(_ file: DiskFileRecord) -> some View {
        let marker = file.activityMarker()
        return CardView(padding: Theme.Spacing.lg, cornerRadius: Theme.Radius.lg, showShadow: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Button {
                    if store.selectedFileIDs.contains(file.id) {
                        store.selectedFileIDs.remove(file.id)
                    } else {
                        store.selectedFileIDs.insert(file.id)
                    }
                } label: {
                    Image(systemName: store.selectedFileIDs.contains(file.id) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(store.selectedFileIDs.contains(file.id) ? Theme.Colors.accent : Theme.Colors.textTertiary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)

                Image(systemName: fileCategoryIcon(file.category))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(fileCategoryColor(file.category))
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(file.name)
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        PillBadge(text: fileFormatLabel(file), color: fileCategoryColor(file.category), size: .medium)
                        PillBadge(text: activityMarkerLabel(marker), color: activityMarkerColor(marker), size: .medium)
                        Spacer()
                        Text(service.formatSize(file.size))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Text(fileDisplayPath(file))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: Theme.Spacing.md) {
                        metadataDateLabel(
                            localizer.t("最后打开", en: "Opened"),
                            date: file.lastOpenedDate,
                            icon: "eye"
                        )
                        metadataDateLabel(
                            localizer.t("最后使用/访问", en: "Accessed"),
                            date: file.accessedDate,
                            icon: "hand.point.up.left"
                        )
                        metadataDateLabel(
                            localizer.t("最后修改", en: "Modified"),
                            date: file.modifiedDate,
                            icon: "pencil"
                        )
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }

                VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                    Button {
                        previewFile = file
                    } label: {
                        Label(localizer.t("预览", en: "Preview"), systemImage: "eye")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 30))

                    Button {
                        revealFile(file)
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 30))
                }
            }
        }
    }

    private var diskAdvisorIsBusy: Bool {
        store.isScanning || store.isAnalyzing
    }

    private func storageOptimizationOverview(_ summary: StorageOptimizationSummary) -> some View {
        CardView(padding: Theme.Spacing.lg, cornerRadius: Theme.Radius.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "internaldrive.fill.badge.checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizer.t("Agent 与构建存储优化", en: "Agent & Build Storage Optimization"))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.t(
                            "按内容指纹分析重复媒体；每组构建保留最近 3 次，安装包由用户勾选清理。",
                            en: "Duplicate media is fingerprinted; the newest 3 builds per group are retained, and installers require manual selection."
                        ))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Text(shortDateTime(summary.completedAt))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Divider().overlay(Theme.Colors.separator)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 4), spacing: Theme.Spacing.md) {
                    optimizationMetric(
                        icon: "bubble.left.and.bubble.right.fill",
                        color: Theme.Colors.info,
                        title: localizer.t("Agent 会话", en: "Agent Sessions"),
                        value: service.formatSize(summary.agentSessionBytes),
                        subtitle: localizer.t("\(summary.agentSessionFileCount) 个会话文件", en: "\(summary.agentSessionFileCount) session files")
                    )
                    optimizationMetric(
                        icon: "square.on.square",
                        color: Theme.Colors.purple,
                        title: localizer.t("完全重复媒体", en: "Exact Duplicate Media"),
                        value: service.formatSize(summary.duplicateMediaBytes),
                        subtitle: localizer.t("只分析，不改写原会话", en: "Analyzed only; sessions unchanged"),
                        actionTitle: localizer.t("了解安全清理方式", en: "How safe cleanup works"),
                        actionIcon: "info.circle"
                    ) {
                        showDuplicateMediaInfo = true
                    }
                    optimizationMetric(
                        icon: "hammer.fill",
                        color: Theme.Colors.warning,
                        title: localizer.t("历史构建", en: "Build History"),
                        value: service.formatSize(summary.historicalBuildBytes),
                        subtitle: localizer.t("\(summary.historicalBuildCount) 项；已保留 \(summary.retainedBuildCount) 项", en: "\(summary.historicalBuildCount) items; \(summary.retainedBuildCount) retained")
                    )
                    optimizationMetric(
                        icon: "shippingbox.fill",
                        color: Theme.Colors.success,
                        title: localizer.t("安装与分发包", en: "Installers & Distributions"),
                        value: service.formatSize(summary.installerArtifactBytes),
                        subtitle: localizer.t("\(summary.installerArtifactCount) 项，需手动勾选", en: "\(summary.installerArtifactCount) items; manual selection"),
                        actionTitle: localizer.t("查看并选择 \(summary.installerArtifactCount) 项", en: "Review \(summary.installerArtifactCount) items"),
                        actionIcon: "arrow.down.circle"
                    ) {
                        focusCleanupCandidates(.installerArtifact)
                    }
                }

                if !summary.agentBreakdown.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(Array(summary.agentBreakdown.prefix(8)), id: \.agentName) { agent in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Theme.Colors.info)
                                        .frame(width: 6, height: 6)
                                    Text(agent.agentName)
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(service.formatSize(agent.sessionBytes))
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    if agent.duplicateMediaBytes > 0 {
                                        Text(localizer.t(
                                            "重复 \(service.formatSize(agent.duplicateMediaBytes))",
                                            en: "dup \(service.formatSize(agent.duplicateMediaBytes))"
                                        ))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Theme.Colors.purple)
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 6)
                                .background(Theme.Colors.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Theme.Colors.separator, lineWidth: 1))
                            }
                        }
                    }
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "bolt.horizontal.circle")
                        .foregroundStyle(Theme.Colors.info)
                    Text(localizer.t(
                        "增量缓存：命中 \(summary.cacheHitCount) 个文件，本次读取 \(summary.hashedFileCount) 个 / \(service.formatSize(summary.fingerprintedBytes))，耗时 \(formatDuration(summary.scanDuration))。重复空间是冷归档优化上限，不会直接删除 Agent 历史。",
                        en: "Incremental cache: \(summary.cacheHitCount) hits, \(summary.hashedFileCount) files / \(service.formatSize(summary.fingerprintedBytes)) read in \(formatDuration(summary.scanDuration)). Duplicate bytes are a cold-archive optimization ceiling; Agent history is never deleted directly."
                    ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private func optimizationMetric(
        icon: String,
        color: Color,
        title: String,
        value: String,
        subtitle: String,
        actionTitle: String? = nil,
        actionIcon: String = "arrow.right.circle",
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(Theme.Font.caption)
                .foregroundStyle(color)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private var diskAdvisorActivityColor: Color {
        store.isAnalyzing ? Theme.Colors.purple : Theme.Colors.info
    }

    private var diskAdvisorActivityTitle: String {
        store.isAnalyzing ? localizer.t("分析中", en: "Analyzing") : localizer.t("扫描中", en: "Scanning")
    }

    private var diskAdvisorActivityDetail: String {
        if !store.statusMessage.isEmpty {
            return store.statusMessage
        }
        if store.isAnalyzing {
            return localizer.t("正在把候选项交给 AI 判断清理风险…", en: "Asking AI to review cleanup risk…")
        }
        return localizer.t("正在扫描常见大文件、缓存和构建产物…", en: "Scanning large files, caches, and build artifacts…")
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md)
        ], spacing: Theme.Spacing.md) {
            StatCardView(icon: "internaldrive", iconColor: Theme.Colors.info, title: localizer.t("候选项", en: "Candidates"), value: "\(store.candidates.count)", subtitle: SandboxPaths.isSandboxed ? localizer.t("授权目录", en: "Authorized folders") : localizer.t("有边界扫描", en: "Bounded scan"))
            StatCardView(icon: "sparkles", iconColor: Theme.Colors.purple, title: localizer.t("AI 建议", en: "AI Suggested"), value: "\(store.suggestedCleanCount)", subtitle: service.formatSize(store.suggestedCleanSize))
            StatCardView(icon: "checkmark.circle.fill", iconColor: Theme.Colors.success, title: localizer.t("已勾选", en: "Selected"), value: "\(store.selectedIDs.count)", subtitle: service.formatSize(store.selectedSize))
            StatCardView(icon: "trash", iconColor: Theme.Colors.warning, title: localizer.t("执行方式", en: "Action"), value: localizer.t("废纸篓", en: "Trash"), subtitle: localizer.t("可恢复", en: "Recoverable"))
        }
    }

    private var actionBar: some View {
        CardView(padding: Theme.Spacing.md, cornerRadius: Theme.Radius.lg, showShadow: false) {
            HStack(spacing: Theme.Spacing.md) {
                FilterSearchBar(placeholder: localizer.t("搜索路径、类型或原因", en: "Search path, category, or reason"), text: $searchText)
                    .frame(maxWidth: 360)

                Menu {
                    cleanupCandidateFilterButton(.all)
                    cleanupCandidateFilterButton(.installerArtifact)
                    cleanupCandidateFilterButton(.historicalBuild)
                } label: {
                    Label(cleanupCandidateFilterTitle(cleanupCandidateFilter), systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 34))

                Spacer()

                Button {
                    store.selectSuggestedClean()
                } label: {
                    Label(localizer.t("选择安全建议", en: "Select Safe"), systemImage: "checkmark.circle")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.success, variant: .secondary, minHeight: 34))
                .disabled(store.suggestedCleanCount == 0)

                Button {
                    store.clearSelection()
                } label: {
                    Label(localizer.t("清空选择", en: "Clear"), systemImage: "xmark.circle")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 34))
                .disabled(store.selectedIDs.isEmpty)

                Button {
                    deleteScope = .cleanupCandidates
                    confirmDelete()
                } label: {
                    Label(localizer.t("清理所选", en: "Clean Selected"), systemImage: "trash")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .primary, minHeight: 34))
                .disabled(store.selectedIDs.isEmpty)
            }
        }
    }

    private var candidateList: some View {
        VStack(spacing: Theme.Spacing.md) {
            if filteredCandidates.isEmpty {
                CardView(padding: Theme.Spacing.xl, cornerRadius: Theme.Radius.lg) {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(localizer.t("暂无候选项", en: "No Candidates"))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.t("运行扫描后会显示可分析的磁盘项目。", en: "Run a scan to list disk items for analysis."))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(filteredCandidates) { candidate in
                    candidateRow(candidate)
                }
            }
        }
    }

    private func candidateRow(_ candidate: DiskAdvisorCandidate) -> some View {
        CardView(padding: Theme.Spacing.lg, cornerRadius: Theme.Radius.lg, showShadow: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Button {
                    toggle(candidate)
                } label: {
                    Image(systemName: store.selectedIDs.contains(candidate.id) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(store.selectedIDs.contains(candidate.id) ? Theme.Colors.accent : Theme.Colors.textTertiary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)

                Image(systemName: candidateIcon(for: candidate))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(candidate.recommendation.color)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(candidate.name)
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        PillBadge(text: candidate.recommendation.label(localizer), color: candidate.recommendation.color, size: .medium)
                        PillBadge(text: candidate.risk.label(localizer), color: candidate.risk.color, size: .medium)
                        Spacer()
                        Text(service.formatSize(candidate.size))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Text(candidate.displayPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)

                    Text(displayReason(for: candidate))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Theme.Spacing.sm) {
                        Label(localizedCategory(candidate.category), systemImage: "tag")
                        Label(candidate.source, systemImage: "brain.head.profile")
                        Label(confidenceText(candidate.confidence), systemImage: "gauge.with.dots.needle.67percent")
                        if let modified = candidate.modifiedDate {
                            Label(shortDate(modified), systemImage: "clock")
                        }
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                    let impactText = displayImpact(for: candidate)
                    if !impactText.isEmpty {
                        Text(impactText)
                            .font(Theme.Font.caption)
                            .foregroundStyle(candidate.risk.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var cleanResultSheet: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.success)

            Text(localizer.cleanComplete)
                .font(Theme.Font.title2Bold)
                .foregroundStyle(Theme.Colors.textPrimary)

            CardView(padding: Theme.Spacing.xl, cornerRadius: Theme.Radius.lg) {
                VStack(spacing: Theme.Spacing.md) {
                    Text(service.formatSize(store.cleanedSize))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.success)
                    Text("\(localizer.total) \(store.cleanedCount) \(localizer.itemsLabel)")
                        .font(Theme.Font.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: 240)
            }

            Button { showCleanResult = false } label: {
                Text(localizer.ok)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(.white)
                    .frame(width: 120)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Gradients.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 380)
    }

    private var activeModelText: String {
        let config = service.aiConfig
        let model = config?.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch config?.providerMode ?? .automatic {
        case .automatic:
            if config?.usesExternalProvider == true {
                return localizer.t("自动：Apple，失败后使用 \(model ?? "External")", en: "Auto: Apple, fallback to \(model ?? "External")")
            }
            return localizer.t("自动：Apple Intelligence", en: "Auto: Apple Intelligence")
        case .apple:
            return "Apple Intelligence"
        case .external:
            return localizer.t("第三方模型：\(model ?? "")", en: "External model: \(model ?? "")")
        }
    }

    private var scanButtonTitle: String {
        SandboxPaths.isSandboxed
            ? localizer.t("授权并扫描", en: "Authorize & Scan")
            : localizer.t("扫描", en: "Scan")
    }

    private var shouldAskExternalAIConsent: Bool {
        guard let config = service.aiConfig else { return false }
        switch config.providerMode {
        case .external:
            return true
        case .automatic:
            return config.usesExternalProvider
        case .apple:
            return false
        }
    }

    private func scanWithAuthorization(promptForAccess: Bool) async {
        if SandboxPaths.isSandboxed {
            let roots = service.authorizedLocalScanRoots(promptForAccess: promptForAccess)
            guard !roots.isEmpty else {
                store.statusMessage = localizer.t(
                    "请选择要扫描的文件夹。TraceFence 只会读取你授权的目录。",
                    en: "Choose folders to scan. TraceFence only reads directories you authorize."
                )
                if promptForAccess {
                    store.errorMessage = localizer.t(
                        "Mac App Store 版本需要先授权文件夹，才能扫描磁盘项目。",
                        en: "The Mac App Store build needs folder authorization before scanning disk items."
                    )
                }
                return
            }
            await store.scan(authorizedRoots: roots, localizer: localizer)
        } else {
            await store.scan(localizer: localizer)
        }
    }

    private func requestAIAnalysis() {
        if shouldAskExternalAIConsent {
            showExternalAIConsent = true
        } else {
            Task { await analyzeWithCurrentModel() }
        }
    }

    private func analyzeWithCurrentModel() async {
        if store.candidates.isEmpty {
            await scanWithAuthorization(promptForAccess: true)
        }
        await store.analyze(config: service.aiConfig, localizer: localizer)
    }

    private func toggle(_ candidate: DiskAdvisorCandidate) {
        if store.selectedIDs.contains(candidate.id) {
            store.selectedIDs.remove(candidate.id)
        } else {
            store.selectedIDs.insert(candidate.id)
        }
    }

    private func confirmDelete() {
        guard pendingDeleteCount > 0 else { return }
        licenseService.refreshTrialState()
        guard TraceFenceEntitlementPolicy.canUseProFeatures else {
            if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                paywallMessage = deleteScope == .inventoryFiles
                    ? localizer.t("订阅 TraceFence Standard 后可将勾选文件移入废纸篓。", en: "Subscribe to TraceFence Standard to move selected files to Trash.")
                    : localizer.t("订阅 TraceFence Standard 后可执行 AI 建议的清理操作。", en: "Subscribe to TraceFence Standard to run cleanup actions recommended by AI Disk Advisor.")
            } else {
                paywallMessage = deleteScope == .inventoryFiles
                    ? localizer.t("试用期可以扫描、筛选和预览文件；执行清理需要激活 TraceFence Standard。", en: "The trial can scan, filter, and preview files. Cleanup execution requires TraceFence Standard.")
                    : localizer.t("试用期可以扫描、浏览和预览 AI 建议；执行清理需要激活 TraceFence Standard。", en: "The trial can scan, browse, and preview AI suggestions. Cleanup execution requires TraceFence Standard.")
            }
            return
        }
        showDeleteConfirm = true
    }

    private func performDelete() {
        let scope = deleteScope
        let candidateSelection = scope == .cleanupCandidates ? store.selectedCandidates : []
        let fileSelection = scope == .inventoryFiles ? store.selectedFiles : []
        let targets: [(id: String, path: String, size: Int64, fileCount: Int)]
        switch scope {
        case .cleanupCandidates:
            targets = candidateSelection.map { (id: $0.id, path: $0.path, size: $0.size, fileCount: $0.fileCount) }
        case .inventoryFiles:
            targets = fileSelection.map { (id: $0.id, path: $0.path, size: $0.size, fileCount: 1) }
        }
        Task {
            let result = await service.deleteAdvisedPaths(targets)
            let succeededIDs = Set((result.results ?? []).filter { $0.success == true }.compactMap { $0.id })
            let cleaned: Int64
            switch scope {
            case .cleanupCandidates:
                cleaned = candidateSelection.filter { succeededIDs.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }
                store.removeCleaned(ids: succeededIDs, cleanedSize: cleaned)
            case .inventoryFiles:
                cleaned = fileSelection.filter { succeededIDs.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }
                store.removeCleanedFiles(ids: succeededIDs, cleanedSize: cleaned)
            }
            service.refreshDiskInfo()
            showCleanResult = !succeededIDs.isEmpty
            if (result.failed ?? 0) > 0 {
                store.errorMessage = localizer.t("部分项目未能移到废纸篓，请检查权限或文件是否仍存在。", en: "Some items could not be moved to Trash. Check permissions or whether they still exist.")
            }
        }
    }

    private var pendingDeleteCount: Int {
        switch deleteScope {
        case .cleanupCandidates: return store.selectedCandidates.count
        case .inventoryFiles: return store.selectedFiles.count
        }
    }

    private var pendingDeleteSize: Int64 {
        switch deleteScope {
        case .cleanupCandidates: return store.selectedSize
        case .inventoryFiles: return store.selectedFileSize
        }
    }

    private func inventoryStats(minimumDays: Int) -> (count: Int, bytes: Int64) {
        store.inactiveFileStats(minimumDays: minimumDays)
    }

    private func inventoryCoverageMessage(_ summary: DiskFileInventorySummary) -> String {
        var messages: [String] = []
        if summary.wasTruncated {
            messages.append(localizer.t(
                "扫描达到有边界上限，当前清单保留体积最大的 \(summary.returnedFileCount) 个文件；可缩小授权目录后再次扫描。",
                en: "The bounded scan limit was reached. The list keeps the largest \(summary.returnedFileCount) files; select a narrower folder and scan again for complete coverage."
            ))
        }
        if summary.unreadableEntryCount > 0 {
            messages.append(localizer.t(
                "另有 \(summary.unreadableEntryCount) 个位置因权限或瞬时文件变化未能读取。",
                en: "\(summary.unreadableEntryCount) locations could not be read because of permissions or transient file changes."
            ))
        }
        return messages.joined(separator: " ")
    }

    private func fileCategoryLabel(_ category: DiskFileCategory) -> String {
        switch category {
        case .image: return localizer.t("图片", en: "Images")
        case .video: return localizer.t("视频", en: "Videos")
        case .audio: return localizer.t("音频", en: "Audio")
        case .document: return localizer.t("文档", en: "Documents")
        case .archive: return localizer.t("压缩包", en: "Archives")
        case .installer: return localizer.t("安装与分发包", en: "Installers")
        case .code: return localizer.t("代码文件", en: "Code")
        case .other: return localizer.t("其它文件", en: "Other")
        }
    }

    private func fileCategoryIcon(_ category: DiskFileCategory) -> String {
        switch category {
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "waveform"
        case .document: return "doc.text.fill"
        case .archive: return "archivebox.fill"
        case .installer: return "shippingbox.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc.fill"
        }
    }

    private func fileCategoryColor(_ category: DiskFileCategory) -> Color {
        switch category {
        case .image: return Theme.Colors.purple
        case .video: return Theme.Colors.danger
        case .audio: return Theme.Colors.accent
        case .document: return Theme.Colors.info
        case .archive: return Theme.Colors.warning
        case .installer: return Theme.Colors.success
        case .code: return Theme.Colors.info
        case .other: return Theme.Colors.textSecondary
        }
    }

    private func fileAgeFilterLabel(_ filter: DiskFileAgeFilter) -> String {
        switch filter {
        case .all: return localizer.t("全部活动时间", en: "All Activity")
        case .days7: return localizer.t("7 天以上未活动", en: "Inactive 7+ Days")
        case .days30: return localizer.t("30 天以上未活动", en: "Inactive 30+ Days")
        case .days90: return localizer.t("90 天以上未活动", en: "Inactive 90+ Days")
        case .unknown: return localizer.t("无活动记录", en: "No Activity Record")
        }
    }

    private func fileSortLabel(_ sort: DiskFileSort) -> String {
        switch sort {
        case .sizeDescending: return localizer.t("按大小", en: "Size")
        case .oldestActivity: return localizer.t("最久未活动", en: "Oldest Activity")
        case .newestActivity: return localizer.t("最近活动", en: "Newest Activity")
        case .name: return localizer.t("按名称", en: "Name")
        }
    }

    private func activityMarkerLabel(_ marker: DiskFileActivityMarker) -> String {
        switch marker {
        case .recent: return localizer.t("7 天内有活动", en: "Active within 7d")
        case .days7: return localizer.t("7–29 天未活动", en: "Inactive 7–29d")
        case .days30: return localizer.t("30–89 天未活动", en: "Inactive 30–89d")
        case .days90: return localizer.t("90 天以上未活动", en: "Inactive 90+d")
        case .unknown: return localizer.t("无活动记录", en: "No activity record")
        }
    }

    private func activityMarkerColor(_ marker: DiskFileActivityMarker) -> Color {
        switch marker {
        case .recent: return Theme.Colors.success
        case .days7: return Theme.Colors.info
        case .days30: return Theme.Colors.warning
        case .days90: return Theme.Colors.danger
        case .unknown: return Theme.Colors.textSecondary
        }
    }

    private func fileFormatLabel(_ file: DiskFileRecord) -> String {
        file.fileExtension.isEmpty
            ? localizer.t("无扩展名", en: "NO EXT")
            : file.fileExtension.uppercased()
    }

    private func fileDisplayPath(_ file: DiskFileRecord) -> String {
        file.path.replacingOccurrences(of: SandboxPaths.realHomeDirectory, with: "~")
    }

    private func metadataDateLabel(_ title: String, date: Date?, icon: String) -> some View {
        Label(
            "\(title) \(date.map(shortDateTime) ?? localizer.t("无记录", en: "No record"))",
            systemImage: icon
        )
    }

    private func revealFile(_ file: DiskFileRecord) {
        let url = URL(fileURLWithPath: file.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            store.errorMessage = localizer.t("文件已不存在，请重新扫描。", en: "The file no longer exists. Run the scan again.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func diskFilePreviewSheet(_ file: DiskFileRecord) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: fileCategoryIcon(file.category))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(fileCategoryColor(file.category))
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(fileDisplayPath(file))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(service.formatSize(file.size))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Button {
                    revealFile(file)
                } label: {
                    Label("Finder", systemImage: "folder")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 32))
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
                } label: {
                    Label(localizer.t("打开原文件", en: "Open Original"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.purple, variant: .primary, minHeight: 32))
            }
            .padding(Theme.Spacing.lg)

            Divider().overlay(Theme.Colors.separator)

            DiskAdvisorQuickLookPreview(url: URL(fileURLWithPath: file.path))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Theme.Colors.background)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func shortDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1 { return String(format: "%.1fs", interval) }
        if interval < 60 { return String(format: "%.0fs", interval) }
        return String(format: "%.1fmin", interval / 60)
    }

    private func candidateIcon(for candidate: DiskAdvisorCandidate) -> String {
        switch candidate.category {
        case "Historical Build": return "hammer.fill"
        case "Installer Artifact": return "shippingbox.fill"
        default: return candidate.isDirectory ? "folder.fill" : "doc.fill"
        }
    }

    @ViewBuilder
    private func cleanupCandidateFilterButton(_ filter: DiskCleanupCandidateFilter) -> some View {
        Button {
            cleanupCandidateFilter = filter
            searchText = ""
        } label: {
            let count = cleanupCandidateCount(filter)
            if cleanupCandidateFilter == filter {
                Label("\(cleanupCandidateFilterTitle(filter)) · \(count)", systemImage: "checkmark")
            } else {
                Text("\(cleanupCandidateFilterTitle(filter)) · \(count)")
            }
        }
    }

    private func cleanupCandidateCount(_ filter: DiskCleanupCandidateFilter) -> Int {
        guard let category = filter.category else { return store.candidates.count }
        return store.candidates.filter { $0.category == category }.count
    }

    private func cleanupCandidateFilterTitle(_ filter: DiskCleanupCandidateFilter) -> String {
        switch filter {
        case .all:
            return localizer.t("全部候选", en: "All Candidates")
        case .installerArtifact:
            return localizer.t("安装与分发包", en: "Installers & Distributions")
        case .historicalBuild:
            return localizer.t("历史构建", en: "Build History")
        }
    }

    private func focusCleanupCandidates(_ filter: DiskCleanupCandidateFilter) {
        section = .cleanup
        cleanupCandidateFilter = filter
        searchText = ""
        cleanupCandidateFocusRequest += 1
    }

    private func localizedCategory(_ category: String) -> String {
        switch category {
        case "Historical Build": return localizer.t("历史构建", en: "Historical Build")
        case "Installer Artifact": return localizer.t("安装与分发包", en: "Installer Artifact")
        case "AI Agent Data": return localizer.t("Agent 数据", en: "Agent Data")
        default: return category
        }
    }

    private func confidenceText(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))%"
    }

    private func displayReason(for candidate: DiskAdvisorCandidate) -> String {
        if let rationale = candidate.rationale {
            return localizer.diskAdvisorReason(rationale)
        }
        return candidate.reason
    }

    private func displayImpact(for candidate: DiskAdvisorCandidate) -> String {
        if let rationale = candidate.rationale {
            return localizer.diskAdvisorImpact(rationale)
        }
        return candidate.impact
    }
}

private enum DiskAdvisorAIClient {
    struct Response {
        let results: [DiskAdvisorLLMResult]
        let source: String
    }

    static func analyze(candidates: [DiskAdvisorCandidate], config: AIConfig?) async throws -> Response {
        let instructions = """
        You are TraceFence's disk cleanup advisor for macOS.
        You only receive metadata: path, size, file count, modified date, category, and a local rule hint.
        Do not claim that you inspected file contents.
        Be conservative: user documents, source code, credentials, archives that may be needed for App Store upload, and project data should be keep or review.
        Recommend clean only for clearly generated caches, logs, downloaded installers, package caches, and build artifacts.
        Return strict JSON only, no markdown, no commentary.
        Return either a raw array or {"results":[...]}.
        Schema: [{"id":"same id","recommendation":"clean|review|keep","risk":"safe|caution|danger|unknown","reason":"short reason","impact":"what may happen after cleanup","confidence":0.0}]
        """

        let prompt = "Analyze these macOS disk cleanup candidates:\n\(payload(for: candidates))"
        switch config?.providerMode ?? .automatic {
        case .apple:
            do {
                let result = try await AppleIntelligenceService.generate(
                    instructions: instructions,
                    prompt: prompt,
                    maximumResponseTokens: 4096
                )
                return Response(results: try parse(result.content), source: result.modelName)
            } catch {
                throw NSError(domain: "DiskAdvisor", code: 10, userInfo: [NSLocalizedDescriptionKey: "\(AppleIntelligenceService.displayName): \(error.localizedDescription)"])
            }
        case .external:
            return try await callExternal(config: config, instructions: instructions, prompt: prompt)
        case .automatic:
            do {
                let result = try await AppleIntelligenceService.generate(
                    instructions: instructions,
                    prompt: prompt,
                    maximumResponseTokens: 4096
                )
                return Response(results: try parse(result.content), source: result.modelName)
            } catch {
                guard hasExternalProvider(config) else {
                    throw NSError(domain: "DiskAdvisor", code: 10, userInfo: [NSLocalizedDescriptionKey: "\(AppleIntelligenceService.displayName): \(error.localizedDescription)"])
                }
                return try await callExternal(config: config, instructions: instructions, prompt: prompt)
            }
        }
    }

    private static func hasExternalProvider(_ config: AIConfig?) -> Bool {
        guard let config else { return false }
        let key = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = config.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty && !model.isEmpty && model != AIConfig.appleIntelligenceModel
    }

    private static func callExternal(config: AIConfig?, instructions: String, prompt: String) async throws -> Response {
        guard let config, hasExternalProvider(config) else {
            throw NSError(domain: "DiskAdvisor", code: 1, userInfo: [NSLocalizedDescriptionKey: "请在 AI 设置里选择第三方模型，并填写 API Key 与模型名。"])
        }
        let apiKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = config.chatCompletionsURL else {
            throw NSError(domain: "DiskAdvisor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL."])
        }

        let body: [String: Any] = [
            "model": config.model ?? "deepseek-chat",
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1,
            "max_tokens": 4096
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "DiskAdvisor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response."])
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "DiskAdvisor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) @ \(url.absoluteString): \(detail.prefix(220))"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "DiskAdvisor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid model response."])
        }
        return Response(results: try parse(content), source: config.model ?? "External Model")
    }

    private static func payload(for candidates: [DiskAdvisorCandidate]) -> String {
        let formatter = ISO8601DateFormatter()
        let items: [[String: Any]] = candidates.map { item in
            [
                "id": item.id,
                "name": item.name,
                "path": item.displayPath,
                "size_bytes": item.size,
                "file_count": item.fileCount,
                "is_directory": item.isDirectory,
                "modified": item.modifiedDate.map { formatter.string(from: $0) } ?? "",
                "category": item.category,
                "local_hint": item.localHint,
                "local_recommendation": item.recommendation.rawValue,
                "local_risk": item.risk.rawValue
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    private static func parse(_ raw: String) throws -> [DiskAdvisorLLMResult] {
        for candidate in jsonCandidates(from: raw) {
            if let results = decodeResults(from: candidate) {
                return results
            }
            if let repaired = repairCommonJSONIssues(candidate),
               let results = decodeResults(from: repaired) {
                return results
            }
        }
        throw NSError(domain: "DiskAdvisor", code: 5, userInfo: [NSLocalizedDescriptionKey: "AI returned text instead of structured cleanup advice."])
    }

    private static func decodeResults(from text: String) -> [DiskAdvisorLLMResult]? {
        guard let data = text.data(using: .utf8) else { return nil }
        if let decoded = try? JSONDecoder().decode([DiskAdvisorLLMResult].self, from: data) {
            return decoded
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return decodeResults(from: object)
    }

    private static func decodeResults(from object: Any) -> [DiskAdvisorLLMResult]? {
        if let array = object as? [[String: Any]] {
            let results = array.compactMap { result(from: $0) }
            return results.isEmpty ? nil : results
        }
        guard let dictionary = object as? [String: Any] else { return nil }
        if let result = result(from: dictionary) {
            return [result]
        }
        for key in ["results", "items", "recommendations", "candidates", "data"] {
            if let nested = dictionary[key], let results = decodeResults(from: nested) {
                return results
            }
        }
        return nil
    }

    private static func result(from dictionary: [String: Any]) -> DiskAdvisorLLMResult? {
        guard let id = stringValue(dictionary["id"] ?? dictionary["path"] ?? dictionary["name"]),
              !id.isEmpty else {
            return nil
        }
        return DiskAdvisorLLMResult(
            id: id,
            recommendation: recommendation(from: dictionary["recommendation"] ?? dictionary["action"] ?? dictionary["decision"]),
            risk: risk(from: dictionary["risk"] ?? dictionary["risk_level"] ?? dictionary["safety"]),
            reason: stringValue(dictionary["reason"] ?? dictionary["why"] ?? dictionary["summary"]),
            impact: stringValue(dictionary["impact"] ?? dictionary["effect"] ?? dictionary["after_cleanup"]),
            confidence: confidence(from: dictionary["confidence"] ?? dictionary["score"])
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func recommendation(from value: Any?) -> DiskAdvisorRecommendation? {
        guard let raw = stringValue(value)?.lowercased() else { return nil }
        if let exact = DiskAdvisorRecommendation(rawValue: raw) { return exact }
        if containsAnyPhrase(raw, [
            "do not delete", "don't delete", "dont delete", "not safe",
            "unsafe", "must keep", "should keep", "keep", "retain",
            "preserve", "danger"
        ]) {
            return .keep
        }
        let tokens = wordTokens(raw)
        if !tokens.isDisjoint(with: ["review", "check", "confirm", "caution"]) {
            return .review
        }
        if !tokens.isDisjoint(with: ["clean", "delete", "remove", "trash"]) {
            return .clean
        }
        return nil
    }

    private static func risk(from value: Any?) -> DiskAdvisorRisk? {
        guard let raw = stringValue(value)?.lowercased() else { return nil }
        if let exact = DiskAdvisorRisk(rawValue: raw) { return exact }
        if containsAnyPhrase(raw, ["not safe", "unsafe"]) {
            return .danger
        }
        let tokens = wordTokens(raw)
        if !tokens.isDisjoint(with: ["danger", "dangerous", "high", "risky"]) {
            return .danger
        }
        if !tokens.isDisjoint(with: ["caution", "medium", "review"]) {
            return .caution
        }
        if !tokens.isDisjoint(with: ["safe", "low"]) {
            return .safe
        }
        if !tokens.isDisjoint(with: ["unknown", "unclear"]) {
            return .unknown
        }
        return nil
    }

    private static func containsAnyPhrase(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func wordTokens(_ text: String) -> Set<String> {
        Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }

    private static func confidence(from value: Any?) -> Double? {
        if let double = value as? Double { return min(max(double, 0), 1) }
        if let number = value as? NSNumber { return min(max(number.doubleValue, 0), 1) }
        guard var text = stringValue(value) else { return nil }
        let isPercent = text.contains("%")
        text = text.replacingOccurrences(of: "%", with: "")
        guard let parsed = Double(text) else { return nil }
        return min(max(isPercent || parsed > 1 ? parsed / 100 : parsed, 0), 1)
    }

    private static func jsonCandidates(from raw: String) -> [String] {
        let stripped = raw
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var candidates: [String] = []
        func append(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else { return }
            candidates.append(trimmed)
        }

        append(stripped)
        if let array = fragment(in: stripped, opening: "[", closing: "]") {
            append(array)
        }
        if let object = fragment(in: stripped, opening: "{", closing: "}") {
            append(object)
        }
        return candidates
    }

    private static func fragment(in text: String, opening: Character, closing: Character) -> String? {
        guard let start = text.firstIndex(of: opening),
              let end = text.lastIndex(of: closing),
              start < end else {
            return nil
        }
        return String(text[start...end])
    }

    private static func repairCommonJSONIssues(_ text: String) -> String? {
        var repaired = text
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        repaired = repaired.replacingOccurrences(
            of: #",\s*([\]}])"#,
            with: "$1",
            options: .regularExpression
        )
        return repaired == text ? nil : repaired
    }
}

private enum DiskAdvisorScanner {
    private static let minSize: Int64 = 30 * 1024 * 1024
    private static let maxCandidates = 120
    private static let artifactNames: Set<String> = [
        "node_modules", ".next", ".nuxt", ".svelte-kit", "dist", "build", ".build",
        "DerivedData", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".turbo",
        "target", ".gradle", ".parcel-cache", ".cache", "coverage", "__pycache__",
        ".venv", "venv"
    ]
    private static let generatedMediaNames: Set<String> = [
        "cache_videos", "local_videos", "videos", "video", "renders", "rendered",
        "recordings", "captures", "exports", "output", "outputs"
    ]
    private static let generatedTaskNames: Set<String> = [
        "tasks", "jobs", "runs", "workflows"
    ]
    private static let sensitiveNames: Set<String> = [
        ".ssh", ".gnupg", "keychains", "wallet", "wallets", "password", "passwords",
        "secrets", "credentials", "private", "certificates"
    ]
    private static let exactDirectories: [(String, String)] = [
        ("Library/Caches", "Cache"),
        ("Library/Logs", "Logs"),
        ("Library/Developer/CoreSimulator/Caches", "Simulator Cache"),
        (".cache", "Developer Cache"),
        (".npm", "Package Cache"),
        (".pnpm-store", "Package Cache"),
        (".gradle/caches", "Package Cache"),
        (".m2/repository", "Package Cache"),
        (".cargo/registry", "Package Cache")
    ]

    static func scan(authorizedRoots: Set<String>? = nil) -> [DiskAdvisorCandidate] {
        let home = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
        var seen = Set<String>()
        var results: [DiskAdvisorCandidate] = []

        if let authorizedRoots, !authorizedRoots.isEmpty {
            scanAuthorizedRoots(authorizedRoots, home: home, into: &results, seen: &seen)
            return results
                .sorted { $0.size > $1.size }
                .prefix(maxCandidates)
                .map { $0 }
        }

        scanDefaultLocations(home: home, into: &results, seen: &seen)

        return results
            .sorted { $0.size > $1.size }
            .prefix(maxCandidates)
            .map { $0 }
    }

    private static func scanAuthorizedRoots(_ rootPaths: Set<String>, home: URL, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        let candidates = rootPaths
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            .filter { isDirectory($0) }
            .sorted { $0.path.count < $1.path.count }
        var roots: [URL] = []
        for candidate in candidates where !roots.contains(where: {
            candidate.path == $0.path || candidate.path.hasPrefix($0.path + "/")
        }) {
            roots.append(candidate)
        }

        for root in roots {
            let category = categoryForAuthorizedRoot(root, home: home)
            if root.standardizedFileURL.path == home.standardizedFileURL.path {
                scanDefaultLocations(home: home, into: &results, seen: &seen)
            } else if category != "AI Agent Data" {
                // The selected root is an authorization boundary, not a cleanup
                // candidate. Showing only its children prevents an accidental
                // whole-project deletion and avoids sizing the same tree twice.
                scanTopLevelChildren(root, category: category, into: &results, seen: &seen)
                scanProjectArtifacts(root, into: &results, seen: &seen)
            }

            if results.count >= maxCandidates * 2 { break }
        }
    }

    private static func scanDefaultLocations(
        home: URL,
        into results: inout [DiskAdvisorCandidate],
        seen: inout Set<String>
    ) {
        scanKnownHighValueDirectories(home: home, into: &results, seen: &seen)
        scanHiddenAppDataDirectories(home: home, into: &results, seen: &seen)
        scanTopLevelChildren(
            home.appendingPathComponent("Downloads", isDirectory: true),
            category: "Downloads",
            into: &results,
            seen: &seen
        )
        scanTopLevelChildren(
            home.appendingPathComponent("Desktop", isDirectory: true),
            category: "Desktop",
            into: &results,
            seen: &seen
        )
        for (relative, category) in exactDirectories {
            scanTopLevelChildren(
                home.appendingPathComponent(relative, isDirectory: true),
                category: category,
                into: &results,
                seen: &seen
            )
        }
        for root in projectRoots(home: home) {
            scanProjectArtifacts(root, into: &results, seen: &seen)
            if results.count >= maxCandidates * 2 { break }
        }
    }

    private static func scanKnownHighValueDirectories(home: URL, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        scanTopLevelChildren(
            home.appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true),
            category: "Simulator Devices",
            into: &results,
            seen: &seen
        )
    }

    private static func scanHiddenAppDataDirectories(home: URL, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: resourceKeys,
            options: []
        ) else {
            return
        }

        for child in children.prefix(300) {
            let lower = child.lastPathComponent.lowercased()
            guard lower.hasPrefix("."),
                  !shouldSkipHomeDirectory(lower),
                  !isAgentDataDirectory(lower),
                  !isSensitive(child) else {
                continue
            }
            addCandidate(child, category: "Hidden App Data", into: &results, seen: &seen)
            if results.count >= maxCandidates * 2 { return }
        }
    }

    private static func scanTopLevelChildren(_ root: URL, category: String, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        guard isDirectory(root),
              let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for child in children.prefix(600) {
            guard !isSensitive(child) else { continue }
            addCandidate(child, category: category, into: &results, seen: &seen)
            if results.count >= maxCandidates * 2 { return }
        }
    }

    private static func scanProjectArtifacts(_ root: URL, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        guard isDirectory(root),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsPackageDescendants]
              ) else {
            return
        }

        let rootDepth = root.pathComponents.count
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 80_000 || results.count >= maxCandidates * 2 { break }
            autoreleasepool {
                let depth = url.pathComponents.count - rootDepth
                if depth > 6 {
                    enumerator.skipDescendants()
                    return
                }
                let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey
                ])
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    return
                }
                guard values?.isDirectory == true, !isSensitive(url) else { return }
                if AgentDataProtection.containsProtectedData(
                    path: url.path,
                    homeDirectory: SandboxPaths.realHomeDirectory
                ) {
                    enumerator.skipDescendants()
                    return
                }

                let name = url.lastPathComponent
                let lower = name.lowercased()
                if generatedMediaNames.contains(lower) {
                    addCandidate(url, category: lower.contains("cache") ? "Generated Media Cache" : "Generated Media", into: &results, seen: &seen)
                    enumerator.skipDescendants()
                } else if generatedTaskNames.contains(lower) {
                    addCandidate(url, category: "Generated Task Data", into: &results, seen: &seen)
                    enumerator.skipDescendants()
                } else if lower == "logs" || lower == "log" {
                    addCandidate(url, category: "Logs", into: &results, seen: &seen)
                    enumerator.skipDescendants()
                } else if artifactNames.contains(name) || artifactNames.contains(lower) {
                    addCandidate(url, category: "Build Artifact", into: &results, seen: &seen)
                    enumerator.skipDescendants()
                } else if shouldSkipDirectory(lower) {
                    enumerator.skipDescendants()
                }
            }
        }
    }

    private static func addCandidate(_ url: URL, category: String, displayName: String? = nil, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        let standardized = url.standardizedFileURL.path
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard !seen.contains(standardized), !seen.contains(canonical) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir) else { return }

        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        if values?.isSymbolicLink == true { return }
        seen.insert(standardized)
        seen.insert(canonical)

        let (size, fileCount) = sizeOfItem(url)
        guard size >= minSize else { return }

        let modified = values?.contentModificationDate
        let classification = classify(url: url, category: category, modified: modified)
        results.append(DiskAdvisorCandidate(
            id: standardized,
            name: displayName ?? (url.lastPathComponent.isEmpty ? standardized : url.lastPathComponent),
            path: standardized,
            size: size,
            fileCount: fileCount,
            isDirectory: isDir.boolValue,
            modifiedDate: modified,
            category: category,
            localHint: classification.hint,
            recommendation: classification.recommendation,
            risk: classification.risk,
            reason: classification.hint,
            impact: classification.impact,
            confidence: classification.confidence,
            source: "Local Rules",
            analyzedAt: nil,
            rationale: classification.rationale
        ))
    }

    private static func classify(url: URL, category: String, modified: Date?) -> (recommendation: DiskAdvisorRecommendation, risk: DiskAdvisorRisk, rationale: DiskAdvisorRationale, hint: String, impact: String, confidence: Double) {
        let path = url.path.lowercased()
        let name = url.lastPathComponent.lowercased()
        let old = modified.map { Date().timeIntervalSince($0) > 7 * 24 * 60 * 60 } ?? false

        if sensitiveNames.contains(where: { path.contains($0) }) {
            return (.keep, .danger, .credentials, "路径像凭据、密钥或私密数据，默认保留。", "删除可能导致登录、签名或账户恢复问题。", 0.85)
        }
        if category == "Personal Files" {
            return (.keep, .danger, .personalFiles, "这是用户个人资料目录，默认只做占用提示，不建议自动清理。", "删除可能造成个人文件或照片资料丢失。", 0.92)
        }
        if category == "Project Data" {
            return (.keep, .danger, .projectData, "这是项目根目录，可能包含源码、配置和生成内容；应只清理明确的缓存子目录。", "删除整个项目会造成源码和工作文件丢失。", 0.88)
        }
        if category == "AI Agent Data" {
            return (.keep, .danger, .aiAgentData, "AI Agent 数据通常包含会话历史、索引或本地状态，TraceFence 不把原始目录作为清理候选。", "删除后可能丢失历史会话、项目上下文或本地 agent 状态。", 0.98)
        }
        if category == "Hidden App Data" {
            return (.review, .caution, .hiddenAppData, "这是用户目录下的大型隐藏应用数据，可能是 Agent、开发工具、包管理器或其它本地状态。", "删除前需要确认来源；它可能包含会话历史、索引、缓存或账户状态。", 0.7)
        }
        if category == "Simulator Devices" {
            return (.review, .caution, .simulatorDevices, "模拟器设备可能包含安装的 App、数据容器和调试状态，可按设备选择删除。", "删除后对应模拟器设备和其中 App 数据会消失，需要重新创建或安装。", 0.76)
        }
        if category == "Simulator dyld Cache" {
            return (.review, .caution, .simulatorDyldCache, "模拟器 dyld 缓存通常可重建，但位于系统级开发者目录，可能需要权限。", "下次启动模拟器可能重新生成缓存，清理操作也可能被系统权限拒绝。", 0.74)
        }
        if category == "Temporary Files" {
            return (old ? .clean : .review, old ? .safe : .caution, .temporaryFiles, "系统临时目录常见于测试、构建和中间文件，旧文件通常值得清理。", "仍在运行的任务可能依赖近期临时文件；清理前建议关闭相关构建或测试进程。", old ? 0.84 : 0.66)
        }
        if category == "Generated Media Cache" || category == "Generated Task Data" {
            return (.review, .caution, .generatedTaskData, "这是生成视频或任务缓存，通常占用较大，适合用户确认后清理。", "删除后相关生成任务、缓存视频或中间结果可能无法继续复用。", 0.8)
        }
        if category == "Generated Media" {
            return (.review, .caution, .generatedMedia, "这是生成的视频输出目录，可能既有缓存也有用户想保留的成品。", "删除后可能丢失已经生成的视频结果。", 0.72)
        }
        if category == "App Update Cache" {
            return (.clean, .safe, .appUpdateCache, "应用更新缓存通常可以重新下载。", "下次更新可能需要重新下载安装包。", 0.86)
        }
        if category == "Xcode Archives" || name.hasSuffix(".xcarchive") {
            return (.review, .caution, .xcodeArchives, "Xcode archive 可能用于重新上传、符号化或回溯版本，删除前需要确认。", "删除后可能无法重新提交或定位线上问题。", 0.74)
        }
        if category.contains("Cache") || category == "Logs" || category == "Xcode DerivedData" || category == "Simulator Cache" {
            return (old ? .clean : .review, old ? .safe : .caution, .cacheOrLogs, "缓存、日志或派生数据通常可以重建。", "首次重新打开相关工具时可能需要重新索引或下载。", old ? 0.82 : 0.68)
        }
        if category == "Build Artifact" {
            return (old ? .clean : .review, old ? .safe : .caution, .buildArtifact, "构建产物通常可以由源码重新生成。", "下次构建可能变慢，未提交生成物请先确认。", old ? 0.78 : 0.64)
        }
        if ["dmg", "pkg", "zip", "tar", "gz", "xz", "rar", "7z"].contains(url.pathExtension.lowercased()) {
            return (.review, .caution, .downloadArchive, "下载的安装包或压缩包可能已经不再需要。", "删除后如需安装或恢复内容，需要重新下载。", 0.62)
        }
        return (.review, .caution, .unknownLargeItem, "这是较大的磁盘项目，建议让 AI 进一步判断用途。", "删除前请确认是否仍在使用。", 0.52)
    }

    private static func sizeOfItem(_ url: URL) -> (Int64, Int) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return (0, 0)
        }

        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey])
            let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0
            return (Int64(size), 1)
        }

        var total: Int64 = 0
        var count = 0
        var visited = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            return (0, 0)
        }

        for case let child as URL in enumerator {
            visited += 1
            if visited > 100_000 || count > 60_000 { break }
            autoreleasepool {
                let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey])
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    return
                }
                guard values?.isRegularFile == true else { return }
                let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0
                total += Int64(size)
                count += 1
            }
        }
        return (total, max(count, 1))
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func isSensitive(_ url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        return sensitiveNames.contains(lower)
    }

    private static func shouldSkipDirectory(_ lowerName: String) -> Bool {
        [".git", ".svn", ".hg", "pictures", "photos library.photoslibrary", "music", "movies", "library", "applications"].contains(lowerName)
    }

    private static func shouldSkipHomeDirectory(_ lowerName: String) -> Bool {
        let skipped = [
            ".ds_store", ".localized", ".trash", ".ssh", ".gnupg",
            "library", "applications", "developer", "projects", "code", "github",
            "downloads", "desktop", "public", "sites"
        ]
        return skipped.contains(lowerName)
    }

    private static func isAgentDataDirectory(_ lowerName: String) -> Bool {
        AgentDataProtection.hiddenRootNames.contains(lowerName)
    }

    private static func projectRoots(home: URL) -> [URL] {
        ["Developer", "Projects", "Code", "GitHub", "Documents", "Downloads"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
    }

    private static func categoryForAuthorizedRoot(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path.lowercased()
        let name = url.lastPathComponent.lowercased()
        if isAgentDataDirectory(name)
            || AgentDataProtection.containsProtectedData(
                path: url.path,
                homeDirectory: home.path
            ) {
            return "AI Agent Data"
        }
        if path.contains("/private/tmp") { return "Temporary Files" }
        if path.contains("/coresimulator/devices") { return "Simulator Devices" }
        if path.contains("/coresimulator/caches") { return "Simulator Cache" }
        if name == "deriveddata" { return "Xcode DerivedData" }
        if name == "archives", path.contains("/xcode/") { return "Xcode Archives" }
        if name == "caches" || path.contains("/library/caches") { return "Cache" }
        if name == "logs" || path.contains("/library/logs") { return "Logs" }
        if name.hasPrefix(".") { return "Hidden App Data" }
        if path.hasPrefix(home.appendingPathComponent("Downloads", isDirectory: true).path.lowercased()) { return "Downloads" }
        if path.hasPrefix(home.appendingPathComponent("Desktop", isDirectory: true).path.lowercased()) { return "Desktop" }
        return "Selected Folder"
    }

    private static var resourceKeys: [URLResourceKey] {
        [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
    }
}

private struct DiskAdvisorQuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        let currentURL = (view.previewItem as? NSURL) as URL?
        guard currentURL != url else { return }
        view.previewItem = url as NSURL
        view.refreshPreviewItem()
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.autostarts = false
        view.previewItem = nil
    }
}
