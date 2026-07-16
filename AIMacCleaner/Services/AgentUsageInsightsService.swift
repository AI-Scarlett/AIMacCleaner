import Combine
import CryptoKit
import Foundation
import SQLite3

// MARK: - Public domain model

/// The local runtime whose metadata is represented by an insights snapshot.
enum AgentUsageScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude
    case combined

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .combined: return "All Agents"
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
    let estimatedAPIValueUSD: AgentUsageValueEstimate
    let dailyBuckets: [AgentUsageDailyBucket]
    let weekdayHourHeatmap: [AgentUsageHeatmapCell]
    let heatmapThresholds: [Int64]
    let previous7DayComparison: AgentUsagePeriodComparison
    let projectRankings7Days: [AgentUsageProjectUsage]
    let projectRankingsAllTime: [AgentUsageProjectUsage]
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
            estimatedAPIValueUSD: .zero,
            dailyBuckets: [],
            weekdayHourHeatmap: [],
            heatmapThresholds: [1, 10, 100, 1_000],
            previous7DayComparison: AgentUsagePeriodComparison(current: .zero, previous: .zero, changePercent: nil, isNewActivity: false),
            projectRankings7Days: [],
            projectRankingsAllTime: [],
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
    case ready
    case partial(message: String)
    case failed(message: String, previous: AgentUsageSnapshot?)
}

enum AgentUsageScanPhase: String, Codable, Equatable, Sendable {
    case idle
    case readingCodexDatabase
    case scanningCodexSessions
    case scanningClaudeTranscripts
    case readingTasks
    case aggregating
    case completed
    case failed
}

struct AgentUsageScanProgress: Codable, Equatable, Sendable {
    let phase: AgentUsageScanPhase
    let current: Int
    let total: Int
    let currentSource: String?
    let message: String

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
    let diagnosticCodes: [String]
    let selfTestFailures: [String]
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

    @Published private(set) var snapshot: AgentUsageSnapshot
    @Published private(set) var state: AgentUsageLoadState = .idle
    @Published private(set) var progress: AgentUsageScanProgress = .idle
    @Published var scope: AgentUsageScope {
        didSet {
            UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeDefaultsKey)
            if let existing = snapshots[scope] {
                snapshot = existing
                state = existing.isPartial ? .partial(message: Self.partialMessage(for: existing)) : .ready
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

    private init(defaults: UserDefaults = .standard) {
        let initialScope = defaults.string(forKey: Self.scopeDefaultsKey)
            .flatMap(AgentUsageScope.init(rawValue:)) ?? .combined
        let initialTimeZoneMode = AgentUsageTimeZoneMode(
            storedValue: defaults.string(forKey: Self.timeZoneDefaultsKey)
        )
        scope = initialScope
        timeZoneMode = initialTimeZoneMode
        snapshot = .empty(scope: initialScope, timeZone: initialTimeZoneMode.resolvedTimeZone)
    }

    func startScheduling() {
        guard scheduler == nil else { return }
        refresh()
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

    func refresh(force: Bool = false) {
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

        refreshGeneration &+= 1
        let generation = refreshGeneration
        let previous = snapshots[scope]
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
            }
        }

        refreshTask = Task { [weak self] in
            let result = await AgentUsageInsightsLoader(
                timeZoneMode: mode,
                now: Date(),
                progress: progressSink
            ).load()
            guard let self, generation == self.refreshGeneration else { return }
            self.refreshTask = nil
            self.lastRefreshAt = Date()

            switch result {
            case let .success(loaded):
                self.snapshots = loaded
                let selected = loaded[self.scope] ?? .empty(scope: self.scope, timeZone: self.timeZoneMode.resolvedTimeZone)
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
            case let .failure(error):
                self.state = .failed(message: error.localizedDescription, previous: previous)
                self.progress = AgentUsageScanProgress(
                    phase: .failed,
                    current: self.progress.current,
                    total: self.progress.total,
                    currentSource: self.progress.currentSource,
                    message: error.localizedDescription
                )
                if let previous { self.snapshot = previous }
            }
        }
    }

    /// Removes only derived aggregate caches. Source transcripts and databases
    /// are never modified.
    func clearCaches() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration &+= 1
        AgentUsageFileCacheStore.clearAll()
        snapshots.removeAll()
        snapshot = .empty(scope: scope, timeZone: timeZoneMode.resolvedTimeZone)
        state = .idle
        progress = .idle
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
        let interval = applicationIsActive ? Self.foregroundInterval : Self.backgroundInterval
        guard lastRefreshAt.map({ Date().timeIntervalSince($0) >= interval }) ?? true else { return }
        refresh()
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
            estimatedAPIValueUSD: estimatedAPIValueUSD,
            dailyBuckets: dailyBuckets,
            weekdayHourHeatmap: weekdayHourHeatmap,
            heatmapThresholds: heatmapThresholds,
            previous7DayComparison: previous7DayComparison,
            projectRankings7Days: redactProjects(projectRankings7Days),
            projectRankingsAllTime: redactProjects(projectRankingsAllTime),
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
}

private enum AgentUsageLoaderError: LocalizedError {
    case noLocalSources
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .noLocalSources: return "No Codex or Claude Code local usage sources were found."
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
    let outputPerMillion: Double
}

/// Centralized API-equivalent reference prices. Values are estimates used only
/// for local comparison; they are not invoices and unknown models are omitted.
private enum AgentUsagePricingCatalog {
    static func price(scope: AgentUsageScope, model: String?) -> AgentUsageModelPrice? {
        let value = (model ?? "").lowercased()
        guard !value.isEmpty else { return nil }

        switch scope {
        case .codex:
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
        case .claude:
            if value.contains("opus") {
                return AgentUsageModelPrice(inputPerMillion: 15, cachedInputPerMillion: 1.5, outputPerMillion: 75)
            }
            if value.contains("sonnet") {
                return AgentUsageModelPrice(inputPerMillion: 3, cachedInputPerMillion: 0.3, outputPerMillion: 15)
            }
            if value.contains("haiku") {
                return AgentUsageModelPrice(inputPerMillion: 0.8, cachedInputPerMillion: 0.08, outputPerMillion: 4)
            }
            return nil
        case .combined:
            return nil
        }
    }

    static func estimatedCost(tokens: AgentUsageTokenTotals, price: AgentUsageModelPrice?) -> (Double, Bool) {
        guard let price else { return (0, false) }
        let input = Double(max(0, tokens.uncachedInput)) / 1_000_000 * price.inputPerMillion
        let cached = Double(max(0, min(tokens.cached, tokens.input))) / 1_000_000 * price.cachedInputPerMillion
        let output = Double(max(0, tokens.output)) / 1_000_000 * price.outputPerMillion
        return (input + cached + output, true)
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
        return AgentUsageFileCache(version: version, entries: limited(decoded.entries))
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
        case .combined: return nil
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

    private func columnNames(table: String) -> Set<String>? {
        guard table == "threads", let rows = rows("PRAGMA table_info(threads);") else { return nil }
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
            let chunk = try handle.read(upToCount: readCount) ?? Data()
            if chunk.isEmpty { break }
            bytesRead += Int64(chunk.count)
            if remaining != nil { remaining! -= Int64(chunk.count) }
            buffer.append(chunk)

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
                        if isInteresting { try body(buffer.subdata(in: lineRange)) }
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
            try body(buffer)
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
        deadline: Date? = nil
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
                tokenRecordCount += 1
                if tokenRecordCount > 250_000 {
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
                let price = AgentUsagePricingCatalog.price(scope: .codex, model: currentModel)
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

                let price = AgentUsagePricingCatalog.price(scope: .claude, model: currentModel)
                let estimated = AgentUsagePricingCatalog.estimatedCost(tokens: tokens, price: price)
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
                    message: "Choose your Codex or Claude Code data folder in TokenScope to authorize local usage analytics.",
                    source: nil
                )]
            )
        }

        let desiredRoots = [AgentUsagePathPolicy.codexRoot, AgentUsagePathPolicy.claudeRoot]
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
                message: "The saved Codex or Claude Code folder permission is unavailable. Choose the folder again in TokenScope.",
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
    case append = 0
    case newFile = 1
    case backfill = 2
}

private struct AgentUsageCodexWorkItem {
    let mode: AgentUsageCodexWorkMode
    let thread: AgentUsageCodexThread
    let url: URL
    let fingerprint: AgentUsageValues.FileFingerprint
    let key: String
    let cached: AgentUsageFileCacheEntry?
}

private final class AgentUsageCodexProvider: @unchecked Sendable {
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
        if threads.count > 2_000 {
            threads.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            threads.removeSubrange(2_000..<threads.count)
            aggregate.partial = true
            aggregate.diagnostics.append(AgentUsageDiagnostic(
                scope: .codex,
                severity: .warning,
                code: "codex_backfill_bounded",
                message: "Codex history exceeds the 2,000-session local backfill limit; the newest sessions were loaded.",
                source: nil
            ))
        }
        threads.sort {
            ($0.recencyAt ?? $0.updatedAt ?? .distantPast)
                > ($1.recencyAt ?? $1.updatedAt ?? .distantPast)
        }

        progress(AgentUsageScanProgress(
            phase: .scanningCodexSessions,
            current: 0,
            total: threads.count,
            currentSource: nil,
            message: "Scanning Codex session metadata"
        ))

        var cache = AgentUsageFileCacheStore.load(scope: .codex)
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
        let hasWarmCache = !cache.entries.isEmpty
        var remainingReadBytes: Int64 = (hasWarmCache ? 16 : 192) * 1_024 * 1_024
        let maximumReadBytesPerFile: Int64 = (hasWarmCache ? 8 : 32) * 1_024 * 1_024
        let scanDeadline = Date().addingTimeInterval(hasWarmCache ? 1.0 : 10)

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
                    current: index,
                    total: threads.count,
                    currentSource: url.lastPathComponent,
                    message: "Reading Codex usage \(index + 1) of \(threads.count)"
                ))
            }
            let key = AgentUsagePrivacy.cacheKey(for: url)
            let cached = cache.entries[key]
            if let cached {
                summariesByKey[key] = cached.summary.rehydrated(
                    projectPath: thread.cwd,
                    sessionID: thread.id,
                    skillIndex: skillIndex
                )
                if cached.coverageIncomplete || cached.skippedRelevantRecord { partialKeys.insert(key) }
            } else {
                partialKeys.insert(key)
            }

            let exactFingerprint = cached?.size == fingerprint.size
                && cached?.modificationTimeNanoseconds == fingerprint.modificationTimeNanoseconds
            if exactFingerprint {
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
        for (workIndex, item) in workItems.enumerated() {
            if Task.isCancelled || Date() >= scanDeadline || remainingReadBytes <= 0 { break }
            progress(AgentUsageScanProgress(
                phase: .scanningCodexSessions,
                current: min(threads.count, workIndex + summariesByKey.count),
                total: threads.count,
                currentSource: item.url.lastPathComponent,
                message: "Updating bounded Codex usage cache"
            ))

            let upperBound: Int64
            let proposedStart: Int64
            switch item.mode {
            case .append:
                guard let cached = item.cached else { continue }
                let appendBytes = item.fingerprint.size - cached.size
                guard appendBytes > 0,
                      appendBytes <= maximumReadBytesPerFile,
                      appendBytes <= remainingReadBytes else { continue }
                proposedStart = cached.size
                upperBound = item.fingerprint.size
            case .backfill:
                guard let cached = item.cached, cached.scannedFromOffset > 0 else { continue }
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

            let startingOffset = alignedLineStart(
                in: item.url,
                proposedOffset: proposedStart,
                upperBound: upperBound
            )
            let rangeBytes = max(0, upperBound - startingOffset)
            guard rangeBytes > 0 || item.fingerprint.size == 0 else { continue }
            guard let parsed = parser.parse(
                url: item.url,
                source: item.thread,
                startingAtOffset: startingOffset,
                startsAtLineBoundary: true,
                maximumBytes: rangeBytes > 0 ? rangeBytes : nil,
                deadline: nil
            ) else {
                failures += 1
                continue
            }
            remainingReadBytes = max(0, remainingReadBytes - max(1, parsed.bytesRead))
            guard parsed.completedRequestedRange else {
                // Never advance a cursor for a partially-read planned range.
                continue
            }

            let parsedDisk = parsed.summary.redactedForDisk()
            let diskSummary: AgentUsageFileSummary
            let coverageIncomplete: Bool
            let skippedRelevantRecord: Bool
            let scannedFromOffset: Int64
            switch item.mode {
            case .append:
                guard let cached = item.cached else { continue }
                diskSummary = cached.summary.merged(with: parsedDisk)
                coverageIncomplete = cached.coverageIncomplete
                skippedRelevantRecord = cached.skippedRelevantRecord || parsed.skippedRelevantRecord
                scannedFromOffset = cached.scannedFromOffset
            case .backfill:
                guard let cached = item.cached else { continue }
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
                summary: diskSummary
            )
            cache.entries[item.key] = entry
            cacheChanged = true
            summariesByKey[item.key] = diskSummary.rehydrated(
                projectPath: item.thread.cwd,
                sessionID: item.thread.id,
                skillIndex: skillIndex
            )
            if coverageIncomplete || skippedRelevantRecord {
                partialKeys.insert(item.key)
            } else {
                partialKeys.remove(item.key)
            }
        }

        let summaries = threads.compactMap { thread -> AgentUsageFileSummary? in
            guard let url = AgentUsagePathPolicy.normalizedRolloutURL(thread.rolloutPath) else { return nil }
            return summariesByKey[AgentUsagePrivacy.cacheKey(for: url)]
        }
        let cappedFiles = partialKeys.count

        if !Task.isCancelled, cacheChanged, !AgentUsageFileCacheStore.save(cache, scope: .codex) {
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
                message: "\(cappedFiles) large or not-yet-cached Codex sessions were bounded for responsiveness; later refreshes continue the local backfill.",
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

    private func alignedLineStart(in url: URL, proposedOffset: Int64, upperBound: Int64) -> Int64 {
        let proposed = max(0, min(proposedOffset, upperBound))
        guard proposed > 0, proposed < upperBound,
              let handle = try? FileHandle(forReadingFrom: url) else { return proposed }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(proposed - 1))
            if try handle.read(upToCount: 1)?.first == 10 { return proposed }
            try handle.seek(toOffset: UInt64(proposed))
            var cursor = proposed
            while cursor < upperBound {
                try Task.checkCancellation()
                let count = Int(min(Int64(64 * 1_024), upperBound - cursor))
                guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
                if let newline = chunk.firstIndex(of: 10) {
                    return cursor + Int64(chunk.distance(from: chunk.startIndex, to: newline)) + 1
                }
                cursor += Int64(chunk.count)
            }
        } catch {
            return upperBound
        }
        return upperBound
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

// MARK: - Snapshot aggregation

private enum AgentUsageProviderLoadResult: Sendable {
    case codex(AgentUsageRuntimeAggregate)
    case claude(AgentUsageRuntimeAggregate)
}

private struct AgentUsageInsightsLoader: Sendable {
    let context: AgentUsageStatisticsContext
    let progress: @Sendable (AgentUsageScanProgress) -> Void

    init(
        timeZoneMode: AgentUsageTimeZoneMode,
        now: Date,
        progress: @escaping @Sendable (AgentUsageScanProgress) -> Void
    ) {
        context = AgentUsageStatisticsContext(mode: timeZoneMode, now: now)
        self.progress = progress
    }

    func load() async -> Result<[AgentUsageScope: AgentUsageSnapshot], AgentUsageLoaderError> {
        let lease = AgentUsageSecurityScopeLease.acquire()
        defer { lease.stop() }
        let skillIndex = AgentUsageSkillIndex.shared
        var codex = AgentUsageRuntimeAggregate(scope: .codex)
        var claude = AgentUsageRuntimeAggregate(scope: .claude)

        await withTaskGroup(of: AgentUsageProviderLoadResult.self) { group in
            group.addTask(priority: .utility) {
                .codex(AgentUsageCodexProvider(
                    context: context,
                    skillIndex: skillIndex,
                    progress: progress
                ).load())
            }
            group.addTask(priority: .utility) {
                .claude(AgentUsageClaudeProvider(
                    context: context,
                    skillIndex: skillIndex,
                    progress: progress
                ).load())
            }
            for await result in group {
                switch result {
                case let .codex(value): codex = value
                case let .claude(value): claude = value
                }
            }
        }

        if Task.isCancelled {
            return .failure(.unexpected("Local usage scan was cancelled."))
        }
        if !lease.diagnostics.isEmpty {
            codex.diagnostics.append(contentsOf: lease.diagnostics)
            claude.diagnostics.append(contentsOf: lease.diagnostics)
            codex.partial = true
            claude.partial = true
        }
        progress(AgentUsageScanProgress(
            phase: .aggregating,
            current: 0,
            total: 3,
            currentSource: nil,
            message: "Aggregating local usage metrics"
        ))

        if !codex.available && !claude.available && lease.diagnostics.isEmpty {
            return .failure(.noLocalSources)
        }
        let builder = AgentUsageSnapshotBuilder(context: context, skillIndex: skillIndex)
        let codexSnapshot = builder.build(scope: .codex, providers: [codex])
        progress(AgentUsageScanProgress(
            phase: .aggregating,
            current: 1,
            total: 3,
            currentSource: "Codex",
            message: "Aggregated Codex usage"
        ))
        let claudeSnapshot = builder.build(scope: .claude, providers: [claude])
        progress(AgentUsageScanProgress(
            phase: .aggregating,
            current: 2,
            total: 3,
            currentSource: "Claude Code",
            message: "Aggregated Claude Code usage"
        ))
        let combinedSnapshot = builder.build(scope: .combined, providers: [codex, claude])
        return .success([
            .codex: codexSnapshot,
            .claude: claudeSnapshot,
            .combined: combinedSnapshot
        ])
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
        var allTime = AgentUsageTokenTotals.zero
        for provider in providers {
            var providerTotal = totals(provider.events.filter {
                $0.date <= context.now.addingTimeInterval(5 * 60)
            })
            let approximateTotal = provider.approximateAllTimeProjects.reduce(Int64(0)) {
                AgentUsageMath.saturatingAdd($0, $1.tokens.total)
            }
            if approximateTotal > 0 {
                providerTotal.total = max(providerTotal.total, approximateTotal)
            }
            allTime.add(providerTotal)
        }
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
        var failures: [String] = []
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            if !value() { failures.append(message) }
        }

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
        return failures
    }

    /// Runs the real local loaders without touching published UI state. The
    /// returned Codable value contains no source paths, titles, or identifiers.
    /// This synchronous wrapper is intended for a DEBUG launch argument or a
    /// command-line regression harness, never for the main-thread UI path.
    nonisolated static func debugRunLocalUsageProbe(timeout: TimeInterval = 120) -> AgentUsageDebugProbe {
        let started = Date()
        let semaphore = DispatchSemaphore(value: 0)
        let box = AgentUsageProbeBox()
        Task.detached(priority: .utility) {
            let result = await AgentUsageInsightsLoader(
                timeZoneMode: .system,
                now: started,
                progress: { _ in }
            ).load()
            let elapsed = max(0, Int(Date().timeIntervalSince(started) * 1_000))
            let selfTests = debugUsageInsightsSelfTestFailures()
            switch result {
            case let .success(snapshots):
                let snapshot = snapshots[.combined] ?? .empty(scope: .combined, now: started)
                box.set(AgentUsageDebugProbe(
                    succeeded: true,
                    elapsedMilliseconds: elapsed,
                    parsedFileCount: snapshot.parsedFileCount,
                    tokenEventCount: snapshot.tokenEventCount,
                    todayTokens: snapshot.today.total,
                    last7DaysTokens: snapshot.last7Days.total,
                    diagnosticCodes: snapshot.diagnostics.map(\.code).sorted(),
                    selfTestFailures: selfTests,
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
                    diagnosticCodes: [],
                    selfTestFailures: selfTests,
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
                diagnosticCodes: ["usage_probe_timeout"],
                selfTestFailures: debugUsageInsightsSelfTestFailures(),
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
