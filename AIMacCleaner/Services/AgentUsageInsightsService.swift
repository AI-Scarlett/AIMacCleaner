import Combine
import CryptoKit
import Darwin
import Foundation
import SQLite3

// MARK: - Public domain model

/// The local runtime whose metadata is represented by an insights snapshot.
enum AgentUsageScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude
    case openCode
    case openClaw
    case combined

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .openCode: return "OpenCode"
        case .openClaw: return "OpenClaw / QClaw"
        case .combined: return "All trusted sources"
        }
    }
}

/// Every date boundary in one refresh uses this single preference.
enum AgentUsageTimeZoneMode: Equatable, Sendable {
    case system
    case utc
    case fixed(identifier: String)

    var resolvedTimeZone: TimeZone {
        switch self {
        case .system:
            return .current
        case .utc:
            return TimeZone(secondsFromGMT: 0)!
        case let .fixed(identifier):
            return TimeZone(identifier: identifier) ?? .current
        }
    }

    fileprivate var storedValue: String {
        switch self {
        case .system: return "system"
        case .utc: return "utc"
        case let .fixed(identifier): return "fixed:\(identifier)"
        }
    }

    fileprivate init(storedValue: String?) {
        guard let storedValue else {
            self = .system
            return
        }
        if storedValue == "utc" {
            self = .utc
        } else if storedValue.hasPrefix("fixed:"),
                  TimeZone(identifier: String(storedValue.dropFirst("fixed:".count))) != nil {
            self = .fixed(identifier: String(storedValue.dropFirst("fixed:".count)))
        } else {
            self = .system
        }
    }
}

extension AgentUsageTimeZoneMode: Codable {
    private enum CodingKeys: String, CodingKey { case kind, identifier }
    private enum Kind: String, Codable { case system, utc, fixed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .system: self = .system
        case .utc: self = .utc
        case .fixed:
            let identifier = try container.decode(String.self, forKey: .identifier)
            self = TimeZone(identifier: identifier) == nil ? .system : .fixed(identifier: identifier)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .system:
            try container.encode(Kind.system, forKey: .kind)
        case .utc:
            try container.encode(Kind.utc, forKey: .kind)
        case let .fixed(identifier):
            try container.encode(Kind.fixed, forKey: .kind)
            try container.encode(identifier, forKey: .identifier)
        }
    }
}

struct AgentUsageTokenTotals: Codable, Equatable, Sendable {
    var input: Int64
    var cached: Int64
    var output: Int64
    var reasoning: Int64
    var total: Int64

    static let zero = AgentUsageTokenTotals(input: 0, cached: 0, output: 0, reasoning: 0, total: 0)

    var uncachedInput: Int64 { max(0, input - cached) }
    var isZero: Bool { input == 0 && cached == 0 && output == 0 && reasoning == 0 && total == 0 }

    mutating func add(_ other: AgentUsageTokenTotals) {
        input = AgentUsageMath.saturatingAdd(input, other.input)
        cached = AgentUsageMath.saturatingAdd(cached, other.cached)
        output = AgentUsageMath.saturatingAdd(output, other.output)
        reasoning = AgentUsageMath.saturatingAdd(reasoning, other.reasoning)
        total = AgentUsageMath.saturatingAdd(total, other.total)
    }

    func subtractingFloorAtZero(_ other: AgentUsageTokenTotals) -> AgentUsageTokenTotals {
        AgentUsageTokenTotals(
            input: max(0, input - other.input),
            cached: max(0, cached - other.cached),
            output: max(0, output - other.output),
            reasoning: max(0, reasoning - other.reasoning),
            total: max(0, total - other.total)
        )
    }
}

/// Canonical formatter for token headlines across Overview, Token & Usage,
/// and the menu bar. A shared formatter prevents the same snapshot from being
/// presented with different units or rounding on different surfaces.
enum AgentUsageTokenFormatter {
    static func string(_ value: Int64) -> String {
        let amount = Double(max(0, value))
        switch amount {
        case 1_000_000_000...:
            return String(format: "%.2fB", amount / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.2fM", amount / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", amount / 1_000)
        default:
            return String(Int64(amount))
        }
    }

    static func exactString(_ value: Int64) -> String {
        let digits = String(max(0, value))
        var grouped: [Character] = []
        grouped.reserveCapacity(digits.count + digits.count / 3)
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        return String(grouped.reversed())
    }
}

struct AgentUsageValueEstimate: Codable, Equatable, Sendable {
    let todayUSD: Double
    let last7DaysUSD: Double
    let currentMonthUSD: Double
    let allTimeUSD: Double
    let isEstimate: Bool
    let unknownModels: [String]

    static let zero = AgentUsageValueEstimate(
        todayUSD: 0,
        last7DaysUSD: 0,
        currentMonthUSD: 0,
        allTimeUSD: 0,
        isEstimate: true,
        unknownModels: []
    )
}

enum AgentUsageSourceQuality: String, Codable, Equatable, Sendable {
    case detailed
    case approximate
    case mixed
    case unavailable
}

struct AgentUsageDailyBucket: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let date: Date
    let tokens: AgentUsageTokenTotals
    let estimatedAPIValueUSD: Double
    let sourceQuality: AgentUsageSourceQuality
}

struct AgentUsageHeatmapCell: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(weekday)-\(hour)" }
    let weekday: Int
    let hour: Int
    let tokens: Int64
    let eventCount: Int
}

struct AgentUsagePeriodComparison: Codable, Equatable, Sendable {
    let current: AgentUsageTokenTotals
    let previous: AgentUsageTokenTotals
    let changePercent: Double?
    let isNewActivity: Bool
}

struct AgentUsageProjectUsage: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let fullPath: String
    let tokens: AgentUsageTokenTotals
    let estimatedAPIValueUSD: Double
    let sessionCount: Int
    let lastActiveAt: Date?
    let sourceQuality: AgentUsageSourceQuality
}

struct AgentUsageModelUsage: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let scope: AgentUsageScope
    let model: String
    let tokens: AgentUsageTokenTotals
    let estimatedAPIValueUSD: Double
    let sessionCount: Int
    let lastActiveAt: Date?
    let sourceQuality: AgentUsageSourceQuality
}

struct AgentUsageSessionUsage: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let scope: AgentUsageScope
    let projectName: String
    let fullProjectPath: String
    let model: String
    let tokens: AgentUsageTokenTotals
    let estimatedAPIValueUSD: Double
    let lastActiveAt: Date?
    let sourceQuality: AgentUsageSourceQuality
}

struct AgentUsageSourceSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String { scope.rawValue }
    let scope: AgentUsageScope
    let available: Bool
    let partial: Bool
    let parsedFileCount: Int
    let tokenEventCount: Int
    let sourceQuality: AgentUsageSourceQuality
    let diagnosticCount: Int
}

struct AgentUsageToolUsage: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(scope.rawValue):\(name)" }
    let scope: AgentUsageScope
    let name: String
    let category: String
    let callCount: Int
    let estimatedTokens: Int64?
    let estimatedAPIValueUSD: Double?
}

struct AgentUsageSkillUsage: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(scope.rawValue):\(path ?? name)" }
    let scope: AgentUsageScope
    let name: String
    let path: String?
    let loadCount: Int
    let sessionCount: Int
    let staticTokenEstimate: Int64?
    let staticByteCount: Int64?
    let lastLoadedAt: Date?
}

enum AgentUsageTaskCategory: String, Codable, CaseIterable, Sendable {
    case active
    case pending
    case scheduled
    case done
}

struct AgentUsageTaskItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let scope: AgentUsageScope
    let category: AgentUsageTaskCategory
    let title: String
    let project: String?
    let updatedAt: Date?
    let tokens: Int64?
}

struct AgentUsageTaskBoard: Codable, Equatable, Sendable {
    let active: [AgentUsageTaskItem]
    let pending: [AgentUsageTaskItem]
    let scheduled: [AgentUsageTaskItem]
    let done: [AgentUsageTaskItem]

    static let empty = AgentUsageTaskBoard(active: [], pending: [], scheduled: [], done: [])

    var all: [AgentUsageTaskItem] { active + pending + scheduled + done }
}

enum AgentUsageDiagnosticSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

struct AgentUsageDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(scope?.rawValue ?? "all"):\(code):\(message)" }
    let scope: AgentUsageScope?
    let severity: AgentUsageDiagnosticSeverity
    let code: String
    let message: String
    let source: String?
}

struct AgentUsageSnapshot: Codable, Equatable, Sendable {
    let scope: AgentUsageScope
    let generatedAt: Date
    let timeZoneIdentifier: String
    let sourceQuality: AgentUsageSourceQuality
    let isPartial: Bool
    let today: AgentUsageTokenTotals
    let last7Days: AgentUsageTokenTotals
    let currentMonth: AgentUsageTokenTotals
    let allTime: AgentUsageTokenTotals
    /// Portion of `allTime` backed by parsed records with a real token
    /// breakdown. The remainder may come from aggregate-only indexes such as
    /// Codex's SQLite thread totals and must not be assigned to fake fields.
    let allTimeDetailed: AgentUsageTokenTotals
    let estimatedAPIValueUSD: AgentUsageValueEstimate
    let dailyBuckets: [AgentUsageDailyBucket]
    let weekdayHourHeatmap: [AgentUsageHeatmapCell]
    let heatmapThresholds: [Int64]
    let previous7DayComparison: AgentUsagePeriodComparison
    let projectRankings7Days: [AgentUsageProjectUsage]
    let projectRankingsAllTime: [AgentUsageProjectUsage]
    let modelRankings: [AgentUsageModelUsage]
    let recentSessions: [AgentUsageSessionUsage]
    let sourceSummaries: [AgentUsageSourceSummary]
    let topTools: [AgentUsageToolUsage]
    let topSkills: [AgentUsageSkillUsage]
    let tasks: AgentUsageTaskBoard
    let diagnostics: [AgentUsageDiagnostic]
    let parsedFileCount: Int
    let tokenEventCount: Int

    static func empty(scope: AgentUsageScope, now: Date = Date(), timeZone: TimeZone = .current) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            scope: scope,
            generatedAt: now,
            timeZoneIdentifier: timeZone.identifier,
            sourceQuality: .unavailable,
            isPartial: false,
            today: .zero,
            last7Days: .zero,
            currentMonth: .zero,
            allTime: .zero,
            allTimeDetailed: .zero,
            estimatedAPIValueUSD: .zero,
            dailyBuckets: [],
            weekdayHourHeatmap: [],
            heatmapThresholds: [1, 10, 100, 1_000],
            previous7DayComparison: AgentUsagePeriodComparison(current: .zero, previous: .zero, changePercent: nil, isNewActivity: false),
            projectRankings7Days: [],
            projectRankingsAllTime: [],
            modelRankings: [],
            recentSessions: [],
            sourceSummaries: [],
            topTools: [],
            topSkills: [],
            tasks: .empty,
            diagnostics: [],
            parsedFileCount: 0,
            tokenEventCount: 0
        )
    }
}

enum AgentUsageLoadState: Equatable, Sendable {
    case idle
    case loading(previous: AgentUsageSnapshot?)
    case paused(previous: AgentUsageSnapshot?)
    case ready
    case partial(message: String)
    case failed(message: String, previous: AgentUsageSnapshot?)
}

enum AgentUsageScanPhase: String, Codable, Equatable, Sendable {
    case idle
    case readingCodexDatabase
    case scanningCodexSessions
    case scanningClaudeTranscripts
    case readingOpenCodeDatabase
    case scanningOpenClawSessions
    case readingTasks
    case aggregating
    case completed
    case failed
}

enum AgentUsageBackfillStage: String, Codable, Equatable, Sendable {
    case inventory
    case restoringCache
    case fillingHistory
    case finalizing
    case paused
    case completed
    case failed
}

enum AgentUsageBackfillEndReason: String, Codable, Equatable, Sendable {
    case allEligibleSessionsScanned
    case timeBudgetReached
    case readBudgetReached
    case runLimitReached
    case inventoryLimitReached
    case pausedByUser
    case scanFailed
}

/// A path-free, user-visible receipt for one local Codex detail pass.
///
/// `checkedSessions` describes inventory inspection, while
/// `advancedThisRun` and `completedThisRun` describe real transcript IO. This
/// distinction prevents a fast cache inventory pass from being presented as a
/// completed historical scan.
struct AgentUsageBackfillStatus: Codable, Equatable, Sendable {
    let stage: AgentUsageBackfillStage
    let checkedSessions: Int
    let totalSessions: Int
    let pendingAtStart: Int
    let advancedThisRun: Int
    let completedThisRun: Int
    let skippedThisRun: Int
    let failedThisRun: Int
    let remainingSessions: Int
    let excludedByInventoryLimit: Int
    let aggregateOnlyHistorySessions: Int
    let endReason: AgentUsageBackfillEndReason?
    let completedAt: Date?

    var hasRemainingWork: Bool {
        remainingSessions > 0 || excludedByInventoryLimit > 0
    }

    var isRunning: Bool {
        switch stage {
        case .inventory, .restoringCache, .fillingHistory, .finalizing:
            return true
        case .paused, .completed, .failed:
            return false
        }
    }

    init(
        stage: AgentUsageBackfillStage,
        checkedSessions: Int = 0,
        totalSessions: Int = 0,
        pendingAtStart: Int = 0,
        advancedThisRun: Int = 0,
        completedThisRun: Int = 0,
        skippedThisRun: Int = 0,
        failedThisRun: Int = 0,
        remainingSessions: Int = 0,
        excludedByInventoryLimit: Int = 0,
        aggregateOnlyHistorySessions: Int = 0,
        endReason: AgentUsageBackfillEndReason? = nil,
        completedAt: Date? = nil
    ) {
        self.stage = stage
        self.checkedSessions = max(0, checkedSessions)
        self.totalSessions = max(0, totalSessions)
        self.pendingAtStart = max(0, pendingAtStart)
        self.advancedThisRun = max(0, advancedThisRun)
        self.completedThisRun = max(0, completedThisRun)
        self.skippedThisRun = max(0, skippedThisRun)
        self.failedThisRun = max(0, failedThisRun)
        self.remainingSessions = max(0, remainingSessions)
        self.excludedByInventoryLimit = max(0, excludedByInventoryLimit)
        self.aggregateOnlyHistorySessions = max(0, aggregateOnlyHistorySessions)
        self.endReason = endReason
        self.completedAt = completedAt
    }

    func replacing(
        stage: AgentUsageBackfillStage,
        endReason: AgentUsageBackfillEndReason?,
        completedAt: Date?
    ) -> AgentUsageBackfillStatus {
        AgentUsageBackfillStatus(
            stage: stage,
            checkedSessions: checkedSessions,
            totalSessions: totalSessions,
            pendingAtStart: pendingAtStart,
            advancedThisRun: advancedThisRun,
            completedThisRun: completedThisRun,
            skippedThisRun: skippedThisRun,
            failedThisRun: failedThisRun,
            remainingSessions: remainingSessions,
            excludedByInventoryLimit: excludedByInventoryLimit,
            aggregateOnlyHistorySessions: aggregateOnlyHistorySessions,
            endReason: endReason,
            completedAt: completedAt
        )
    }
}

struct AgentUsageScanProgress: Codable, Equatable, Sendable {
    let phase: AgentUsageScanPhase
    let current: Int
    let total: Int
    let currentSource: String?
    let message: String
    let backfill: AgentUsageBackfillStatus?

    init(
        phase: AgentUsageScanPhase,
        current: Int,
        total: Int,
        currentSource: String?,
        message: String,
        backfill: AgentUsageBackfillStatus? = nil
    ) {
        self.phase = phase
        self.current = current
        self.total = total
        self.currentSource = currentSource
        self.message = message
        self.backfill = backfill
    }

    static let idle = AgentUsageScanProgress(phase: .idle, current: 0, total: 0, currentSource: nil, message: "")
    var fractionCompleted: Double? { total > 0 ? min(1, max(0, Double(current) / Double(total))) : nil }
}

/// Path-free payload for DEBUG launch probes and reproducible performance QA.
struct AgentUsageDebugProbe: Codable, Equatable, Sendable {
    let succeeded: Bool
    let elapsedMilliseconds: Int
    let parsedFileCount: Int
    let tokenEventCount: Int
    let todayTokens: Int64
    let last7DaysTokens: Int64
    let allTimeTokens: Int64
    let allTimeDetailedTokens: Int64
    let allTimeUnattributedTokens: Int64
    let sourceAllTimeTokens: [String: Int64]
    let sourceDetailedTokens: [String: Int64]
    let sourceTokenEventCounts: [String: Int]
    let diagnosticCodes: [String]
    let selfTestFailures: [String]
    let backfillCheckedSessions: Int
    let backfillTotalSessions: Int
    let backfillPendingAtStart: Int
    let backfillAdvancedThisRun: Int
    let backfillCompletedThisRun: Int
    let backfillSkippedThisRun: Int
    let backfillFailedThisRun: Int
    let backfillRemainingSessions: Int
    let backfillExcludedSessions: Int
    let backfillAggregateOnlyHistorySessions: Int
    let backfillEndReason: String?
    let error: String?
}

// MARK: - Main actor facade

/// Privacy-first, local-only usage analytics for TraceFence.
///
/// The event-counter normalizer and analytics shape are informed by codexU's
/// MIT-licensed implementation. TraceFence keeps its own service boundaries,
/// models, cache format and UI. No theme or presentation code is copied.
@MainActor
final class AgentUsageInsightsService: ObservableObject {
    static let shared = AgentUsageInsightsService()

    private static let scopeDefaultsKey = "traceFence.agentUsage.scope"
    private static let timeZoneDefaultsKey = "traceFence.agentUsage.timeZone"
    private static let foregroundInterval: TimeInterval = 5 * 60
    private static let backgroundInterval: TimeInterval = 15 * 60
    private static let maximumAutomaticSnapshotAge: TimeInterval = 6 * 60 * 60

    @Published private(set) var snapshot: AgentUsageSnapshot
    @Published private(set) var state: AgentUsageLoadState = .idle
    @Published private(set) var progress: AgentUsageScanProgress = .idle
    @Published private(set) var backfillStatus: AgentUsageBackfillStatus? = nil
    @Published var scope: AgentUsageScope {
        didSet {
            UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeDefaultsKey)
            if let existing = snapshots[scope] {
                snapshot = existing
                if case .paused = state {
                    state = .paused(previous: existing)
                } else {
                    state = existing.isPartial ? .partial(message: Self.partialMessage(for: existing)) : .ready
                }
            } else if refreshTask == nil {
                refresh(force: true)
            }
        }
    }
    @Published var timeZoneMode: AgentUsageTimeZoneMode {
        didSet {
            UserDefaults.standard.set(timeZoneMode.storedValue, forKey: Self.timeZoneDefaultsKey)
            refresh(force: true)
        }
    }

    var isRefreshing: Bool { refreshTask != nil }

    private var snapshots: [AgentUsageScope: AgentUsageSnapshot] = [:]
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var scheduler: Timer?
    private var applicationIsActive = true
    private var lastRefreshAt: Date?
    private var refreshPreviousSnapshot: AgentUsageSnapshot?
    private var automaticRefreshPaused = false
    private var snapshotSourceSignatures: [String: String] = [:]

    private init(defaults: UserDefaults = .standard) {
        Self.retireLegacyTokenScopeCache()
        let persisted = AgentUsageSnapshotCacheStore.load()
        let initialScope = defaults.string(forKey: Self.scopeDefaultsKey)
            .flatMap(AgentUsageScope.init(rawValue:)) ?? .combined
        let initialTimeZoneMode = AgentUsageTimeZoneMode(
            storedValue: defaults.string(forKey: Self.timeZoneDefaultsKey)
        )
        scope = initialScope
        timeZoneMode = initialTimeZoneMode
        if let persisted {
            snapshots = Dictionary(uniqueKeysWithValues: persisted.snapshots.compactMap { rawScope, value in
                guard let parsedScope = AgentUsageScope(rawValue: rawScope),
                      value.timeZoneIdentifier == initialTimeZoneMode.resolvedTimeZone.identifier else { return nil }
                return (parsedScope, value)
            })
            snapshotSourceSignatures = persisted.sourceSignatures
            lastRefreshAt = persisted.lastRefreshAt
            backfillStatus = persisted.backfillStatus
        }
        if let cached = snapshots[initialScope] {
            snapshot = cached
            state = cached.isPartial ? .partial(message: Self.partialMessage(for: cached)) : .ready
            progress = AgentUsageScanProgress(
                phase: .completed,
                current: cached.parsedFileCount,
                total: cached.parsedFileCount,
                currentSource: nil,
                message: "Using cached local usage snapshot",
                backfill: backfillStatus
            )
        } else {
            snapshot = .empty(scope: initialScope, timeZone: initialTimeZoneMode.resolvedTimeZone)
        }
    }

    nonisolated private static func retireLegacyTokenScopeCache() {
        // The old TokenScope cache was derived from a second scanner with a
        // different file cap and token arithmetic. Bookmarks are intentionally
        // preserved; only the conflicting derived cache is retired.
        let url = URL(fileURLWithPath: SandboxPaths.shared.tokenScopeCachePath)
        try? FileManager.default.removeItem(at: url)
    }

    func startScheduling() {
        Self.retireLegacyTokenScopeCache()
        guard scheduler == nil else { return }
        refreshIfDue()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIfDue()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduler = timer
    }

    func stopScheduling() {
        scheduler?.invalidate()
        scheduler = nil
    }

    func setApplicationActive(_ active: Bool) {
        applicationIsActive = active
        if active { refreshIfDue() }
    }

    /// Returns a stable scope snapshot without changing the user's filter.
    /// Overview uses `.combined` so switching the analytics page to Codex or
    /// Claude cannot silently change the global headline.
    func snapshot(for scope: AgentUsageScope) -> AgentUsageSnapshot {
        if let value = snapshots[scope] { return value }
        if snapshot.scope == scope { return snapshot }
        return .empty(scope: scope, timeZone: timeZoneMode.resolvedTimeZone)
    }

    func refresh(force: Bool = false, completePendingBackfill: Bool = false) {
        guard force || !automaticRefreshPaused else { return }
        // Scheduled requests coalesce. A force request (for example a time-zone
        // preference change) cancels the old generation so stale boundaries can
        // never overwrite the newly-selected statistics mode.
        if let refreshTask {
            guard force else { return }
            refreshTask.cancel()
            self.refreshTask = nil
            refreshGeneration &+= 1
        }
        if !force, let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < 20 {
            return
        }
        if !force, snapshotCanBeReused(currentSignatures: AgentUsageSourceFingerprint.currentSignatures()) {
            publishCachedState()
            return
        }

        refreshGeneration &+= 1
        let generation = refreshGeneration
        let previous = snapshots[scope]
        refreshPreviousSnapshot = previous
        automaticRefreshPaused = false
        state = .loading(previous: previous)
        progress = AgentUsageScanProgress(
            phase: .readingCodexDatabase,
            current: 0,
            total: 0,
            currentSource: nil,
            message: "Preparing local usage scan…"
        )
        let mode = timeZoneMode
        let progressSink: @Sendable (AgentUsageScanProgress) -> Void = { [weak self] value in
            Task { @MainActor in
                guard let self, generation == self.refreshGeneration else { return }
                self.progress = value
                if let backfill = value.backfill {
                    self.backfillStatus = backfill
                }
            }
        }

        refreshTask = Task { [weak self] in
            let result = await AgentUsageInsightsLoader(
                timeZoneMode: mode,
                now: Date(),
                progress: progressSink,
                completePendingBackfill: completePendingBackfill
            ).load()
            guard let self, generation == self.refreshGeneration else { return }
            self.refreshTask = nil
            self.lastRefreshAt = Date()

            switch result {
            case let .success(loaded):
                self.snapshots = loaded.snapshots
                self.backfillStatus = loaded.backfillStatus
                self.snapshotSourceSignatures = AgentUsageSourceFingerprint.currentSignatures()
                _ = AgentUsageSnapshotCacheStore.save(AgentUsageSnapshotCache(
                    version: 4,
                    generatedAt: Date(),
                    lastRefreshAt: self.lastRefreshAt,
                    sourceSignatures: self.snapshotSourceSignatures,
                    snapshots: Dictionary(uniqueKeysWithValues: loaded.snapshots.map { ($0.key.rawValue, $0.value) }),
                    backfillStatus: loaded.backfillStatus
                ))
                let selected = loaded.snapshots[self.scope] ?? .empty(scope: self.scope, timeZone: self.timeZoneMode.resolvedTimeZone)
                self.snapshot = selected
                if selected.isPartial {
                    self.state = .partial(message: Self.partialMessage(for: selected))
                } else {
                    self.state = .ready
                }
                self.progress = AgentUsageScanProgress(
                    phase: .completed,
                    current: selected.parsedFileCount,
                    total: selected.parsedFileCount,
                    currentSource: nil,
                    message: "Local usage scan complete"
                )
                self.refreshPreviousSnapshot = nil
            case let .failure(error):
                self.state = .failed(message: error.localizedDescription, previous: previous)
                let failedStatus = self.backfillStatus ?? AgentUsageBackfillStatus(stage: .failed)
                self.backfillStatus = failedStatus.replacing(
                    stage: .failed,
                    endReason: .scanFailed,
                    completedAt: Date()
                )
                self.progress = AgentUsageScanProgress(
                    phase: .failed,
                    current: self.progress.current,
                    total: self.progress.total,
                    currentSource: self.progress.currentSource,
                    message: error.localizedDescription
                )
                if let previous { self.snapshot = previous }
                self.refreshPreviousSnapshot = nil
            }
        }
    }

    func continueBackfill() {
        automaticRefreshPaused = false
        refresh(force: true, completePendingBackfill: true)
    }

    func retryScan() {
        automaticRefreshPaused = false
        refresh(force: true)
    }

    /// Rebuilds monetary estimates from compact per-file counters after a
    /// validated pricing catalog changes. Unchanged multi-gigabyte transcripts
    /// remain cache hits and are not replayed from disk.
    func applyPricingCatalogUpdate() {
        guard !automaticRefreshPaused,
              snapshotSourceSignatures["pricing"] != AgentUsagePricingCatalog.revisionSignature else { return }
        refresh(force: true)
    }

    /// Stops an in-flight local pass without discarding the last published
    /// snapshot or any cache chunks already committed by providers. Automatic
    /// refresh remains paused until the user explicitly continues or retries.
    func pauseScan() {
        guard refreshTask != nil else { return }
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration &+= 1
        automaticRefreshPaused = true

        let previous = refreshPreviousSnapshot ?? snapshots[scope]
        if let previous {
            snapshot = previous
        }
        state = .paused(previous: previous)
        let paused = backfillStatus ?? AgentUsageBackfillStatus(stage: .paused)
        backfillStatus = paused.replacing(
            stage: .paused,
            endReason: .pausedByUser,
            completedAt: Date()
        )
        progress = AgentUsageScanProgress(
            phase: progress.phase,
            current: progress.current,
            total: progress.total,
            currentSource: nil,
            message: "Local detail scan paused",
            backfill: backfillStatus
        )
        refreshPreviousSnapshot = nil
    }

    /// Removes only derived aggregate caches. Source transcripts and databases
    /// are never modified.
    func clearCaches() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration &+= 1
        AgentUsageFileCacheStore.clearAll()
        AgentUsageSnapshotCacheStore.clear()
        snapshotSourceSignatures.removeAll()
        snapshots.removeAll()
        snapshot = .empty(scope: scope, timeZone: timeZoneMode.resolvedTimeZone)
        state = .idle
        progress = .idle
        backfillStatus = nil
        automaticRefreshPaused = false
        refreshPreviousSnapshot = nil
        refresh(force: true)
    }

    /// Exports aggregate metrics. Paths, task titles and source identifiers are
    /// removed unless the user explicitly requests a sensitive export.
    func exportJSON(includeSensitive: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(includeSensitive ? snapshot : snapshot.redactedForExport())
    }

    private func refreshIfDue() {
        guard !automaticRefreshPaused else { return }
        if snapshotCanBeReused(currentSignatures: AgentUsageSourceFingerprint.currentSignatures()) {
            publishCachedState()
            return
        }
        let interval = applicationIsActive ? Self.foregroundInterval : Self.backgroundInterval
        guard lastRefreshAt.map({ Date().timeIntervalSince($0) >= interval }) ?? true else { return }
        refresh()
    }

    private func snapshotCanBeReused(currentSignatures: [String: String]) -> Bool {
        guard !snapshots.isEmpty,
              let lastRefreshAt,
              Date().timeIntervalSince(lastRefreshAt) < Self.maximumAutomaticSnapshotAge,
              snapshotSourceSignatures == currentSignatures else { return false }
        return snapshots[scope]?.timeZoneIdentifier == timeZoneMode.resolvedTimeZone.identifier
    }

    private func publishCachedState() {
        guard let cached = snapshots[scope] else { return }
        snapshot = cached
        state = cached.isPartial ? .partial(message: Self.partialMessage(for: cached)) : .ready
        progress = AgentUsageScanProgress(
            phase: .completed,
            current: cached.parsedFileCount,
            total: cached.parsedFileCount,
            currentSource: nil,
            message: "Using cached local usage snapshot",
            backfill: backfillStatus
        )
    }

    private static func partialMessage(for snapshot: AgentUsageSnapshot) -> String {
        snapshot.diagnostics.first(where: { $0.severity != .info })?.message ?? "Some local usage sources were unavailable."
    }
}

private extension AgentUsageSnapshot {
    func redactedForExport() -> AgentUsageSnapshot {
        func redactProjects(_ values: [AgentUsageProjectUsage]) -> [AgentUsageProjectUsage] {
            values.enumerated().map { index, value in
                AgentUsageProjectUsage(
                    id: "project-\(index + 1)",
                    name: "Project \(index + 1)",
                    fullPath: "",
                    tokens: value.tokens,
                    estimatedAPIValueUSD: value.estimatedAPIValueUSD,
                    sessionCount: value.sessionCount,
                    lastActiveAt: value.lastActiveAt,
                    sourceQuality: value.sourceQuality
                )
            }
        }
        func redactTasks(_ values: [AgentUsageTaskItem], category: AgentUsageTaskCategory) -> [AgentUsageTaskItem] {
            values.enumerated().map { index, value in
                AgentUsageTaskItem(
                    id: "\(category.rawValue)-\(index + 1)",
                    scope: value.scope,
                    category: value.category,
                    title: "\(value.scope.displayName) task",
                    project: nil,
                    updatedAt: value.updatedAt,
                    tokens: value.tokens
                )
            }
        }
        let redactedTasks = AgentUsageTaskBoard(
            active: redactTasks(tasks.active, category: .active),
            pending: redactTasks(tasks.pending, category: .pending),
            scheduled: redactTasks(tasks.scheduled, category: .scheduled),
            done: redactTasks(tasks.done, category: .done)
        )
        let redactedSessions = recentSessions.enumerated().map { index, value in
            AgentUsageSessionUsage(
                id: "session-\(index + 1)",
                scope: value.scope,
                projectName: "Project \(index + 1)",
                fullProjectPath: "",
                model: value.model,
                tokens: value.tokens,
                estimatedAPIValueUSD: value.estimatedAPIValueUSD,
                lastActiveAt: value.lastActiveAt,
                sourceQuality: value.sourceQuality
            )
        }
        return AgentUsageSnapshot(
            scope: scope,
            generatedAt: generatedAt,
            timeZoneIdentifier: timeZoneIdentifier,
            sourceQuality: sourceQuality,
            isPartial: isPartial,
            today: today,
            last7Days: last7Days,
            currentMonth: currentMonth,
            allTime: allTime,
            allTimeDetailed: allTimeDetailed,
            estimatedAPIValueUSD: estimatedAPIValueUSD,
            dailyBuckets: dailyBuckets,
            weekdayHourHeatmap: weekdayHourHeatmap,
            heatmapThresholds: heatmapThresholds,
            previous7DayComparison: previous7DayComparison,
            projectRankings7Days: redactProjects(projectRankings7Days),
            projectRankingsAllTime: redactProjects(projectRankingsAllTime),
            modelRankings: modelRankings,
            recentSessions: redactedSessions,
            sourceSummaries: sourceSummaries,
            topTools: topTools,
            topSkills: topSkills.map {
                AgentUsageSkillUsage(
                    scope: $0.scope,
                    name: $0.name,
                    path: nil,
                    loadCount: $0.loadCount,
                    sessionCount: $0.sessionCount,
                    staticTokenEstimate: $0.staticTokenEstimate,
                    staticByteCount: $0.staticByteCount,
                    lastLoadedAt: $0.lastLoadedAt
                )
            },
            tasks: redactedTasks,
            diagnostics: diagnostics.map {
                AgentUsageDiagnostic(scope: $0.scope, severity: $0.severity, code: $0.code, message: $0.message, source: nil)
            },
            parsedFileCount: parsedFileCount,
            tokenEventCount: tokenEventCount
        )
    }
}

// MARK: - Internal aggregate model

private struct AgentUsageEvent: Codable, Equatable, Sendable {
    let id: String?
    let date: Date
    let tokens: AgentUsageTokenTotals
    let estimatedCostUSD: Double
    let priceKnown: Bool
    let model: String?
    let projectPath: String
    let sessionID: String
}

private struct AgentUsageSkillEvent: Codable, Equatable, Sendable {
    let name: String
    let path: String?
    let date: Date?
    let sessionID: String
}

private struct AgentUsageFileSummary: Codable, Equatable, Sendable {
    let events: [AgentUsageEvent]
    let toolCalls: [String: Int]
    let skillEvents: [AgentUsageSkillEvent]
    let lastActiveAt: Date?
}

private struct AgentUsageEventBucketKey: Hashable {
    let quarterHour: Int64
    let model: String
    let project: String
    let session: String
    let priceKnown: Bool
}

private struct AgentUsageEventAccumulator {
    private var grouped: [AgentUsageEventBucketKey: AgentUsageEvent] = [:]

    mutating func add(_ event: AgentUsageEvent) {
        let key = AgentUsageEventBucketKey(
            quarterHour: Int64(floor(event.date.timeIntervalSince1970 / 900)),
            model: event.model ?? "",
            project: event.projectPath,
            session: event.sessionID,
            priceKnown: event.priceKnown
        )
        if let existing = grouped[key] {
            var tokens = existing.tokens
            tokens.add(event.tokens)
            grouped[key] = AgentUsageEvent(
                id: nil,
                date: min(existing.date, event.date),
                tokens: tokens,
                estimatedCostUSD: existing.estimatedCostUSD + event.estimatedCostUSD,
                priceKnown: existing.priceKnown && event.priceKnown,
                model: event.model,
                projectPath: event.projectPath,
                sessionID: event.sessionID
            )
        } else {
            grouped[key] = event
        }
    }

    var events: [AgentUsageEvent] {
        grouped.values.sorted { $0.date < $1.date }
    }
}

private struct AgentUsageFileCacheEntry: Codable {
    let size: Int64
    let modificationTimeNanoseconds: Int64
    let coverageIncomplete: Bool
    let skippedRelevantRecord: Bool
    let scannedFromOffset: Int64
    let summary: AgentUsageFileSummary
    var lineageDedupVersion: Int? = nil
}

private struct AgentUsageFileCache: Codable {
    let version: Int
    var entries: [String: AgentUsageFileCacheEntry]
}

private struct AgentUsageRuntimeAggregate: Sendable {
    let scope: AgentUsageScope
    var events: [AgentUsageEvent] = []
    var approximateAllTimeProjects: [AgentUsageProjectUsage] = []
    var toolCalls: [String: Int] = [:]
    var skillEvents: [AgentUsageSkillEvent] = []
    var tasks: [AgentUsageTaskItem] = []
    var diagnostics: [AgentUsageDiagnostic] = []
    var parsedFileCount = 0
    var tokenEventCount = 0
    var sourceQuality: AgentUsageSourceQuality = .unavailable
    var available = false
    var partial = false
    var backfillStatus: AgentUsageBackfillStatus?
}

private enum AgentUsageLoaderError: LocalizedError {
    case noLocalSources
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .noLocalSources: return "No trusted local Agent token sources were found."
        case let .unexpected(message): return message
        }
    }
}

// MARK: - Shared policy and pure helpers

private enum AgentUsageMath {
    static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        if !overflow { return value }
        return rhs >= 0 ? Int64.max : Int64.min
    }
}

private enum AgentUsageBackfillOutcomePolicy {
    /// Counts only work that entered this pass but produced neither a committed
    /// cache advance nor a recorded failure. Candidates never reached because
    /// a time/read budget ended remain visible solely in `remainingSessions`.
    static func skippedCount(
        attemptedThisRun: Int,
        advancedThisRun: Int,
        failedThisRun: Int
    ) -> Int {
        max(0, attemptedThisRun - advancedThisRun - failedThisRun)
    }

    static func resolve(
        remainingSessions: Int,
        excludedByInventoryLimit: Int,
        cancelled: Bool,
        stoppedByDeadline: Bool,
        stoppedByReadBudget: Bool,
        failedThisRun: Int
    ) -> AgentUsageBackfillEndReason {
        if cancelled { return .pausedByUser }
        if remainingSessions <= 0 {
            return excludedByInventoryLimit > 0
                ? .inventoryLimitReached
                : .allEligibleSessionsScanned
        }
        if stoppedByDeadline { return .timeBudgetReached }
        if stoppedByReadBudget { return .readBudgetReached }
        if failedThisRun > 0 { return .scanFailed }
        return .runLimitReached
    }
}

/// Normalizes providers whose native schema reports cache and reasoning as
/// separate, non-overlapping components. TraceFence stores `input` inclusive
/// of cached input and `output` inclusive of reasoning so the four UI rows can
/// remain mutually exclusive (`input - cached`, `cached`, `output - reasoning`,
/// `reasoning`) without double counting.
private enum AgentUsageExplicitTokenNormalizer {
    static func isZeroUsage(
        input: Int64,
        cacheRead: Int64,
        cacheWrite: Int64,
        output: Int64,
        reasoning: Int64,
        reportedTotal: Int64?
    ) -> Bool {
        input == 0
            && cacheRead == 0
            && cacheWrite == 0
            && output == 0
            && reasoning == 0
            && (reportedTotal ?? 0) == 0
    }

    static func totals(
        input: Int64,
        cacheRead: Int64,
        cacheWrite: Int64,
        output: Int64,
        reasoning: Int64,
        reportedTotal: Int64?
    ) -> AgentUsageTokenTotals? {
        let fields = [input, cacheRead, cacheWrite, output, reasoning]
        guard fields.allSatisfy({ $0 >= 0 }), (reportedTotal ?? 0) >= 0 else { return nil }
        let cached = AgentUsageMath.saturatingAdd(cacheRead, cacheWrite)
        let inclusiveInput = AgentUsageMath.saturatingAdd(input, cached)
        let inclusiveOutput = AgentUsageMath.saturatingAdd(output, reasoning)
        let componentTotal = AgentUsageMath.saturatingAdd(inclusiveInput, inclusiveOutput)
        guard componentTotal > 0 else { return nil }
        if let reportedTotal, reportedTotal > 0, reportedTotal != componentTotal {
            return nil
        }
        return AgentUsageTokenTotals(
            input: inclusiveInput,
            cached: cached,
            output: inclusiveOutput,
            reasoning: reasoning,
            total: reportedTotal.flatMap { $0 > 0 ? $0 : nil } ?? componentTotal
        )
    }
}

private struct AgentUsageStatisticsContext: Sendable {
    let now: Date
    let timeZone: TimeZone

    init(mode: AgentUsageTimeZoneMode, now: Date) {
        self.now = now
        timeZone = mode.resolvedTimeZone
    }

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = timeZone
        return value
    }

    var todayStart: Date { calendar.startOfDay(for: now) }

    var sevenDayStart: Date {
        calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
    }

    var previousSevenDayStart: Date {
        calendar.date(byAdding: .day, value: -13, to: todayStart) ?? todayStart
    }

    var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? todayStart
    }

    var heatmapStart: Date {
        calendar.date(byAdding: .day, value: -179, to: todayStart) ?? todayStart
    }

    func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private struct AgentUsageModelPrice {
    let inputPerMillion: Double
    let cachedInputPerMillion: Double
    let cacheWrite5mPerMillion: Double
    let cacheWrite1hPerMillion: Double
    let outputPerMillion: Double
    let longContextThreshold: Int64?
    let longContextInputMultiplier: Double
    let longContextOutputMultiplier: Double

    init(
        inputPerMillion: Double,
        cachedInputPerMillion: Double,
        cacheWrite5mPerMillion: Double? = nil,
        cacheWrite1hPerMillion: Double? = nil,
        outputPerMillion: Double,
        longContextThreshold: Int64? = nil,
        longContextInputMultiplier: Double = 1,
        longContextOutputMultiplier: Double = 1
    ) {
        self.inputPerMillion = inputPerMillion
        self.cachedInputPerMillion = cachedInputPerMillion
        self.cacheWrite5mPerMillion = cacheWrite5mPerMillion ?? inputPerMillion
        self.cacheWrite1hPerMillion = cacheWrite1hPerMillion ?? inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.longContextThreshold = longContextThreshold
        self.longContextInputMultiplier = longContextInputMultiplier
        self.longContextOutputMultiplier = longContextOutputMultiplier
    }
}

/// Centralized API-equivalent reference prices. Values are estimates used only
/// for local comparison; they are not invoices and unknown models are omitted.
/// Official references checked 2026-07-30:
/// - https://developers.openai.com/api/docs/models
/// - https://platform.claude.com/docs/en/about-claude/pricing
/// - https://platform.minimax.io/docs/guides/pricing-paygo
private enum AgentUsagePricingCatalog {
    static var revisionSignature: String {
        AgentUsageRemotePricingCatalog.revisionSignature
    }

    static func price(scope: AgentUsageScope, model: String?, at date: Date? = nil) -> AgentUsageModelPrice? {
        let value = (model ?? "").lowercased()
        guard !value.isEmpty else { return nil }

        if let remote = AgentUsageRemotePricingCatalog.price(scope: scope, model: value, at: date) {
            return AgentUsageModelPrice(
                inputPerMillion: remote.inputPerMillion,
                cachedInputPerMillion: remote.cachedInputPerMillion,
                cacheWrite5mPerMillion: remote.cacheWrite5mPerMillion,
                cacheWrite1hPerMillion: remote.cacheWrite1hPerMillion,
                outputPerMillion: remote.outputPerMillion,
                longContextThreshold: remote.longContextThreshold,
                longContextInputMultiplier: remote.longContextInputMultiplier,
                longContextOutputMultiplier: remote.longContextOutputMultiplier
            )
        }

        switch scope {
        case .codex:
            return openAIPrice(value, at: date)
        case .claude:
            return claudePrice(value, at: date)
        case .openCode, .openClaw:
            // Prefer the runtime's explicit per-message cost. When it is
            // absent, resolve only public model IDs; router aliases remain
            // unknown rather than inheriting a guessed price.
            return miniMaxPrice(value)
                ?? openAIPrice(value, at: date)
                ?? claudePrice(value, at: date)
        case .combined:
            return nil
        }
    }

    private static func openAIPrice(_ value: String, at date: Date?) -> AgentUsageModelPrice? {
        let gpt56LongContext: (Int64, Double, Double) = (272_000, 2, 1.5)
        let july30PriceChange = Date(timeIntervalSince1970: 1_785_369_600)
        if matchesModelID(value, id: "gpt-5.6-sol") {
            return AgentUsageModelPrice(
                inputPerMillion: 5,
                cachedInputPerMillion: 0.5,
                cacheWrite5mPerMillion: 6.25,
                cacheWrite1hPerMillion: 6.25,
                outputPerMillion: 30,
                longContextThreshold: gpt56LongContext.0,
                longContextInputMultiplier: gpt56LongContext.1,
                longContextOutputMultiplier: gpt56LongContext.2
            )
        }
        if matchesModelID(value, id: "gpt-5.6-terra") {
            let usesReducedPrice = (date ?? Date()) >= july30PriceChange
            return AgentUsageModelPrice(
                inputPerMillion: usesReducedPrice ? 2 : 2.5,
                cachedInputPerMillion: usesReducedPrice ? 0.2 : 0.25,
                cacheWrite5mPerMillion: usesReducedPrice ? 2.5 : 3.125,
                cacheWrite1hPerMillion: usesReducedPrice ? 2.5 : 3.125,
                outputPerMillion: usesReducedPrice ? 12 : 15,
                longContextThreshold: gpt56LongContext.0,
                longContextInputMultiplier: gpt56LongContext.1,
                longContextOutputMultiplier: gpt56LongContext.2
            )
        }
        if matchesModelID(value, id: "gpt-5.6-luna") {
            let usesReducedPrice = (date ?? Date()) >= july30PriceChange
            return AgentUsageModelPrice(
                inputPerMillion: usesReducedPrice ? 0.2 : 1,
                cachedInputPerMillion: usesReducedPrice ? 0.02 : 0.1,
                cacheWrite5mPerMillion: usesReducedPrice ? 0.25 : 1.25,
                cacheWrite1hPerMillion: usesReducedPrice ? 0.25 : 1.25,
                outputPerMillion: usesReducedPrice ? 1.2 : 6,
                longContextThreshold: gpt56LongContext.0,
                longContextInputMultiplier: gpt56LongContext.1,
                longContextOutputMultiplier: gpt56LongContext.2
            )
        }
        if value.contains("gpt-5.5-pro") || value.contains("gpt-5.4-pro") {
            return AgentUsageModelPrice(inputPerMillion: 30, cachedInputPerMillion: 30, outputPerMillion: 180)
        }
        if value.contains("gpt-5.5") || value == "chat-latest" {
            return AgentUsageModelPrice(inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30)
        }
        if value.contains("gpt-5.4-mini") {
            return AgentUsageModelPrice(inputPerMillion: 0.75, cachedInputPerMillion: 0.075, outputPerMillion: 4.5)
        }
        if value.contains("gpt-5.4-nano") {
            return AgentUsageModelPrice(inputPerMillion: 0.2, cachedInputPerMillion: 0.02, outputPerMillion: 1.25)
        }
        if value.contains("gpt-5.4") {
            return AgentUsageModelPrice(inputPerMillion: 2.5, cachedInputPerMillion: 0.25, outputPerMillion: 15)
        }
        if value.contains("gpt-5.3-codex") || value.contains("gpt-5.2-codex")
            || value.contains("gpt-5.3-chat") || value.contains("gpt-5.2") {
            return AgentUsageModelPrice(inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14)
        }
        if value.contains("gpt-5-codex") || value == "gpt-5" {
            return AgentUsageModelPrice(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10)
        }
        if value.contains("o3") {
            return AgentUsageModelPrice(inputPerMillion: 2, cachedInputPerMillion: 0.5, outputPerMillion: 8)
        }
        if value.contains("o4-mini") {
            return AgentUsageModelPrice(inputPerMillion: 1.1, cachedInputPerMillion: 0.275, outputPerMillion: 4.4)
        }
        return nil
    }

    private static func matchesModelID(_ value: String, id: String) -> Bool {
        let unnamespaced = value.split(separator: "/").last.map(String.init) ?? value
        return unnamespaced == id || unnamespaced.hasPrefix(id + "-20")
    }

    private static func claudePrice(_ value: String, at date: Date?) -> AgentUsageModelPrice? {
        if value.contains("fable-5") || value.contains("mythos-5") {
            return AgentUsageModelPrice(inputPerMillion: 10, cachedInputPerMillion: 1, cacheWrite5mPerMillion: 12.5, cacheWrite1hPerMillion: 20, outputPerMillion: 50)
        }
        if containsClaudeVersion(value, family: "opus", versions: ["5", "5-0", "4-5", "4-6", "4-7", "4-8"]) {
            return AgentUsageModelPrice(inputPerMillion: 5, cachedInputPerMillion: 0.5, cacheWrite5mPerMillion: 6.25, cacheWrite1hPerMillion: 10, outputPerMillion: 25)
        }
        if value.contains("opus") {
            return AgentUsageModelPrice(inputPerMillion: 15, cachedInputPerMillion: 1.5, cacheWrite5mPerMillion: 18.75, cacheWrite1hPerMillion: 30, outputPerMillion: 75)
        }
        if containsClaudeVersion(value, family: "sonnet", versions: ["5", "5-0"]) {
            let introductoryPriceEnds = Date(timeIntervalSince1970: 1_788_220_800) // 2026-09-01 00:00:00 UTC
            if (date ?? Date()) < introductoryPriceEnds {
                return AgentUsageModelPrice(inputPerMillion: 2, cachedInputPerMillion: 0.2, cacheWrite5mPerMillion: 2.5, cacheWrite1hPerMillion: 4, outputPerMillion: 10)
            }
            return AgentUsageModelPrice(inputPerMillion: 3, cachedInputPerMillion: 0.3, cacheWrite5mPerMillion: 3.75, cacheWrite1hPerMillion: 6, outputPerMillion: 15)
        }
        if value.contains("sonnet") {
            return AgentUsageModelPrice(inputPerMillion: 3, cachedInputPerMillion: 0.3, cacheWrite5mPerMillion: 3.75, cacheWrite1hPerMillion: 6, outputPerMillion: 15)
        }
        if containsClaudeVersion(value, family: "haiku", versions: ["4-5"]) {
            return AgentUsageModelPrice(inputPerMillion: 1, cachedInputPerMillion: 0.1, cacheWrite5mPerMillion: 1.25, cacheWrite1hPerMillion: 2, outputPerMillion: 5)
        }
        if containsClaudeVersion(value, family: "haiku", versions: ["3-5"]) {
            return AgentUsageModelPrice(inputPerMillion: 0.8, cachedInputPerMillion: 0.08, cacheWrite5mPerMillion: 1, cacheWrite1hPerMillion: 1.6, outputPerMillion: 4)
        }
        if value.contains("haiku") {
            return AgentUsageModelPrice(inputPerMillion: 0.25, cachedInputPerMillion: 0.03, cacheWrite5mPerMillion: 0.3, cacheWrite1hPerMillion: 0.5, outputPerMillion: 1.25)
        }
        return nil
    }

    private static func miniMaxPrice(_ value: String) -> AgentUsageModelPrice? {
        if value.contains("minimax-m3") {
            return AgentUsageModelPrice(
                inputPerMillion: 0.3,
                cachedInputPerMillion: 0.06,
                cacheWrite5mPerMillion: 0.3,
                cacheWrite1hPerMillion: 0.3,
                outputPerMillion: 1.2,
                longContextThreshold: 512_000,
                longContextInputMultiplier: 2,
                longContextOutputMultiplier: 2
            )
        }
        if value.contains("minimax-m2.7-highspeed") {
            return AgentUsageModelPrice(inputPerMillion: 0.6, cachedInputPerMillion: 0.06, cacheWrite5mPerMillion: 0.375, cacheWrite1hPerMillion: 0.375, outputPerMillion: 2.4)
        }
        if value.contains("minimax-m2.7") {
            return AgentUsageModelPrice(inputPerMillion: 0.3, cachedInputPerMillion: 0.06, cacheWrite5mPerMillion: 0.375, cacheWrite1hPerMillion: 0.375, outputPerMillion: 1.2)
        }
        if value.contains("minimax-m2.5-highspeed") {
            return AgentUsageModelPrice(inputPerMillion: 0.6, cachedInputPerMillion: 0.03, cacheWrite5mPerMillion: 0.375, cacheWrite1hPerMillion: 0.375, outputPerMillion: 2.4)
        }
        if value.contains("minimax-m2.5") || value.contains("minimax-m2.1") {
            return AgentUsageModelPrice(inputPerMillion: 0.3, cachedInputPerMillion: 0.03, cacheWrite5mPerMillion: 0.375, cacheWrite1hPerMillion: 0.375, outputPerMillion: 1.2)
        }
        return nil
    }

    private static func containsClaudeVersion(_ value: String, family: String, versions: [String]) -> Bool {
        versions.contains { version in
            let dotted = version.replacingOccurrences(of: "-", with: ".")
            return value.contains("\(family)-\(version)")
                || value.contains("\(family)_\(version)")
                || value.contains("\(family) \(version)")
                || value.contains("\(family)-\(dotted)")
                || value.contains("\(family)_\(dotted)")
                || value.contains("\(family) \(dotted)")
        }
    }

    static func estimatedCost(
        tokens: AgentUsageTokenTotals,
        price: AgentUsageModelPrice?,
        cacheReadTokens: Int64? = nil,
        cacheWriteTokens: Int64 = 0,
        cacheWriteOneHourTokens: Int64 = 0
    ) -> (Double, Bool) {
        guard let price else { return (0, false) }
        let usesLongContextTier = price.longContextThreshold.map { tokens.input > $0 } ?? false
        let inputMultiplier = usesLongContextTier ? price.longContextInputMultiplier : 1
        let outputMultiplier = usesLongContextTier ? price.longContextOutputMultiplier : 1
        if let cacheReadTokens {
            let inputTokens = max(0, tokens.input)
            let readTokens = min(max(0, cacheReadTokens), inputTokens)
            let writeTokens = min(max(0, cacheWriteTokens), max(0, inputTokens - readTokens))
            let oneHourTokens = min(max(0, cacheWriteOneHourTokens), writeTokens)
            let fiveMinuteTokens = max(0, writeTokens - oneHourTokens)
            let uncachedTokens = max(0, inputTokens - readTokens - writeTokens)
            let input = Double(uncachedTokens) / 1_000_000 * price.inputPerMillion * inputMultiplier
            let read = Double(readTokens) / 1_000_000 * price.cachedInputPerMillion * inputMultiplier
            let write5m = Double(fiveMinuteTokens) / 1_000_000 * price.cacheWrite5mPerMillion * inputMultiplier
            let write1h = Double(oneHourTokens) / 1_000_000 * price.cacheWrite1hPerMillion * inputMultiplier
            let output = Double(max(0, tokens.output)) / 1_000_000 * price.outputPerMillion * outputMultiplier
            return (input + read + write5m + write1h + output, true)
        }
        let input = Double(max(0, tokens.uncachedInput)) / 1_000_000 * price.inputPerMillion * inputMultiplier
        let cached = Double(max(0, min(tokens.cached, tokens.input))) / 1_000_000 * price.cachedInputPerMillion * inputMultiplier
        let output = Double(max(0, tokens.output)) / 1_000_000 * price.outputPerMillion * outputMultiplier
        return (input + cached + output, true)
    }

    static func resolvedCost(
        scope: AgentUsageScope,
        model: String?,
        date: Date,
        tokens: AgentUsageTokenTotals,
        explicitCostUSD: Double?,
        cacheReadTokens: Int64? = nil,
        cacheWriteTokens: Int64 = 0,
        cacheWriteOneHourTokens: Int64 = 0
    ) -> (Double, Bool) {
        // A positive native cost is authoritative. Several Agent runtimes emit
        // a literal zero when the cost field is unsupported or usage came from
        // a subscription, so zero must fall back to the public API-equivalent
        // catalog instead of being presented as a free model.
        if let explicitCostUSD, explicitCostUSD > 0 {
            return (explicitCostUSD, true)
        }
        return estimatedCost(
            tokens: tokens,
            price: price(scope: scope, model: model, at: date),
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            cacheWriteOneHourTokens: cacheWriteOneHourTokens
        )
    }
}

private extension AgentUsageFileCacheEntry {
    /// Reprice compact cached counters without replaying multi-gigabyte source
    /// transcripts. The compact cache does not retain the split between cache
    /// write TTLs, so historical cached input uses the cache-read reference
    /// rate until that individual source file changes and is parsed again.
    func repriced(scope: AgentUsageScope) -> AgentUsageFileCacheEntry {
        let events = summary.events.map { event -> AgentUsageEvent in
            let resolved = AgentUsagePricingCatalog.resolvedCost(
                scope: scope,
                model: event.model,
                date: event.date,
                tokens: event.tokens,
                explicitCostUSD: nil
            )
            return AgentUsageEvent(
                id: event.id,
                date: event.date,
                tokens: event.tokens,
                estimatedCostUSD: resolved.0,
                priceKnown: resolved.1,
                model: event.model,
                projectPath: event.projectPath,
                sessionID: event.sessionID
            )
        }
        return AgentUsageFileCacheEntry(
            size: size,
            modificationTimeNanoseconds: modificationTimeNanoseconds,
            coverageIncomplete: coverageIncomplete,
            skippedRelevantRecord: skippedRelevantRecord,
            scannedFromOffset: scannedFromOffset,
            summary: AgentUsageFileSummary(
                events: events,
                toolCalls: summary.toolCalls,
                skillEvents: summary.skillEvents,
                lastActiveAt: summary.lastActiveAt
            ),
            lineageDedupVersion: lineageDedupVersion
        )
    }
}

private enum AgentUsagePathPolicy {
    private static let sensitiveComponents: Set<String> = [
        ".git", ".env", "secrets", "secret", "credentials", "auth.json",
        "tokens.json", "id_rsa", "id_ed25519"
    ]
    private static let disallowedExtensions: Set<String> = ["db", "sqlite", "sqlite3", "pem", "key", "p12"]

    static var home: URL {
        URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    static var codexRoot: URL {
        home.appendingPathComponent(".codex", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    static var claudeRoot: URL {
        home.appendingPathComponent(".claude", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    static var openCodeRoot: URL {
        home.appendingPathComponent(".local/share/opencode", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    static var miniMaxRoot: URL {
        home.appendingPathComponent(".minimax", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    static var qClawRoot: URL {
        home.appendingPathComponent(".qclaw", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    static var openClawRoot: URL {
        home.appendingPathComponent(".openclaw", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    static var allowedSkillRoots: [URL] {
        [
            codexRoot.appendingPathComponent("skills", isDirectory: true),
            claudeRoot.appendingPathComponent("skills", isDirectory: true),
            codexRoot.appendingPathComponent("plugins/cache", isDirectory: true)
        ].map { $0.standardizedFileURL.resolvingSymlinksInPath() }
    }

    static func normalizedRolloutURL(_ rawPath: String) -> URL? {
        let expanded: String
        if rawPath == "~" {
            expanded = home.path
        } else if rawPath.hasPrefix("~/") {
            expanded = home.path + "/" + rawPath.dropFirst(2)
        } else {
            expanded = rawPath
        }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "jsonl",
              isContained(url, in: codexRoot),
              isSafe(url) else { return nil }
        return url
    }

    static func normalizedClaudeTranscriptURL(_ url: URL) -> URL? {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        let projects = claudeRoot.appendingPathComponent("projects", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard normalized.pathExtension.lowercased() == "jsonl",
              isContained(normalized, in: projects),
              isSafe(normalized) else { return nil }
        return normalized
    }

    static func normalizedOpenClawTranscriptURL(_ url: URL) -> URL? {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        let roots = [qClawRoot, openClawRoot]
        guard normalized.pathExtension.lowercased() == "jsonl",
              !normalized.lastPathComponent.contains(".reset."),
              !normalized.lastPathComponent.contains(".deleted."),
              normalized.pathComponents.contains("sessions"),
              roots.contains(where: { isContained(normalized, in: $0) }),
              isSafe(normalized) else { return nil }
        return normalized
    }

    static func normalizedSkillURL(_ url: URL) -> URL? {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        guard normalized.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame,
              allowedSkillRoots.contains(where: { isContained(normalized, in: $0) }),
              isSafe(normalized) else { return nil }
        return normalized
    }

    static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        var rootPath = root.standardizedFileURL.path
        if rootPath.hasSuffix("/") { rootPath.removeLast() }
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    static func isSafe(_ url: URL) -> Bool {
        let components = url.pathComponents.map { $0.lowercased() }
        guard !components.contains(where: { component in
            sensitiveComponents.contains(component)
                || component.hasPrefix(".env.")
                || component.contains("private_key")
                || component.contains("api_key")
        }) else { return false }
        return !disallowedExtensions.contains(url.pathExtension.lowercased())
    }
}

private final class AgentUsageSkillIndex: @unchecked Sendable {
    static let shared = AgentUsageSkillIndex()
    private let byName: [String: URL]

    init(fileManager: FileManager = .default) {
        var result: [String: URL] = [:]
        for root in AgentUsagePathPolicy.allowedSkillRoots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            var visited = 0
            for case let rawURL as URL in enumerator {
                visited += 1
                if visited > 20_000 || result.count >= 4_096 {
                    enumerator.skipDescendants()
                    break
                }
                guard rawURL.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame,
                      let url = AgentUsagePathPolicy.normalizedSkillURL(rawURL) else { continue }
                let name = url.deletingLastPathComponent().lastPathComponent
                if result[name.lowercased()] == nil { result[name.lowercased()] = url }
            }
        }
        byName = result
    }

    func resolve(name: String) -> URL? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized.count <= 160 else { return nil }
        return byName[normalized]
    }

    func resolve(path: String) -> URL? {
        let expanded: String
        if path.hasPrefix("~/") {
            expanded = AgentUsagePathPolicy.home.path + "/" + path.dropFirst(2)
        } else {
            expanded = path
        }
        return AgentUsagePathPolicy.normalizedSkillURL(URL(fileURLWithPath: expanded))
    }
}

/// Final aggregate snapshots are intentionally cached separately from the
/// per-transcript parser cache. This lets a 10 GB Codex history render its last
/// verified totals immediately instead of replaying the inventory whenever the
/// app or page is opened.
private struct AgentUsageSnapshotCache: Codable {
    let version: Int
    let generatedAt: Date
    let lastRefreshAt: Date?
    let sourceSignatures: [String: String]
    let snapshots: [String: AgentUsageSnapshot]
    let backfillStatus: AgentUsageBackfillStatus?
}

private extension AgentUsageSnapshot {
    func compactForSnapshotCache() -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            scope: scope,
            generatedAt: generatedAt,
            timeZoneIdentifier: timeZoneIdentifier,
            sourceQuality: sourceQuality,
            isPartial: isPartial,
            today: today,
            last7Days: last7Days,
            currentMonth: currentMonth,
            allTime: allTime,
            allTimeDetailed: allTimeDetailed,
            estimatedAPIValueUSD: estimatedAPIValueUSD,
            dailyBuckets: Array(dailyBuckets.suffix(365)),
            weekdayHourHeatmap: Array(weekdayHourHeatmap.prefix(300)),
            heatmapThresholds: heatmapThresholds,
            previous7DayComparison: previous7DayComparison,
            projectRankings7Days: Array(projectRankings7Days.prefix(80)),
            projectRankingsAllTime: Array(projectRankingsAllTime.prefix(160)),
            modelRankings: Array(modelRankings.prefix(120)),
            recentSessions: Array(recentSessions.prefix(40)),
            sourceSummaries: sourceSummaries,
            topTools: Array(topTools.prefix(60)),
            topSkills: Array(topSkills.prefix(80)),
            tasks: AgentUsageTaskBoard(
                active: Array(tasks.active.prefix(24)),
                pending: Array(tasks.pending.prefix(24)),
                scheduled: Array(tasks.scheduled.prefix(24)),
                done: Array(tasks.done.prefix(24))
            ),
            diagnostics: Array(diagnostics.prefix(40)),
            parsedFileCount: parsedFileCount,
            tokenEventCount: tokenEventCount
        )
    }
}

private enum AgentUsageSnapshotCacheStore {
    // v4 adds the active pricing revision to final aggregate fingerprints so a
    // remote catalog change can reprice compact counters without stale totals.
    private static let version = 4
    private static let maximumEncodedBytes = 32 * 1_024 * 1_024

    static func load() -> AgentUsageSnapshotCache? {
        let cacheURL = url
        guard let values = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= maximumEncodedBytes,
              let data = try? Data(contentsOf: cacheURL, options: [.mappedIfSafe]),
              let decoded = try? JSONDecoder().decode(AgentUsageSnapshotCache.self, from: data),
              decoded.version == version,
              decoded.sourceSignatures["pricing"] == AgentUsagePricingCatalog.revisionSignature,
              !decoded.snapshots.isEmpty else { return nil }
        return decoded
    }

    static func save(_ cache: AgentUsageSnapshotCache) -> Bool {
        do {
            let normalized = AgentUsageSnapshotCache(
                version: version,
                generatedAt: cache.generatedAt,
                lastRefreshAt: cache.lastRefreshAt,
                sourceSignatures: cache.sourceSignatures,
                snapshots: Dictionary(uniqueKeysWithValues: cache.snapshots.compactMap { rawScope, snapshot in
                    AgentUsageScope(rawValue: rawScope).map { ($0.rawValue, snapshot.compactForSnapshotCache()) }
                }),
                backfillStatus: cache.backfillStatus
            )
            let encoded = try JSONEncoder().encode(normalized)
            guard encoded.count <= maximumEncodedBytes else { return false }
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try encoded.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    private static var url: URL {
        URL(fileURLWithPath: SandboxPaths.shared.agentUsageSnapshotCachePath)
    }
}

/// A cheap source fingerprint avoids opening thousands of transcripts merely
/// to discover that nothing changed. Database WAL files are included because
/// active Codex/OpenCode sessions often update there before the main database.
private enum AgentUsageSourceFingerprint {
    static func currentSignatures() -> [String: String] {
        let values: [AgentUsageScope: String] = [
            .codex: signature(for: .codex),
            .claude: signature(for: .claude),
            .openCode: signature(for: .openCode),
            .openClaw: signature(for: .openClaw)
        ]
        var result = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        let combined = values.keys.sorted { $0.rawValue < $1.rawValue }
            .compactMap { values[$0] }
            .joined(separator: "|")
        result[AgentUsageScope.combined.rawValue] = digest("combined|\(combined)")
        result["pricing"] = AgentUsagePricingCatalog.revisionSignature
        return result
    }

    private static func signature(for scope: AgentUsageScope) -> String {
        let roots: [URL]
        switch scope {
        case .codex:
            roots = databaseFamily(AgentUsagePathPolicy.codexRoot.appendingPathComponent("state_5.sqlite"))
                + databaseFamily(AgentUsagePathPolicy.codexRoot.appendingPathComponent("sqlite/state_5.sqlite"))
                + [
                    AgentUsagePathPolicy.codexRoot.appendingPathComponent("sessions", isDirectory: true),
                    AgentUsagePathPolicy.codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
                ]
        case .claude:
            roots = [
                AgentUsagePathPolicy.claudeRoot.appendingPathComponent("projects", isDirectory: true),
                AgentUsagePathPolicy.claudeRoot.appendingPathComponent("history.jsonl"),
                AgentUsagePathPolicy.claudeRoot.appendingPathComponent("stats-cache.json"),
                AgentUsagePathPolicy.home.appendingPathComponent(".claude.json")
            ]
        case .openCode:
            roots = databaseFamily(AgentUsagePathPolicy.openCodeRoot.appendingPathComponent("opencode.db"))
                + databaseFamily(AgentUsagePathPolicy.miniMaxRoot.appendingPathComponent("sqlite.db"))
        case .openClaw:
            roots = [AgentUsagePathPolicy.qClawRoot, AgentUsagePathPolicy.openClawRoot]
        case .combined:
            return currentSignatures()[AgentUsageScope.combined.rawValue] ?? ""
        }
        return digest(scope.rawValue + "|" + roots.map(fileSignature).joined(separator: "|"))
    }

    private static func databaseFamily(_ database: URL) -> [URL] {
        [
            database,
            URL(fileURLWithPath: database.path + "-wal"),
            URL(fileURLWithPath: database.path + "-shm")
        ]
    }

    private static func fileSignature(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "missing"
        }
        let type = (attributes[.type] as? FileAttributeType) == .typeDirectory ? "dir" : "file"
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modified = Int64(((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1_000_000_000)
        return "\(type):\(size):\(modified)"
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private enum AgentUsageFileCacheStore {
    private static let version = 5
    private static let limit = 2_048
    private static let maximumEncodedBytes = 32 * 1_024 * 1_024
    private static let codexName = "agent_usage_codex_cache_v5.json"
    private static let claudeName = "agent_usage_claude_cache_v5.json"

    static func load(scope: AgentUsageScope) -> AgentUsageFileCache {
        guard let url = url(scope: scope),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let byteCount = values.fileSize,
              byteCount >= 0,
              byteCount <= maximumEncodedBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let decoded = try? JSONDecoder().decode(AgentUsageFileCache.self, from: data),
              decoded.version == version else {
            return AgentUsageFileCache(version: version, entries: [:])
        }
        let repriced = decoded.entries.mapValues { $0.repriced(scope: scope) }
        return AgentUsageFileCache(version: version, entries: limited(repriced))
    }

    static func save(_ cache: AgentUsageFileCache, scope: AgentUsageScope) -> Bool {
        guard let url = url(scope: scope) else { return false }
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            var entries = limited(cache.entries)
            var encoded = try JSONEncoder().encode(AgentUsageFileCache(version: version, entries: entries))
            if encoded.count > maximumEncodedBytes {
                let orderedKeys = entries.sorted { lhs, rhs in
                    if lhs.value.modificationTimeNanoseconds == rhs.value.modificationTimeNanoseconds {
                        return lhs.key < rhs.key
                    }
                    return lhs.value.modificationTimeNanoseconds > rhs.value.modificationTimeNanoseconds
                }.map(\.key)
                var keepCount = orderedKeys.count
                while encoded.count > maximumEncodedBytes, keepCount > 1 {
                    keepCount = max(1, keepCount * 3 / 4)
                    let keep = Set(orderedKeys.prefix(keepCount))
                    entries = entries.filter { keep.contains($0.key) }
                    encoded = try JSONEncoder().encode(AgentUsageFileCache(version: version, entries: entries))
                }
            }
            guard encoded.count <= maximumEncodedBytes else { return false }
            try encoded.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    static func clearAll() {
        for name in [
            codexName, claudeName,
            "agent_usage_codex_lineage_cache_v1.json",
            "agent_usage_codex_cache_v4.json", "agent_usage_claude_cache_v4.json",
            "agent_usage_codex_cache_v3.json", "agent_usage_claude_cache_v3.json",
            "agent_usage_codex_cache_v2.json", "agent_usage_claude_cache_v2.json",
            "agent_usage_codex_cache_v1.json", "agent_usage_claude_cache_v1.json"
        ] {
            let url = URL(fileURLWithPath: SandboxPaths.shared.dataDirectory, isDirectory: true)
                .appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func url(scope: AgentUsageScope) -> URL? {
        let name: String
        switch scope {
        case .codex: name = codexName
        case .claude: name = claudeName
        case .openCode, .openClaw, .combined: return nil
        }
        return URL(fileURLWithPath: SandboxPaths.shared.dataDirectory, isDirectory: true)
            .appendingPathComponent(name)
    }

    private static func limited(_ entries: [String: AgentUsageFileCacheEntry]) -> [String: AgentUsageFileCacheEntry] {
        guard entries.count > limit else { return entries }
        return Dictionary(uniqueKeysWithValues: entries.sorted { lhs, rhs in
            if lhs.value.modificationTimeNanoseconds == rhs.value.modificationTimeNanoseconds {
                return lhs.key < rhs.key
            }
            return lhs.value.modificationTimeNanoseconds > rhs.value.modificationTimeNanoseconds
        }.prefix(limit).map { ($0.key, $0.value) })
    }
}

private enum AgentUsagePrivacy {
    static func digest(_ value: String) -> String {
        let bytes = SHA256.hash(data: Data(value.utf8))
        return bytes.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func cacheKey(for url: URL) -> String {
        digest(url.standardizedFileURL.path)
    }
}

private struct AgentUsageLineageFingerprintCacheEntry: Codable {
    let size: Int64
    let modificationTimeNanoseconds: Int64
    let fingerprints: [AgentUsageCounterFingerprint]
    let lastAccessedAt: Date
}

private struct AgentUsageLineageFingerprintCache: Codable {
    let version: Int
    var entries: [String: AgentUsageLineageFingerprintCacheEntry]
}

/// Persists compact, content-free counter identities for fork parents. A very
/// large parent transcript then needs to be streamed only once instead of on
/// every cold detail pass. Prompts, replies, paths and session IDs are absent.
private enum AgentUsageLineageFingerprintCacheStore {
    private static let version = 1
    private static let name = "agent_usage_codex_lineage_cache_v1.json"
    private static let maximumEntries = 64
    private static let maximumEncodedBytes = 16 * 1_024 * 1_024

    static func load() -> AgentUsageLineageFingerprintCache {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size >= 0,
              size <= maximumEncodedBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let decoded = try? JSONDecoder().decode(AgentUsageLineageFingerprintCache.self, from: data),
              decoded.version == version else {
            return AgentUsageLineageFingerprintCache(version: version, entries: [:])
        }
        return AgentUsageLineageFingerprintCache(
            version: version,
            entries: limited(decoded.entries)
        )
    }

    @discardableResult
    static func save(_ cache: AgentUsageLineageFingerprintCache) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            var entries = limited(cache.entries)
            var data = try JSONEncoder().encode(AgentUsageLineageFingerprintCache(
                version: version,
                entries: entries
            ))
            while data.count > maximumEncodedBytes, !entries.isEmpty {
                guard let oldest = entries.min(by: {
                    $0.value.lastAccessedAt < $1.value.lastAccessedAt
                })?.key else { break }
                entries.removeValue(forKey: oldest)
                data = try JSONEncoder().encode(AgentUsageLineageFingerprintCache(
                    version: version,
                    entries: entries
                ))
            }
            guard data.count <= maximumEncodedBytes else { return false }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private static var url: URL {
        URL(fileURLWithPath: SandboxPaths.shared.dataDirectory, isDirectory: true)
            .appendingPathComponent(name)
    }

    private static func limited(
        _ entries: [String: AgentUsageLineageFingerprintCacheEntry]
    ) -> [String: AgentUsageLineageFingerprintCacheEntry] {
        guard entries.count > maximumEntries else { return entries }
        return Dictionary(uniqueKeysWithValues: entries.sorted {
            $0.value.lastAccessedAt > $1.value.lastAccessedAt
        }.prefix(maximumEntries).map { ($0.key, $0.value) })
    }
}

private extension AgentUsageFileSummary {
    /// The disk cache never stores source paths, transcript/message identifiers,
    /// task titles, prompts, or tool arguments. Source identity is restored from
    /// the currently-authorized inventory on every refresh.
    func redactedForDisk() -> AgentUsageFileSummary {
        AgentUsageFileSummary(
            events: events.map {
                AgentUsageEvent(
                    id: $0.id,
                    date: $0.date,
                    tokens: $0.tokens,
                    estimatedCostUSD: $0.estimatedCostUSD,
                    priceKnown: $0.priceKnown,
                    model: $0.model,
                    projectPath: "",
                    sessionID: AgentUsagePrivacy.digest($0.sessionID)
                )
            },
            toolCalls: toolCalls,
            skillEvents: skillEvents.map {
                AgentUsageSkillEvent(
                    name: $0.name,
                    path: nil,
                    date: $0.date,
                    sessionID: AgentUsagePrivacy.digest($0.sessionID)
                )
            },
            lastActiveAt: lastActiveAt
        )
    }

    func rehydrated(projectPath: String, sessionID: String, skillIndex: AgentUsageSkillIndex) -> AgentUsageFileSummary {
        AgentUsageFileSummary(
            events: events.map {
                AgentUsageEvent(
                    id: $0.id,
                    date: $0.date,
                    tokens: $0.tokens,
                    estimatedCostUSD: $0.estimatedCostUSD,
                    priceKnown: $0.priceKnown,
                    model: $0.model,
                    projectPath: projectPath,
                    sessionID: sessionID
                )
            },
            toolCalls: toolCalls,
            skillEvents: skillEvents.map {
                let resolved = skillIndex.resolve(name: $0.name)
                return AgentUsageSkillEvent(
                    name: $0.name,
                    path: resolved?.path,
                    date: $0.date,
                    sessionID: sessionID
                )
            },
            lastActiveAt: lastActiveAt
        )
    }

    func merged(with other: AgentUsageFileSummary) -> AgentUsageFileSummary {
        var mergedTools = toolCalls
        for (name, count) in other.toolCalls { mergedTools[name, default: 0] += count }
        let mergedLastActive: Date?
        switch (lastActiveAt, other.lastActiveAt) {
        case let (lhs?, rhs?): mergedLastActive = max(lhs, rhs)
        case let (lhs?, nil): mergedLastActive = lhs
        case let (nil, rhs?): mergedLastActive = rhs
        case (nil, nil): mergedLastActive = nil
        }
        return AgentUsageFileSummary(
            events: events + other.events,
            toolCalls: mergedTools,
            skillEvents: Array((skillEvents + other.skillEvents).prefix(4_096)),
            lastActiveAt: mergedLastActive
        ).compacted()
    }

    /// Token events are compacted into fifteen-minute absolute-time buckets.
    /// This keeps very large JSONL files bounded while retaining correct day and
    /// hour attribution for every currently-used civil time-zone offset.
    func compacted() -> AgentUsageFileSummary {
        var accumulator = AgentUsageEventAccumulator()
        for event in events { accumulator.add(event) }
        return AgentUsageFileSummary(
            events: accumulator.events,
            toolCalls: toolCalls,
            skillEvents: skillEvents,
            lastActiveAt: lastActiveAt
        )
    }
}

// MARK: - Codex counter normalization

private struct AgentUsageCounterSample: Equatable {
    let input: Int64?
    let cached: Int64?
    let output: Int64?
    let reasoning: Int64?
    let total: Int64?

    var containsNegative: Bool {
        [input, cached, output, reasoning, total].compactMap { $0 }.contains { $0 < 0 }
    }

    func totals(fillingMissingFrom previous: AgentUsageTokenTotals = .zero) -> AgentUsageTokenTotals {
        let nextInput = max(0, input ?? previous.input)
        let nextCached = max(0, cached ?? previous.cached)
        let nextOutput = max(0, output ?? previous.output)
        let nextReasoning = max(0, reasoning ?? previous.reasoning)
        let derivedTotal = AgentUsageMath.saturatingAdd(nextInput, nextOutput)
        let nextTotal = max(0, total ?? max(previous.total, derivedTotal))
        return AgentUsageTokenTotals(
            input: nextInput,
            cached: nextCached,
            output: nextOutput,
            reasoning: nextReasoning,
            total: max(nextTotal, derivedTotal)
        )
    }
}

/// Stable, content-free identity for one Codex `token_count` record. Forked
/// subagent rollouts replay their ancestor's counter records byte-for-byte in
/// meaning even though the child has a different session identifier. Hashing
/// only the ten numeric counter fields lets TraceFence remove that inherited
/// history without retaining prompts, replies, tool data, or file paths.
private struct AgentUsageCounterFingerprint: Hashable, Codable {
    /// Two independently mixed words keep an in-memory lineage index compact.
    /// The previous representation retained ten Int64 fields plus Set storage
    /// for every record, which amplified cold scans of large forked sessions.
    let high: UInt64
    let low: UInt64

    init(cumulative: AgentUsageCounterSample?, last: AgentUsageCounterSample?) {
        func value(_ raw: Int64?) -> Int64 { raw ?? Int64.min }
        let fields = [
            value(cumulative?.input), value(cumulative?.cached),
            value(cumulative?.output), value(cumulative?.reasoning),
            value(cumulative?.total), value(last?.input),
            value(last?.cached), value(last?.output),
            value(last?.reasoning), value(last?.total)
        ]
        var first: UInt64 = 0x243F_6A88_85A3_08D3
        var second: UInt64 = 0x1319_8A2E_0370_7344
        for (index, field) in fields.enumerated() {
            let bits = UInt64(bitPattern: field)
            first = Self.mix(first ^ bits ^ UInt64(index &* 0x9E37))
            second = Self.mix(second &+ bits &+ UInt64(index &* 0x85EB))
        }
        high = first
        low = second
    }

    private static func mix(_ value: UInt64) -> UInt64 {
        var result = value
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}

private struct AgentUsageCounterState {
    var cumulativeHighWater: AgentUsageTokenTotals?
}

/// Normalizes cumulative `token_count` snapshots without replaying the whole
/// counter after duplicates, partial regressions or a confirmed reset.
private enum AgentUsageCounterNormalizer {
    static func consume(
        cumulative: AgentUsageCounterSample?,
        last: AgentUsageCounterSample?,
        state: inout AgentUsageCounterState
    ) -> AgentUsageTokenTotals? {
        let lastDelta = validNonzero(last?.containsNegative == false ? last?.totals() : nil)

        guard let cumulative, !cumulative.containsNegative else {
            return lastDelta
        }

        guard let previous = state.cumulativeHighWater else {
            let current = cumulative.totals()
            state.cumulativeHighWater = current
            return lastDelta ?? validNonzero(current)
        }

        if isConfirmedReset(cumulative, previous: previous) {
            let current = cumulative.totals()
            state.cumulativeHighWater = current
            return lastDelta ?? validNonzero(current)
        }

        let observed = cumulative.totals(fillingMissingFrom: previous)
        let highWater = AgentUsageTokenTotals(
            input: max(previous.input, observed.input),
            cached: max(previous.cached, observed.cached),
            output: max(previous.output, observed.output),
            reasoning: max(previous.reasoning, observed.reasoning),
            total: max(previous.total, observed.total)
        )
        state.cumulativeHighWater = highWater
        var fallback = highWater.subtractingFloorAtZero(previous)
        fallback.total = max(
            fallback.total,
            AgentUsageMath.saturatingAdd(fallback.input, fallback.output)
        )
        guard !fallback.isZero else { return nil }
        if let lastDelta, lastDelta.total == fallback.total {
            return lastDelta
        }
        return validNonzero(fallback)
    }

    private static func isConfirmedReset(_ sample: AgentUsageCounterSample, previous: AgentUsageTokenTotals) -> Bool {
        let comparisons: [(Int64?, Int64)] = [
            (sample.input, previous.input),
            (sample.output, previous.output),
            (sample.total, previous.total)
        ]
        let present = comparisons.compactMap { current, old -> ComparisonResult? in
            guard let current, current >= 0 else { return nil }
            if current < old { return .orderedAscending }
            if current > old { return .orderedDescending }
            return .orderedSame
        }
        let regressions = present.filter { $0 == .orderedAscending }.count
        let increases = present.filter { $0 == .orderedDescending }.count
        return present.count >= 2 && regressions >= 2 && increases == 0
    }

    private static func validNonzero(_ value: AgentUsageTokenTotals?) -> AgentUsageTokenTotals? {
        guard let value, !value.isZero else { return nil }
        return value
    }
}

private enum AgentUsageDetailedSanity {
    static func isSuspicious(detailed: Int64, approximate: Int64) -> Bool {
        guard approximate >= 1_000_000,
              detailed > approximate,
              detailed - approximate >= 500_000_000 else { return false }
        return Double(detailed) / Double(approximate) >= 8
    }
}

// MARK: - SQLite inventory

private struct AgentUsageCodexThread {
    let id: String
    let rolloutPath: String
    let createdAt: Date?
    let updatedAt: Date?
    let recencyAt: Date?
    let archivedAt: Date?
    let cwd: String
    let tokens: Int64
    let archived: Bool
    let model: String?
    let title: String?
}

private struct AgentUsageOpenCodeMessageRow {
    let id: String
    let sessionID: String
    let createdAt: Date?
    let directory: String
    let data: String
}

private struct AgentUsageMiniMaxTokenRow {
    let usageID: String
    let turnID: String?
    let sessionID: String
    let createdAt: Date?
    let model: String?
    let directory: String
    let input: Int64
    let output: Int64
    let reasoning: Int64
    let cacheRead: Int64
    let cacheWrite: Int64
    let raw: String?
    let costUSD: Double?
}

private final class AgentUsageSQLiteReader {
    private var database: OpaquePointer?

    init?(path: String) {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK else {
            if let database { sqlite3_close_v2(database) }
            database = nil
            return nil
        }
        sqlite3_busy_timeout(database, 250)
    }

    deinit {
        if let database { sqlite3_close_v2(database) }
    }

    func codexThreads() -> [AgentUsageCodexThread]? {
        guard let columns = columnNames(table: "threads"),
              columns.contains("id"),
              columns.contains("rollout_path") else { return nil }
        func expression(_ name: String, fallback: String = "NULL") -> String {
            columns.contains(name) ? name : "\(fallback) AS \(name)"
        }
        let sql = """
        SELECT id, rollout_path,
               \(expression("created_at", fallback: "0")),
               \(expression("updated_at", fallback: "0")),
               \(expression("recency_at", fallback: "0")),
               \(expression("archived_at")),
               \(expression("cwd", fallback: "''")),
               \(expression("tokens_used", fallback: "0")),
               \(expression("archived", fallback: "0")),
               \(expression("model"))
        FROM threads
        ORDER BY \(columns.contains("updated_at") ? "updated_at" : "rowid") ASC;
        """
        guard let rows = rows(sql) else { return nil }
        return rows.map { row in
            AgentUsageCodexThread(
                id: row.string("id") ?? UUID().uuidString,
                rolloutPath: row.string("rollout_path") ?? "",
                createdAt: AgentUsageDateParser.epoch(row.int64("created_at")),
                updatedAt: AgentUsageDateParser.epoch(row.int64("updated_at")),
                recencyAt: AgentUsageDateParser.epoch(row.int64("recency_at")),
                archivedAt: AgentUsageDateParser.epoch(row.int64("archived_at")),
                cwd: row.string("cwd") ?? "",
                tokens: max(0, row.int64("tokens_used") ?? 0),
                archived: (row.int64("archived") ?? 0) != 0,
                model: row.string("model"),
                // Thread titles and previews can be derived from user prompts.
                // They are intentionally never selected from SQLite.
                title: nil
            )
        }
    }

    func openCodeMessages() -> [AgentUsageOpenCodeMessageRow]? {
        guard let messageColumns = columnNames(table: "message"),
              let sessionColumns = columnNames(table: "session"),
              messageColumns.isSuperset(of: ["id", "session_id", "time_created", "data"]),
              sessionColumns.isSuperset(of: ["id", "directory"]) else { return nil }
        let sql = """
        SELECT m.id AS message_id,
               m.session_id AS session_id,
               m.time_created AS time_created,
               m.data AS data,
               COALESCE(s.directory, '') AS directory
        FROM message AS m
        LEFT JOIN session AS s ON s.id = m.session_id
        ORDER BY m.time_created ASC, m.id ASC;
        """
        guard let rows = rows(sql) else { return nil }
        return rows.compactMap { row in
            guard let id = row.string("message_id"),
                  let sessionID = row.string("session_id"),
                  let data = row.string("data") else { return nil }
            return AgentUsageOpenCodeMessageRow(
                id: id,
                sessionID: sessionID,
                createdAt: AgentUsageDateParser.epoch(row.int64("time_created")),
                directory: row.string("directory") ?? "",
                data: data
            )
        }
    }

    func miniMaxTokenRows() -> [AgentUsageMiniMaxTokenRow]? {
        guard let usageColumns = columnNames(table: "token_usage"),
              usageColumns.isSuperset(of: [
                "id", "session_id", "ts", "input_tokens", "output_tokens",
                "reasoning_tokens", "cache_read_tokens", "cache_write_tokens"
              ]) else { return nil }
        let hasSessions = columnNames(table: "sessions")?.isSuperset(of: ["session_id", "workspace_dir"]) == true
        let join = hasSessions
            ? "LEFT JOIN sessions AS s ON s.session_id = t.session_id"
            : ""
        let directory = hasSessions ? "COALESCE(s.workspace_dir, '')" : "''"
        func expression(_ name: String, fallback: String = "NULL") -> String {
            usageColumns.contains(name) ? "t.\(name)" : fallback
        }
        let sql = """
        SELECT t.id AS usage_id,
               \(expression("turn_id")) AS turn_id,
               t.session_id AS session_id,
               t.ts AS ts,
               \(expression("model")) AS model,
               \(directory) AS directory,
               t.input_tokens AS input_tokens,
               t.output_tokens AS output_tokens,
               t.reasoning_tokens AS reasoning_tokens,
               t.cache_read_tokens AS cache_read_tokens,
               t.cache_write_tokens AS cache_write_tokens,
               \(expression("raw")) AS raw,
               \(expression("cost_usd")) AS cost_usd
        FROM token_usage AS t
        \(join)
        ORDER BY t.ts ASC, t.id ASC;
        """
        guard let rows = rows(sql) else { return nil }
        return rows.compactMap { row in
            guard let usageID = row.string("usage_id"),
                  let sessionID = row.string("session_id") else { return nil }
            return AgentUsageMiniMaxTokenRow(
                usageID: usageID,
                turnID: row.string("turn_id").flatMap { $0.isEmpty ? nil : $0 },
                sessionID: sessionID,
                createdAt: AgentUsageDateParser.epoch(row.int64("ts")),
                model: row.string("model"),
                directory: row.string("directory") ?? "",
                input: max(0, row.int64("input_tokens") ?? 0),
                output: max(0, row.int64("output_tokens") ?? 0),
                reasoning: max(0, row.int64("reasoning_tokens") ?? 0),
                cacheRead: max(0, row.int64("cache_read_tokens") ?? 0),
                cacheWrite: max(0, row.int64("cache_write_tokens") ?? 0),
                raw: row.string("raw"),
                costUSD: row.double("cost_usd")
            )
        }
    }

    private func columnNames(table: String) -> Set<String>? {
        let sql: String
        switch table {
        case "threads": sql = "PRAGMA table_info(threads);"
        case "message": sql = "PRAGMA table_info(message);"
        case "session": sql = "PRAGMA table_info(session);"
        case "token_usage": sql = "PRAGMA table_info(token_usage);"
        case "sessions": sql = "PRAGMA table_info(sessions);"
        default: return nil
        }
        guard let rows = rows(sql) else { return nil }
        return Set(rows.compactMap { $0.string("name") })
    }

    private func rows(_ sql: String) -> [AgentUsageSQLiteRow]? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)
        var result: [AgentUsageSQLiteRow] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW else { return nil }
            var values: [String: AgentUsageSQLiteValue] = [:]
            for index in 0..<columnCount {
                guard let namePointer = sqlite3_column_name(statement, index) else { continue }
                let name = String(cString: namePointer)
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    values[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    values[name] = .double(sqlite3_column_double(statement, index))
                case SQLITE_TEXT:
                    if let pointer = sqlite3_column_text(statement, index) {
                        values[name] = .text(String(cString: pointer))
                    }
                default:
                    values[name] = .null
                }
            }
            result.append(AgentUsageSQLiteRow(values: values))
        }
    }
}

private enum AgentUsageSQLiteValue {
    case integer(Int64)
    case double(Double)
    case text(String)
    case null
}

private struct AgentUsageSQLiteRow {
    let values: [String: AgentUsageSQLiteValue]

    func string(_ key: String) -> String? {
        switch values[key] {
        case let .text(value): return value
        case let .integer(value): return String(value)
        case let .double(value): return String(value)
        default: return nil
        }
    }

    func int64(_ key: String) -> Int64? {
        switch values[key] {
        case let .integer(value): return value
        case let .double(value): return Int64(value)
        case let .text(value): return Int64(value)
        default: return nil
        }
    }

    func double(_ key: String) -> Double? {
        switch values[key] {
        case let .integer(value): return Double(value)
        case let .double(value): return value
        case let .text(value): return Double(value)
        default: return nil
        }
    }
}

// MARK: - Streaming parsers

private final class AgentUsageDateParser {
    private let fractional: ISO8601DateFormatter
    private let plain: ISO8601DateFormatter

    init() {
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
    }

    func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber { return Self.epoch(number.int64Value) }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if let numeric = Int64(string), let date = Self.epoch(numeric) { return date }
        return fractional.date(from: string) ?? plain.date(from: string)
    }

    static func epoch(_ value: Int64?) -> Date? {
        guard let value, value > 0 else { return nil }
        let magnitude = abs(value)
        let seconds: Double
        if magnitude > 10_000_000_000_000_000 {
            seconds = Double(value) / 1_000_000_000
        } else if magnitude > 10_000_000_000_000 {
            seconds = Double(value) / 1_000_000
        } else if magnitude > 10_000_000_000 {
            seconds = Double(value) / 1_000
        } else {
            seconds = Double(value)
        }
        return Date(timeIntervalSince1970: seconds)
    }
}

private struct AgentUsageJSONStreamStats {
    let bytesRead: Int64
    let beganMidLine: Bool
    let hitByteLimit: Bool
    let oversizedRelevantLineCount: Int
}

private enum AgentUsageResidentMemoryGuard {
    /// Token analytics is background metadata work. It must yield long before
    /// it can make the rest of the Mac unresponsive, regardless of source size.
    static let maximumResidentBytes: UInt64 = 512 * 1_024 * 1_024

    static func isOverLimit() -> Bool {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    rebound,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS && info.phys_footprint >= maximumResidentBytes
    }
}

private enum AgentUsageJSONStream {
    @discardableResult
    static func forEachLine(
        at url: URL,
        maximumLineBytes: Int = 512 * 1_024,
        startingAtOffset: Int64 = 0,
        startsAtLineBoundary: Bool = false,
        maximumBytes: Int64? = nil,
        deadline: Date? = nil,
        prefilterPatterns: [Data] = [],
        _ body: (Data) throws -> Void
    ) throws -> AgentUsageJSONStreamStats {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let start = max(0, startingAtOffset)
        let fileSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)
        if start > 0 { try handle.seek(toOffset: UInt64(start)) }
        var buffer = Data()
        var discardingOversizedLine = start > 0 && !startsAtLineBoundary
        var remaining = maximumBytes.map { max(0, $0) }
        var bytesRead: Int64 = 0
        var hitByteLimit = false
        var oversizedRelevantLineCount = 0
        var discardedLineWasInteresting = false
        var scanOffset = 0
        var nextMemoryCheckAt: Int64 = 4 * 1_024 * 1_024

        while true {
            try Task.checkCancellation()
            if deadline.map({ Date() >= $0 }) == true {
                throw AgentUsageParserStop.bounded
            }
            if let remaining, remaining <= 0 {
                hitByteLimit = fileSize < 0 || start + bytesRead < fileSize
                break
            }
            let readCount = Int(min(Int64(64 * 1_024), remaining ?? Int64(64 * 1_024)))
            var chunkCount = 0
            let reachedEnd = try autoreleasepool { () -> Bool in
                let chunk = try handle.read(upToCount: readCount) ?? Data()
                guard !chunk.isEmpty else { return true }
                chunkCount = chunk.count
                buffer.append(chunk)
                return false
            }
            if reachedEnd { break }
            bytesRead += Int64(chunkCount)
            if remaining != nil { remaining! -= Int64(chunkCount) }
            if bytesRead >= nextMemoryCheckAt {
                if AgentUsageResidentMemoryGuard.isOverLimit() {
                    throw AgentUsageParserStop.bounded
                }
                nextMemoryCheckAt = bytesRead + 4 * 1_024 * 1_024
            }

            var lineStartOffset = 0
            var consumedOffset = 0
            while scanOffset < buffer.count {
                let searchStart = buffer.index(buffer.startIndex, offsetBy: scanOffset)
                guard let newline = buffer[searchStart...].firstIndex(of: 10) else {
                    scanOffset = buffer.count
                    break
                }
                let newlineOffset = buffer.distance(from: buffer.startIndex, to: newline)
                if !discardingOversizedLine {
                    let lineStart = buffer.index(buffer.startIndex, offsetBy: lineStartOffset)
                    let lineRange = lineStart..<newline
                    let lineByteCount = newlineOffset - lineStartOffset
                    if lineByteCount <= maximumLineBytes {
                        let isInteresting = prefilterPatterns.isEmpty || prefilterPatterns.contains {
                            buffer.range(of: $0, options: [], in: lineRange) != nil
                        }
                        if isInteresting {
                            try autoreleasepool {
                                try body(buffer.subdata(in: lineRange))
                            }
                        }
                    } else {
                        let isRelevant = prefilterPatterns.isEmpty || prefilterPatterns.contains {
                            buffer.range(of: $0, options: [], in: lineRange) != nil
                        }
                        if isRelevant { oversizedRelevantLineCount += 1 }
                    }
                } else {
                    let tailRange = buffer.startIndex..<newline
                    let tailIsInteresting = prefilterPatterns.isEmpty || prefilterPatterns.contains {
                        buffer.range(of: $0, options: [], in: tailRange) != nil
                    }
                    if discardedLineWasInteresting || tailIsInteresting {
                        oversizedRelevantLineCount += 1
                    }
                }
                discardingOversizedLine = false
                discardedLineWasInteresting = false
                lineStartOffset = newlineOffset + 1
                scanOffset = lineStartOffset
                consumedOffset = lineStartOffset
            }
            if consumedOffset > 0 {
                let consumedThrough = buffer.index(buffer.startIndex, offsetBy: consumedOffset)
                buffer.removeSubrange(buffer.startIndex..<consumedThrough)
                scanOffset = max(0, scanOffset - consumedOffset)
            }

            if buffer.count > maximumLineBytes {
                if prefilterPatterns.isEmpty || prefilterPatterns.contains(where: { buffer.range(of: $0) != nil }) {
                    discardedLineWasInteresting = true
                }
                buffer.removeAll(keepingCapacity: true)
                discardingOversizedLine = true
                scanOffset = 0
            }
        }

        if !hitByteLimit, !buffer.isEmpty, !discardingOversizedLine, buffer.count <= maximumLineBytes {
            try autoreleasepool { try body(buffer) }
        }
        return AgentUsageJSONStreamStats(
            bytesRead: bytesRead,
            beganMidLine: start > 0,
            hitByteLimit: hitByteLimit,
            oversizedRelevantLineCount: oversizedRelevantLineCount
        )
    }
}

private enum AgentUsageParserStop: Error {
    case bounded
}

private struct AgentUsageParsedFile {
    let summary: AgentUsageFileSummary
    let completedRequestedRange: Bool
    let skippedRelevantRecord: Bool
    let bytesRead: Int64
}

private final class AgentUsageCodexSessionParser {
    private let dateParser = AgentUsageDateParser()
    private let skillIndex: AgentUsageSkillIndex

    init(skillIndex: AgentUsageSkillIndex) {
        self.skillIndex = skillIndex
    }

    func parse(
        url: URL,
        source: AgentUsageCodexThread,
        startingAtOffset: Int64 = 0,
        startsAtLineBoundary: Bool = false,
        maximumBytes: Int64? = nil,
        deadline: Date? = nil,
        allowCompleteTokenScan: Bool = false,
        excludingTokenFingerprints: Set<AgentUsageCounterFingerprint> = []
    ) -> AgentUsageParsedFile? {
        var counterState = AgentUsageCounterState()
        var events = AgentUsageEventAccumulator()
        var tools: [String: Int] = [:]
        var skills: [AgentUsageSkillEvent] = []
        var lastActive: Date?
        var currentModel = source.model
        var currentProject = source.cwd
        var processedLineCount = 0
        var matchingLineCount = 0
        var tokenRecordCount = 0
        var wasBounded = false
        var streamStats: AgentUsageJSONStreamStats?
        let tokenPattern = Data(#""type":"token_count""#.utf8)
        let functionPattern = Data(#""type":"function_call""#.utf8)
        let customToolPattern = Data(#""type":"custom_tool_call""#.utf8)
        let contextPattern = Data(#""type":"turn_context""#.utf8)
        let sessionPattern = Data(#""type":"session_meta""#.utf8)

        do {
            streamStats = try AgentUsageJSONStream.forEachLine(
                at: url,
                startingAtOffset: startingAtOffset,
                startsAtLineBoundary: startsAtLineBoundary,
                maximumBytes: maximumBytes,
                deadline: deadline,
                prefilterPatterns: [tokenPattern, functionPattern, customToolPattern, contextPattern, sessionPattern]
            ) { line in
                processedLineCount += 1
                if processedLineCount % 2_048 == 0,
                   deadline.map({ Date() >= $0 }) == true {
                    wasBounded = true
                    throw AgentUsageParserStop.bounded
                }
                let isToken = line.range(of: tokenPattern) != nil
                let isTool = line.range(of: functionPattern) != nil
                    || line.range(of: customToolPattern) != nil
                let isContext = line.range(of: contextPattern) != nil
                    || line.range(of: sessionPattern) != nil
                if isToken || isTool || isContext {
                    matchingLineCount += 1
                    if matchingLineCount % 256 == 0,
                       deadline.map({ Date() >= $0 }) == true {
                        wasBounded = true
                        throw AgentUsageParserStop.bounded
                    }
                }
                guard isToken || isTool || isContext,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let payload = object["payload"] as? [String: Any],
                      let type = AgentUsageValues.string(payload["type"])
                        ?? AgentUsageValues.string(object["type"]) else { return }

                let date = dateParser.date(object["timestamp"]) ?? source.updatedAt ?? Date.distantPast
                if lastActive == nil || date > lastActive! { lastActive = date }

                if type == "turn_context" || type == "session_meta" {
                    currentModel = AgentUsageValues.string(payload["model"]) ?? currentModel
                    currentProject = AgentUsageValues.string(payload["cwd"]) ?? currentProject
                    return
                }

                if type == "function_call" || type == "custom_tool_call" {
                    if let name = AgentUsageValues.string(payload["name"]), !name.isEmpty {
                        let boundedName = String(name.prefix(160))
                        if tools[boundedName] != nil || tools.count < 512 {
                            tools[boundedName, default: 0] += 1
                        }
                    }
                    for skill in line.count <= 512 * 1_024
                        ? extractSkillEvents(from: payload, date: date, sessionID: source.id)
                        : [] where skills.count < 4_096 {
                        skills.append(skill)
                    }
                    return
                }

                guard type == "token_count",
                      let info = payload["info"] as? [String: Any] else { return }
                let cumulative = (info["total_token_usage"] as? [String: Any]).map(AgentUsageValues.counterSample)
                let last = (info["last_token_usage"] as? [String: Any]).map(AgentUsageValues.counterSample)
                guard cumulative != nil || last != nil else { return }
                let tokenFingerprint = AgentUsageCounterFingerprint(cumulative: cumulative, last: last)
                tokenRecordCount += 1
                if !allowCompleteTokenScan, tokenRecordCount > 250_000 {
                    wasBounded = true
                    throw AgentUsageParserStop.bounded
                }
                if startingAtOffset > 0,
                   counterState.cumulativeHighWater == nil,
                   last == nil,
                   let cumulative {
                    // A tail scan cannot attribute a session-to-date cumulative
                    // counter to the timestamp of the first visible record.
                    counterState.cumulativeHighWater = cumulative.totals()
                    return
                }
                guard let tokens = AgentUsageCounterNormalizer.consume(
                    cumulative: cumulative,
                    last: last,
                    state: &counterState
                ) else { return }
                // The normalizer must still observe inherited records so the
                // child's later cumulative counters have the correct baseline.
                // Only the resulting duplicate contribution is discarded.
                guard !excludingTokenFingerprints.contains(tokenFingerprint) else { return }
                let price = AgentUsagePricingCatalog.price(scope: .codex, model: currentModel, at: date)
                let estimated = AgentUsagePricingCatalog.estimatedCost(tokens: tokens, price: price)
                events.add(AgentUsageEvent(
                    id: nil,
                    date: date,
                    tokens: tokens,
                    estimatedCostUSD: estimated.0,
                    priceKnown: estimated.1,
                    model: currentModel,
                    projectPath: currentProject,
                    sessionID: source.id
                ))
            }
        } catch AgentUsageParserStop.bounded {
            wasBounded = true
        } catch {
            return nil
        }

        let stats = streamStats
        return AgentUsageParsedFile(
            summary: AgentUsageFileSummary(
                events: events.events,
                toolCalls: tools,
                skillEvents: skills,
                lastActiveAt: lastActive
            ),
            completedRequestedRange: !wasBounded,
            skippedRelevantRecord: (stats?.oversizedRelevantLineCount ?? 0) > 0,
            bytesRead: stats?.bytesRead ?? 0
        )
    }

    private func extractSkillEvents(from payload: [String: Any], date: Date, sessionID: String) -> [AgentUsageSkillEvent] {
        var strings: [String] = []
        for key in ["arguments", "input", "cmd", "command", "path"] {
            AgentUsageValues.collectStrings(payload[key], into: &strings, depth: 0)
        }
        var result: [AgentUsageSkillEvent] = []
        var seen = Set<String>()
        for string in strings.prefix(128) {
            for path in AgentUsageValues.candidateSkillPaths(in: string) {
                guard let url = skillIndex.resolve(path: path), seen.insert(url.path).inserted else { continue }
                result.append(AgentUsageSkillEvent(
                    name: url.deletingLastPathComponent().lastPathComponent,
                    path: url.path,
                    date: date,
                    sessionID: sessionID
                ))
            }
        }
        return result
    }
}

private enum AgentUsageValues {
    static func string(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    static func int64(_ value: Any?) -> Int64? {
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    static func counterSample(_ value: [String: Any]) -> AgentUsageCounterSample {
        AgentUsageCounterSample(
            input: int64(value["input_tokens"]),
            cached: int64(value["cached_input_tokens"]),
            output: int64(value["output_tokens"]),
            reasoning: int64(value["reasoning_output_tokens"]),
            total: int64(value["total_tokens"])
        )
    }

    static func tokenFingerprint(
        date: Date,
        cumulative: AgentUsageCounterSample?,
        last: AgentUsageCounterSample?
    ) -> String {
        let values: [Int64?] = [
            cumulative?.input, cumulative?.cached, cumulative?.output, cumulative?.reasoning, cumulative?.total,
            last?.input, last?.cached, last?.output, last?.reasoning, last?.total
        ]
        return String(Int64(date.timeIntervalSince1970 * 1_000)) + ":" + values.map { $0.map(String.init) ?? "_" }.joined(separator: ",")
    }

    static func collectStrings(_ value: Any?, into result: inout [String], depth: Int) {
        guard depth <= 4, result.count < 128, let value else { return }
        if let text = value as? String {
            result.append(text)
        } else if let values = value as? [Any] {
            for child in values.prefix(64) { collectStrings(child, into: &result, depth: depth + 1) }
        } else if let values = value as? [String: Any] {
            for child in values.values.prefix(64) { collectStrings(child, into: &result, depth: depth + 1) }
        }
    }

    static func candidateSkillPaths(in text: String) -> [String] {
        guard text.contains("SKILL.md") else { return [] }
        let delimiters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`<>|,;(){}[]"))
        return text.components(separatedBy: delimiters)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\\")) }
            .filter { $0.hasSuffix("SKILL.md") && ($0.hasPrefix("/") || $0.hasPrefix("~/")) }
    }
}

private struct AgentUsageCodexLineageMetadata {
    let parentThreadID: String?
}

private enum AgentUsageCodexLineageStop: Error {
    case metadataFound
    case recordLimitReached
}

/// Reads only `session_meta` and `token_count` records. The lineage repair does
/// not deserialize prompts, assistant replies, tool arguments, or artifacts.
private enum AgentUsageCodexLineageReader {
    static let dedupVersion = 2
    static let directAncestorDedupVersion = 1
    private static let metadataReadLimit: Int64 = 2 * 1_024 * 1_024
    static let fingerprintReadLimit: Int64 = 2 * 1_024 * 1_024 * 1_024
    private static let fingerprintRecordLimit = 1_000_000

    static func metadata(at url: URL) -> AgentUsageCodexLineageMetadata? {
        var result: AgentUsageCodexLineageMetadata?
        let sessionPattern = Data(#""type":"session_meta""#.utf8)
        do {
            let stats = try AgentUsageJSONStream.forEachLine(
                at: url,
                maximumBytes: metadataReadLimit,
                prefilterPatterns: [sessionPattern]
            ) { line in
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let payload = object["payload"] as? [String: Any],
                      (AgentUsageValues.string(payload["type"]) ?? AgentUsageValues.string(object["type"])) == "session_meta" else { return }
                let source = payload["source"] as? [String: Any]
                let subagent = source?["subagent"] as? [String: Any]
                let spawn = subagent?["thread_spawn"] as? [String: Any]
                let parent = AgentUsageValues.string(spawn?["parent_thread_id"])
                    ?? AgentUsageValues.string(payload["parent_thread_id"])
                result = AgentUsageCodexLineageMetadata(parentThreadID: parent)
                throw AgentUsageCodexLineageStop.metadataFound
            }
            guard !stats.hitByteLimit, stats.oversizedRelevantLineCount == 0 else { return nil }
        } catch AgentUsageCodexLineageStop.metadataFound {
            return result
        } catch {
            return nil
        }
        return result
    }

    static func tokenFingerprints(at url: URL) -> Set<AgentUsageCounterFingerprint>? {
        guard let fingerprint = AgentUsageValues.fileFingerprint(url),
              fingerprint.size >= 0,
              fingerprint.size <= fingerprintReadLimit,
              // Never fall back to copying a multi-gigabyte rollout into the
              // app heap if Foundation cannot establish a read-only mapping.
              let data = try? Data(contentsOf: url, options: [.alwaysMapped]) else { return nil }
        var result = Set<AgentUsageCounterFingerprint>()
        result.reserveCapacity(4_096)
        var recordCount = 0
        var searchOffset = data.startIndex
        let tokenPattern = Data(#""type":"token_count""#.utf8)
        let maximumTokenLineBytes = 512 * 1_024

        // Searching the memory-mapped bytes jumps directly between the small
        // token_count records. It avoids constructing Data/String objects for
        // gigabytes of prompts, artifacts and repeated media payloads.
        while searchOffset < data.endIndex,
              let match = data.range(
                of: tokenPattern,
                options: [],
                in: searchOffset..<data.endIndex
              ) {
            let lineStart = data[..<match.lowerBound].lastIndex(of: 0x0A).map { $0 + 1 }
                ?? data.startIndex
            let newline = data[match.upperBound...].firstIndex(of: 0x0A)
            let lineEnd = newline ?? data.endIndex
            guard lineEnd - lineStart <= maximumTokenLineBytes else { return nil }

            autoreleasepool {
                let line = data.subdata(in: lineStart..<lineEnd)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let payload = object["payload"] as? [String: Any],
                      (AgentUsageValues.string(payload["type"]) ?? AgentUsageValues.string(object["type"])) == "token_count",
                      let info = payload["info"] as? [String: Any] else { return }
                let cumulative = (info["total_token_usage"] as? [String: Any]).map(AgentUsageValues.counterSample)
                let last = (info["last_token_usage"] as? [String: Any]).map(AgentUsageValues.counterSample)
                guard cumulative != nil || last != nil else { return }
                recordCount += 1
                result.insert(AgentUsageCounterFingerprint(cumulative: cumulative, last: last))
            }
            guard recordCount <= fingerprintRecordLimit else { return nil }
            if recordCount % 256 == 0, AgentUsageResidentMemoryGuard.isOverLimit() { return nil }
            searchOffset = newline.map { min(data.endIndex, $0 + 1) } ?? data.endIndex
        }
        return result
    }
}

// MARK: - Claude Code provider

private final class AgentUsageClaudeTranscriptParser {
    private let dateParser = AgentUsageDateParser()
    private let skillIndex: AgentUsageSkillIndex

    init(skillIndex: AgentUsageSkillIndex) {
        self.skillIndex = skillIndex
    }

    func parse(url: URL) -> AgentUsageFileSummary? {
        let sessionID = url.deletingPathExtension().lastPathComponent
        var events = AgentUsageEventAccumulator()
        var tools: [String: Int] = [:]
        var skills: [AgentUsageSkillEvent] = []
        var seenMessageIDs = Set<String>()
        var lastActive: Date?
        var currentProject = AgentUsageValues.inferClaudeProjectPath(url)
        var currentModel: String?
        let fallbackDate = AgentUsageValues.fileModificationDate(url) ?? Date.distantPast
        let usagePattern = Data(#""usage""#.utf8)
        let toolPattern = Data(#""tool_use""#.utf8)
        let attributionPattern = Data("attribution".utf8)

        do {
            try AgentUsageJSONStream.forEachLine(
                at: url,
                maximumLineBytes: 1 * 1_024 * 1_024,
                prefilterPatterns: [usagePattern, toolPattern, attributionPattern]
            ) { line in
                guard line.range(of: usagePattern) != nil
                        || line.range(of: toolPattern) != nil
                        || line.range(of: attributionPattern) != nil,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }

                let message = object["message"] as? [String: Any]
                let date = dateParser.date(object["timestamp"])
                    ?? fallbackDate
                if lastActive == nil || date > lastActive! { lastActive = date }
                currentProject = AgentUsageValues.string(object["cwd"])
                    ?? AgentUsageValues.string(object["projectPath"])
                    ?? currentProject
                currentModel = AgentUsageValues.string(message?["model"])
                    ?? AgentUsageValues.string(object["model"])
                    ?? currentModel

                parseExplicitAttribution(object: object, message: message, date: date, sessionID: sessionID, into: &skills)
                parseTools(message?["content"], date: date, sessionID: sessionID, tools: &tools, skills: &skills)

                guard let usage = message?["usage"] as? [String: Any],
                      let tokens = parseUsage(usage), !tokens.isZero else { return }
                let messageID = AgentUsageValues.string(message?["id"])
                    ?? AgentUsageValues.string(object["uuid"])
                    ?? AgentUsageValues.string(object["id"])
                if let messageID, !seenMessageIDs.insert(messageID).inserted { return }

                let price = AgentUsagePricingCatalog.price(scope: .claude, model: currentModel, at: date)
                let cacheRead = max(0, AgentUsageValues.int64(usage["cache_read_input_tokens"]) ?? 0)
                let cacheWrite = max(0, AgentUsageValues.int64(usage["cache_creation_input_tokens"]) ?? 0)
                let cacheCreation = usage["cache_creation"] as? [String: Any]
                let cacheWriteOneHour = max(
                    0,
                    AgentUsageValues.int64(cacheCreation?["ephemeral_1h_input_tokens"]) ?? 0
                )
                let estimated = AgentUsagePricingCatalog.estimatedCost(
                    tokens: tokens,
                    price: price,
                    cacheReadTokens: cacheRead,
                    cacheWriteTokens: cacheWrite,
                    cacheWriteOneHourTokens: cacheWriteOneHour
                )
                events.add(AgentUsageEvent(
                    id: messageID.map(AgentUsagePrivacy.digest),
                    date: date,
                    tokens: tokens,
                    estimatedCostUSD: estimated.0,
                    priceKnown: estimated.1,
                    model: currentModel,
                    projectPath: currentProject,
                    sessionID: sessionID
                ))
            }
        } catch {
            return nil
        }

        return AgentUsageFileSummary(
            events: events.events,
            toolCalls: tools,
            skillEvents: Array(skills.prefix(4_096)),
            lastActiveAt: lastActive
        )
    }

    private func parseUsage(_ usage: [String: Any]) -> AgentUsageTokenTotals? {
        let directInput = max(0, AgentUsageValues.int64(usage["input_tokens"]) ?? 0)
        let cacheCreation = max(0, AgentUsageValues.int64(usage["cache_creation_input_tokens"]) ?? 0)
        let cacheRead = max(0, AgentUsageValues.int64(usage["cache_read_input_tokens"]) ?? 0)
        let output = max(0, AgentUsageValues.int64(usage["output_tokens"]) ?? 0)
        let reasoning = max(0, AgentUsageValues.int64(usage["reasoning_output_tokens"]) ?? 0)
        let input = AgentUsageMath.saturatingAdd(directInput, AgentUsageMath.saturatingAdd(cacheCreation, cacheRead))
        let defaultTotal = AgentUsageMath.saturatingAdd(input, output)
        let total = max(0, AgentUsageValues.int64(usage["total_tokens"]) ?? defaultTotal)
        let result = AgentUsageTokenTotals(
            input: input,
            cached: AgentUsageMath.saturatingAdd(cacheCreation, cacheRead),
            output: output,
            reasoning: reasoning,
            total: total
        )
        return result.isZero ? nil : result
    }

    private func parseExplicitAttribution(
        object: [String: Any],
        message: [String: Any]?,
        date: Date,
        sessionID: String,
        into skills: inout [AgentUsageSkillEvent]
    ) {
        let candidates = [
            AgentUsageValues.string(object["attributionSkill"]),
            AgentUsageValues.string(object["attribution_skill"]),
            AgentUsageValues.string(message?["attributionSkill"]),
            AgentUsageValues.string(message?["attribution_skill"])
        ].compactMap { $0 }
        for value in candidates {
            if let url = skillIndex.resolve(path: value) ?? skillIndex.resolve(name: value) {
                skills.append(AgentUsageSkillEvent(
                    name: url.deletingLastPathComponent().lastPathComponent,
                    path: url.path,
                    date: date,
                    sessionID: sessionID
                ))
            }
        }
    }

    private func parseTools(
        _ content: Any?,
        date: Date,
        sessionID: String,
        tools: inout [String: Int],
        skills: inout [AgentUsageSkillEvent]
    ) {
        guard let items = content as? [Any] else { return }
        for rawItem in items.prefix(512) {
            guard let item = rawItem as? [String: Any],
                  AgentUsageValues.string(item["type"]) == "tool_use",
                  let name = AgentUsageValues.string(item["name"]), !name.isEmpty else { continue }
            tools[name, default: 0] += 1
            guard name.lowercased().contains("skill") else { continue }

            let input = item["input"] as? [String: Any]
            let candidates = [
                AgentUsageValues.string(input?["skill"]),
                AgentUsageValues.string(input?["name"]),
                AgentUsageValues.string(input?["path"])
            ].compactMap { $0 }
            for value in candidates {
                if let url = skillIndex.resolve(path: value) ?? skillIndex.resolve(name: value) {
                    skills.append(AgentUsageSkillEvent(
                        name: url.deletingLastPathComponent().lastPathComponent,
                        path: url.path,
                        date: date,
                        sessionID: sessionID
                    ))
                }
            }
        }
    }
}

private final class AgentUsageClaudeProvider {
    private let fileManager = FileManager.default
    private let context: AgentUsageStatisticsContext
    private let progress: @Sendable (AgentUsageScanProgress) -> Void
    private let skillIndex: AgentUsageSkillIndex

    init(
        context: AgentUsageStatisticsContext,
        skillIndex: AgentUsageSkillIndex,
        progress: @escaping @Sendable (AgentUsageScanProgress) -> Void
    ) {
        self.context = context
        self.skillIndex = skillIndex
        self.progress = progress
    }

    func load() -> AgentUsageRuntimeAggregate {
        var aggregate = AgentUsageRuntimeAggregate(scope: .claude)
        let projectsRoot = AgentUsagePathPolicy.claudeRoot.appendingPathComponent("projects", isDirectory: true)
        let files = enumerateTranscripts(root: projectsRoot)

        guard fileManager.fileExists(atPath: projectsRoot.path) else {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .claude,
                severity: .info,
                code: "claude_projects_missing",
                message: "No Claude Code transcript directory was found.",
                source: "~/.claude/projects"
            ))
            aggregate.tasks = readTasks()
            return aggregate
        }

        progress(AgentUsageScanProgress(
            phase: .scanningClaudeTranscripts,
            current: 0,
            total: files.count,
            currentSource: nil,
            message: "Scanning Claude Code transcript metadata"
        ))

        var cache = AgentUsageFileCacheStore.load(scope: .claude)
        let liveKeys = Set(files.map { AgentUsagePrivacy.cacheKey(for: $0) })
        var cacheChanged = cache.entries.keys.contains(where: { !liveKeys.contains($0) })
        cache.entries = cache.entries.filter { liveKeys.contains($0.key) }
        let parser = AgentUsageClaudeTranscriptParser(skillIndex: skillIndex)
        var summaries: [AgentUsageFileSummary] = []
        var failures = 0

        for (index, file) in files.enumerated() {
            if Task.isCancelled { break }
            if index == 0 || index == files.count - 1 || index % 8 == 0 {
                progress(AgentUsageScanProgress(
                    phase: .scanningClaudeTranscripts,
                    current: index,
                    total: files.count,
                    currentSource: file.lastPathComponent,
                    message: "Reading Claude Code usage \(index + 1) of \(files.count)"
                ))
            }
            guard let fingerprint = AgentUsageValues.fileFingerprint(file) else { continue }
            let cacheKey = AgentUsagePrivacy.cacheKey(for: file)
            let sessionID = file.deletingPathExtension().lastPathComponent
            let projectPath = AgentUsageValues.peekClaudeProjectPath(file)
                ?? AgentUsageValues.inferClaudeProjectPath(file)
            if let cached = cache.entries[cacheKey],
               cached.size == fingerprint.size,
               cached.modificationTimeNanoseconds == fingerprint.modificationTimeNanoseconds {
                summaries.append(cached.summary.rehydrated(
                    projectPath: projectPath,
                    sessionID: sessionID,
                    skillIndex: skillIndex
                ))
                continue
            }
            guard let summary = parser.parse(url: file) else {
                failures += 1
                continue
            }
            summaries.append(summary)
            cache.entries[cacheKey] = AgentUsageFileCacheEntry(
                size: fingerprint.size,
                modificationTimeNanoseconds: fingerprint.modificationTimeNanoseconds,
                coverageIncomplete: false,
                skippedRelevantRecord: false,
                scannedFromOffset: 0,
                summary: summary.redactedForDisk()
            )
            cacheChanged = true
        }

        if !Task.isCancelled, cacheChanged, !AgentUsageFileCacheStore.save(cache, scope: .claude) {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .claude,
                severity: .warning,
                code: "claude_cache_write_failed",
                message: "Claude Code usage cache could not be saved; the next refresh may be slower.",
                source: nil
            ))
        }

        var seenMessageIDs = Set<String>()
        for summary in summaries {
            if Task.isCancelled { break }
            aggregate.parsedFileCount += 1
            for event in summary.events {
                if let id = event.id, !seenMessageIDs.insert(id).inserted { continue }
                aggregate.events.append(event)
                aggregate.tokenEventCount += 1
            }
            for (name, count) in summary.toolCalls {
                aggregate.toolCalls[name, default: 0] += count
            }
            aggregate.skillEvents.append(contentsOf: summary.skillEvents)
        }
        aggregate.tasks = readTasks()
        aggregate.available = !files.isEmpty || !aggregate.tasks.isEmpty
        aggregate.sourceQuality = aggregate.events.isEmpty ? (files.isEmpty ? .unavailable : .approximate) : .detailed

        if failures > 0 {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .claude,
                severity: .warning,
                code: "claude_transcript_parse_partial",
                message: "\(failures) Claude Code transcript files could not be parsed.",
                source: nil
            ))
        }
        if files.isEmpty {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .claude,
                severity: .info,
                code: "claude_transcripts_empty",
                message: "No Claude Code transcript JSONL files were found.",
                source: "~/.claude/projects"
            ))
        } else if aggregate.events.isEmpty {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .claude,
                severity: .warning,
                code: "claude_usage_empty",
                message: "Claude Code transcripts were found, but no message.usage records were available.",
                source: nil
            ))
        }

        progress(AgentUsageScanProgress(
            phase: .scanningClaudeTranscripts,
            current: files.count,
            total: files.count,
            currentSource: nil,
            message: "Claude Code transcript scan complete"
        ))
        return aggregate
    }

    private func enumerateTranscripts(root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var result: [URL] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 50_000 {
                enumerator.skipDescendants()
                break
            }
            guard url.pathExtension.lowercased() == "jsonl",
                  let normalized = AgentUsagePathPolicy.normalizedClaudeTranscriptURL(url) else { continue }
            result.append(normalized)
        }
        if result.count > 2_000 {
            result.sort {
                (AgentUsageValues.fileModificationDate($0) ?? .distantPast)
                    > (AgentUsageValues.fileModificationDate($1) ?? .distantPast)
            }
            result.removeSubrange(2_000..<result.count)
        }
        return result.sorted { $0.path < $1.path }
    }

    private func readTasks() -> [AgentUsageTaskItem] {
        progress(AgentUsageScanProgress(
            phase: .readingTasks,
            current: 0,
            total: 0,
            currentSource: "Claude Code",
            message: "Reading Claude Code task metadata"
        ))
        let root = AgentUsagePathPolicy.claudeRoot.appendingPathComponent("tasks", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [AgentUsageTaskItem] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            guard AgentUsagePathPolicy.isContained(normalized, in: root), AgentUsagePathPolicy.isSafe(normalized),
                  let fingerprint = AgentUsageValues.fileFingerprint(normalized),
                  fingerprint.size <= 2 * 1_024 * 1_024,
                  let data = try? Data(contentsOf: normalized, options: [.mappedIfSafe]),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let status = (AgentUsageValues.string(object["status"]) ?? "pending").lowercased()
            let category: AgentUsageTaskCategory
            switch status {
            case "in_progress", "active", "running": category = .active
            case "completed", "done", "success": category = .done
            case "scheduled", "queued_for_later": category = .scheduled
            default: category = .pending
            }
            let updated = AgentUsageDateParser().date(object["updatedAt"])
                ?? AgentUsageDateParser().date(object["updated_at"])
                ?? AgentUsageValues.fileModificationDate(normalized)
            guard category == .active || category == .scheduled || (updated.map { $0 >= context.todayStart } ?? false) else { continue }
            let rawTitle = AgentUsageValues.string(object["subject"])
                ?? AgentUsageValues.string(object["title"])
                ?? "Claude Code task"
            result.append(AgentUsageTaskItem(
                id: "claude-" + normalized.deletingPathExtension().lastPathComponent,
                scope: .claude,
                category: category,
                title: AgentUsageValues.metadataLabel(rawTitle, fallback: "Claude Code task"),
                project: AgentUsageValues.string(object["project"]),
                updatedAt: updated,
                tokens: nil
            ))
        }
        return result
    }
}

private extension AgentUsageValues {
    private enum PeekComplete: Error { case done }

    struct FileFingerprint {
        let size: Int64
        let modificationTimeNanoseconds: Int64
    }

    static func fileFingerprint(_ url: URL) -> FileFingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value else { return nil }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return FileFingerprint(size: size, modificationTimeNanoseconds: Int64(modified * 1_000_000_000))
    }

    static func fileModificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    static func inferClaudeProjectPath(_ transcript: URL) -> String {
        let encoded = transcript.deletingLastPathComponent().lastPathComponent
        return encoded
    }

    static func peekClaudeProjectPath(_ transcript: URL) -> String? {
        var result: String?
        var inspected = 0
        let cwdPattern = Data(#""cwd""#.utf8)
        do {
            try AgentUsageJSONStream.forEachLine(
                at: transcript,
                maximumLineBytes: 512 * 1_024,
                maximumBytes: 2 * 1_024 * 1_024,
                prefilterPatterns: [cwdPattern]
            ) { line in
                inspected += 1
                if line.range(of: cwdPattern) != nil,
                   let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let cwd = string(object["cwd"]), !cwd.isEmpty {
                    result = cwd
                    throw PeekComplete.done
                }
                if inspected >= 256 { throw PeekComplete.done }
            }
        } catch PeekComplete.done {
            return result
        } catch {
            return nil
        }
        return result
    }

    static func metadataLabel(_ value: String, fallback: String) -> String {
        let singleLine = value.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return fallback }
        return String(singleLine.prefix(160))
    }
}

// MARK: - Sandboxed source access

private final class AgentUsageSecurityScopeLease {
    private var accessedURLs: [URL]
    let diagnostics: [AgentUsageDiagnostic]

    private init(accessedURLs: [URL], diagnostics: [AgentUsageDiagnostic]) {
        self.accessedURLs = accessedURLs
        self.diagnostics = diagnostics
    }

    static func acquire() -> AgentUsageSecurityScopeLease {
        guard SandboxPaths.isSandboxed else {
            return AgentUsageSecurityScopeLease(accessedURLs: [], diagnostics: [])
        }

        let bookmarkURL = URL(fileURLWithPath: SandboxPaths.shared.tokenScopeBookmarksPath)
        guard let data = try? Data(contentsOf: bookmarkURL, options: [.mappedIfSafe]),
              data.count <= 8 * 1_024 * 1_024,
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return AgentUsageSecurityScopeLease(
                accessedURLs: [],
                diagnostics: [AgentUsageDiagnostic(
                    scope: nil,
                    severity: .warning,
                    code: "usage_bookmark_required",
                    message: "Choose an Agent data folder or your home folder to authorize local usage analytics.",
                    source: nil
                )]
            )
        }

        let desiredRoots = [
            AgentUsagePathPolicy.codexRoot,
            AgentUsagePathPolicy.claudeRoot,
            AgentUsagePathPolicy.openCodeRoot,
            AgentUsagePathPolicy.miniMaxRoot,
            AgentUsagePathPolicy.qClawRoot,
            AgentUsagePathPolicy.openClawRoot
        ]
        var accessed: [URL] = []
        var failures = 0
        for (_, bookmark) in bookmarks.sorted(by: { $0.key < $1.key }).prefix(64) {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                failures += 1
                continue
            }
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            let relevant = desiredRoots.contains {
                AgentUsagePathPolicy.isContained($0, in: normalized)
                    || AgentUsagePathPolicy.isContained(normalized, in: $0)
            }
            guard relevant else { continue }
            if normalized.startAccessingSecurityScopedResource() {
                accessed.append(normalized)
            } else {
                failures += 1
            }
        }

        var diagnostics: [AgentUsageDiagnostic] = []
        if accessed.isEmpty {
            diagnostics.append(AgentUsageDiagnostic(
                scope: nil,
                severity: .warning,
                code: "usage_bookmark_unavailable",
                message: "The saved Agent data-folder permission is unavailable. Choose the folder again in Token & Usage.",
                source: nil
            ))
        } else if failures > 0 {
            diagnostics.append(AgentUsageDiagnostic(
                scope: nil,
                severity: .info,
                code: "usage_bookmark_partial",
                message: "Some saved local-data permissions are stale; available authorized folders will still be scanned.",
                source: nil
            ))
        }
        return AgentUsageSecurityScopeLease(accessedURLs: accessed, diagnostics: diagnostics)
    }

    func stop() {
        let urls = accessedURLs
        accessedURLs.removeAll()
        for url in urls { url.stopAccessingSecurityScopedResource() }
    }

    deinit { stop() }
}

// MARK: - Codex provider

private enum AgentUsageCodexWorkMode: Int {
    case lineageRebuild = 0
    case append = 1
    case newFile = 2
    case backfill = 3
}

private struct AgentUsageCodexScanBudget {
    let totalTranscriptBytes: Int64
    let ordinaryBytesPerFile: Int64
    let lineageBytesPerFile: Int64
    let lineageFingerprintBytes: Int64
    let deadline: Date?

    static func make(hasWarmCache: Bool, completePendingBackfill: Bool) -> Self {
        let mebibyte: Int64 = 1_024 * 1_024
        if completePendingBackfill {
            // "Continue" is a resumable pass, never an unbounded whole-disk
            // replay. One pass can still finish the largest current child
            // rollout, then commits its compact cache before another pass.
            return Self(
                totalTranscriptBytes: 1_024 * mebibyte,
                ordinaryBytesPerFile: 128 * mebibyte,
                lineageBytesPerFile: 1_024 * mebibyte,
                lineageFingerprintBytes: 2_048 * mebibyte,
                deadline: Date().addingTimeInterval(60)
            )
        }
        if hasWarmCache {
            return Self(
                totalTranscriptBytes: 80 * mebibyte,
                ordinaryBytesPerFile: 8 * mebibyte,
                lineageBytesPerFile: 64 * mebibyte,
                lineageFingerprintBytes: 1_280 * mebibyte,
                deadline: Date().addingTimeInterval(2)
            )
        }
        return Self(
            totalTranscriptBytes: 320 * mebibyte,
            ordinaryBytesPerFile: 32 * mebibyte,
            lineageBytesPerFile: 192 * mebibyte,
            lineageFingerprintBytes: 1_280 * mebibyte,
            deadline: Date().addingTimeInterval(12)
        )
    }
}

private struct AgentUsageCodexWorkItem {
    let mode: AgentUsageCodexWorkMode
    let thread: AgentUsageCodexThread
    let url: URL
    let fingerprint: AgentUsageValues.FileFingerprint
    let key: String
    let cached: AgentUsageFileCacheEntry?
}

private enum AgentUsageLineAlignmentResult: Equatable {
    case aligned(Int64)
    case insufficientBudget
    case ioFailure
}

private enum AgentUsageLineAlignment {
    static func resolve(in url: URL, proposedOffset: Int64, upperBound: Int64) -> AgentUsageLineAlignmentResult {
        let proposed = max(0, min(proposedOffset, upperBound))
        if proposed == 0 { return .aligned(0) }
        guard proposed < upperBound else { return .insufficientBudget }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            return .ioFailure
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(proposed - 1))
            if try handle.read(upToCount: 1)?.first == 10 { return .aligned(proposed) }
            try handle.seek(toOffset: UInt64(proposed))
            var cursor = proposed
            while cursor < upperBound {
                try Task.checkCancellation()
                let count = Int(min(Int64(64 * 1_024), upperBound - cursor))
                guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                    return .ioFailure
                }
                if let newline = chunk.firstIndex(of: 10) {
                    return .aligned(
                        cursor + Int64(chunk.distance(from: chunk.startIndex, to: newline)) + 1
                    )
                }
                cursor += Int64(chunk.count)
            }
        } catch {
            return .ioFailure
        }
        return .insufficientBudget
    }
}

private final class AgentUsageCodexProvider: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let context: AgentUsageStatisticsContext
    private let progress: @Sendable (AgentUsageScanProgress) -> Void
    private let skillIndex: AgentUsageSkillIndex
    private let completePendingBackfill: Bool

    init(
        context: AgentUsageStatisticsContext,
        skillIndex: AgentUsageSkillIndex,
        progress: @escaping @Sendable (AgentUsageScanProgress) -> Void,
        completePendingBackfill: Bool = false
    ) {
        self.context = context
        self.skillIndex = skillIndex
        self.progress = progress
        self.completePendingBackfill = completePendingBackfill
    }

    func load() -> AgentUsageRuntimeAggregate {
        var aggregate = AgentUsageRuntimeAggregate(scope: .codex)
        progress(AgentUsageScanProgress(
            phase: .readingCodexDatabase,
            current: 0,
            total: 0,
            currentSource: "Codex",
            message: "Reading Codex thread inventory"
        ))

        let databaseURL = codexDatabaseURL()
        let databaseThreads = databaseURL
            .flatMap { AgentUsageSQLiteReader(path: $0.path)?.codexThreads() }
        var threads = databaseThreads ?? fallbackThreads()
        // Preserve the complete read-only inventory for ancestor resolution.
        // The visible detail window is filtered below, but a recent child may
        // point to an older parent whose token fingerprints are still needed.
        let threadInventoryByID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })

        if databaseURL == nil {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: databaseThreads == nil && SandboxPaths.isSandboxed ? .warning : .info,
                code: "codex_state_unavailable",
                message: SandboxPaths.isSandboxed
                    ? "Codex state is not authorized; authorized session transcripts will still be scanned."
                    : "Codex state_5.sqlite was not found; session transcripts will still be scanned.",
                source: nil
            ))
        } else if databaseThreads == nil {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: .warning,
                code: "codex_state_read_failed",
                message: "Codex state_5.sqlite could not be read; session folders were used as a fallback.",
                source: nil
            ))
        }

        let approximateProjects = makeApproximateProjects(threads)
        aggregate.approximateAllTimeProjects = approximateProjects
        aggregate.tasks = makeTasks(threads)

        let oldThreadCount = threads.filter {
            ($0.recencyAt ?? $0.updatedAt ?? $0.createdAt ?? .distantPast) < context.heatmapStart
        }.count
        threads = threads.filter {
            ($0.recencyAt ?? $0.updatedAt ?? $0.createdAt ?? .distantPast) >= context.heatmapStart
        }

        var rejectedPaths = 0
        var uniquePaths = Set<String>()
        threads = threads.filter { thread in
            guard let url = AgentUsagePathPolicy.normalizedRolloutURL(thread.rolloutPath),
                  fileManager.isReadableFile(atPath: url.path),
                  uniquePaths.insert(url.path).inserted else {
                if !thread.rolloutPath.isEmpty { rejectedPaths += 1 }
                return false
            }
            return true
        }
        var excludedByInventoryLimit = 0
        if threads.count > 2_000 {
            excludedByInventoryLimit = threads.count - 2_000
            threads.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            threads.removeSubrange(2_000..<threads.count)
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: .warning,
                code: "codex_backfill_bounded",
                message: "\(excludedByInventoryLimit) Codex sessions exceed the 2,000-session detail inventory limit; aggregate all-time totals still include older history.",
                source: nil
            ))
        }
        threads.sort {
            ($0.recencyAt ?? $0.updatedAt ?? .distantPast)
                > ($1.recencyAt ?? $1.updatedAt ?? .distantPast)
        }

        var cache = AgentUsageFileCacheStore.load(scope: .codex)
        let hasWarmCache = !cache.entries.isEmpty
        let scanBudget = AgentUsageCodexScanBudget.make(
            hasWarmCache: hasWarmCache,
            completePendingBackfill: completePendingBackfill
        )
        var remainingLineageFingerprintBytes = scanBudget.lineageFingerprintBytes
        var lineageFingerprintBudgetReached = false
        var persistedLineageCache = AgentUsageLineageFingerprintCacheStore.load()
        var resolvedLineageThreadIDs = Set<String>()
        var lineageParentByThreadID: [String: String] = [:]
        var fingerprintCacheByThreadID: [String: Set<AgentUsageCounterFingerprint>] = [:]
        var fingerprintFailures = Set<String>()

        func lineageParent(for threadID: String) -> String? {
            if resolvedLineageThreadIDs.contains(threadID) {
                return lineageParentByThreadID[threadID]
            }
            resolvedLineageThreadIDs.insert(threadID)
            guard let thread = threadInventoryByID[threadID],
                  let url = AgentUsagePathPolicy.normalizedRolloutURL(thread.rolloutPath),
                  let metadata = AgentUsageCodexLineageReader.metadata(at: url),
                  let parent = metadata.parentThreadID,
                  !parent.isEmpty,
                  parent != threadID else { return nil }
            lineageParentByThreadID[threadID] = parent
            return parent
        }

        func fingerprints(for threadID: String) -> Set<AgentUsageCounterFingerprint>? {
            if let cached = fingerprintCacheByThreadID[threadID] { return cached }
            if fingerprintFailures.contains(threadID) { return nil }
            guard let thread = threadInventoryByID[threadID],
                  let url = AgentUsagePathPolicy.normalizedRolloutURL(thread.rolloutPath),
                  let sourceFingerprint = AgentUsageValues.fileFingerprint(url) else {
                fingerprintFailures.insert(threadID)
                return nil
            }
            let cacheKey = AgentUsagePrivacy.cacheKey(for: url)
            if let persisted = persistedLineageCache.entries[cacheKey],
               persisted.size == sourceFingerprint.size,
               persisted.modificationTimeNanoseconds == sourceFingerprint.modificationTimeNanoseconds {
                let values = Set(persisted.fingerprints)
                fingerprintCacheByThreadID[threadID] = values
                return values
            }
            guard sourceFingerprint.size <= AgentUsageCodexLineageReader.fingerprintReadLimit,
                  sourceFingerprint.size <= remainingLineageFingerprintBytes else {
                lineageFingerprintBudgetReached = true
                fingerprintFailures.insert(threadID)
                return nil
            }
            remainingLineageFingerprintBytes -= sourceFingerprint.size
            guard let values = AgentUsageCodexLineageReader.tokenFingerprints(at: url) else {
                if AgentUsageResidentMemoryGuard.isOverLimit() {
                    lineageFingerprintBudgetReached = true
                }
                fingerprintFailures.insert(threadID)
                return nil
            }
            fingerprintCacheByThreadID[threadID] = values
            persistedLineageCache.entries[cacheKey] = AgentUsageLineageFingerprintCacheEntry(
                size: sourceFingerprint.size,
                modificationTimeNanoseconds: sourceFingerprint.modificationTimeNanoseconds,
                fingerprints: values.sorted {
                    $0.high == $1.high ? $0.low < $1.low : $0.high < $1.high
                },
                lastAccessedAt: Date()
            )
            _ = AgentUsageLineageFingerprintCacheStore.save(persistedLineageCache)
            return values
        }

        func inheritedFingerprints(for threadID: String) -> Set<AgentUsageCounterFingerprint>? {
            var result = Set<AgentUsageCounterFingerprint>()
            var visited = Set<String>()
            var current = lineageParent(for: threadID)
            while let ancestorID = current, visited.insert(ancestorID).inserted {
                if let ancestor = fingerprints(for: ancestorID) {
                    result.formUnion(ancestor)
                } else {
                    // Archived parent inventories can disappear while their
                    // fork files remain. Other children of that same parent
                    // still contain the inherited prefix and provide a bounded
                    // metadata-only fallback without keeping the bad totals.
                    var siblingFallback: Set<AgentUsageCounterFingerprint>?
                    var siblingCount = 0
                    for siblingID in lineageParentByThreadID.keys.sorted()
                    where siblingID != threadID && lineageParentByThreadID[siblingID] == ancestorID {
                        if let sibling = fingerprints(for: siblingID) {
                            siblingCount += 1
                            if siblingFallback == nil {
                                siblingFallback = sibling
                            } else {
                                siblingFallback?.formIntersection(sibling)
                            }
                        }
                    }
                    guard siblingCount >= 2,
                          let siblingFallback,
                          !siblingFallback.isEmpty else { return nil }
                    result.formUnion(siblingFallback)
                    return result
                }
                current = lineageParent(for: ancestorID)
            }
            return result
        }

        // Version 1 is already exact when every ancestor rollout is still
        // available: it compares the child directly with each real parent.
        // Version 2 only changes the conservative sibling fallback used when
        // an archived parent has disappeared (or is too large to inspect).
        // Keeping these versions separate avoids re-reading gigabytes of
        // already-correct child history when that fallback improves.
        func requiredLineageDedupVersion(for threadID: String) -> Int {
            var visited = Set<String>()
            var current = lineageParent(for: threadID)
            while let ancestorID = current, visited.insert(ancestorID).inserted {
                guard let ancestor = threadInventoryByID[ancestorID],
                      let url = AgentUsagePathPolicy.normalizedRolloutURL(ancestor.rolloutPath),
                      fileManager.isReadableFile(atPath: url.path),
                      let fingerprint = AgentUsageValues.fileFingerprint(url),
                      fingerprint.size <= AgentUsageCodexLineageReader.fingerprintReadLimit else {
                    return AgentUsageCodexLineageReader.dedupVersion
                }
                current = lineageParent(for: ancestorID)
            }
            return AgentUsageCodexLineageReader.directAncestorDedupVersion
        }

        // `session_meta` is the first small record in Codex rollouts. This
        // metadata-only probe is cheap and makes legacy cache migration
        // targeted: root sessions stay cached, only forked children rebuild.
        for thread in threads { _ = lineageParent(for: thread.id) }

        progress(AgentUsageScanProgress(
            phase: .scanningCodexSessions,
            current: 0,
            total: threads.count,
            currentSource: nil,
            message: "Checking Codex detail inventory",
            backfill: AgentUsageBackfillStatus(
                stage: .inventory,
                checkedSessions: 0,
                totalSessions: threads.count,
                excludedByInventoryLimit: excludedByInventoryLimit,
                aggregateOnlyHistorySessions: oldThreadCount
            )
        ))

        let liveKeys = Set(threads.compactMap { thread -> String? in
            guard let url = AgentUsagePathPolicy.normalizedRolloutURL(thread.rolloutPath) else { return nil }
            return AgentUsagePrivacy.cacheKey(for: url)
        })
        var cacheChanged = cache.entries.keys.contains { !liveKeys.contains($0) }
        cache.entries = cache.entries.filter { liveKeys.contains($0.key) }
        let parser = AgentUsageCodexSessionParser(skillIndex: skillIndex)
        var summariesByKey: [String: AgentUsageFileSummary] = [:]
        summariesByKey.reserveCapacity(threads.count)
        var workItems: [AgentUsageCodexWorkItem] = []
        workItems.reserveCapacity(threads.count)
        var partialKeys = Set<String>()
        var failures = 0
        var cacheWriteFailed = false
        var remainingReadBytes = scanBudget.totalTranscriptBytes
        let maximumReadBytesPerFile = scanBudget.ordinaryBytesPerFile
        let maximumLineageReadBytesPerFile = scanBudget.lineageBytesPerFile
        let scanDeadline = scanBudget.deadline

        // Pass 1 is budget-free: every valid cached aggregate is restored before
        // any new IO. A deadline can therefore never make displayed totals drop.
        for (index, thread) in threads.enumerated() {
            if Task.isCancelled { break }
            guard let url = AgentUsagePathPolicy.normalizedRolloutURL(thread.rolloutPath),
                  let fingerprint = AgentUsageValues.fileFingerprint(url) else {
                failures += 1
                continue
            }
            if index == 0 || index == threads.count - 1 || index % 8 == 0 {
                progress(AgentUsageScanProgress(
                    phase: .scanningCodexSessions,
                    current: index + 1,
                    total: threads.count,
                    currentSource: url.lastPathComponent,
                    message: "Checking Codex detail inventory \(index + 1) of \(threads.count)",
                    backfill: AgentUsageBackfillStatus(
                        stage: .restoringCache,
                        checkedSessions: index + 1,
                        totalSessions: threads.count,
                        pendingAtStart: partialKeys.count,
                        remainingSessions: partialKeys.count,
                        excludedByInventoryLimit: excludedByInventoryLimit,
                        aggregateOnlyHistorySessions: oldThreadCount
                    )
                ))
            }
            let key = AgentUsagePrivacy.cacheKey(for: url)
            let cached = cache.entries[key]
            let exactFingerprint = cached?.size == fingerprint.size
                && cached?.modificationTimeNanoseconds == fingerprint.modificationTimeNanoseconds
            let isLineageChild = lineageParentByThreadID[thread.id] != nil
            let requiredDedupVersion = isLineageChild
                ? requiredLineageDedupVersion(for: thread.id)
                : nil
            let requiresLineageRebuild = isLineageChild && (
                cached?.lineageDedupVersion != requiredDedupVersion
                    || (!exactFingerprint && cached != nil && fingerprint.size <= (cached?.size ?? 0))
            )

            if let cached, !requiresLineageRebuild {
                summariesByKey[key] = cached.summary.rehydrated(
                    projectPath: thread.cwd,
                    sessionID: thread.id,
                    skillIndex: skillIndex
                )
                if cached.coverageIncomplete || cached.skippedRelevantRecord { partialKeys.insert(key) }
            } else {
                // Never keep publishing a known pre-fix child aggregate while
                // its one-time lineage rebuild is pending. A partial snapshot
                // is safer than another multi-billion duplicated headline.
                partialKeys.insert(key)
            }

            if requiresLineageRebuild {
                workItems.append(AgentUsageCodexWorkItem(
                    mode: .lineageRebuild,
                    thread: thread,
                    url: url,
                    fingerprint: fingerprint,
                    key: key,
                    cached: cached
                ))
            } else if exactFingerprint {
                if let cached, cached.coverageIncomplete, cached.scannedFromOffset > 0 {
                    workItems.append(AgentUsageCodexWorkItem(
                        mode: .backfill,
                        thread: thread,
                        url: url,
                        fingerprint: fingerprint,
                        key: key,
                        cached: cached
                    ))
                }
            } else {
                let mode: AgentUsageCodexWorkMode
                if let cached, fingerprint.size > cached.size {
                    mode = .append
                } else {
                    mode = .newFile
                }
                workItems.append(AgentUsageCodexWorkItem(
                    mode: mode,
                    thread: thread,
                    url: url,
                    fingerprint: fingerprint,
                    key: key,
                    cached: cached
                ))
                partialKeys.insert(key)
            }
        }

        workItems.sort {
            if $0.mode.rawValue != $1.mode.rawValue { return $0.mode.rawValue < $1.mode.rawValue }
            return ($0.thread.recencyAt ?? $0.thread.updatedAt ?? .distantPast)
                > ($1.thread.recencyAt ?? $1.thread.updatedAt ?? .distantPast)
        }

        // Pass 2 spends a bounded IO budget on append, new, then backfill work.
        // The receipt deliberately separates a checked inventory entry from an
        // entry whose transcript bytes actually advanced during this pass.
        let pendingAtStart = partialKeys.count
        let inventoryFailures = failures
        var attemptedThisRun = 0
        var advancedThisRun = 0
        var completedThisRun = 0
        var stoppedByDeadline = false
        var stoppedByReadBudget = false
        progress(AgentUsageScanProgress(
            phase: .scanningCodexSessions,
            current: 0,
            total: workItems.count,
            currentSource: nil,
            message: workItems.isEmpty ? "Codex detail cache is already complete" : "Starting bounded Codex detail backfill",
            backfill: AgentUsageBackfillStatus(
                stage: .fillingHistory,
                checkedSessions: threads.count,
                totalSessions: threads.count,
                pendingAtStart: pendingAtStart,
                remainingSessions: pendingAtStart,
                excludedByInventoryLimit: excludedByInventoryLimit,
                aggregateOnlyHistorySessions: oldThreadCount
            )
        ))

        workLoop: for (workIndex, item) in workItems.enumerated() {
            if Task.isCancelled { break }
            if let scanDeadline, Date() >= scanDeadline {
                stoppedByDeadline = true
                break
            }
            if remainingReadBytes <= 0 {
                stoppedByReadBudget = true
                break
            }
            progress(AgentUsageScanProgress(
                phase: .scanningCodexSessions,
                current: workIndex + 1,
                total: workItems.count,
                currentSource: item.url.lastPathComponent,
                message: item.mode == .lineageRebuild
                    ? "Reconciling inherited Agent counters \(workIndex + 1) of \(workItems.count)"
                    : "Backfilling Codex detail \(workIndex + 1) of \(workItems.count)",
                backfill: AgentUsageBackfillStatus(
                    stage: .fillingHistory,
                    checkedSessions: threads.count,
                    totalSessions: threads.count,
                    pendingAtStart: pendingAtStart,
                    advancedThisRun: advancedThisRun,
                    completedThisRun: completedThisRun,
                    failedThisRun: failures,
                    remainingSessions: partialKeys.count,
                    excludedByInventoryLimit: excludedByInventoryLimit,
                    aggregateOnlyHistorySessions: oldThreadCount
                )
            ))

            let upperBound: Int64
            let proposedStart: Int64
            switch item.mode {
            case .lineageRebuild:
                guard item.fingerprint.size <= maximumLineageReadBytesPerFile,
                      item.fingerprint.size <= remainingReadBytes else {
                    stoppedByReadBudget = true
                    continue workLoop
                }
                proposedStart = 0
                upperBound = item.fingerprint.size
            case .append:
                guard let cached = item.cached else {
                    failures += 1
                    continue
                }
                let appendBytes = item.fingerprint.size - cached.size
                guard appendBytes > 0,
                      appendBytes <= maximumReadBytesPerFile,
                      appendBytes <= remainingReadBytes else {
                    if appendBytes > remainingReadBytes { stoppedByReadBudget = true }
                    continue workLoop
                }
                proposedStart = cached.size
                upperBound = item.fingerprint.size
            case .backfill:
                guard let cached = item.cached, cached.scannedFromOffset > 0 else {
                    failures += 1
                    continue workLoop
                }
                upperBound = cached.scannedFromOffset
                proposedStart = max(
                    0,
                    upperBound - min(maximumReadBytesPerFile, remainingReadBytes)
                )
            case .newFile:
                let planned = min(item.fingerprint.size, maximumReadBytesPerFile, remainingReadBytes)
                proposedStart = max(0, item.fingerprint.size - planned)
                upperBound = item.fingerprint.size
            }

            let startingOffset: Int64
            switch AgentUsageLineAlignment.resolve(
                in: item.url,
                proposedOffset: proposedStart,
                upperBound: upperBound
            ) {
            case let .aligned(value):
                startingOffset = value
            case .insufficientBudget:
                stoppedByReadBudget = true
                break workLoop
            case .ioFailure:
                failures += 1
                continue workLoop
            }
            let rangeBytes = max(0, upperBound - startingOffset)
            guard rangeBytes > 0 || item.fingerprint.size == 0 else {
                stoppedByReadBudget = true
                break workLoop
            }
            attemptedThisRun += 1
            let inherited: Set<AgentUsageCounterFingerprint>
            if item.mode == .lineageRebuild {
                guard let values = inheritedFingerprints(for: item.thread.id) else {
                    if lineageFingerprintBudgetReached {
                        stoppedByReadBudget = true
                        break workLoop
                    }
                    failures += 1
                    continue workLoop
                }
                inherited = values
            } else {
                inherited = []
            }
            guard let parsed = parser.parse(
                url: item.url,
                source: item.thread,
                startingAtOffset: startingOffset,
                startsAtLineBoundary: true,
                maximumBytes: rangeBytes > 0 ? rangeBytes : nil,
                deadline: scanDeadline,
                allowCompleteTokenScan: completePendingBackfill || item.mode == .lineageRebuild,
                excludingTokenFingerprints: inherited
            ) else {
                failures += 1
                continue workLoop
            }
            remainingReadBytes = max(0, remainingReadBytes - max(1, parsed.bytesRead))
            guard parsed.completedRequestedRange else {
                // Never advance a cursor for a partially-read planned range.
                if AgentUsageResidentMemoryGuard.isOverLimit() {
                    stoppedByReadBudget = true
                    break workLoop
                }
                if scanDeadline.map({ Date() >= $0 }) == true {
                    stoppedByDeadline = true
                    break workLoop
                }
                failures += 1
                continue workLoop
            }

            let parsedDisk = parsed.summary.redactedForDisk()
            let diskSummary: AgentUsageFileSummary
            let coverageIncomplete: Bool
            let skippedRelevantRecord: Bool
            let scannedFromOffset: Int64
            switch item.mode {
            case .lineageRebuild:
                diskSummary = parsedDisk
                coverageIncomplete = false
                skippedRelevantRecord = parsed.skippedRelevantRecord
                scannedFromOffset = 0
            case .append:
                guard let cached = item.cached else {
                    failures += 1
                    continue
                }
                diskSummary = cached.summary.merged(with: parsedDisk)
                coverageIncomplete = cached.coverageIncomplete
                skippedRelevantRecord = cached.skippedRelevantRecord || parsed.skippedRelevantRecord
                scannedFromOffset = cached.scannedFromOffset
            case .backfill:
                guard let cached = item.cached else {
                    failures += 1
                    continue
                }
                diskSummary = cached.summary.merged(with: parsedDisk)
                coverageIncomplete = startingOffset > 0
                skippedRelevantRecord = cached.skippedRelevantRecord || parsed.skippedRelevantRecord
                scannedFromOffset = startingOffset
            case .newFile:
                diskSummary = parsedDisk
                coverageIncomplete = startingOffset > 0
                skippedRelevantRecord = parsed.skippedRelevantRecord
                scannedFromOffset = startingOffset
            }

            let entry = AgentUsageFileCacheEntry(
                size: item.fingerprint.size,
                modificationTimeNanoseconds: item.fingerprint.modificationTimeNanoseconds,
                coverageIncomplete: coverageIncomplete,
                skippedRelevantRecord: skippedRelevantRecord,
                scannedFromOffset: scannedFromOffset,
                summary: diskSummary,
                lineageDedupVersion: item.mode == .lineageRebuild
                    ? requiredLineageDedupVersion(for: item.thread.id)
                    : item.cached?.lineageDedupVersion
            )
            cache.entries[item.key] = entry
            cacheChanged = true
            advancedThisRun += 1
            summariesByKey[item.key] = diskSummary.rehydrated(
                projectPath: item.thread.cwd,
                sessionID: item.thread.id,
                skillIndex: skillIndex
            )
            if coverageIncomplete || skippedRelevantRecord {
                partialKeys.insert(item.key)
            } else {
                partialKeys.remove(item.key)
                completedThisRun += 1
            }
        }

        let ioFailures = max(0, failures - inventoryFailures)
        let failedThisRun = failures
        let skippedThisRun = AgentUsageBackfillOutcomePolicy.skippedCount(
            attemptedThisRun: attemptedThisRun,
            advancedThisRun: advancedThisRun,
            failedThisRun: ioFailures
        )
        let endReason = AgentUsageBackfillOutcomePolicy.resolve(
            remainingSessions: partialKeys.count,
            excludedByInventoryLimit: excludedByInventoryLimit,
            cancelled: Task.isCancelled,
            stoppedByDeadline: stoppedByDeadline,
            stoppedByReadBudget: stoppedByReadBudget,
            failedThisRun: failedThisRun
        )
        let finalBackfillStatus = AgentUsageBackfillStatus(
            stage: Task.isCancelled ? .paused : .completed,
            checkedSessions: threads.count,
            totalSessions: threads.count,
            pendingAtStart: pendingAtStart,
            advancedThisRun: advancedThisRun,
            completedThisRun: completedThisRun,
            skippedThisRun: skippedThisRun,
            failedThisRun: failedThisRun,
            remainingSessions: partialKeys.count,
            excludedByInventoryLimit: excludedByInventoryLimit,
            aggregateOnlyHistorySessions: oldThreadCount,
            endReason: endReason,
            completedAt: Date()
        )
        aggregate.backfillStatus = finalBackfillStatus
        progress(AgentUsageScanProgress(
            phase: .scanningCodexSessions,
            current: workItems.count,
            total: workItems.count,
            currentSource: nil,
            message: "Codex detail pass finished",
            backfill: finalBackfillStatus
        ))

        let summaries = threads.compactMap { thread -> AgentUsageFileSummary? in
            guard let url = AgentUsagePathPolicy.normalizedRolloutURL(thread.rolloutPath) else { return nil }
            return summariesByKey[AgentUsagePrivacy.cacheKey(for: url)]
        }
        let cappedFiles = partialKeys.count

        if cacheChanged, !AgentUsageFileCacheStore.save(cache, scope: .codex) {
            cacheWriteFailed = true
        }
        if cacheWriteFailed {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: .warning,
                code: "codex_cache_write_failed",
                message: "Codex usage cache could not be saved; the next refresh may be slower.",
                source: nil
            ))
        }

        if oldThreadCount > 0 {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: .info,
                code: "codex_old_history_aggregated",
                message: "\(oldThreadCount) older Codex threads use the bounded SQLite all-time aggregate instead of transcript replay.",
                source: nil
            ))
        }
        if cappedFiles > 0 {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: .warning,
                code: "codex_scan_bounded",
                message: "\(cappedFiles) Codex sessions still need local detail backfill after this pass; \(advancedThisRun) advanced and \(completedThisRun) became complete.",
                source: nil
            ))
        }

        for summary in summaries {
            if Task.isCancelled { break }
            aggregate.parsedFileCount += 1
            aggregate.events.append(contentsOf: summary.events)
            aggregate.tokenEventCount += summary.events.count
            for (name, count) in summary.toolCalls {
                aggregate.toolCalls[name, default: 0] += count
            }
            aggregate.skillEvents.append(contentsOf: summary.skillEvents)
        }

        let detailedTotal = totalTokens(aggregate.events)
        let approximateTotal = approximateProjects.reduce(Int64(0)) {
            AgentUsageMath.saturatingAdd($0, $1.tokens.total)
        }
        if AgentUsageDetailedSanity.isSuspicious(detailed: detailedTotal.total, approximate: approximateTotal) {
            aggregate.events.removeAll()
            aggregate.tokenEventCount = 0
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: .warning,
                code: "codex_detailed_usage_rejected",
                message: "Detailed Codex counters were inconsistent with the thread inventory, so conservative thread totals are shown.",
                source: nil
            ))
        }

        aggregate.available = databaseURL != nil || !threads.isEmpty || !aggregate.tasks.isEmpty
        if !aggregate.events.isEmpty, !approximateProjects.isEmpty {
            aggregate.sourceQuality = .mixed
        } else if !aggregate.events.isEmpty {
            aggregate.sourceQuality = .detailed
        } else if !approximateProjects.isEmpty {
            aggregate.sourceQuality = .approximate
        }
        if rejectedPaths > 0 {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: .warning,
                code: "codex_rollout_rejected",
                message: "\(rejectedPaths) Codex session paths were unavailable, outside the authorized root, or duplicated.",
                source: nil
            ))
        }
        if failures > 0 {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: .warning,
                code: "codex_session_parse_partial",
                message: "\(failures) Codex session files could not be parsed.",
                source: nil
            ))
        }
        if databaseURL == nil && threads.isEmpty {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: .info,
                code: "codex_sources_missing",
                message: "No readable Codex local usage sources were found.",
                source: "~/.codex"
            ))
        }
        progress(AgentUsageScanProgress(
            phase: .scanningCodexSessions,
            current: threads.count,
            total: threads.count,
            currentSource: nil,
            message: "Codex session scan complete"
        ))
        return aggregate
    }

    private func codexDatabaseURL() -> URL? {
        let candidates = [
            AgentUsagePathPolicy.codexRoot.appendingPathComponent("state_5.sqlite"),
            AgentUsagePathPolicy.codexRoot.appendingPathComponent("sqlite/state_5.sqlite")
        ]
        return candidates.first { candidate in
            let normalized = candidate.standardizedFileURL.resolvingSymlinksInPath()
            return AgentUsagePathPolicy.isContained(normalized, in: AgentUsagePathPolicy.codexRoot)
                && fileManager.isReadableFile(atPath: normalized.path)
        }
    }

    private func fallbackThreads() -> [AgentUsageCodexThread] {
        let roots = ["sessions", "archived_sessions"].map {
            AgentUsagePathPolicy.codexRoot.appendingPathComponent($0, isDirectory: true)
        }
        var files: [URL] = []
        var visited = 0
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                visited += 1
                if visited > 50_000 || files.count >= 2_000 {
                    enumerator.skipDescendants()
                    break
                }
                guard let normalized = AgentUsagePathPolicy.normalizedRolloutURL(url.path) else { continue }
                files.append(normalized)
            }
        }
        return files.map { url in
            let modified = AgentUsageValues.fileModificationDate(url)
            return AgentUsageCodexThread(
                id: AgentUsagePrivacy.digest(url.path),
                rolloutPath: url.path,
                createdAt: modified,
                updatedAt: modified,
                recencyAt: modified,
                archivedAt: nil,
                cwd: "",
                tokens: 0,
                archived: url.path.contains("/archived_sessions/"),
                model: nil,
                title: nil
            )
        }
    }

    private func makeApproximateProjects(_ threads: [AgentUsageCodexThread]) -> [AgentUsageProjectUsage] {
        struct Accumulator {
            var tokens: Int64 = 0
            var sessions = Set<String>()
            var lastActive: Date?
        }
        var grouped: [String: Accumulator] = [:]
        for thread in threads where !thread.cwd.isEmpty && thread.tokens > 0 {
            var value = grouped[thread.cwd, default: Accumulator()]
            value.tokens = AgentUsageMath.saturatingAdd(value.tokens, thread.tokens)
            value.sessions.insert(thread.id)
            let active = thread.recencyAt ?? thread.updatedAt
            if let active, value.lastActive == nil || active > value.lastActive! { value.lastActive = active }
            grouped[thread.cwd] = value
        }
        return grouped.map { path, value in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return AgentUsageProjectUsage(
                id: "codex:" + AgentUsagePrivacy.digest(path),
                name: name.isEmpty ? "Codex project" : name,
                fullPath: path,
                tokens: AgentUsageTokenTotals(input: 0, cached: 0, output: 0, reasoning: 0, total: value.tokens),
                estimatedAPIValueUSD: 0,
                sessionCount: value.sessions.count,
                lastActiveAt: value.lastActive,
                sourceQuality: .approximate
            )
        }.sorted { $0.tokens.total > $1.tokens.total }
    }

    private func makeTasks(_ threads: [AgentUsageCodexThread]) -> [AgentUsageTaskItem] {
        let activeCutoff = context.now.addingTimeInterval(-30 * 60)
        return threads.compactMap { thread in
            let updated = thread.recencyAt ?? thread.updatedAt ?? thread.createdAt
            let category: AgentUsageTaskCategory?
            if thread.archived {
                category = updated.map { $0 >= context.todayStart } == true ? .done : nil
            } else if updated.map({ $0 >= activeCutoff }) == true {
                category = .active
            } else if updated.map({ $0 >= context.todayStart }) == true {
                category = .pending
            } else {
                category = nil
            }
            guard let category else { return nil }
            let projectName = thread.cwd.isEmpty ? nil : URL(fileURLWithPath: thread.cwd).lastPathComponent
            return AgentUsageTaskItem(
                id: "codex-" + AgentUsagePrivacy.digest(thread.id),
                scope: .codex,
                category: category,
                title: "Codex task",
                project: projectName,
                updatedAt: updated,
                tokens: thread.tokens > 0 ? thread.tokens : nil
            )
        }
    }

    private func totalTokens(_ events: [AgentUsageEvent]) -> AgentUsageTokenTotals {
        events.reduce(into: .zero) { $0.add($1.tokens) }
    }
}

// MARK: - OpenCode / MiniMax provider family

/// OpenCode and the MiniMax host can mirror the same turn counters into two
/// local databases. MiniMax rows carry the OpenCode message id in `turn_id`,
/// so this provider family normalizes both stores and counts every turn once.
private final class AgentUsageOpenCodeProvider: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let progress: @Sendable (AgentUsageScanProgress) -> Void

    init(progress: @escaping @Sendable (AgentUsageScanProgress) -> Void) {
        self.progress = progress
    }

    func load() -> AgentUsageRuntimeAggregate {
        var aggregate = AgentUsageRuntimeAggregate(scope: .openCode)
        let openCodeDatabase = AgentUsagePathPolicy.openCodeRoot.appendingPathComponent("opencode.db")
        let miniMaxDatabase = AgentUsagePathPolicy.miniMaxRoot.appendingPathComponent("sqlite.db")
        let openCodeReadable = isReadableDatabase(openCodeDatabase, inside: AgentUsagePathPolicy.openCodeRoot)
        let miniMaxReadable = isReadableDatabase(miniMaxDatabase, inside: AgentUsagePathPolicy.miniMaxRoot)
        let sourceCount = (openCodeReadable ? 1 : 0) + (miniMaxReadable ? 1 : 0)
        aggregate.available = sourceCount > 0

        progress(AgentUsageScanProgress(
            phase: .readingOpenCodeDatabase,
            current: 0,
            total: sourceCount,
            currentSource: nil,
            message: "Reading trusted OpenCode / MiniMax token records"
        ))

        var seenCanonicalIDs = Set<String>()
        var invalidRows = 0
        var mirroredRows = 0
        var readFailures = 0
        var completedSources = 0

        // Prefer MiniMax-hosted rows when both stores contain the same turn:
        // they retain the same native counters plus host/workspace metadata.
        if miniMaxReadable {
            if let rows = AgentUsageSQLiteReader(path: miniMaxDatabase.path)?.miniMaxTokenRows() {
                aggregate.parsedFileCount += 1
                for row in rows {
                    let reportedTotal = miniMaxReportedTotal(row.raw)
                    if AgentUsageExplicitTokenNormalizer.isZeroUsage(
                        input: row.input,
                        cacheRead: row.cacheRead,
                        cacheWrite: row.cacheWrite,
                        output: row.output,
                        reasoning: row.reasoning,
                        reportedTotal: reportedTotal
                    ) {
                        continue
                    }
                    guard let date = row.createdAt,
                          let totals = AgentUsageExplicitTokenNormalizer.totals(
                            input: row.input,
                            cacheRead: row.cacheRead,
                            cacheWrite: row.cacheWrite,
                            output: row.output,
                            reasoning: row.reasoning,
                            reportedTotal: reportedTotal
                          ) else {
                        invalidRows += 1
                        continue
                    }
                    let canonicalID = row.turnID ?? "minimax:\(row.usageID)"
                    guard seenCanonicalIDs.insert(canonicalID).inserted else {
                        mirroredRows += 1
                        continue
                    }
                    let resolvedCost = AgentUsagePricingCatalog.resolvedCost(
                        scope: .openCode,
                        model: row.model,
                        date: date,
                        tokens: totals,
                        explicitCostUSD: row.costUSD,
                        cacheReadTokens: row.cacheRead,
                        cacheWriteTokens: row.cacheWrite
                    )
                    aggregate.events.append(AgentUsageEvent(
                        id: AgentUsagePrivacy.digest("opencode-family:" + canonicalID),
                        date: date,
                        tokens: totals,
                        estimatedCostUSD: resolvedCost.0,
                        priceKnown: resolvedCost.1,
                        model: row.model,
                        projectPath: row.directory,
                        sessionID: row.sessionID
                    ))
                }
            } else {
                readFailures += 1
            }
            completedSources += 1
            progress(AgentUsageScanProgress(
                phase: .readingOpenCodeDatabase,
                current: completedSources,
                total: sourceCount,
                currentSource: "MiniMax",
                message: "Read MiniMax-hosted OpenCode token records"
            ))
        }

        if openCodeReadable {
            if let rows = AgentUsageSQLiteReader(path: openCodeDatabase.path)?.openCodeMessages() {
                aggregate.parsedFileCount += 1
                for row in rows {
                    guard let data = row.data.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        invalidRows += 1
                        continue
                    }
                    guard AgentUsageValues.string(object["role"]) == "assistant",
                          let tokenObject = object["tokens"] as? [String: Any] else { continue }
                    guard let cacheObject = tokenObject["cache"] as? [String: Any] else {
                        invalidRows += 1
                        continue
                    }
                    let input = AgentUsageValues.int64(tokenObject["input"]) ?? 0
                    let cacheRead = AgentUsageValues.int64(cacheObject["read"]) ?? 0
                    let cacheWrite = AgentUsageValues.int64(cacheObject["write"]) ?? 0
                    let output = AgentUsageValues.int64(tokenObject["output"]) ?? 0
                    let reasoning = AgentUsageValues.int64(tokenObject["reasoning"]) ?? 0
                    let reportedTotal = AgentUsageValues.int64(tokenObject["total"])
                    if AgentUsageExplicitTokenNormalizer.isZeroUsage(
                        input: input,
                        cacheRead: cacheRead,
                        cacheWrite: cacheWrite,
                        output: output,
                        reasoning: reasoning,
                        reportedTotal: reportedTotal
                    ) {
                        continue
                    }
                    guard let date = row.createdAt,
                          let totals = AgentUsageExplicitTokenNormalizer.totals(
                            input: input,
                            cacheRead: cacheRead,
                            cacheWrite: cacheWrite,
                            output: output,
                            reasoning: reasoning,
                            reportedTotal: reportedTotal
                          ) else {
                        invalidRows += 1
                        continue
                    }
                    guard seenCanonicalIDs.insert(row.id).inserted else {
                        mirroredRows += 1
                        continue
                    }
                    let costValue = AgentUsageValues.double(object["cost"])
                    let model = AgentUsageValues.string(object["modelID"])
                        ?? AgentUsageValues.string(object["model"])
                    let resolvedCost = AgentUsagePricingCatalog.resolvedCost(
                        scope: .openCode,
                        model: model,
                        date: date,
                        tokens: totals,
                        explicitCostUSD: costValue,
                        cacheReadTokens: cacheRead,
                        cacheWriteTokens: cacheWrite
                    )
                    aggregate.events.append(AgentUsageEvent(
                        id: AgentUsagePrivacy.digest("opencode-family:" + row.id),
                        date: date,
                        tokens: totals,
                        estimatedCostUSD: resolvedCost.0,
                        priceKnown: resolvedCost.1,
                        model: model,
                        projectPath: row.directory,
                        sessionID: row.sessionID
                    ))
                }
            } else {
                readFailures += 1
            }
            completedSources += 1
            progress(AgentUsageScanProgress(
                phase: .readingOpenCodeDatabase,
                current: completedSources,
                total: sourceCount,
                currentSource: "OpenCode",
                message: "Read standalone OpenCode token records"
            ))
        }

        aggregate.tokenEventCount = aggregate.events.count
        aggregate.sourceQuality = aggregate.events.isEmpty ? .unavailable : .detailed
        if !aggregate.available {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .openCode,
                severity: .info,
                code: "opencode_sources_missing",
                message: "No readable OpenCode or MiniMax token database was found.",
                source: nil
            ))
        } else if aggregate.events.isEmpty {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .openCode,
                severity: .info,
                code: "opencode_usage_empty",
                message: "OpenCode / MiniMax databases were found, but they contain no nonzero native token records.",
                source: nil
            ))
        }
        if mirroredRows > 0 {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .openCode,
                severity: .info,
                code: "opencode_mirror_deduplicated",
                message: "\(mirroredRows) MiniMax-hosted OpenCode turns were mirrored across local databases and counted once.",
                source: nil
            ))
        }
        if invalidRows > 0 {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .openCode,
                severity: .warning,
                code: "opencode_usage_inconsistent",
                message: "\(invalidRows) OpenCode / MiniMax token rows failed the native total consistency check and were skipped.",
                source: nil
            ))
        }
        if readFailures > 0 {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .openCode,
                severity: .warning,
                code: "opencode_database_read_failed",
                message: "\(readFailures) OpenCode / MiniMax token databases could not be read.",
                source: nil
            ))
        }
        return aggregate
    }

    private func isReadableDatabase(_ url: URL, inside root: URL) -> Bool {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        return AgentUsagePathPolicy.isContained(normalized, in: root)
            && fileManager.isReadableFile(atPath: normalized.path)
    }

    private func miniMaxReportedTotal(_ raw: String?) -> Int64? {
        guard let raw, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return AgentUsageValues.int64(object["total"])
    }
}

// MARK: - OpenClaw / QClaw provider family

private final class AgentUsageOpenClawProvider: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let progress: @Sendable (AgentUsageScanProgress) -> Void
    private let dateParser = AgentUsageDateParser()

    init(progress: @escaping @Sendable (AgentUsageScanProgress) -> Void) {
        self.progress = progress
    }

    func load() -> AgentUsageRuntimeAggregate {
        var aggregate = AgentUsageRuntimeAggregate(scope: .openClaw)
        let files = transcriptFiles()
        aggregate.available = !files.isEmpty
        progress(AgentUsageScanProgress(
            phase: .scanningOpenClawSessions,
            current: 0,
            total: files.count,
            currentSource: nil,
            message: "Scanning native OpenClaw / QClaw usage records"
        ))

        var seenEventIDs = Set<String>()
        var invalidRows = 0
        var duplicateRows = 0
        var parseFailures = 0

        for (index, file) in files.enumerated() {
            if Task.isCancelled { break }
            if index == 0 || index == files.count - 1 || index % 8 == 0 {
                progress(AgentUsageScanProgress(
                    phase: .scanningOpenClawSessions,
                    current: index,
                    total: files.count,
                    currentSource: file.lastPathComponent,
                    message: "Reading OpenClaw / QClaw session \(index + 1) of \(files.count)"
                ))
            }
            var sessionID = file.deletingPathExtension().lastPathComponent
            var projectPath = ""
            var localEvents: [AgentUsageEvent] = []
            do {
                let stats = try AgentUsageJSONStream.forEachLine(
                    at: file,
                    maximumLineBytes: 8 * 1_024 * 1_024
                ) { line in
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let type = AgentUsageValues.string(object["type"]) else { return }
                    if type == "session" {
                        if let value = AgentUsageValues.string(object["id"]) { sessionID = value }
                        if let value = AgentUsageValues.string(object["cwd"]) { projectPath = value }
                        return
                    }
                    guard type == "message",
                          let message = object["message"] as? [String: Any],
                          AgentUsageValues.string(message["role"]) == "assistant",
                          let usage = message["usage"] as? [String: Any] else { return }
                    let input = AgentUsageValues.int64(usage["input"]) ?? 0
                    let cacheRead = AgentUsageValues.int64(usage["cacheRead"]) ?? 0
                    let cacheWrite = AgentUsageValues.int64(usage["cacheWrite"]) ?? 0
                    let output = AgentUsageValues.int64(usage["output"]) ?? 0
                    let reasoning = AgentUsageValues.int64(usage["reasoning"]) ?? 0
                    let reportedTotal = AgentUsageValues.int64(usage["totalTokens"])
                    if AgentUsageExplicitTokenNormalizer.isZeroUsage(
                        input: input,
                        cacheRead: cacheRead,
                        cacheWrite: cacheWrite,
                        output: output,
                        reasoning: reasoning,
                        reportedTotal: reportedTotal
                    ) {
                        return
                    }
                    guard let rawEventID = AgentUsageValues.string(object["id"]),
                          let date = dateParser.date(object["timestamp"])
                            ?? dateParser.date(message["timestamp"]),
                          let totals = AgentUsageExplicitTokenNormalizer.totals(
                            input: input,
                            cacheRead: cacheRead,
                            cacheWrite: cacheWrite,
                            output: output,
                            reasoning: reasoning,
                            reportedTotal: reportedTotal
                          ) else {
                        invalidRows += 1
                        return
                    }
                    guard seenEventIDs.insert(rawEventID).inserted else {
                        duplicateRows += 1
                        return
                    }
                    let costValue = (usage["cost"] as? [String: Any])
                        .flatMap { AgentUsageValues.double($0["total"]) }
                    let model = AgentUsageValues.string(message["model"])
                    let resolvedCost = AgentUsagePricingCatalog.resolvedCost(
                        scope: .openClaw,
                        model: model,
                        date: date,
                        tokens: totals,
                        explicitCostUSD: costValue,
                        cacheReadTokens: cacheRead,
                        cacheWriteTokens: cacheWrite
                    )
                    localEvents.append(AgentUsageEvent(
                        id: AgentUsagePrivacy.digest("openclaw-family:" + rawEventID),
                        date: date,
                        tokens: totals,
                        estimatedCostUSD: resolvedCost.0,
                        priceKnown: resolvedCost.1,
                        model: model,
                        projectPath: projectPath,
                        sessionID: sessionID
                    ))
                }
                if stats.oversizedRelevantLineCount > 0 {
                    invalidRows += stats.oversizedRelevantLineCount
                }
                // Rehydrate after the full pass so session metadata remains
                // correct even if it appears after an assistant record.
                aggregate.events.append(contentsOf: localEvents.map { event in
                    AgentUsageEvent(
                        id: event.id,
                        date: event.date,
                        tokens: event.tokens,
                        estimatedCostUSD: event.estimatedCostUSD,
                        priceKnown: event.priceKnown,
                        model: event.model,
                        projectPath: projectPath,
                        sessionID: sessionID
                    )
                })
                aggregate.parsedFileCount += 1
            } catch {
                parseFailures += 1
            }
        }

        aggregate.tokenEventCount = aggregate.events.count
        aggregate.sourceQuality = aggregate.events.isEmpty ? .unavailable : .detailed
        if files.isEmpty {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .openClaw,
                severity: .info,
                code: "openclaw_sessions_missing",
                message: "No readable OpenClaw / QClaw native session usage files were found.",
                source: nil
            ))
        } else if aggregate.events.isEmpty {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .openClaw,
                severity: .info,
                code: "openclaw_usage_empty",
                message: "OpenClaw / QClaw sessions were found, but no nonzero native message.usage records were available.",
                source: nil
            ))
        }
        if duplicateRows > 0 {
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .openClaw,
                severity: .info,
                code: "openclaw_events_deduplicated",
                message: "\(duplicateRows) mirrored OpenClaw / QClaw usage events were counted once by native event id.",
                source: nil
            ))
        }
        if invalidRows > 0 {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .openClaw,
                severity: .warning,
                code: "openclaw_usage_inconsistent",
                message: "\(invalidRows) OpenClaw / QClaw usage rows lacked a stable id/time or failed the native total consistency check.",
                source: nil
            ))
        }
        if parseFailures > 0 {
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .openClaw,
                severity: .warning,
                code: "openclaw_session_parse_partial",
                message: "\(parseFailures) OpenClaw / QClaw session files could not be parsed.",
                source: nil
            ))
        }
        progress(AgentUsageScanProgress(
            phase: .scanningOpenClawSessions,
            current: files.count,
            total: files.count,
            currentSource: nil,
            message: "OpenClaw / QClaw native usage scan complete"
        ))
        return aggregate
    }

    private func transcriptFiles() -> [URL] {
        var result: [URL] = []
        for root in [AgentUsagePathPolicy.qClawRoot, AgentUsagePathPolicy.openClawRoot] {
            let agentsRoot = root.appendingPathComponent("agents", isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: agentsRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            ) else { continue }
            var visited = 0
            for case let url as URL in enumerator {
                visited += 1
                if visited > 50_000 || result.count >= 2_000 {
                    enumerator.skipDescendants()
                    break
                }
                guard let normalized = AgentUsagePathPolicy.normalizedOpenClawTranscriptURL(url) else { continue }
                result.append(normalized)
            }
        }
        return Array(Set(result.map(\.path)))
            .map(URL.init(fileURLWithPath:))
            .sorted { $0.path < $1.path }
    }
}

// MARK: - Snapshot aggregation

private struct AgentUsageProviderBundle: Sendable {
    let codex: AgentUsageRuntimeAggregate
    let claude: AgentUsageRuntimeAggregate
    let openCode: AgentUsageRuntimeAggregate
    let openClaw: AgentUsageRuntimeAggregate
}

private struct AgentUsageInsightsLoadPayload: Sendable {
    let snapshots: [AgentUsageScope: AgentUsageSnapshot]
    let backfillStatus: AgentUsageBackfillStatus?
}

private struct AgentUsageInsightsLoader: Sendable {
    let context: AgentUsageStatisticsContext
    let progress: @Sendable (AgentUsageScanProgress) -> Void
    let completePendingBackfill: Bool

    init(
        timeZoneMode: AgentUsageTimeZoneMode,
        now: Date,
        progress: @escaping @Sendable (AgentUsageScanProgress) -> Void,
        completePendingBackfill: Bool = false
    ) {
        context = AgentUsageStatisticsContext(mode: timeZoneMode, now: now)
        self.progress = progress
        self.completePendingBackfill = completePendingBackfill
    }

    func load() async -> Result<AgentUsageInsightsLoadPayload, AgentUsageLoaderError> {
        let lease = AgentUsageSecurityScopeLease.acquire()
        defer { lease.stop() }
        let skillIndex = AgentUsageSkillIndex.shared
        // Provider parsers are intentionally serialized. Running four local
        // history readers at once multiplies transient Foundation allocations
        // and disk pressure without making a cached refresh meaningfully faster.
        let worker = Task.detached(priority: .utility) {
            let codex = AgentUsageCodexProvider(
                    context: context,
                    skillIndex: skillIndex,
                    progress: progress,
                    completePendingBackfill: completePendingBackfill
                ).load()
            let claude = AgentUsageClaudeProvider(
                    context: context,
                    skillIndex: skillIndex,
                    progress: progress
                ).load()
            let openCode = AgentUsageOpenCodeProvider(progress: progress).load()
            let openClaw = AgentUsageOpenClawProvider(progress: progress).load()
            return AgentUsageProviderBundle(
                codex: codex,
                claude: claude,
                openCode: openCode,
                openClaw: openClaw
            )
        }
        let providers = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        var codex = providers.codex
        var claude = providers.claude
        var openCode = providers.openCode
        var openClaw = providers.openClaw

        if Task.isCancelled {
            return .failure(.unexpected("Local usage scan was cancelled."))
        }
        if !lease.diagnostics.isEmpty {
            codex.diagnostics.append(contentsOf: lease.diagnostics)
            claude.diagnostics.append(contentsOf: lease.diagnostics)
            openCode.diagnostics.append(contentsOf: lease.diagnostics)
            openClaw.diagnostics.append(contentsOf: lease.diagnostics)
            codex.partial = true
            claude.partial = true
            openCode.partial = true
            openClaw.partial = true
        }
        progress(AgentUsageScanProgress(
            phase: .aggregating,
            current: 0,
            total: 5,
            currentSource: nil,
            message: "Aggregating local usage metrics"
        ))

        if !codex.available && !claude.available && !openCode.available && !openClaw.available
            && lease.diagnostics.isEmpty {
            return .failure(.noLocalSources)
        }
        let builder = AgentUsageSnapshotBuilder(context: context, skillIndex: skillIndex)
        let codexSnapshot = builder.build(scope: .codex, providers: [codex])
        progress(AgentUsageScanProgress(
            phase: .aggregating,
            current: 1,
            total: 5,
            currentSource: "Codex",
            message: "Aggregated Codex usage"
        ))
        let claudeSnapshot = builder.build(scope: .claude, providers: [claude])
        progress(AgentUsageScanProgress(
            phase: .aggregating,
            current: 2,
            total: 5,
            currentSource: "Claude Code",
            message: "Aggregated Claude Code usage"
        ))
        let openCodeSnapshot = builder.build(scope: .openCode, providers: [openCode])
        progress(AgentUsageScanProgress(
            phase: .aggregating,
            current: 3,
            total: 5,
            currentSource: "OpenCode / MiniMax",
            message: "Aggregated OpenCode / MiniMax usage"
        ))
        let openClawSnapshot = builder.build(scope: .openClaw, providers: [openClaw])
        progress(AgentUsageScanProgress(
            phase: .aggregating,
            current: 4,
            total: 5,
            currentSource: "OpenClaw / QClaw",
            message: "Aggregated OpenClaw / QClaw usage"
        ))
        let combinedSnapshot = builder.build(scope: .combined, providers: [codex, claude, openCode, openClaw])
        return .success(AgentUsageInsightsLoadPayload(
            snapshots: [
                .codex: codexSnapshot,
                .claude: claudeSnapshot,
                .openCode: openCodeSnapshot,
                .openClaw: openClawSnapshot,
                .combined: combinedSnapshot
            ],
            backfillStatus: codex.backfillStatus
        ))
    }
}

private struct AgentUsageSnapshotBuilder {
    let context: AgentUsageStatisticsContext
    let skillIndex: AgentUsageSkillIndex

    func build(scope: AgentUsageScope, providers: [AgentUsageRuntimeAggregate]) -> AgentUsageSnapshot {
        let events = providers.flatMap(\.events).filter { $0.date <= context.now.addingTimeInterval(5 * 60) }
        let todayEvents = events.filter { $0.date >= context.todayStart }
        let sevenDayEvents = events.filter { $0.date >= context.sevenDayStart }
        let monthEvents = events.filter { $0.date >= context.monthStart }
        let previousEvents = events.filter { $0.date >= context.previousSevenDayStart && $0.date < context.sevenDayStart }
        let today = totals(todayEvents)
        let last7Days = totals(sevenDayEvents)
        let currentMonth = totals(monthEvents)
        let allTimeReconciliation = Self.reconcileAllTime(
            providers: providers,
            through: context.now.addingTimeInterval(5 * 60)
        )
        let allTime = allTimeReconciliation.reported
        let allTimeDetailed = allTimeReconciliation.detailed
        let previous = totals(previousEvents)

        let quality = sourceQuality(providers)
        let diagnostics = deduplicatedDiagnostics(providers.flatMap(\.diagnostics))
        let daily = makeDailyBuckets(events: events, quality: quality)
        let heatmap = makeHeatmap(events: events)
        let comparison = AgentUsagePeriodComparison(
            current: last7Days,
            previous: previous,
            changePercent: previous.total > 0
                ? (Double(last7Days.total - previous.total) / Double(previous.total)) * 100
                : nil,
            isNewActivity: previous.total == 0 && last7Days.total > 0
        )

        return AgentUsageSnapshot(
            scope: scope,
            generatedAt: context.now,
            timeZoneIdentifier: context.timeZone.identifier,
            sourceQuality: quality,
            isPartial: providers.contains(where: \.partial),
            today: today,
            last7Days: last7Days,
            currentMonth: currentMonth,
            allTime: allTime,
            allTimeDetailed: allTimeDetailed,
            estimatedAPIValueUSD: AgentUsageValueEstimate(
                todayUSD: cost(todayEvents),
                last7DaysUSD: cost(sevenDayEvents),
                currentMonthUSD: cost(monthEvents),
                allTimeUSD: cost(events),
                isEstimate: true,
                unknownModels: Array(Set(events.filter { !$0.priceKnown }.map { $0.model ?? "Unknown model" })).sorted()
            ),
            dailyBuckets: daily,
            weekdayHourHeatmap: heatmap,
            heatmapThresholds: heatmapThresholds(heatmap),
            previous7DayComparison: comparison,
            projectRankings7Days: projectRankings(providers: providers, since: context.sevenDayStart, approximateFallback: false),
            projectRankingsAllTime: projectRankings(providers: providers, since: nil, approximateFallback: true),
            modelRankings: modelRankings(providers),
            recentSessions: recentSessions(providers),
            sourceSummaries: sourceSummaries(providers),
            topTools: topTools(providers),
            topSkills: topSkills(providers),
            tasks: taskBoard(providers.flatMap(\.tasks)),
            diagnostics: diagnostics,
            parsedFileCount: providers.reduce(0) { $0 + $1.parsedFileCount },
            tokenEventCount: providers.reduce(0) { $0 + $1.tokenEventCount }
        )
    }

    private func totals(_ events: [AgentUsageEvent]) -> AgentUsageTokenTotals {
        events.reduce(into: .zero) { $0.add($1.tokens) }
    }

    fileprivate static func reconcileAllTime(
        providers: [AgentUsageRuntimeAggregate],
        through cutoff: Date
    ) -> (reported: AgentUsageTokenTotals, detailed: AgentUsageTokenTotals) {
        var reported = AgentUsageTokenTotals.zero
        var detailed = AgentUsageTokenTotals.zero
        for provider in providers {
            let providerDetailed = provider.events
                .filter { $0.date <= cutoff }
                .reduce(into: AgentUsageTokenTotals.zero) { $0.add($1.tokens) }
            detailed.add(providerDetailed)

            var providerReported = providerDetailed
            let aggregateOnlyTotal = provider.approximateAllTimeProjects.reduce(Int64(0)) {
                AgentUsageMath.saturatingAdd($0, $1.tokens.total)
            }
            if aggregateOnlyTotal > 0 {
                providerReported.total = max(providerReported.total, aggregateOnlyTotal)
            }
            reported.add(providerReported)
        }
        return (reported, detailed)
    }

    private func cost(_ events: [AgentUsageEvent]) -> Double {
        events.reduce(0) { $0 + $1.estimatedCostUSD }
    }

    private func sourceQuality(_ providers: [AgentUsageRuntimeAggregate]) -> AgentUsageSourceQuality {
        let qualities = providers.filter(\.available).map(\.sourceQuality).filter { $0 != .unavailable }
        guard let first = qualities.first else { return .unavailable }
        return qualities.dropFirst().allSatisfy { $0 == first } ? first : .mixed
    }

    private func makeDailyBuckets(
        events: [AgentUsageEvent],
        quality: AgentUsageSourceQuality
    ) -> [AgentUsageDailyBucket] {
        let grouped = Dictionary(grouping: events.filter { $0.date >= context.heatmapStart }) {
            context.dayKey(for: $0.date)
        }
        return (0..<180).compactMap { offset -> AgentUsageDailyBucket? in
            guard let date = context.calendar.date(byAdding: .day, value: offset, to: context.heatmapStart) else { return nil }
            let key = context.dayKey(for: date)
            let values = grouped[key] ?? []
            return AgentUsageDailyBucket(
                id: key,
                date: date,
                tokens: totals(values),
                estimatedAPIValueUSD: cost(values),
                sourceQuality: quality
            )
        }
    }

    private func makeHeatmap(events: [AgentUsageEvent]) -> [AgentUsageHeatmapCell] {
        struct Cell { var tokens: Int64 = 0; var count = 0 }
        var grouped: [String: Cell] = [:]
        for event in events where event.date >= context.heatmapStart {
            let parts = context.calendar.dateComponents([.weekday, .hour], from: event.date)
            guard let weekday = parts.weekday, let hour = parts.hour else { continue }
            let key = "\(weekday)-\(hour)"
            var cell = grouped[key, default: Cell()]
            cell.tokens = AgentUsageMath.saturatingAdd(cell.tokens, event.tokens.total)
            cell.count += 1
            grouped[key] = cell
        }
        return (1...7).flatMap { weekday in
            (0..<24).map { hour in
                let value = grouped["\(weekday)-\(hour)"] ?? Cell()
                return AgentUsageHeatmapCell(
                    weekday: weekday,
                    hour: hour,
                    tokens: value.tokens,
                    eventCount: value.count
                )
            }
        }
    }

    private func heatmapThresholds(_ cells: [AgentUsageHeatmapCell]) -> [Int64] {
        let values = cells.map(\.tokens).filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return [1, 10, 100, 1_000] }
        func percentile(_ fraction: Double) -> Int64 {
            values[min(values.count - 1, Int(Double(values.count - 1) * fraction))]
        }
        var thresholds = [percentile(0.25), percentile(0.50), percentile(0.75), percentile(0.90)]
        for index in 1..<thresholds.count where thresholds[index] <= thresholds[index - 1] {
            thresholds[index] = AgentUsageMath.saturatingAdd(thresholds[index - 1], 1)
        }
        return thresholds
    }

    private func projectRankings(
        providers: [AgentUsageRuntimeAggregate],
        since: Date?,
        approximateFallback: Bool
    ) -> [AgentUsageProjectUsage] {
        var result: [AgentUsageProjectUsage] = []
        for provider in providers {
            let filtered = provider.events.filter { event in
                since.map { start in event.date >= start } ?? true
            }
            let detailed = detailedProjects(filtered, scope: provider.scope)
            if approximateFallback, !provider.approximateAllTimeProjects.isEmpty {
                result.append(contentsOf: provider.approximateAllTimeProjects)
            } else if !detailed.isEmpty {
                result.append(contentsOf: detailed)
            }
        }
        return result.sorted {
            if $0.tokens.total == $1.tokens.total { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.tokens.total > $1.tokens.total
        }.prefix(50).map { $0 }
    }

    private func detailedProjects(_ events: [AgentUsageEvent], scope: AgentUsageScope) -> [AgentUsageProjectUsage] {
        struct Accumulator {
            var tokens = AgentUsageTokenTotals.zero
            var cost: Double = 0
            var sessions = Set<String>()
            var lastActive: Date?
        }
        var grouped: [String: Accumulator] = [:]
        for event in events {
            let path = event.projectPath.isEmpty ? "Unknown project" : event.projectPath
            var value = grouped[path, default: Accumulator()]
            value.tokens.add(event.tokens)
            value.cost += event.estimatedCostUSD
            value.sessions.insert(event.sessionID)
            if value.lastActive == nil || event.date > value.lastActive! { value.lastActive = event.date }
            grouped[path] = value
        }
        return grouped.map { path, value in
            let component = URL(fileURLWithPath: path).lastPathComponent
            return AgentUsageProjectUsage(
                id: scope.rawValue + ":" + AgentUsagePrivacy.digest(path),
                name: component.isEmpty ? path : component,
                fullPath: path == "Unknown project" ? "" : path,
                tokens: value.tokens,
                estimatedAPIValueUSD: value.cost,
                sessionCount: value.sessions.count,
                lastActiveAt: value.lastActive,
                sourceQuality: .detailed
            )
        }
    }

    private func modelRankings(_ providers: [AgentUsageRuntimeAggregate]) -> [AgentUsageModelUsage] {
        struct Accumulator {
            var tokens = AgentUsageTokenTotals.zero
            var cost: Double = 0
            var sessions = Set<String>()
            var lastActive: Date?
        }
        var result: [AgentUsageModelUsage] = []
        for provider in providers {
            var grouped: [String: Accumulator] = [:]
            for event in provider.events {
                let model = event.model?.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = (model?.isEmpty == false ? model! : "Unknown model")
                var value = grouped[key, default: Accumulator()]
                value.tokens.add(event.tokens)
                value.cost += event.estimatedCostUSD
                value.sessions.insert(event.sessionID)
                if value.lastActive == nil || event.date > value.lastActive! { value.lastActive = event.date }
                grouped[key] = value
            }
            result.append(contentsOf: grouped.map { model, value in
                AgentUsageModelUsage(
                    id: provider.scope.rawValue + ":" + AgentUsagePrivacy.digest(model),
                    scope: provider.scope,
                    model: model,
                    tokens: value.tokens,
                    estimatedAPIValueUSD: value.cost,
                    sessionCount: value.sessions.count,
                    lastActiveAt: value.lastActive,
                    sourceQuality: provider.sourceQuality
                )
            })
        }
        return result.sorted {
            if $0.tokens.total == $1.tokens.total {
                return $0.model.localizedStandardCompare($1.model) == .orderedAscending
            }
            return $0.tokens.total > $1.tokens.total
        }.prefix(100).map { $0 }
    }

    private func recentSessions(_ providers: [AgentUsageRuntimeAggregate]) -> [AgentUsageSessionUsage] {
        struct Accumulator {
            var tokens = AgentUsageTokenTotals.zero
            var cost: Double = 0
            var projectPath = ""
            var model = "Unknown model"
            var lastActive: Date?
        }
        var result: [AgentUsageSessionUsage] = []
        for provider in providers {
            var grouped: [String: Accumulator] = [:]
            for event in provider.events {
                var value = grouped[event.sessionID, default: Accumulator()]
                value.tokens.add(event.tokens)
                value.cost += event.estimatedCostUSD
                if !event.projectPath.isEmpty { value.projectPath = event.projectPath }
                if let model = event.model, !model.isEmpty { value.model = model }
                if value.lastActive == nil || event.date > value.lastActive! { value.lastActive = event.date }
                grouped[event.sessionID] = value
            }
            result.append(contentsOf: grouped.map { sessionID, value in
                let component = URL(fileURLWithPath: value.projectPath).lastPathComponent
                return AgentUsageSessionUsage(
                    id: provider.scope.rawValue + ":" + AgentUsagePrivacy.digest(sessionID),
                    scope: provider.scope,
                    projectName: component.isEmpty ? "Unknown project" : component,
                    fullProjectPath: value.projectPath,
                    model: value.model,
                    tokens: value.tokens,
                    estimatedAPIValueUSD: value.cost,
                    lastActiveAt: value.lastActive,
                    sourceQuality: provider.sourceQuality
                )
            })
        }
        return result.sorted {
            let left = $0.lastActiveAt ?? .distantPast
            let right = $1.lastActiveAt ?? .distantPast
            if left == right { return $0.tokens.total > $1.tokens.total }
            return left > right
        }.prefix(100).map { $0 }
    }

    private func sourceSummaries(_ providers: [AgentUsageRuntimeAggregate]) -> [AgentUsageSourceSummary] {
        providers.map { provider in
            AgentUsageSourceSummary(
                scope: provider.scope,
                available: provider.available,
                partial: provider.partial,
                parsedFileCount: provider.parsedFileCount,
                tokenEventCount: provider.tokenEventCount,
                sourceQuality: provider.sourceQuality,
                diagnosticCount: provider.diagnostics.count
            )
        }.sorted { $0.scope.rawValue < $1.scope.rawValue }
    }

    private func topTools(_ providers: [AgentUsageRuntimeAggregate]) -> [AgentUsageToolUsage] {
        providers.flatMap { provider in
            provider.toolCalls.map { name, count in
                AgentUsageToolUsage(
                    scope: provider.scope,
                    name: name,
                    category: toolCategory(name),
                    callCount: count,
                    estimatedTokens: nil,
                    estimatedAPIValueUSD: nil
                )
            }
        }.sorted {
            if $0.callCount == $1.callCount { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.callCount > $1.callCount
        }.prefix(50).map { $0 }
    }

    private func toolCategory(_ name: String) -> String {
        let value = name.lowercased()
        if value.contains("shell") || value.contains("exec") || value.contains("command") { return "Command" }
        if value.contains("read") || value.contains("write") || value.contains("patch") || value.contains("file") { return "File" }
        if value.contains("web") || value.contains("browser") || value.contains("http") { return "Network" }
        if value.contains("agent") || value.contains("task") { return "Agent" }
        return "Other"
    }

    private func topSkills(_ providers: [AgentUsageRuntimeAggregate]) -> [AgentUsageSkillUsage] {
        struct Accumulator {
            var path: String?
            var loads = 0
            var sessions = Set<String>()
            var lastLoaded: Date?
        }
        var result: [AgentUsageSkillUsage] = []
        for provider in providers {
            var grouped: [String: Accumulator] = [:]
            for event in provider.skillEvents {
                let key = event.path ?? event.name.lowercased()
                var value = grouped[key, default: Accumulator()]
                value.path = value.path ?? event.path ?? skillIndex.resolve(name: event.name)?.path
                value.loads += 1
                value.sessions.insert(event.sessionID)
                if let date = event.date, value.lastLoaded == nil || date > value.lastLoaded! { value.lastLoaded = date }
                grouped[key] = value
            }
            result.append(contentsOf: grouped.map { key, value in
                let url = value.path.map(URL.init(fileURLWithPath:))
                let byteCount = url.flatMap { AgentUsageValues.fileFingerprint($0)?.size }
                return AgentUsageSkillUsage(
                    scope: provider.scope,
                    name: url?.deletingLastPathComponent().lastPathComponent ?? key,
                    path: value.path,
                    loadCount: value.loads,
                    sessionCount: value.sessions.count,
                    staticTokenEstimate: byteCount.map { max(1, $0 / 4) },
                    staticByteCount: byteCount,
                    lastLoadedAt: value.lastLoaded
                )
            })
        }
        return result.sorted {
            if $0.loadCount == $1.loadCount { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.loadCount > $1.loadCount
        }.prefix(50).map { $0 }
    }

    private func taskBoard(_ tasks: [AgentUsageTaskItem]) -> AgentUsageTaskBoard {
        var seen = Set<String>()
        let values = tasks.filter { seen.insert($0.id).inserted }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        func items(_ category: AgentUsageTaskCategory) -> [AgentUsageTaskItem] {
            Array(values.filter { $0.category == category }.prefix(25))
        }
        return AgentUsageTaskBoard(
            active: items(.active),
            pending: items(.pending),
            scheduled: items(.scheduled),
            done: items(.done)
        )
    }

    private func deduplicatedDiagnostics(_ diagnostics: [AgentUsageDiagnostic]) -> [AgentUsageDiagnostic] {
        var seen = Set<String>()
        return diagnostics.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Deterministic debug regression checks

extension AgentUsageInsightsService {
    nonisolated static func debugUsageInsightsSelfTestFailures() -> [String] {
        var failures = AgentUsageRemotePricingCatalog.debugSelfTestFailures()
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            if !value() { failures.append(message) }
        }

        let coldBudget = AgentUsageCodexScanBudget.make(
            hasWarmCache: false,
            completePendingBackfill: false
        )
        let continueBudget = AgentUsageCodexScanBudget.make(
            hasWarmCache: true,
            completePendingBackfill: true
        )
        expect(coldBudget.totalTranscriptBytes <= 320 * 1_024 * 1_024, "cold Codex detail scan must remain byte-bounded")
        expect(coldBudget.lineageBytesPerFile <= 192 * 1_024 * 1_024, "automatic lineage repair must remain per-file bounded")
        expect(continueBudget.totalTranscriptBytes <= 1_024 * 1_024 * 1_024, "Continue backfill must remain a bounded resumable pass")
        expect(continueBudget.deadline != nil, "Continue backfill must retain a responsiveness deadline")

        let distinctFingerprintA = AgentUsageCounterFingerprint(
            cumulative: AgentUsageCounterSample(input: 1, cached: 2, output: 3, reasoning: 4, total: 5),
            last: nil
        )
        let distinctFingerprintB = AgentUsageCounterFingerprint(
            cumulative: AgentUsageCounterSample(input: 1, cached: 2, output: 3, reasoning: 4, total: 6),
            last: nil
        )
        expect(distinctFingerprintA != distinctFingerprintB, "compact lineage fingerprints must distinguish counter changes")

        var duplicateState = AgentUsageCounterState()
        let initial = AgentUsageCounterSample(input: 100, cached: 20, output: 40, reasoning: 5, total: 140)
        let first = AgentUsageCounterNormalizer.consume(cumulative: initial, last: nil, state: &duplicateState)
        expect(first?.total == 140, "initial cumulative sample must be counted once")
        let duplicate = AgentUsageCounterNormalizer.consume(cumulative: initial, last: initial, state: &duplicateState)
        expect(duplicate == nil, "duplicate cumulative sample must not replay last usage")

        var missingState = AgentUsageCounterState(cumulativeHighWater: AgentUsageTokenTotals(
            input: 100, cached: 10, output: 50, reasoning: 0, total: 150
        ))
        let missing = AgentUsageCounterNormalizer.consume(
            cumulative: AgentUsageCounterSample(input: 125, cached: nil, output: nil, reasoning: nil, total: nil),
            last: nil,
            state: &missingState
        )
        expect(missing?.input == 25, "missing cumulative fields must preserve prior counters")
        expect(missing?.total == 25, "derived total must advance when total_tokens is absent")

        var regressionState = AgentUsageCounterState(cumulativeHighWater: AgentUsageTokenTotals(
            input: 100, cached: 10, output: 50, reasoning: 0, total: 150
        ))
        let regression = AgentUsageCounterNormalizer.consume(
            cumulative: AgentUsageCounterSample(input: 90, cached: 10, output: 70, reasoning: 0, total: 160),
            last: nil,
            state: &regressionState
        )
        expect(regression?.input == 0 && regression?.output == 20, "partial regression must use component high-water marks")

        var resetState = AgentUsageCounterState(cumulativeHighWater: AgentUsageTokenTotals(
            input: 1_000, cached: 100, output: 500, reasoning: 0, total: 1_500
        ))
        let reset = AgentUsageCounterNormalizer.consume(
            cumulative: AgentUsageCounterSample(input: 10, cached: 0, output: 5, reasoning: 0, total: 15),
            last: nil,
            state: &resetState
        )
        expect(reset?.total == 15, "confirmed counter reset must establish a new baseline")

        let lineageFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("tracefence-agent-usage-lineage-\(UUID().uuidString).jsonl")
        do {
            let firstCumulative = AgentUsageCounterSample(
                input: 100, cached: 80, output: 20, reasoning: 5, total: 120
            )
            let firstLast = AgentUsageCounterSample(
                input: 100, cached: 80, output: 20, reasoning: 5, total: 120
            )
            let secondCumulative = AgentUsageCounterSample(
                input: 150, cached: 120, output: 30, reasoning: 7, total: 180
            )
            let secondLast = AgentUsageCounterSample(
                input: 50, cached: 40, output: 10, reasoning: 2, total: 60
            )
            func usageObject(_ value: AgentUsageCounterSample) -> [String: Int64] {
                [
                    "input_tokens": value.input ?? 0,
                    "cached_input_tokens": value.cached ?? 0,
                    "output_tokens": value.output ?? 0,
                    "reasoning_output_tokens": value.reasoning ?? 0,
                    "total_tokens": value.total ?? 0
                ]
            }
            var fixture = Data()
            let records: [[String: Any]] = [
                [
                    "timestamp": "2026-07-30T02:00:00Z",
                    "payload": [
                        "type": "session_meta",
                        "model": "test-model",
                        "cwd": "/tmp/project",
                        "source": [
                            "subagent": [
                                "thread_spawn": ["parent_thread_id": "parent-thread"]
                            ]
                        ]
                    ]
                ],
                [
                    "timestamp": "2026-07-30T02:00:01Z",
                    "payload": [
                        "type": "token_count",
                        "info": [
                            "total_token_usage": usageObject(firstCumulative),
                            "last_token_usage": usageObject(firstLast)
                        ]
                    ]
                ],
                [
                    "timestamp": "2026-07-30T02:00:02Z",
                    "payload": [
                        "type": "token_count",
                        "info": [
                            "total_token_usage": usageObject(secondCumulative),
                            "last_token_usage": usageObject(secondLast)
                        ]
                    ]
                ]
            ]
            for record in records {
                fixture.append(try JSONSerialization.data(withJSONObject: record))
                fixture.append(0x0A)
            }
            try fixture.write(to: lineageFixture, options: .atomic)
            defer { try? FileManager.default.removeItem(at: lineageFixture) }

            let metadata = AgentUsageCodexLineageReader.metadata(at: lineageFixture)
            expect(metadata?.parentThreadID == "parent-thread", "subagent parent lineage must be read from session_meta")
            let rawFingerprints = AgentUsageCodexLineageReader.tokenFingerprints(at: lineageFixture)
            expect(rawFingerprints?.count == 2, "lineage scan must retain only numeric token record fingerprints")

            let parsed = AgentUsageCodexSessionParser(skillIndex: .shared).parse(
                url: lineageFixture,
                source: AgentUsageCodexThread(
                    id: "child-thread",
                    rolloutPath: lineageFixture.path,
                    createdAt: nil,
                    updatedAt: nil,
                    recencyAt: nil,
                    archivedAt: nil,
                    cwd: "/tmp/project",
                    tokens: 0,
                    archived: false,
                    model: "test-model",
                    title: nil
                ),
                allowCompleteTokenScan: true,
                excludingTokenFingerprints: [
                    AgentUsageCounterFingerprint(cumulative: firstCumulative, last: firstLast)
                ]
            )
            let filteredTotal = parsed?.summary.events.reduce(Int64(0)) {
                AgentUsageMath.saturatingAdd($0, $1.tokens.total)
            }
            expect(filteredTotal == 60, "lineage filtering must advance the counter baseline but keep only child-new usage")
        } catch {
            failures.append("lineage token fixture could not be evaluated: \(error.localizedDescription)")
        }

        let fixedMode = AgentUsageTimeZoneMode.fixed(identifier: "America/Los_Angeles")
        let dstNow = Date(timeIntervalSince1970: 1_741_512_600) // 2025-03-09 near US DST transition
        let dstContext = AgentUsageStatisticsContext(mode: fixedMode, now: dstNow)
        expect(dstContext.calendar.timeZone.identifier == "America/Los_Angeles", "fixed IANA time zone must be preserved")
        expect(dstContext.dayKey(for: dstContext.todayStart) == dstContext.dayKey(for: dstNow), "DST day start must stay in the selected civil day")

        let sensitivePath = "/Users/example/Private Client"
        let sensitiveSession = "session-secret-123"
        let cached = AgentUsageFileSummary(
            events: [AgentUsageEvent(
                id: AgentUsagePrivacy.digest("message-secret"),
                date: Date(timeIntervalSince1970: 1_700_000_000),
                tokens: AgentUsageTokenTotals(input: 1, cached: 0, output: 1, reasoning: 0, total: 2),
                estimatedCostUSD: 0,
                priceKnown: false,
                model: "test-model",
                projectPath: sensitivePath,
                sessionID: sensitiveSession
            )],
            toolCalls: ["read": 1],
            skillEvents: [],
            lastActiveAt: nil
        ).redactedForDisk()
        let cacheData = try? JSONEncoder().encode(cached)
        let cacheText = cacheData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        expect(!cacheText.contains(sensitivePath), "disk cache must not contain project paths")
        expect(!cacheText.contains(sensitiveSession), "disk cache must not contain session identifiers")

        expect(!AgentUsageDetailedSanity.isSuspicious(detailed: 2_000_000, approximate: 1_000_000), "normal detailed variance must remain accepted")
        expect(AgentUsageDetailedSanity.isSuspicious(detailed: 8_000_000_000, approximate: 1_000_000_000), "extreme detailed inflation must fail closed")

        expect(
            AgentUsageBackfillOutcomePolicy.resolve(
                remainingSessions: 0,
                excludedByInventoryLimit: 0,
                cancelled: false,
                stoppedByDeadline: false,
                stoppedByReadBudget: false,
                failedThisRun: 0
            ) == .allEligibleSessionsScanned,
            "a zero-remainder detail pass must report fully scanned"
        )
        expect(
            AgentUsageBackfillOutcomePolicy.resolve(
                remainingSessions: 12,
                excludedByInventoryLimit: 0,
                cancelled: false,
                stoppedByDeadline: true,
                stoppedByReadBudget: false,
                failedThisRun: 0
            ) == .timeBudgetReached,
            "a bounded pass with remaining work must expose its time budget stop"
        )
        expect(
            AgentUsageBackfillOutcomePolicy.resolve(
                remainingSessions: 0,
                excludedByInventoryLimit: 3,
                cancelled: false,
                stoppedByDeadline: false,
                stoppedByReadBudget: false,
                failedThisRun: 0
            ) == .inventoryLimitReached,
            "inventory exclusions must never be presented as fully scanned"
        )
        expect(
            AgentUsageBackfillOutcomePolicy.skippedCount(
                attemptedThisRun: 6,
                advancedThisRun: 6,
                failedThisRun: 0
            ) == 0,
            "budget-unattempted candidates must remain pending instead of becoming skipped"
        )
        expect(
            AgentUsageBackfillOutcomePolicy.skippedCount(
                attemptedThisRun: 5,
                advancedThisRun: 2,
                failedThisRun: 1
            ) == 2,
            "skipped must count only attempted work with no advance and no failure"
        )

        let lineAlignmentFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("tracefence-agent-usage-line-alignment-\(UUID().uuidString).jsonl")
        do {
            // The newline is deliberately one byte beyond upperBound. A warm
            // pass with only 57 bytes left cannot form a complete JSONL range.
            var fixture = Data(repeating: 0x61, count: 100)
            fixture.append(0x0A)
            try fixture.write(to: lineAlignmentFixture, options: .atomic)
            defer { try? FileManager.default.removeItem(at: lineAlignmentFixture) }

            let residualBudgetResult = AgentUsageLineAlignment.resolve(
                in: lineAlignmentFixture,
                proposedOffset: 43,
                upperBound: 100
            )
            expect(
                residualBudgetResult == .insufficientBudget,
                "a 57-byte residual without a line boundary must be deferred, not reported as IO failure"
            )

            // Repeating the same warm-cache boundary must remain stable. This
            // guards against a later pass turning deferred work into a burst of
            // failures or skips merely because the cache is already populated.
            let consecutiveWarmResults = (0..<2).map { _ in
                AgentUsageLineAlignment.resolve(
                    in: lineAlignmentFixture,
                    proposedOffset: 43,
                    upperBound: 100
                )
            }
            let consecutiveWarmAttempts = consecutiveWarmResults.reduce(into: 0) { count, result in
                if case .aligned = result { count += 1 }
            }
            let consecutiveWarmFailures = consecutiveWarmResults.reduce(into: 0) { count, result in
                if case .ioFailure = result { count += 1 }
            }
            expect(
                consecutiveWarmAttempts == 0 && consecutiveWarmFailures == 0,
                "consecutive warm-cache budget deferrals must not become attempted or failed reads"
            )
            expect(
                AgentUsageBackfillOutcomePolicy.skippedCount(
                    attemptedThisRun: consecutiveWarmAttempts,
                    advancedThisRun: 0,
                    failedThisRun: consecutiveWarmFailures
                ) == 0,
                "consecutive warm-cache budget deferrals must remain pending instead of skipped"
            )
            expect(
                AgentUsageBackfillOutcomePolicy.resolve(
                    remainingSessions: 1,
                    excludedByInventoryLimit: 0,
                    cancelled: false,
                    stoppedByDeadline: false,
                    stoppedByReadBudget: true,
                    failedThisRun: consecutiveWarmFailures
                ) == .readBudgetReached,
                "a 57-byte warm-cache boundary must end as read-budget reached"
            )

            let missingFixture = lineAlignmentFixture
                .deletingLastPathComponent()
                .appendingPathComponent("tracefence-agent-usage-missing-\(UUID().uuidString).jsonl")
            expect(
                AgentUsageLineAlignment.resolve(
                    in: missingFixture,
                    proposedOffset: 1,
                    upperBound: 2
                ) == .ioFailure,
                "a genuine file-open failure must remain distinguishable from insufficient budget"
            )
        } catch {
            failures.append("line-alignment fixture could not be created")
        }

        let statusReceipt = AgentUsageBackfillStatus(
            stage: .completed,
            checkedSessions: 20,
            totalSessions: 20,
            pendingAtStart: 5,
            advancedThisRun: 2,
            completedThisRun: 1,
            skippedThisRun: 3,
            remainingSessions: 4,
            endReason: .readBudgetReached,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        expect(statusReceipt.hasRemainingWork, "backfill receipt must retain a visible remaining-work signal")
        expect(statusReceipt.checkedSessions == statusReceipt.totalSessions, "inventory completion must not erase detail remainder")
        let pausedReceipt = statusReceipt.replacing(
            stage: .paused,
            endReason: .pausedByUser,
            completedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        expect(pausedReceipt.remainingSessions == 4, "pausing must preserve the exact remaining-session receipt")
        expect(pausedReceipt.endReason == .pausedByUser, "pausing must expose a distinct user stop reason")
        let aggregateOnlyReceipt = AgentUsageBackfillStatus(
            stage: .completed,
            checkedSessions: 20,
            totalSessions: 20,
            aggregateOnlyHistorySessions: 7,
            endReason: .allEligibleSessionsScanned,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        expect(!aggregateOnlyReceipt.hasRemainingWork, "aggregate-only old history must be disclosed without enabling a false continue action")

        let explicit = AgentUsageExplicitTokenNormalizer.totals(
            input: 100,
            cacheRead: 30,
            cacheWrite: 20,
            output: 40,
            reasoning: 10,
            reportedTotal: 200
        )
        expect(explicit?.input == 150, "explicit native input must include cache components exactly once")
        expect(explicit?.cached == 50, "explicit native cache components must be preserved")
        expect(explicit?.output == 50, "explicit native output must include reasoning exactly once")
        expect(explicit?.reasoning == 10, "explicit native reasoning must be preserved")
        expect(explicit?.total == 200, "explicit native total must reconcile with its components")
        let inconsistentExplicit = AgentUsageExplicitTokenNormalizer.totals(
            input: 100,
            cacheRead: 30,
            cacheWrite: 20,
            output: 40,
            reasoning: 10,
            reportedTotal: 201
        )
        expect(inconsistentExplicit == nil, "inconsistent explicit native totals must fail closed")

        let fixtureDate = Date(timeIntervalSince1970: 1_700_000_000)
        func fixtureProvider(
            scope: AgentUsageScope,
            tokens: AgentUsageTokenTotals,
            aggregateOnlyTotal: Int64
        ) -> AgentUsageRuntimeAggregate {
            var provider = AgentUsageRuntimeAggregate(scope: scope)
            provider.events = [AgentUsageEvent(
                id: nil,
                date: fixtureDate,
                tokens: tokens,
                estimatedCostUSD: 0,
                priceKnown: false,
                model: nil,
                projectPath: "/fixture/\(scope.rawValue)",
                sessionID: "fixture-\(scope.rawValue)"
            )]
            provider.approximateAllTimeProjects = [AgentUsageProjectUsage(
                id: "fixture-\(scope.rawValue)",
                name: "Fixture",
                fullPath: "/fixture/\(scope.rawValue)",
                tokens: AgentUsageTokenTotals(input: 0, cached: 0, output: 0, reasoning: 0, total: aggregateOnlyTotal),
                estimatedAPIValueUSD: 0,
                sessionCount: 1,
                lastActiveAt: fixtureDate,
                sourceQuality: .approximate
            )]
            return provider
        }
        let fixtureCodex = fixtureProvider(
            scope: .codex,
            tokens: AgentUsageTokenTotals(input: 100, cached: 80, output: 40, reasoning: 10, total: 140),
            aggregateOnlyTotal: 1_000
        )
        let codexReconciliation = AgentUsageSnapshotBuilder.reconcileAllTime(
            providers: [fixtureCodex],
            through: fixtureDate.addingTimeInterval(1)
        )
        expect(codexReconciliation.reported.total == 1_000, "aggregate-only inventory must remain the all-time headline")
        expect(codexReconciliation.detailed.total == 140, "parsed all-time detail must remain independently measurable")
        expect(codexReconciliation.reported.total - codexReconciliation.detailed.total == 860, "unattributed all-time history must reconcile exactly")
        expect(codexReconciliation.reported.input == codexReconciliation.detailed.input, "aggregate-only inventory must not fabricate input tokens")
        expect(codexReconciliation.reported.output == codexReconciliation.detailed.output, "aggregate-only inventory must not fabricate output tokens")
        expect(codexReconciliation.detailed.cached <= codexReconciliation.detailed.input, "cached input must remain a subset of input")
        expect(codexReconciliation.detailed.reasoning <= codexReconciliation.detailed.output, "reasoning output must remain a subset of output")
        expect(codexReconciliation.detailed.total >= AgentUsageMath.saturatingAdd(codexReconciliation.detailed.input, codexReconciliation.detailed.output), "reported detailed total must cover input plus output")

        let fixtureClaude = fixtureProvider(
            scope: .claude,
            tokens: AgentUsageTokenTotals(input: 40, cached: 10, output: 20, reasoning: 5, total: 60),
            aggregateOnlyTotal: 200
        )
        let combinedReconciliation = AgentUsageSnapshotBuilder.reconcileAllTime(
            providers: [fixtureCodex, fixtureClaude],
            through: fixtureDate.addingTimeInterval(1)
        )
        expect(combinedReconciliation.reported.total == 1_200, "combined all-time inventory must add provider headlines once")
        expect(combinedReconciliation.detailed.total == 200, "combined parsed detail must add provider detail once")
        expect(AgentUsageInsightsMode.tokenAnalytics.entryScope == .combined, "Token & Usage must enter on the same combined scope used by Overview")
        expect(AgentUsageInsightsMode.projectMonitor.entryScope == nil, "project drill-down must preserve the user's explicit source filter")
        expect(AgentUsageTokenFormatter.string(40_254_839_013) == "40.25B", "shared token formatter must use the B unit consistently")
        expect(AgentUsageTokenFormatter.string(250_000_000) == "250.00M", "shared token formatter must use the M unit consistently")
        expect(AgentUsageTokenFormatter.string(-10) == "0", "shared token formatter must clamp invalid negative totals")
        expect(AgentUsageTokenFormatter.exactString(40_747_845_038) == "40,747,845,038", "exact token formatter must preserve every digit")
        let opus48 = AgentUsagePricingCatalog.price(scope: .claude, model: "claude-opus-4-8")
        expect(opus48?.inputPerMillion == 5 && opus48?.outputPerMillion == 25, "Claude Opus 4.8 must use its current model-specific price")
        let sonnet5Intro = AgentUsagePricingCatalog.price(
            scope: .claude,
            model: "claude-sonnet-5",
            at: Date(timeIntervalSince1970: 1_785_000_000)
        )
        expect(sonnet5Intro?.inputPerMillion == 2 && sonnet5Intro?.outputPerMillion == 10, "Claude Sonnet 5 introductory pricing must apply to usage before September 2026")
        let sonnet5Standard = AgentUsagePricingCatalog.price(
            scope: .claude,
            model: "claude-sonnet-5",
            at: Date(timeIntervalSince1970: 1_788_220_800)
        )
        expect(sonnet5Standard?.inputPerMillion == 3 && sonnet5Standard?.outputPerMillion == 15, "Claude Sonnet 5 standard pricing must apply after the introductory period")
        let haiku45 = AgentUsagePricingCatalog.price(scope: .claude, model: "claude-haiku-4-5")
        expect(haiku45?.inputPerMillion == 1 && haiku45?.outputPerMillion == 5, "Claude Haiku 4.5 must not inherit the older Haiku 3.5 price")
        let gpt56Sol = AgentUsagePricingCatalog.price(scope: .codex, model: "gpt-5.6-sol")
        expect(gpt56Sol?.inputPerMillion == 5 && gpt56Sol?.cachedInputPerMillion == 0.5 && gpt56Sol?.outputPerMillion == 30, "GPT-5.6 Sol must use the public Sol token prices")
        let beforeJuly30 = Date(timeIntervalSince1970: 1_785_369_599)
        let afterJuly30 = Date(timeIntervalSince1970: 1_785_369_600)
        let gpt56Terra = AgentUsagePricingCatalog.price(scope: .codex, model: "gpt-5.6-terra", at: afterJuly30)
        expect(gpt56Terra?.inputPerMillion == 2 && gpt56Terra?.cachedInputPerMillion == 0.2 && gpt56Terra?.outputPerMillion == 12, "GPT-5.6 Terra must use its reduced price from July 30, 2026")
        let historicalTerra = AgentUsagePricingCatalog.price(scope: .codex, model: "gpt-5.6-terra", at: beforeJuly30)
        expect(historicalTerra?.inputPerMillion == 2.5 && historicalTerra?.cachedInputPerMillion == 0.25 && historicalTerra?.outputPerMillion == 15, "GPT-5.6 Terra usage before July 30 must retain its historical price")
        let gpt56Luna = AgentUsagePricingCatalog.price(scope: .codex, model: "gpt-5.6-luna", at: afterJuly30)
        expect(gpt56Luna?.inputPerMillion == 0.2 && gpt56Luna?.cachedInputPerMillion == 0.02 && gpt56Luna?.outputPerMillion == 1.2, "GPT-5.6 Luna must use its reduced price from July 30, 2026")
        let historicalLuna = AgentUsagePricingCatalog.price(scope: .codex, model: "gpt-5.6-luna", at: beforeJuly30)
        expect(historicalLuna?.inputPerMillion == 1 && historicalLuna?.cachedInputPerMillion == 0.1 && historicalLuna?.outputPerMillion == 6, "GPT-5.6 Luna usage before July 30 must retain its historical price")
        let opus5 = AgentUsagePricingCatalog.price(scope: .claude, model: "claude-opus-5")
        expect(opus5?.inputPerMillion == 5 && opus5?.cachedInputPerMillion == 0.5 && opus5?.outputPerMillion == 25, "Claude Opus 5 must not inherit legacy Opus pricing")
        let fable5 = AgentUsagePricingCatalog.price(scope: .claude, model: "claude-fable-5")
        expect(fable5?.inputPerMillion == 10 && fable5?.cachedInputPerMillion == 1 && fable5?.outputPerMillion == 50, "Claude Fable 5 must use its public model price")
        let miniMaxM3 = AgentUsagePricingCatalog.price(scope: .openCode, model: "minimax/MiniMax-M3")
        expect(miniMaxM3?.inputPerMillion == 0.3 && miniMaxM3?.cachedInputPerMillion == 0.06 && miniMaxM3?.outputPerMillion == 1.2, "MiniMax M3 must resolve through its namespaced OpenCode model ID")
        let miniMaxM27 = AgentUsagePricingCatalog.price(scope: .openClaw, model: "MiniMax-M2.7")
        expect(miniMaxM27?.inputPerMillion == 0.3 && miniMaxM27?.cachedInputPerMillion == 0.06 && miniMaxM27?.outputPerMillion == 1.2, "MiniMax M2.7 must fall back to public pricing when the runtime omits cost")
        let longContextEstimate = AgentUsagePricingCatalog.estimatedCost(
            tokens: AgentUsageTokenTotals(input: 300_000, cached: 0, output: 10_000, reasoning: 0, total: 310_000),
            price: gpt56Sol
        )
        expect(abs(longContextEstimate.0 - 3.45) < 0.000_001, "GPT-5.6 requests above 272K input must use the published long-context multipliers")
        expect(AgentUsagePricingCatalog.price(scope: .codex, model: "gpt-5.6-sol-pro") == nil, "Non-API Sol Pro aliases must not inherit the public Sol API price")
        expect(AgentUsagePricingCatalog.price(scope: .codex, model: "codex-auto-review") == nil, "Internal router aliases must remain explicitly unpriced")
        return failures
    }

    /// Runs the real local loaders without touching published UI state. The
    /// returned Codable value contains no source paths, titles, or identifiers.
    /// This synchronous wrapper is intended for a DEBUG launch argument or a
    /// command-line regression harness, never for the main-thread UI path.
    nonisolated static func debugRunLocalUsageProbe(
        timeout: TimeInterval = 120,
        completePendingBackfill: Bool = false
    ) -> AgentUsageDebugProbe {
        retireLegacyTokenScopeCache()
        let started = Date()
        let semaphore = DispatchSemaphore(value: 0)
        let box = AgentUsageProbeBox()
        Task.detached(priority: .utility) {
            let result = await AgentUsageInsightsLoader(
                timeZoneMode: .system,
                now: started,
                progress: { _ in },
                completePendingBackfill: completePendingBackfill
            ).load()
            let elapsed = max(0, Int(Date().timeIntervalSince(started) * 1_000))
            let selfTests = debugUsageInsightsSelfTestFailures()
            switch result {
            case let .success(loaded):
                let snapshot = loaded.snapshots[.combined] ?? .empty(scope: .combined, now: started)
                let sourceSnapshots = loaded.snapshots.filter { $0.key != .combined }
                box.set(AgentUsageDebugProbe(
                    succeeded: true,
                    elapsedMilliseconds: elapsed,
                    parsedFileCount: snapshot.parsedFileCount,
                    tokenEventCount: snapshot.tokenEventCount,
                    todayTokens: snapshot.today.total,
                    last7DaysTokens: snapshot.last7Days.total,
                    allTimeTokens: snapshot.allTime.total,
                    allTimeDetailedTokens: snapshot.allTimeDetailed.total,
                    allTimeUnattributedTokens: max(0, snapshot.allTime.total - snapshot.allTimeDetailed.total),
                    sourceAllTimeTokens: Dictionary(uniqueKeysWithValues: sourceSnapshots.map { ($0.key.rawValue, $0.value.allTime.total) }),
                    sourceDetailedTokens: Dictionary(uniqueKeysWithValues: sourceSnapshots.map { ($0.key.rawValue, $0.value.allTimeDetailed.total) }),
                    sourceTokenEventCounts: Dictionary(uniqueKeysWithValues: sourceSnapshots.map { ($0.key.rawValue, $0.value.tokenEventCount) }),
                    diagnosticCodes: snapshot.diagnostics.map(\.code).sorted(),
                    selfTestFailures: selfTests,
                    backfillCheckedSessions: loaded.backfillStatus?.checkedSessions ?? 0,
                    backfillTotalSessions: loaded.backfillStatus?.totalSessions ?? 0,
                    backfillPendingAtStart: loaded.backfillStatus?.pendingAtStart ?? 0,
                    backfillAdvancedThisRun: loaded.backfillStatus?.advancedThisRun ?? 0,
                    backfillCompletedThisRun: loaded.backfillStatus?.completedThisRun ?? 0,
                    backfillSkippedThisRun: loaded.backfillStatus?.skippedThisRun ?? 0,
                    backfillFailedThisRun: loaded.backfillStatus?.failedThisRun ?? 0,
                    backfillRemainingSessions: loaded.backfillStatus?.remainingSessions ?? 0,
                    backfillExcludedSessions: loaded.backfillStatus?.excludedByInventoryLimit ?? 0,
                    backfillAggregateOnlyHistorySessions: loaded.backfillStatus?.aggregateOnlyHistorySessions ?? 0,
                    backfillEndReason: loaded.backfillStatus?.endReason?.rawValue,
                    error: nil
                ))
            case let .failure(error):
                box.set(AgentUsageDebugProbe(
                    succeeded: false,
                    elapsedMilliseconds: elapsed,
                    parsedFileCount: 0,
                    tokenEventCount: 0,
                    todayTokens: 0,
                    last7DaysTokens: 0,
                    allTimeTokens: 0,
                    allTimeDetailedTokens: 0,
                    allTimeUnattributedTokens: 0,
                    sourceAllTimeTokens: [:],
                    sourceDetailedTokens: [:],
                    sourceTokenEventCounts: [:],
                    diagnosticCodes: [],
                    selfTestFailures: selfTests,
                    backfillCheckedSessions: 0,
                    backfillTotalSessions: 0,
                    backfillPendingAtStart: 0,
                    backfillAdvancedThisRun: 0,
                    backfillCompletedThisRun: 0,
                    backfillSkippedThisRun: 0,
                    backfillFailedThisRun: 0,
                    backfillRemainingSessions: 0,
                    backfillExcludedSessions: 0,
                    backfillAggregateOnlyHistorySessions: 0,
                    backfillEndReason: AgentUsageBackfillEndReason.scanFailed.rawValue,
                    error: error.localizedDescription
                ))
            }
            semaphore.signal()
        }
        let deadline = DispatchTime.now() + max(1, timeout)
        guard semaphore.wait(timeout: deadline) == .success, let value = box.get() else {
            return AgentUsageDebugProbe(
                succeeded: false,
                elapsedMilliseconds: max(0, Int(Date().timeIntervalSince(started) * 1_000)),
                parsedFileCount: 0,
                tokenEventCount: 0,
                todayTokens: 0,
                last7DaysTokens: 0,
                allTimeTokens: 0,
                allTimeDetailedTokens: 0,
                allTimeUnattributedTokens: 0,
                sourceAllTimeTokens: [:],
                sourceDetailedTokens: [:],
                sourceTokenEventCounts: [:],
                diagnosticCodes: ["usage_probe_timeout"],
                selfTestFailures: debugUsageInsightsSelfTestFailures(),
                backfillCheckedSessions: 0,
                backfillTotalSessions: 0,
                backfillPendingAtStart: 0,
                backfillAdvancedThisRun: 0,
                backfillCompletedThisRun: 0,
                backfillSkippedThisRun: 0,
                backfillFailedThisRun: 0,
                backfillRemainingSessions: 0,
                backfillExcludedSessions: 0,
                backfillAggregateOnlyHistorySessions: 0,
                backfillEndReason: AgentUsageBackfillEndReason.scanFailed.rawValue,
                error: "Local usage probe timed out."
            )
        }
        return value
    }
}

private final class AgentUsageProbeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AgentUsageDebugProbe?

    func set(_ value: AgentUsageDebugProbe) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> AgentUsageDebugProbe? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
