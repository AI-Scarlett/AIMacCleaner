import AppKit
import CryptoKit
import Foundation
import ImageIO
import SQLite3

private enum ArtifactShelfPatterns {
    static let markdownTarget = try! NSRegularExpression(
        pattern: #"!?\[[^\]\r\n]*\]\(\s*(?:<([^>\r\n]+)>|([^\)\r\n]+))\s*\)"#
    )
    static let rawTargets = [
        try! NSRegularExpression(
            pattern: #"https?://[^\s<>\"'`\u3000-\u9fff\uff00-\uffef]+"#,
            options: [.caseInsensitive]
        ),
        try! NSRegularExpression(
            pattern: #"(?:file://)?/(?:Users|home|tmp|private|var|Volumes|Applications|opt|workspace|root)/[^\n\r\t\"'`<>|{}\[\]]+"#,
            options: [.caseInsensitive]
        )
    ]
    static let sensitivePathComponent = try! NSRegularExpression(
        pattern: #"^(\.env(?:\..*)?|\.ssh|\.gnupg|\.aws|\.netrc|credentials?(?:\..*)?|secrets?(?:\..*)?|auth(?:\..*)?|tokens?(?:\..*)?|id_(?:rsa|ed25519)(?:\..*)?|.*private[_-]?key.*|.*api[_-]?key.*)$"#,
        options: .caseInsensitive
    )
}

struct ArtifactShelfTask: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let cwd: String
    let rolloutPath: String
    let updatedAt: Date
    let phase: String

    var agentID: String {
        let parts = id.split(separator: "|", omittingEmptySubsequences: false)
        if parts.count >= 3, parts[0] == "adapter" || parts[0] == "core" {
            return String(parts[1]).lowercased()
        }
        return "codex"
    }

    var agentDisplayName: String {
        switch agentID {
        case "codex": return "Codex"
        case "claude": return "Claude"
        case "cursor": return "Cursor"
        case "gemini": return "Gemini"
        case "grok": return "Grok"
        case "qwen": return "Qwen"
        default: return agentID.capitalized
        }
    }
}

struct ArtifactShelfCandidate: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case file, directory, image, html, url
    }

    var id: String { target }
    let kind: Kind
    let target: String
    let title: String
    let discoveredAt: Date
    let exists: Bool
}

struct ArtifactShelfBookmark: Identifiable, Codable, Hashable {
    let id: UUID
    let taskID: String
    let kind: ArtifactShelfCandidate.Kind
    let target: String
    var title: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
}

@MainActor
final class ArtifactShelfService: ObservableObject {
    static let shared = ArtifactShelfService()
    private static let selectedTaskDefaultsKey = "artifactShelfSelectedTaskID"
    private static let defaultVisibleCandidateLimit = 12
    private static let initialRolloutReadLimit: UInt64 = 16 * 1_024 * 1_024
    private static let taskCatalogRefreshInterval: TimeInterval = 12

    enum Consumer: Hashable {
        case sidecar
        case taskArtifactsView
    }

    @Published private(set) var tasks: [ArtifactShelfTask] = []
    @Published private(set) var candidates: [ArtifactShelfCandidate] = []
    @Published private(set) var bookmarks: [ArtifactShelfBookmark] = []
    @Published var selectedTaskID: String?
    @Published var searchText = "" {
        didSet {
            let oldQueryWasEmpty = oldValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let newQueryIsEmpty = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if oldQueryWasEmpty, !newQueryIsEmpty, let selectedTaskID {
                scanTaskSelection(id: selectedTaskID, requireCompleteHistory: true)
            } else if !oldQueryWasEmpty, newQueryIsEmpty, let selectedTaskID {
                // Abandon an expensive full-history search as soon as the user
                // clears the query and return to the bounded recent scan.
                scanTaskSelection(id: selectedTaskID)
            }
        }
    }
    @Published private(set) var isRefreshing = false
    @Published private(set) var isScanningSelectedTask = false
    @Published private(set) var lastError: String?
    @Published private(set) var focusedAgentName = "Codex"
    @Published private(set) var focusedTaskTitle: String?
    @Published private(set) var focusMatchIsExact = false

    private var refreshTimer: Timer?
    private var activeConsumers: Set<Consumer> = []
    private var pausedAutomaticRefreshConsumers: Set<Consumer> = []
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var lastTaskCatalogRefreshAt: Date?
    private var restoredSelectionPending = false
    private var lastScannedSignature = ""
    private var selectionGeneration: UInt64 = 0
    private var scanRequestGeneration: UInt64 = 0
    private var externallyFocusedTaskID: String?
    private var externalFocusUpdatedAt: Date?
    private var manualSelectionUntil: Date?
    private var rolloutScanCache: [String: RolloutScanCacheEntry] = [:]
    private var selectionScanTask: Task<Void, Never>?
    private var activeRolloutScanTask: Task<RolloutScanState?, Never>?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let thumbnailCache = NSCache<NSString, NSImage>()

    private struct RolloutScanCacheEntry {
        let size: Int64
        let modifiedAt: Date?
        let fileIdentifier: UInt64?
        let candidates: [ArtifactShelfCandidate]
        let scanState: RolloutScanState?
        var lastAccessedAt: Date
    }

    private struct RolloutScanState: Sendable {
        var scannedOffset: UInt64
        var finalDeliveries: [String: ArtifactShelfCandidate]
        var lastUnphasedDeliveries: [String: ArtifactShelfCandidate]
        var pendingLine: Data
        var pendingLineWasConsumed: Bool
        var skippingOversizedLine: Bool
        var historyComplete: Bool
    }

    private init() {
        if let savedTaskID = UserDefaults.standard.string(forKey: Self.selectedTaskDefaultsKey),
           !savedTaskID.isEmpty {
            selectedTaskID = savedTaskID
            // A selection restored from a previous launch is only a visual
            // fallback. Treating it as a fresh manual lock can pin the shelf to
            // an old, very large rollout instead of the current conversation.
            restoredSelectionPending = true
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        thumbnailCache.countLimit = 48
        thumbnailCache.totalCostLimit = 32 * 1_024 * 1_024
        loadBookmarks()
    }

    var selectedTask: ArtifactShelfTask? {
        tasks.first { $0.id == selectedTaskID }
    }

    var isLoadingCandidates: Bool {
        isRefreshing || isScanningSelectedTask
    }

    var visibleCandidates: [ArtifactShelfCandidate] {
        let values = unsavedCandidates
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return values.filter { matchesSearch($0.title, $0.target) }
        }
        return Array(values
            .filter { !Self.isLikelyProcessArtifact($0) }
            .prefix(Self.defaultVisibleCandidateLimit))
    }

    /// Old delivery batches and review-stage files remain searchable without
    /// overwhelming the default companion shelf.
    var hiddenCandidateCount: Int {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        return max(0, unsavedCandidates.count - visibleCandidates.count)
    }

    private var unsavedCandidates: [ArtifactShelfCandidate] {
        guard let selectedTaskID else { return [] }
        let savedTargets = Set(bookmarks.lazy
            .filter { $0.taskID == selectedTaskID }
            .map(\.target))
        return candidates.filter { !savedTargets.contains($0.target) }
    }

    var bookmarksForSelectedTask: [ArtifactShelfBookmark] {
        guard let selectedTaskID else { return [] }
        return bookmarks
            .filter { $0.taskID == selectedTaskID && matchesSearch($0.title, $0.target) }
            .sorted { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
            }
    }

    func start(for consumer: Consumer) {
        guard SandboxPaths.isDirectDistribution else { return }
        activeConsumers.insert(consumer)
        if !automaticRefreshPaused { refresh() }
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.automaticRefreshPaused else { return }
                self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .default)
        refreshTimer = timer
    }

    func stop(for consumer: Consumer) {
        let wasPaused = automaticRefreshPaused
        activeConsumers.remove(consumer)
        pausedAutomaticRefreshConsumers.remove(consumer)
        if activeConsumers.isEmpty {
            stopAllWork()
        } else if !wasPaused, automaticRefreshPaused {
            cancelAutomaticWork()
        }
    }

    func stop() {
        activeConsumers.removeAll()
        pausedAutomaticRefreshConsumers.removeAll()
        stopAllWork()
    }

    func setAutomaticRefreshPaused(_ paused: Bool, for consumer: Consumer) {
        let wasPaused = automaticRefreshPaused
        if paused {
            pausedAutomaticRefreshConsumers.insert(consumer)
        } else {
            pausedAutomaticRefreshConsumers.remove(consumer)
        }
        let isPaused = automaticRefreshPaused
        guard wasPaused != isPaused else { return }
        if isPaused {
            cancelAutomaticWork()
        } else if !activeConsumers.isEmpty {
            refresh()
        }
    }

    private var automaticRefreshPaused: Bool {
        !activeConsumers.isEmpty
            && activeConsumers.isSubset(of: pausedAutomaticRefreshConsumers)
    }

    private func cancelAutomaticWork() {
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        selectionScanTask?.cancel()
        selectionScanTask = nil
        activeRolloutScanTask?.cancel()
        activeRolloutScanTask = nil
        isScanningSelectedTask = false
        lastScannedSignature = ""
    }

    private func stopAllWork() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancelAutomaticWork()
    }

    func refresh(force: Bool = false) {
        guard SandboxPaths.isDirectDistribution,
              !activeConsumers.isEmpty,
              (force || !automaticRefreshPaused) else { return }
        if isRefreshing {
            guard force else { return }
            // A newly focused Agent task is more important than an older
            // periodic refresh. Upgrade the in-flight request so the forced
            // catalog lookup is not delayed until the next 12-second window.
            cancelAutomaticWork()
        }
        isRefreshing = true
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.refreshGeneration == generation {
                    self.isRefreshing = false
                    self.refreshTask = nil
                }
            }
            let now = Date()
            let shouldRefreshCatalog = force
                || self.tasks.isEmpty
                || self.lastTaskCatalogRefreshAt.map {
                    now.timeIntervalSince($0) >= Self.taskCatalogRefreshInterval
                } != false

            if shouldRefreshCatalog {
                let snapshots = await CodexControlPlaneService.shared.sessionSnapshots()
                guard !Task.isCancelled, self.refreshGeneration == generation else { return }
                let snapshotTasks = snapshots.map {
                    ArtifactShelfTask(id: $0.id, title: $0.preview, cwd: $0.cwd, rolloutPath: $0.sourcePath, updatedAt: $0.updatedAt, phase: $0.phase)
                }
                let localCodexTasks = await Task.detached(priority: .utility) {
                    Self.loadLocalCodexTasks()
                }.value
                guard !Task.isCancelled, self.refreshGeneration == generation else { return }
                var merged = Dictionary(uniqueKeysWithValues: snapshotTasks.map { ($0.id, $0) })
                for local in localCodexTasks {
                    if let live = merged[local.id] {
                        let liveTitle = live.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let genericLiveTitle = liveTitle.isEmpty || ["codex 会话", "codex session"].contains(liveTitle.lowercased())
                        merged[local.id] = ArtifactShelfTask(
                            id: local.id,
                            title: genericLiveTitle ? local.title : live.title,
                            cwd: local.cwd.isEmpty ? live.cwd : local.cwd,
                            rolloutPath: local.rolloutPath.isEmpty ? live.rolloutPath : local.rolloutPath,
                            updatedAt: max(local.updatedAt, live.updatedAt),
                            phase: live.phase
                        )
                    } else {
                        merged[local.id] = local
                    }
                }
                let nextTasks = merged.values.sorted { $0.updatedAt > $1.updatedAt }
                if self.tasks != nextTasks {
                    self.tasks = nextTasks
                }
                self.followCurrentTask(in: nextTasks)
                self.lastTaskCatalogRefreshAt = now
            }
            guard !Task.isCancelled, self.refreshGeneration == generation else { return }
            await self.scanSelectedTask(force: force)
        }
        refreshTask = task
    }

    func selectTask(_ id: String) {
        restoredSelectionPending = false
        updateSelectedTaskID(id)
        UserDefaults.standard.set(id, forKey: Self.selectedTaskDefaultsKey)
        manualSelectionUntil = Date().addingTimeInterval(10 * 60)
        lastScannedSignature = ""
        scanTaskSelection(id: id)
    }

    /// A manual picker selection remains fixed while companion-window
    /// following is paused. Resuming follow releases the lock immediately.
    func setManualSelectionLocked(_ locked: Bool) {
        if locked, selectedTaskID != nil {
            manualSelectionUntil = .distantFuture
            // A Picker selection and the pause action happen in the same main-
            // actor turn. Drop the previous foreground lease so the next
            // catalog refresh cannot overwrite that manual choice before the
            // paused state has a chance to take effect.
            externallyFocusedTaskID = nil
            externalFocusUpdatedAt = nil
            setFocusMatchIsExact(false)
        } else if !locked {
            manualSelectionUntil = nil
        }
    }

    func focusTask(title: String?, projectHint: String?, bundleIdentifier: String) {
        let agentID = Self.agentID(for: bundleIdentifier)
        let nextAgentName = Self.agentDisplayName(for: agentID)
        if focusedAgentName != nextAgentName { focusedAgentName = nextAgentName }
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextFocusedTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
        if focusedTaskTitle != nextFocusedTitle { focusedTaskTitle = nextFocusedTitle }

        let agentTasks = tasks.filter { $0.agentID == agentID }
        guard !agentTasks.isEmpty else {
            setFocusMatchIsExact(false)
            externallyFocusedTaskID = nil
            externalFocusUpdatedAt = Date()
            // focusTask can run before the first asynchronous task refresh.
            // Keep a restored/manual choice alive until that refresh has had a
            // chance to resolve its task instead of clearing it at launch.
            if tasks.isEmpty,
               let manualSelectionUntil, manualSelectionUntil > Date(), selectedTaskID != nil {
                return
            }
            updateSelectedTaskID(nil)
            return
        }

        if let focusedTaskTitle {
            let wanted = Self.normalizedMatchText(focusedTaskTitle)
            var exactMatches = agentTasks.filter { Self.normalizedMatchText($0.title) == wanted }
            if exactMatches.isEmpty, wanted.count >= 4 {
                exactMatches = agentTasks.filter {
                    let candidate = Self.normalizedMatchText($0.title)
                    return candidate.hasPrefix(wanted) || wanted.hasPrefix(candidate)
                }
            }
            if exactMatches.count > 1, let project = Self.projectName(from: projectHint) {
                let projectMatches = exactMatches.filter {
                    Self.normalizedMatchText(URL(fileURLWithPath: $0.cwd).lastPathComponent) == Self.normalizedMatchText(project)
                }
                if !projectMatches.isEmpty { exactMatches = projectMatches }
            }
            if let matched = exactMatches.max(by: { $0.updatedAt < $1.updatedAt }) {
                applyExternalFocus(matched, exact: true)
                return
            }

            setFocusMatchIsExact(false)
            externalFocusUpdatedAt = Date()
            if let manualSelectionUntil, manualSelectionUntil > Date(),
               let selectedTask, selectedTask.agentID == agentID {
                return
            }
            externallyFocusedTaskID = nil
            updateSelectedTaskID(nil)
            return
        }

        if let manualSelectionUntil, manualSelectionUntil > Date(),
           let selectedTask, selectedTask.agentID == agentID {
            setFocusMatchIsExact(false)
            return
        }

        let fallback = agentTasks.first(where: { Self.activePhases.contains($0.phase) }) ?? agentTasks[0]
        applyExternalFocus(fallback, exact: false)
    }

    /// Keeps the current agent-derived selection stable while the companion
    /// panel itself temporarily owns keyboard focus.
    func retainExternalFocus() {
        guard externallyFocusedTaskID == selectedTaskID else { return }
        externalFocusUpdatedAt = Date()
    }

    func addBookmark(_ candidate: ArtifactShelfCandidate) {
        guard let selectedTaskID else { return }
        if let index = bookmarks.firstIndex(where: { $0.taskID == selectedTaskID && $0.target == candidate.target }) {
            bookmarks[index].updatedAt = Date()
        } else {
            let nextOrder = (bookmarks.filter { $0.taskID == selectedTaskID }.map(\.sortOrder).max() ?? -1) + 1
            bookmarks.append(.init(
                id: UUID(), taskID: selectedTaskID, kind: candidate.kind, target: candidate.target,
                title: candidate.title, sortOrder: nextOrder, createdAt: Date(), updatedAt: Date()
            ))
        }
        saveBookmarks()
    }

    func addTarget(_ rawTarget: String) {
        guard let candidate = Self.candidate(from: rawTarget, discoveredAt: Date(), context: nil) else { return }
        addBookmark(candidate)
    }

    func removeBookmark(_ bookmark: ArtifactShelfBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        normalizeOrders(for: bookmark.taskID)
        saveBookmarks()
    }

    func renameBookmark(_ bookmark: ArtifactShelfBookmark, title: String) {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index].title = String(value.prefix(160))
        bookmarks[index].updatedAt = Date()
        saveBookmarks()
    }

    func moveBookmark(_ bookmark: ArtifactShelfBookmark, offset: Int) {
        var ordered = bookmarks.filter { $0.taskID == bookmark.taskID }.sorted { $0.sortOrder < $1.sortOrder }
        guard let oldIndex = ordered.firstIndex(where: { $0.id == bookmark.id }) else { return }
        let newIndex = min(max(0, oldIndex + offset), ordered.count - 1)
        guard newIndex != oldIndex else { return }
        let item = ordered.remove(at: oldIndex)
        ordered.insert(item, at: newIndex)
        for (order, row) in ordered.enumerated() {
            if let index = bookmarks.firstIndex(where: { $0.id == row.id }) { bookmarks[index].sortOrder = order }
        }
        saveBookmarks()
    }

    func open(_ target: String) {
        guard let url = targetURL(target) else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ target: String) {
        guard !Self.isHTTPURL(target) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
    }

    func copyTarget(_ target: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(target, forType: .string)
    }

    func thumbnail(for item: ArtifactShelfCandidate) -> NSImage? {
        thumbnail(kind: item.kind, target: item.target)
    }

    func thumbnail(for item: ArtifactShelfBookmark) -> NSImage? {
        thumbnail(kind: item.kind, target: item.target)
    }

    private func thumbnail(kind: ArtifactShelfCandidate.Kind, target: String) -> NSImage? {
        guard kind == .image,
              let attributes = try? FileManager.default.attributesOfItem(atPath: target) else { return nil }
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let key = "\(target)|\(modifiedAt)|\(fileSize)" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let url = URL(fileURLWithPath: target) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
        let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 192,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let cost = min(Int.max, cgImage.bytesPerRow * cgImage.height)
        thumbnailCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    private func followCurrentTask(in nextTasks: [ArtifactShelfTask]) {
        guard !nextTasks.isEmpty else {
            if let manualSelectionUntil, manualSelectionUntil > Date(), selectedTaskID != nil {
                return
            }
            updateSelectedTaskID(nil)
            return
        }
        if let externallyFocusedTaskID,
           let externalFocusUpdatedAt,
           Date().timeIntervalSince(externalFocusUpdatedAt) < 8,
           nextTasks.contains(where: { $0.id == externallyFocusedTaskID }) {
            updateSelectedTaskID(externallyFocusedTaskID)
            return
        }
        if let manualSelectionUntil, manualSelectionUntil > Date(),
           let selectedTaskID, nextTasks.contains(where: { $0.id == selectedTaskID }) {
            return
        }
        if restoredSelectionPending {
            restoredSelectionPending = false
            let current = nextTasks.first(where: { Self.activePhases.contains($0.phase) }) ?? nextTasks[0]
            updateSelectedTaskID(current.id)
            return
        }
        if let selectedTaskID, nextTasks.contains(where: { $0.id == selectedTaskID }) {
            let active = nextTasks.first { Self.activePhases.contains($0.phase) }
            if let active, selectedTask?.phase == "idle", active.id != selectedTaskID {
                updateSelectedTaskID(active.id)
            }
            return
        }
        updateSelectedTaskID(nextTasks.first(where: { Self.activePhases.contains($0.phase) })?.id ?? nextTasks[0].id)
    }

    private func applyExternalFocus(_ task: ArtifactShelfTask, exact: Bool) {
        externalFocusUpdatedAt = Date()
        externallyFocusedTaskID = task.id
        setFocusMatchIsExact(exact)
        if exact {
            UserDefaults.standard.set(task.id, forKey: Self.selectedTaskDefaultsKey)
        }
        guard selectedTaskID != task.id else { return }
        updateSelectedTaskID(task.id)
        scanTaskSelection(id: task.id)
    }

    private func setFocusMatchIsExact(_ exact: Bool) {
        if focusMatchIsExact != exact { focusMatchIsExact = exact }
    }

    @discardableResult
    private func updateSelectedTaskID(_ id: String?) -> Bool {
        guard selectedTaskID != id else { return false }
        selectionScanTask?.cancel()
        selectionScanTask = nil
        activeRolloutScanTask?.cancel()
        activeRolloutScanTask = nil
        selectionGeneration &+= 1
        scanRequestGeneration &+= 1
        isScanningSelectedTask = false
        selectedTaskID = id
        candidates = []
        lastError = nil
        lastScannedSignature = ""
        return true
    }

    private func scanTaskSelection(id: String, requireCompleteHistory: Bool? = nil) {
        selectionScanTask?.cancel()
        activeRolloutScanTask?.cancel()
        selectionGeneration &+= 1
        let generation = selectionGeneration
        let shouldRequireCompleteHistory = requireCompleteHistory
            ?? !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isScanningSelectedTask = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.scanSelectedTask(
                force: true,
                selectionGeneration: generation,
                requireCompleteHistory: shouldRequireCompleteHistory
            )
            if self.selectionGeneration == generation, self.selectedTaskID == id {
                self.isScanningSelectedTask = false
                self.selectionScanTask = nil
            }
        }
        selectionScanTask = task
    }

    private func scanSelectedTask(
        force: Bool,
        selectionGeneration expectedSelectionGeneration: UInt64? = nil,
        requireCompleteHistory requestedCompleteHistory: Bool? = nil
    ) async {
        let requireCompleteHistory = requestedCompleteHistory
            ?? !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let selectionGenerationAtStart = expectedSelectionGeneration ?? selectionGeneration
        guard let task = selectedTask else {
            if selectionGeneration == selectionGenerationAtStart {
                candidates = []
            }
            return
        }
        let path = task.rolloutPath
        let hasRolloutPath = !path.isEmpty
        let attributes: [FileAttributeKey: Any]? = hasRolloutPath
            ? (try? FileManager.default.attributesOfItem(atPath: path))
            : nil
        let size = attributes?[.size] as? NSNumber
        let modified = attributes?[.modificationDate] as? Date
        let fileIdentifier = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        let signature = "\(task.id)|\(size?.int64Value ?? 0)|\(modified?.timeIntervalSince1970 ?? 0)|\(task.updatedAt.timeIntervalSince1970)"
        guard force || signature != lastScannedSignature else { return }
        scanRequestGeneration &+= 1
        let requestGeneration = scanRequestGeneration
        lastScannedSignature = signature

        if hasRolloutPath, var cached = rolloutScanCache[path],
           cached.size == (size?.int64Value ?? 0),
           cached.modifiedAt == modified,
           cached.fileIdentifier == nil || fileIdentifier == nil || cached.fileIdentifier == fileIdentifier,
           !requireCompleteHistory || cached.scanState?.historyComplete != false {
            cached.lastAccessedAt = Date()
            rolloutScanCache[path] = cached
            guard selectionGeneration == selectionGenerationAtStart,
                  scanRequestGeneration == requestGeneration,
                  selectedTaskID == task.id else { return }
            candidates = cached.candidates
            lastError = nil
            return
        }

        let context = ScanContext(cwd: task.cwd, rolloutPath: path)
        var previousState: RolloutScanState?
        if let cached = rolloutScanCache[path],
           let cachedState = cached.scanState,
           !requireCompleteHistory || cachedState.historyComplete,
           let currentSize = size?.int64Value,
           currentSize > cached.size,
           cached.fileIdentifier == nil || fileIdentifier == nil || cached.fileIdentifier == fileIdentifier {
            previousState = cachedState
        }
        // The local JSONL is the authoritative source and can be streamed on a
        // utility executor. Avoid thread/read here: it returns the entire task
        // as one JSON-RPC record and its decoder can stall the main actor even
        // for apparently small rollouts.
        var result: [ArtifactShelfCandidate] = []
        guard !Task.isCancelled else { return }
        var rolloutState: RolloutScanState?
        if hasRolloutPath {
            activeRolloutScanTask?.cancel()
            let initialReadLimit: UInt64? = requireCompleteHistory ? nil : Self.initialRolloutReadLimit
            let scanTask = Task.detached(priority: .utility) {
                Self.scanRollout(
                    path: path,
                    context: context,
                    previousState: previousState,
                    initialReadLimit: initialReadLimit
                )
            }
            activeRolloutScanTask = scanTask
            rolloutState = await scanTask.value
            if scanRequestGeneration == requestGeneration {
                activeRolloutScanTask = nil
            }
            guard !Task.isCancelled, let rolloutState else {
                if scanRequestGeneration == requestGeneration,
                   selectionGeneration == selectionGenerationAtStart,
                   selectedTaskID == task.id {
                    lastScannedSignature = ""
                }
                return
            }
            let rolloutCandidates = Self.candidates(from: rolloutState)
            result = rolloutCandidates
        }
        if hasRolloutPath {
            let finalAttributes = try? FileManager.default.attributesOfItem(atPath: path)
            let finalSize = (finalAttributes?[.size] as? NSNumber)?.int64Value ?? size?.int64Value ?? 0
            let scannedSize = rolloutState.map { Int64(clamping: $0.scannedOffset) } ?? finalSize
            rolloutScanCache[path] = RolloutScanCacheEntry(
                size: scannedSize,
                modifiedAt: finalAttributes?[.modificationDate] as? Date ?? modified,
                fileIdentifier: (finalAttributes?[.systemFileNumber] as? NSNumber)?.uint64Value ?? fileIdentifier,
                candidates: result,
                scanState: rolloutState,
                lastAccessedAt: Date()
            )
            trimRolloutScanCache()
        }
        guard selectionGeneration == selectionGenerationAtStart,
              scanRequestGeneration == requestGeneration,
              selectedTaskID == task.id else { return }
        candidates = result
        if hasRolloutPath {
            lastError = FileManager.default.fileExists(atPath: path) ? nil : "Task log is unavailable."
        } else {
            lastError = "Task history is unavailable."
        }
    }

    private struct ScanContext: Sendable {
        let cwd: String
        let rolloutPath: String
    }

    nonisolated private static func scanArtifactMessages(
        _ messages: [CodexArtifactMessageSnapshot],
        context: ScanContext
    ) -> [ArtifactShelfCandidate] {
        var finalDeliveries: [String: ArtifactShelfCandidate] = [:]
        for message in messages {
            guard message.isFinalAnswer else { continue }
            let discoveredAt = Date(timeIntervalSinceReferenceDate: TimeInterval(message.order))
            for raw in extractTargets(from: message.text) {
                guard let candidate = candidate(from: raw, discoveredAt: discoveredAt, context: context),
                      isUserFacingArtifact(candidate) else { continue }
                finalDeliveries[candidate.target] = candidate
            }
        }
        return sortedCandidates(finalDeliveries.values)
    }

    nonisolated private static func scanRollout(
        path: String,
        context: ScanContext,
        previousState: RolloutScanState?,
        initialReadLimit: UInt64?
    ) -> RolloutScanState? {
        guard !Task.isCancelled,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let emptyState = RolloutScanState(
            scannedOffset: 0,
            finalDeliveries: [:],
            lastUnphasedDeliveries: [:],
            pendingLine: Data(),
            pendingLineWasConsumed: false,
            skippingOversizedLine: false,
            historyComplete: true
        )
        var state = previousState ?? emptyState
        do {
            let currentFileSize = try handle.seekToEnd()
            let needsFreshScan = previousState == nil || currentFileSize < state.scannedOffset
            if currentFileSize < state.scannedOffset {
                state = emptyState
            }
            if needsFreshScan, let initialReadLimit, currentFileSize > initialReadLimit {
                state.scannedOffset = currentFileSize - initialReadLimit
                state.historyComplete = false
            }
            try handle.seek(toOffset: state.scannedOffset)
        } catch {
            return nil
        }
        let initialPendingLineCount = state.pendingLine.count
        let initialPendingLineWasConsumed = state.pendingLineWasConsumed
        var scannedOffset = state.scannedOffset
        let compactAssistantRole = Data("\"role\":\"assistant\"".utf8)
        let spacedAssistantRole = Data("\"role\": \"assistant\"".utf8)
        let compactAgentMessage = Data("\"type\":\"agent_message\"".utf8)
        let spacedAgentMessage = Data("\"type\": \"agent_message\"".utf8)
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func consume(_ line: Data) {
            guard !line.isEmpty,
                  line.range(of: compactAssistantRole) != nil
                    || line.range(of: spacedAssistantRole) != nil
                    || line.range(of: compactAgentMessage) != nil
                    || line.range(of: spacedAgentMessage) != nil,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let selected = assistantText(from: object) else { return }
            let discoveredAt = (object["timestamp"] as? String).flatMap(timestampFormatter.date(from:)) ?? Date()
            let payload = object["payload"] as? [String: Any]
            let phase = (payload?["phase"] as? String ?? object["phase"] as? String ?? "").lowercased()
            let isFinalAnswer = phase == "final_answer" || phase == "finalanswer"
            var messageDeliveries: [String: ArtifactShelfCandidate] = [:]
            for raw in extractTargets(from: selected) {
                guard let candidate = candidate(from: raw, discoveredAt: discoveredAt, context: context),
                      isUserFacingArtifact(candidate) else { continue }
                messageDeliveries[candidate.target] = candidate
            }
            if isFinalAnswer {
                for (target, candidate) in messageDeliveries {
                    state.finalDeliveries[target] = candidate
                }
            } else if phase.isEmpty {
                // Claude/Cursor history formats do not always tag phases. In
                // that case the last assistant message is the closest reliable
                // equivalent of a final response; do not union intermediate
                // messages into the user-facing artifact list.
                state.lastUnphasedDeliveries = messageDeliveries
            }
        }

        // Historical Codex tasks can be hundreds of megabytes because tool
        // output lives in the same JSONL. Stream every record instead of only
        // reading the last few MiB, and prefilter non-assistant lines before
        // JSON decoding so old artifact cards remain discoverable cheaply.
        let chunkSize = 1_024 * 1_024
        let maximumRecordSize = 8 * 1_024 * 1_024
        var buffer = state.pendingLine
        var searchOffset = buffer.count
        var isFirstBufferedLine = true
        var reachedEOF = false
        var cancelled = false
        var skippingOversizedLine = state.skippingOversizedLine
        while !reachedEOF && !cancelled {
            if Task.isCancelled { return nil }
            autoreleasepool {
                let chunk: Data
                do {
                    guard let next = try handle.read(upToCount: chunkSize), !next.isEmpty else {
                        reachedEOF = true
                        return
                    }
                    chunk = next
                } catch {
                    reachedEOF = true
                    return
                }
                scannedOffset &+= UInt64(chunk.count)
                buffer.append(chunk)
                if skippingOversizedLine {
                    guard let newline = buffer.firstIndex(of: 0x0A) else {
                        // Keep memory bounded while discarding a record that
                        // cannot contain a practical user-facing final link.
                        buffer = Data()
                        searchOffset = 0
                        return
                    }
                    let afterNewline = buffer.index(after: newline)
                    buffer = afterNewline < buffer.endIndex ? Data(buffer[afterNewline...]) : Data()
                    skippingOversizedLine = false
                    searchOffset = 0
                    isFirstBufferedLine = false
                }
                var lineStart = buffer.startIndex
                var searchStart = buffer.index(
                    buffer.startIndex,
                    offsetBy: min(searchOffset, buffer.count)
                )
                while searchStart < buffer.endIndex,
                      let newline = buffer[searchStart...].firstIndex(of: 0x0A) {
                    if Task.isCancelled {
                        cancelled = true
                        return
                    }
                    let lineLength = buffer.distance(from: lineStart, to: newline)
                    let alreadyConsumedPendingLine = isFirstBufferedLine
                        && initialPendingLineWasConsumed
                        && lineLength == initialPendingLineCount
                    if !alreadyConsumedPendingLine,
                       lineLength <= maximumRecordSize {
                        consume(buffer[lineStart..<newline])
                    }
                    isFirstBufferedLine = false
                    lineStart = buffer.index(after: newline)
                    searchStart = lineStart
                }
                if lineStart > buffer.startIndex {
                    buffer = lineStart < buffer.endIndex ? Data(buffer[lineStart...]) : Data()
                }
                if buffer.count > maximumRecordSize {
                    buffer = Data()
                    skippingOversizedLine = true
                }
                // The remaining suffix has already been checked for a newline;
                // the next chunk only needs to scan newly appended bytes.
                searchOffset = buffer.count
            }
        }
        guard !cancelled, !Task.isCancelled else { return nil }
        if !skippingOversizedLine, !buffer.isEmpty {
            autoreleasepool { consume(buffer) }
        }
        state.scannedOffset = scannedOffset
        state.pendingLine = buffer
        state.pendingLineWasConsumed = !skippingOversizedLine && !buffer.isEmpty
        state.skippingOversizedLine = skippingOversizedLine
        return state
    }

    nonisolated private static func candidates(from state: RolloutScanState) -> [ArtifactShelfCandidate] {
        let selected = state.finalDeliveries.isEmpty
            ? state.lastUnphasedDeliveries
            : state.finalDeliveries
        return sortedCandidates(selected.values)
    }

    nonisolated private static func assistantText(from record: [String: Any]) -> String? {
        let payload = record["payload"] as? [String: Any]
        if let payload, record["type"] as? String == "response_item",
           payload["type"] as? String == "message", payload["role"] as? String == "assistant" {
            return collectStrings(payload["content"]).joined(separator: "\n")
        }
        if let payload, record["type"] as? String == "event_msg", payload["type"] as? String == "agent_message" {
            return payload["message"] as? String
        }
        if let message = record["message"] as? [String: Any],
           message["role"] as? String == "assistant" {
            return collectAssistantText(message["content"]).joined(separator: "\n")
        }
        if record["role"] as? String == "assistant" {
            return collectAssistantText(record["content"]).joined(separator: "\n")
        }
        return nil
    }

    nonisolated private static func collectAssistantText(_ value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] { return array.flatMap(collectAssistantText) }
        guard let dictionary = value as? [String: Any] else { return [] }
        let type = (dictionary["type"] as? String ?? "").lowercased()
        if type.isEmpty || ["text", "output_text", "input_text"].contains(type) {
            if let text = dictionary["text"] as? String { return [text] }
            if let text = dictionary["content"] as? String { return [text] }
        }
        return []
    }

    nonisolated private static func collectStrings(_ value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] { return array.flatMap(collectStrings) }
        if let dictionary = value as? [String: Any] {
            return dictionary.filter { $0.key != "encrypted_content" }.flatMap { collectStrings($0.value) }
        }
        return []
    }

    nonisolated private static func extractTargets(from text: String) -> [String] {
        // Markdown links are an explicit presentation choice in the final
        // answer and most closely match Codex's own file cards. If at least
        // one local Markdown destination exists, ignore incidental bare paths
        // elsewhere in the prose.
        if !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            let markdownTargets: [String] = ArtifactShelfPatterns.markdownTarget.matches(in: text, range: range).compactMap { match in
                for captureIndex in 1..<match.numberOfRanges {
                    let capture = match.range(at: captureIndex)
                    guard capture.location != NSNotFound,
                          let targetRange = Range(capture, in: text) else { continue }
                    let target = String(text[targetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !target.isEmpty { return target }
                }
                return nil
            }
            let hasLocalMarkdownTarget = markdownTargets.contains {
                let value = $0.lowercased()
                return value.hasPrefix("/") || value.hasPrefix("file://")
            }
            if hasLocalMarkdownTarget {
                var seen: Set<String> = []
                return markdownTargets.filter { seen.insert($0).inserted }
            }
        }

        var result: [String] = []
        for regex in ArtifactShelfPatterns.rawTargets {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let range = Range(match.range, in: text) { result.append(String(text[range])) }
            }
        }
        var seen: Set<String> = []
        return result.filter { seen.insert($0).inserted }
    }

    nonisolated private static func candidate(from raw: String, discoveredAt: Date, context: ScanContext?) -> ArtifactShelfCandidate? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?，。；：！？、)]}>）】》」』"))
        if isHTTPURL(value) {
            guard let url = URL(string: value), !isSensitive(url: url) else { return nil }
            return .init(kind: .url, target: url.absoluteString, title: url.host ?? url.absoluteString, discoveredAt: discoveredAt, exists: true)
        }
        if value.hasPrefix("file://"), let url = URL(string: value) { value = url.path }
        value = value.replacingOccurrences(of: #"[#:]L?\d+(?::\d+)?$"#, with: "", options: .regularExpression)
        while !FileManager.default.fileExists(atPath: value), let space = value.lastIndex(of: " ") {
            value = String(value[..<space]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard value.hasPrefix("/"), !isSensitive(path: value, context: context) else { return nil }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: value, isDirectory: &isDirectory)
        guard exists else { return nil }
        let ext = URL(fileURLWithPath: value).pathExtension.lowercased()
        let kind: ArtifactShelfCandidate.Kind = isDirectory.boolValue ? .directory
            : ["png", "jpg", "jpeg", "gif", "webp", "heic", "avif"].contains(ext) ? .image
            : ["html", "htm"].contains(ext) ? .html : .file
        return .init(kind: kind, target: value, title: URL(fileURLWithPath: value).lastPathComponent, discoveredAt: discoveredAt, exists: exists)
    }

    nonisolated private static func isSensitive(url: URL) -> Bool {
        if url.user != nil || url.password != nil { return true }
        return url.queryItems?.contains { item in
            item.name.range(of: #"(^|[_-])(access[_-]?token|refresh[_-]?token|token|api[_-]?key|secret|signature|credential|authorization|auth|sig|key)([_-]|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
        } ?? false
    }

    nonisolated private static func isSensitive(path: String, context: ScanContext?) -> Bool {
        let lower = path.lowercased().replacingOccurrences(of: "\\", with: "/")
        let parts = lower.split(separator: "/").map(String.init)
        if parts.contains(where: { $0.hasPrefix(".") && $0 != ".well-known" }) { return true }
        if parts.contains(where: {
            ArtifactShelfPatterns.sensitivePathComponent.firstMatch(
                in: $0,
                range: NSRange($0.startIndex..., in: $0)
            ) != nil
        }) { return true }
        if lower.contains("/node_modules/") || lower.contains("/.git/") || lower.contains("/.codex/sessions/") || lower.contains("/.codex/plugins/cache/") { return true }
        if lower.range(of: #"\.(sqlite3?|db)(-(wal|shm))?$"#, options: .regularExpression) != nil { return true }
        if let context, path == context.cwd || path == context.rolloutPath { return true }
        return false
    }

    nonisolated private static func isHTTPURL(_ value: String) -> Bool {
        value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://")
    }

    /// Automatic discovery is deliberately narrower than manual bookmarks:
    /// show final user deliverables, not implementation files or references.
    nonisolated static func isUserFacingArtifact(_ candidate: ArtifactShelfCandidate) -> Bool {
        guard candidate.kind != .url else { return false }
        let url = URL(fileURLWithPath: candidate.target)
        let ext = url.pathExtension.lowercased()
        if candidate.kind == .directory {
            return !["xcodeproj", "xcworkspace", "playground"].contains(ext)
        }

        let implementationExtensions: Set<String> = [
            "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx", "cs",
            "java", "kt", "kts", "go", "rs", "rb", "php", "py", "pyi", "ipynb",
            "js", "mjs", "cjs", "jsx", "ts", "tsx", "vue", "svelte",
            "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd", "sql", "graphql", "gql",
            "css", "scss", "sass", "less", "yaml", "yml", "toml", "ini", "conf",
            "plist", "xcconfig", "entitlements", "pbxproj"
        ]
        guard !implementationExtensions.contains(ext) else { return false }

        let implementationNames: Set<String> = [
            "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock",
            "podfile", "podfile.lock", "gemfile", "gemfile.lock",
            "requirements.txt", "pyproject.toml", "cargo.toml", "cargo.lock",
            "go.mod", "go.sum", "makefile", "dockerfile"
        ]
        return !implementationNames.contains(url.lastPathComponent.lowercased())
    }

    /// A conservative presentation hint, not a destructive filter. These
    /// items stay in `candidates` and reappear as soon as the user searches.
    nonisolated private static func isLikelyProcessArtifact(_ candidate: ArtifactShelfCandidate) -> Bool {
        let tail = candidate.target
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .suffix(2)
            .joined(separator: "/")
            .lowercased()
        let chineseMarkers = [
            "内部", "待审", "候选", "底稿", "质检", "审校", "台账", "参考资料", "草稿"
        ]
        if chineseMarkers.contains(where: tail.contains) { return true }
        let englishTokens = tail
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let processTokens: Set<String> = ["draft", "working", "intermediate", "tmp", "temp"]
        return !Set(englishTokens).isDisjoint(with: processTokens)
    }

    private static let activePhases: Set<String> = ["processing", "waitingApproval", "waitingInput", "compacting"]

    private static func agentID(for bundleIdentifier: String) -> String {
        switch bundleIdentifier {
        case "com.openai.codex": return "codex"
        case "com.anthropic.claudefordesktop": return "claude"
        case "com.todesktop.230313mzl4w4u92": return "cursor"
        default: return "codex"
        }
    }

    private static func agentDisplayName(for agentID: String) -> String {
        switch agentID {
        case "codex": return "Codex"
        case "claude": return "Claude"
        case "cursor": return "Cursor"
        default: return agentID.capitalized
        }
    }

    nonisolated private static func normalizedMatchText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    nonisolated private static func projectName(from hint: String?) -> String? {
        var value = hint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for suffix in ["中的已安排任务", "的已安排任务", " scheduled tasks"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        return value.isEmpty || ["置顶", "pinned"].contains(value.lowercased()) ? nil : value
    }

    nonisolated private static func nativeThreadID(from taskID: String) -> String {
        taskID.split(separator: "|", omittingEmptySubsequences: true).last.map(String.init) ?? taskID
    }

    nonisolated private static func sortedCandidates<S: Sequence>(_ values: S) -> [ArtifactShelfCandidate]
    where S.Element == ArtifactShelfCandidate {
        values
            .sorted {
                $0.discoveredAt == $1.discoveredAt
                    ? $0.target.localizedStandardCompare($1.target) == .orderedAscending
                    : $0.discoveredAt > $1.discoveredAt
            }
            .prefix(400)
            .map { $0 }
    }

    nonisolated private static func loadLocalCodexTasks() -> [ArtifactShelfTask] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            home + "/.codex/state_5.sqlite",
            home + "/.codex/sqlite/state_5.sqlite"
        ].filter { FileManager.default.fileExists(atPath: $0) }
        guard let path = candidates.max(by: {
            let left = (try? FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date) ?? .distantPast
            let right = (try? FileManager.default.attributesOfItem(atPath: $1)[.modificationDate] as? Date) ?? .distantPast
            return left < right
        }) else { return [] }

        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close(database) }
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 350)

        let sql = """
        SELECT id, title, preview, cwd, rollout_path,
               COALESCE(NULLIF(recency_at, 0), updated_at)
          FROM threads
         WHERE archived = 0 AND rollout_path <> ''
         ORDER BY recency_at DESC, updated_at DESC
         LIMIT 320
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        func string(at index: Int32) -> String {
            guard let value = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: value)
        }

        var result: [ArtifactShelfTask] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = string(at: 0)
            let title = string(at: 1).trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = string(at: 2).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            var timestamp = sqlite3_column_double(statement, 5)
            if timestamp > 10_000_000_000 { timestamp /= 1_000 }
            result.append(ArtifactShelfTask(
                id: id,
                title: String((title.isEmpty ? preview : title).prefix(180)),
                cwd: string(at: 3),
                rolloutPath: string(at: 4),
                updatedAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : .distantPast,
                phase: "idle"
            ))
        }
        return result
    }

    private func targetURL(_ target: String) -> URL? {
        Self.isHTTPURL(target) ? URL(string: target) : URL(fileURLWithPath: target)
    }

    private func matchesSearch(_ title: String, _ target: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || title.localizedCaseInsensitiveContains(query) || target.localizedCaseInsensitiveContains(query)
    }

    private func normalizeOrders(for taskID: String) {
        let rows = bookmarks.filter { $0.taskID == taskID }.sorted { $0.sortOrder < $1.sortOrder }
        for (order, row) in rows.enumerated() {
            if let index = bookmarks.firstIndex(where: { $0.id == row.id }) { bookmarks[index].sortOrder = order }
        }
    }

    private func trimRolloutScanCache() {
        guard rolloutScanCache.count > 16 else { return }
        let overflow = rolloutScanCache.count - 16
        let stalePaths = rolloutScanCache
            .sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
            .prefix(overflow)
            .map(\.key)
        stalePaths.forEach { rolloutScanCache.removeValue(forKey: $0) }
    }

    private func loadBookmarks() {
        let url = URL(fileURLWithPath: SandboxPaths.shared.artifactShelfPath)
        guard let data = try? Data(contentsOf: url), let decoded = try? decoder.decode([ArtifactShelfBookmark].self, from: data) else { return }
        bookmarks = decoded
    }

    private func saveBookmarks() {
        guard let data = try? encoder.encode(bookmarks) else { return }
        try? data.write(to: URL(fileURLWithPath: SandboxPaths.shared.artifactShelfPath), options: .atomic)
    }
}

private extension URL {
    var queryItems: [URLQueryItem]? { URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems }
}
