import Foundation
import Darwin
import CommonCrypto
import LocalAuthentication
import os
import Security
import SQLite3
import SwiftUI

struct ProviderQuotaWindow: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case fiveHour
        case weekly
        case monthly
        case extra
    }

    let id: String
    let kind: Kind
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct ProviderQuotaSnapshot: Identifiable, Codable {
    let id: String
    let providerName: String
    let planName: String?
    let accountLabel: String?
    let credits: Double?
    let windows: [ProviderQuotaWindow]
    let resetCredits: ProviderQuotaResetCredits?
    let updatedAt: Date
    let source: String
    let errorMessage: String?
    let setupHint: String?
    let isSetupNotice: Bool
    /// `true` when quota values come from the last successful refresh because
    /// the latest attempt did not return a trustworthy provider snapshot.
    let isStale: Bool
    /// The wall-clock time of the refresh that most recently produced the
    /// authoritative values displayed by this snapshot.
    let lastSuccessfulAt: Date?
    /// The latest refresh diagnostic. Kept separate from `errorMessage` so a
    /// stale last-known-good snapshot remains renderable by existing clients.
    let refreshErrorMessage: String?
    /// Whether the provider response authoritatively described its quota
    /// topology. This is false for transport failures and ambiguous Codex
    /// window payloads, even when diagnostic or extra-window data is present.
    let quotaReadSucceeded: Bool

    enum Freshness: String, Codable {
        case fresh
        case stale
        case unavailable
    }

    var freshness: Freshness {
        if isStale { return .stale }
        return quotaReadSucceeded ? .fresh : .unavailable
    }

    var isFresh: Bool { freshness == .fresh }

    init(
        id: String,
        providerName: String,
        planName: String?,
        accountLabel: String?,
        credits: Double?,
        windows: [ProviderQuotaWindow],
        resetCredits: ProviderQuotaResetCredits?,
        updatedAt: Date,
        source: String,
        errorMessage: String?,
        setupHint: String?,
        isSetupNotice: Bool,
        isStale: Bool = false,
        lastSuccessfulAt: Date? = nil,
        refreshErrorMessage: String? = nil,
        quotaReadSucceeded: Bool? = nil
    ) {
        self.id = id
        self.providerName = providerName
        self.planName = planName
        self.accountLabel = accountLabel
        self.credits = credits
        self.windows = windows
        self.resetCredits = resetCredits
        self.updatedAt = updatedAt
        self.source = source
        self.errorMessage = errorMessage
        self.setupHint = setupHint
        self.isSetupNotice = isSetupNotice
        self.isStale = isStale
        self.lastSuccessfulAt = lastSuccessfulAt
        self.refreshErrorMessage = refreshErrorMessage
        self.quotaReadSucceeded = quotaReadSucceeded
            ?? (!isSetupNotice && (!windows.isEmpty || resetCredits != nil || credits != nil))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case providerName
        case planName
        case accountLabel
        case credits
        case windows
        case resetCredits
        case updatedAt
        case source
        case errorMessage
        case setupHint
        case isSetupNotice
        case isStale
        case lastSuccessfulAt
        case refreshErrorMessage
        case quotaReadSucceeded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        providerName = try container.decode(String.self, forKey: .providerName)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
        accountLabel = try container.decodeIfPresent(String.self, forKey: .accountLabel)
        credits = try container.decodeIfPresent(Double.self, forKey: .credits)
        windows = try container.decodeIfPresent([ProviderQuotaWindow].self, forKey: .windows) ?? []
        resetCredits = try container.decodeIfPresent(ProviderQuotaResetCredits.self, forKey: .resetCredits)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        source = try container.decode(String.self, forKey: .source)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        setupHint = try container.decodeIfPresent(String.self, forKey: .setupHint)
        isSetupNotice = try container.decodeIfPresent(Bool.self, forKey: .isSetupNotice) ?? false
        isStale = try container.decodeIfPresent(Bool.self, forKey: .isStale) ?? false
        lastSuccessfulAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt)
        refreshErrorMessage = try container.decodeIfPresent(String.self, forKey: .refreshErrorMessage)
        quotaReadSucceeded = try container.decodeIfPresent(Bool.self, forKey: .quotaReadSucceeded)
            ?? (!isSetupNotice && (!windows.isEmpty || resetCredits != nil || credits != nil))
    }

    var tightestWindow: ProviderQuotaWindow? {
        windows.min { lhs, rhs in
            lhs.remainingPercent < rhs.remainingPercent
        }
    }
}

struct ProviderQuotaResetCredits: Codable {
    let availableCount: Int
    let credits: [ProviderQuotaResetCredit]
    let updatedAt: Date

    var nextExpiringAvailableCredit: ProviderQuotaResetCredit? {
        credits
            .filter { $0.status == .available && ($0.expiresAt ?? .distantPast) > updatedAt }
            .min { lhs, rhs in
                guard let lhsDate = lhs.expiresAt else { return false }
                guard let rhsDate = rhs.expiresAt else { return true }
                return lhsDate < rhsDate
            }
    }
}

struct ProviderQuotaResetCredit: Identifiable, Codable {
    enum Status: String, Codable {
        case available
        case redeeming
        case redeemed
        case expired
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    let id: String
    let resetType: String
    let status: Status
    let grantedAt: Date?
    let expiresAt: Date?
    let redeemStartedAt: Date?
    let redeemedAt: Date?
    let title: String?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case resetType = "reset_type"
        case status
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case redeemStartedAt = "redeem_started_at"
        case redeemedAt = "redeemed_at"
        case title
        case description
    }
}

final class ProviderQuotaService: ObservableObject {
    @Published private(set) var snapshots: [ProviderQuotaSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var lastRefreshRequestedDate: Date?

    private static let minimumRefreshInterval: TimeInterval = 20
    private let provider = CodexBarQuotaProvider()
    private let logger = Logger(subsystem: "com.tracefence.app", category: "provider-quota")
    private var timer: Timer?

    var menuBarSummary: String? {
        snapshots
            .flatMap(\.windows)
            .filter(\.isAllowanceWindow)
            .min { lhs, rhs in lhs.remainingPercent < rhs.remainingPercent }
            .map { window in
                "\(window.shortTitle) \(Int(window.remainingPercent.rounded()))%"
            }
    }

    /// Pure reconciliation entry point used by the live refresh path and debug
    /// tests. Identity deliberately excludes plan/source so an OAuth fallback
    /// or plan-label change cannot split one provider account into two cards.
    static func reconcileQuotaSnapshots(
        previous: [ProviderQuotaSnapshot],
        incoming: [ProviderQuotaSnapshot],
        attemptedAt: Date
    ) -> [ProviderQuotaSnapshot] {
        let previousCandidates = previous.filter(\.canSeedQuotaContinuity)
        var previousByKey: [ProviderQuotaContinuityKey: ProviderQuotaSnapshot] = [:]
        for snapshot in previousCandidates {
            previousByKey[snapshot.continuityKey] = snapshot
        }

        let engineFailure = incoming.first(where: { $0.isProviderEngineNotice && $0.errorMessage != nil })
        var failedProviders: [String: String] = [:]
        var representedKeys = Set<ProviderQuotaContinuityKey>()
        var reconciled: [ProviderQuotaSnapshot] = []

        for snapshot in incoming {
            if snapshot.isSetupNotice || snapshot.isProviderEngineNotice {
                // Notices remain diagnostics only and never participate in
                // quota identity matching or last-known-good selection.
                reconciled.append(snapshot)
                continue
            }

            let key = snapshot.continuityKey
            if snapshot.quotaReadSucceeded {
                reconciled.append(snapshot.markedFresh(at: attemptedAt))
                representedKeys.insert(key)
                continue
            }

            let diagnostic = snapshot.refreshDiagnostic
            if key.account == nil {
                let providerHistory = previousCandidates.filter {
                    $0.continuityKey.provider == key.provider
                }
                if !providerHistory.isEmpty {
                    // A provider-level failure has no reliable account identity.
                    // Fan it out onto existing accounts instead of replacing a
                    // healthy multi-account set with one anonymous error card.
                    failedProviders[key.provider] = diagnostic
                    continue
                }
            }

            if let lastGood = previousByKey[key] {
                reconciled.append(lastGood.retainingQuota(after: snapshot, diagnostic: diagnostic))
                representedKeys.insert(key)
            } else {
                reconciled.append(snapshot)
            }
        }

        if let engineFailure {
            let diagnostic = engineFailure.refreshDiagnostic
            for snapshot in previousCandidates where !representedKeys.contains(snapshot.continuityKey) {
                reconciled.append(snapshot.retainingQuota(after: nil, diagnostic: diagnostic))
                representedKeys.insert(snapshot.continuityKey)
            }
        } else if !failedProviders.isEmpty {
            for snapshot in previousCandidates where !representedKeys.contains(snapshot.continuityKey) {
                let key = snapshot.continuityKey
                guard let diagnostic = failedProviders[key.provider] else { continue }
                reconciled.append(snapshot.retainingQuota(after: nil, diagnostic: diagnostic))
                representedKeys.insert(key)
            }
        }

        return reconciled
    }

    /// Deterministic protocol/continuity checks that can be called by a debug
    /// command or XCTest target without launching CodexBar or touching disk.
    static func debugQuotaSelfTestFailures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        let reversed = CodexOfficialWindowNormalizer.normalize(
            windowMinutes: [10_080, 300],
            hasWindowFields: true,
            hasMalformedWindow: false
        )
        expect(reversed.fiveHourIndex == 1, "300 minutes must classify as 5h regardless of slot order")
        expect(reversed.sevenDayIndex == 0, "10080 minutes must classify as 7d regardless of slot order")
        expect(reversed.isAuthoritative, "known exact durations should be authoritative")

        let duplicate = CodexOfficialWindowNormalizer.normalize(
            windowMinutes: [300, 300, 10_080],
            hasWindowFields: true,
            hasMalformedWindow: false
        )
        expect(duplicate.fiveHourIndex == nil, "duplicate 300-minute windows must fail closed")
        expect(!duplicate.isAuthoritative, "duplicate official windows must not be authoritative")

        let unknown = CodexOfficialWindowNormalizer.normalize(
            windowMinutes: [43_200, 10_080],
            hasWindowFields: true,
            hasMalformedWindow: false
        )
        expect(unknown.fiveHourIndex == nil, "unknown duration must not be labeled 5h")
        expect(unknown.sevenDayIndex == 1, "known 7d duration should survive beside an unknown window")
        expect(unknown.untrustedIndexes == [0], "unknown duration should remain explicitly unclassified")
        expect(!unknown.isAuthoritative, "unknown official duration must not define a trustworthy topology")

        let nullWindows = CodexOfficialWindowNormalizer.normalize(
            windowMinutes: [],
            hasWindowFields: true,
            hasMalformedWindow: false
        )
        expect(!nullWindows.isAuthoritative, "null or empty official windows must not replace trusted quota data")

        let missingWindows = CodexOfficialWindowNormalizer.normalize(
            windowMinutes: [],
            hasWindowFields: false,
            hasMalformedWindow: false
        )
        expect(!missingWindows.isAuthoritative, "missing official window fields must not be authoritative")

        let missingFiveHour = CodexOfficialWindowNormalizer.normalize(
            windowMinutes: [10_080],
            hasWindowFields: true,
            hasMalformedWindow: false
        )
        expect(!missingFiveHour.isAuthoritative, "a partial payload missing the 5h window must not evict complete quota data")

        let missingWeekly = CodexOfficialWindowNormalizer.normalize(
            windowMinutes: [300],
            hasWindowFields: true,
            hasMalformedWindow: false
        )
        expect(!missingWeekly.isAuthoritative, "a partial payload missing the 7d window must not evict complete quota data")

        let successfulAt = Date(timeIntervalSince1970: 1_800_000_000)
        let attemptedAt = successfulAt.addingTimeInterval(120)
        let weekly = ProviderQuotaWindow(
            id: "secondary",
            kind: .weekly,
            title: "Weekly quota",
            usedPercent: 25,
            resetsAt: successfulAt.addingTimeInterval(3_600),
            windowMinutes: 10_080
        )
        let resetCredits = ProviderQuotaResetCredits(
            availableCount: 1,
            credits: [],
            updatedAt: successfulAt
        )
        func snapshot(
            id: String,
            account: String?,
            windows: [ProviderQuotaWindow],
            resetCredits: ProviderQuotaResetCredits? = nil,
            error: String? = nil,
            setup: Bool = false,
            succeeded: Bool
        ) -> ProviderQuotaSnapshot {
            ProviderQuotaSnapshot(
                id: id,
                providerName: setup ? "Other Providers" : "Codex",
                planName: nil,
                accountLabel: account,
                credits: nil,
                windows: windows,
                resetCredits: resetCredits,
                updatedAt: successfulAt,
                source: setup ? "setup" : "auto",
                errorMessage: error,
                setupHint: nil,
                isSetupNotice: setup,
                lastSuccessfulAt: succeeded ? successfulAt : nil,
                quotaReadSucceeded: succeeded
            )
        }

        let accountA = snapshot(
            id: "codex-a",
            account: "a@example.com",
            windows: [weekly],
            resetCredits: resetCredits,
            succeeded: true
        )
        let accountB = snapshot(
            id: "codex-b",
            account: "b@example.com",
            windows: [weekly],
            succeeded: true
        )
        let anonymousFailure = snapshot(
            id: "codex-auto-failure",
            account: "auto",
            windows: [],
            error: "Codex quota read timed out",
            succeeded: false
        )
        let retainedAccounts = reconcileQuotaSnapshots(
            previous: [accountA, accountB],
            incoming: [anonymousFailure],
            attemptedAt: attemptedAt
        )
        expect(retainedAccounts.count == 2, "one anonymous failure must not replace multiple Codex accounts")
        expect(retainedAccounts.allSatisfy(\.isStale), "provider failure should mark every retained account stale")
        expect(retainedAccounts.allSatisfy { $0.windows == [weekly] }, "stale accounts should retain trusted windows")
        expect(retainedAccounts.first(where: { $0.id == "codex-a" })?.resetCredits?.availableCount == 1,
               "stale continuity should retain reset credits")

        let recovered = snapshot(
            id: "codex-a-new-source",
            account: "a@example.com",
            windows: [weekly],
            resetCredits: resetCredits,
            succeeded: true
        )
        let recoveredResult = reconcileQuotaSnapshots(
            previous: retainedAccounts,
            incoming: [recovered],
            attemptedAt: attemptedAt
        )
        expect(recoveredResult.count == 1 && recoveredResult[0].isFresh,
               "a successful account refresh should replace stale continuity data")
        expect(recoveredResult[0].lastSuccessfulAt == attemptedAt,
               "fresh recovery should publish the latest successful refresh time")

        let setupNotice = snapshot(
            id: "provider-setup-notice",
            account: "Optional setup",
            windows: [],
            error: "inactive providers",
            setup: true,
            succeeded: false
        )
        let noticeResult = reconcileQuotaSnapshots(
            previous: [],
            incoming: [setupNotice],
            attemptedAt: attemptedAt
        )
        expect(noticeResult.count == 1 && !noticeResult[0].hasReadableQuotaData,
               "setup notices must never count as available quota data")
        failures.append(contentsOf: ClaudeDesktopQuotaReader.debugSelfTestFailures())
        return failures
    }

#if DEBUG
    static func debugClaudeDesktopQuotaProbe() -> (snapshot: ProviderQuotaSnapshot?, diagnostic: String?) {
        switch ClaudeDesktopQuotaReader().fetchSnapshot() {
        case .snapshot(let snapshot):
            return (snapshot, nil)
        case .unavailable(let diagnostic):
            return (nil, diagnostic)
        }
    }

    static func debugProviderQuotaProbe() -> [ProviderQuotaSnapshot] {
        CodexBarQuotaProvider().fetch()
    }
#endif

    func start() {
        logger.info("Quota service start requested; snapshots=\(self.snapshots.count, privacy: .public) refreshing=\(self.isRefreshing, privacy: .public)")
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        }
        if snapshots.isEmpty, !isRefreshing {
            refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        if let lastRefreshDate, !force {
            let interval = Date().timeIntervalSince(lastRefreshDate)
            if interval < Self.minimumRefreshInterval {
                logger.debug("Quota refresh skipped by cooldown: remaining=\(Self.minimumRefreshInterval - interval, privacy: .public)")
                return
            }
        }
        isRefreshing = true
        lastRefreshRequestedDate = Date()
        logger.info("Quota refresh started")

        DispatchQueue.global(qos: .utility).async { [provider] in
            let result = provider.fetch()
            DispatchQueue.main.async {
                let completedAt = Date()
                self.snapshots = Self.reconcileQuotaSnapshots(
                    previous: self.snapshots,
                    incoming: result,
                    attemptedAt: completedAt
                ).sortedByQuotaReadiness()
                self.lastRefreshDate = completedAt
                self.isRefreshing = false
                let readableCount = self.snapshots.filter(\.hasReadableQuotaData).count
                if readableCount > 0 {
                    let menuSummary = self.menuBarSummary ?? "unavailable"
                    self.logger.info("Quota refresh completed: \(readableCount, privacy: .public) readable of \(result.count, privacy: .public) snapshots; menu=\(menuSummary, privacy: .private)")
                } else {
                    self.logger.error("Quota refresh completed without readable snapshots")
                }
            }
        }
    }

    func refreshCooldownRemaining() -> TimeInterval {
        guard let lastRefreshDate else { return 0 }
        return max(0, Self.minimumRefreshInterval - Date().timeIntervalSince(lastRefreshDate))
    }
}

private extension Array where Element == ProviderQuotaSnapshot {
    func sortedByQuotaReadiness() -> [ProviderQuotaSnapshot] {
        enumerated()
            .sorted { lhs, rhs in
                let lhsRank = lhs.element.quotaReadinessRank
                let rhsRank = rhs.element.quotaReadinessRank
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

private struct ProviderQuotaContinuityKey: Hashable {
    let provider: String
    let account: String?
}

private extension ProviderQuotaSnapshot {
    var quotaReadinessRank: Int {
        if hasReadableQuotaData { return 0 }
        if isProviderEngineNotice { return 1 }
        if isSetupNotice { return 3 }
        return 2
    }

    var hasReadableQuotaData: Bool {
        !isSetupNotice && (!windows.isEmpty || resetCredits != nil || credits != nil)
    }

    var isProviderEngineNotice: Bool {
        id.hasPrefix("provider-engine-")
    }

    var canSeedQuotaContinuity: Bool {
        !isSetupNotice
            && !isProviderEngineNotice
            && hasReadableQuotaData
            && (quotaReadSucceeded || isStale)
    }

    var continuityKey: ProviderQuotaContinuityKey {
        ProviderQuotaContinuityKey(
            provider: normalizedQuotaIdentityPart(providerName),
            account: normalizedQuotaAccount(accountLabel, source: source)
        )
    }

    var refreshDiagnostic: String {
        refreshErrorMessage
            ?? errorMessage
            ?? "The latest quota refresh did not return a trustworthy snapshot."
    }

    func markedFresh(at date: Date) -> ProviderQuotaSnapshot {
        ProviderQuotaSnapshot(
            id: id,
            providerName: providerName,
            planName: planName,
            accountLabel: accountLabel,
            credits: credits,
            windows: windows,
            resetCredits: resetCredits,
            updatedAt: updatedAt,
            source: source,
            errorMessage: errorMessage,
            setupHint: setupHint,
            isSetupNotice: isSetupNotice,
            isStale: false,
            lastSuccessfulAt: date,
            refreshErrorMessage: nil,
            quotaReadSucceeded: true
        )
    }

    func retainingQuota(
        after failedSnapshot: ProviderQuotaSnapshot?,
        diagnostic: String
    ) -> ProviderQuotaSnapshot {
        let retainedWindows = mergedContinuityWindows(with: failedSnapshot)
        return ProviderQuotaSnapshot(
            id: id,
            providerName: providerName,
            planName: planName,
            accountLabel: accountLabel,
            credits: failedSnapshot?.credits ?? credits,
            windows: retainedWindows,
            resetCredits: failedSnapshot?.resetCredits ?? resetCredits,
            updatedAt: updatedAt,
            source: source,
            // Existing UI treats errorMessage as mutually exclusive with data.
            // Keep the refresh error in its dedicated field so retained quota
            // remains visible while newer UI can render stale diagnostics.
            errorMessage: nil,
            setupHint: failedSnapshot?.setupHint ?? setupHint,
            isSetupNotice: false,
            isStale: true,
            lastSuccessfulAt: lastSuccessfulAt ?? updatedAt,
            refreshErrorMessage: diagnostic,
            quotaReadSucceeded: false
        )
    }

    func mergedContinuityWindows(with failedSnapshot: ProviderQuotaSnapshot?) -> [ProviderQuotaWindow] {
        guard let failedSnapshot, !failedSnapshot.windows.isEmpty else { return windows }
        guard providerName.caseInsensitiveCompare("Codex") == .orderedSame else { return windows }

        // Ambiguous official Codex slots never replace confirmed 5h/7d data,
        // but independently sourced extras (including Spark) may still update.
        var merged = windows
        for candidate in failedSnapshot.windows where !candidate.isPrimaryAllowanceWindow {
            if let index = merged.firstIndex(where: { $0.id == candidate.id }) {
                merged[index] = candidate
            } else {
                merged.append(candidate)
            }
        }
        return merged
    }
}

private func normalizedQuotaIdentityPart(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func normalizedQuotaAccount(_ accountLabel: String?, source: String) -> String? {
    guard let accountLabel else { return nil }
    let normalized = normalizedQuotaIdentityPart(accountLabel)
    guard !normalized.isEmpty else { return nil }
    let anonymousLabels = Set([
        "auto", "oauth", "web", "api", "cli", "bundle", "setup",
        normalizedQuotaIdentityPart(source)
    ])
    return anonymousLabels.contains(normalized) ? nil : normalized
}

extension ProviderQuotaWindow {
    var isPrimaryAllowanceWindow: Bool {
        id == "primary" || id == "secondary" || id == "tertiary"
    }

    var isScopedWeeklyAllowanceWindow: Bool {
        kind == .extra && windowMinutes == 10_080 && id.hasPrefix("claude-weekly-")
    }

    var isAllowanceWindow: Bool {
        isPrimaryAllowanceWindow || isScopedWeeklyAllowanceWindow
    }

    var scopedWeeklyAllowanceDisplayName: String? {
        guard isScopedWeeklyAllowanceWindow else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let opening = trimmedTitle.lastIndex(of: "("),
           trimmedTitle.last == ")",
           opening < trimmedTitle.index(before: trimmedTitle.endIndex) {
            let start = trimmedTitle.index(after: opening)
            let end = trimmedTitle.index(before: trimmedTitle.endIndex)
            let candidate = trimmedTitle[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty { return candidate }
        }

        let suffix = id.dropFirst("claude-weekly-".count)
        let words = suffix.split(separator: "-").map { String($0).capitalized }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    var shortTitle: String {
        if let scopedName = scopedWeeklyAllowanceDisplayName { return scopedName }
        switch kind {
        case .fiveHour: return "5h"
        case .weekly: return "7d"
        case .monthly: return "30d"
        case .extra: return title
        }
    }
}

private struct CodexOfficialWindowClassification {
    let fiveHourIndex: Int?
    let sevenDayIndex: Int?
    let untrustedIndexes: [Int]
    let fiveHourMatchCount: Int
    let sevenDayMatchCount: Int
    let isAuthoritative: Bool
}

private enum CodexOfficialWindowNormalizer {
    static let fiveHourMinutes = 300
    static let sevenDayMinutes = 10_080

    /// Classifies official primary/secondary/tertiary slots by exact protocol
    /// duration, never by slot order or a fuzzy duration range.
    static func normalize(
        windowMinutes: [Int?],
        hasWindowFields: Bool,
        hasMalformedWindow: Bool
    ) -> CodexOfficialWindowClassification {
        let fiveHourMatches = windowMinutes.indices.filter {
            windowMinutes[$0] == fiveHourMinutes
        }
        let sevenDayMatches = windowMinutes.indices.filter {
            windowMinutes[$0] == sevenDayMinutes
        }
        let unknown = windowMinutes.indices.filter { index in
            guard let minutes = windowMinutes[index] else { return true }
            return minutes != fiveHourMinutes && minutes != sevenDayMinutes
        }
        let untrusted = Set(
            unknown
                + (fiveHourMatches.count == 1 ? [] : fiveHourMatches)
                + (sevenDayMatches.count == 1 ? [] : sevenDayMatches)
        )

        return CodexOfficialWindowClassification(
            fiveHourIndex: fiveHourMatches.count == 1 ? fiveHourMatches[0] : nil,
            sevenDayIndex: sevenDayMatches.count == 1 ? sevenDayMatches[0] : nil,
            untrustedIndexes: untrusted.sorted(),
            fiveHourMatchCount: fiveHourMatches.count,
            sevenDayMatchCount: sevenDayMatches.count,
            isAuthoritative: hasWindowFields
                && !hasMalformedWindow
                && fiveHourMatches.count == 1
                && sevenDayMatches.count == 1
                && unknown.isEmpty
        )
    }
}

private struct ProviderQuotaWindowBuildResult {
    let windows: [ProviderQuotaWindow]
    let officialTopologyIsAuthoritative: Bool
    let diagnostic: String?
}

private struct CodexBarQuotaProvider {
    private let logger = Logger(subsystem: "com.tracefence.app", category: "provider-quota")

    func fetch() -> [ProviderQuotaSnapshot] {
        guard let executable = findExecutable() else {
            return [ProviderQuotaSnapshot(
                id: "provider-engine-missing",
                providerName: "TraceFence",
                planName: nil,
                accountLabel: nil,
                credits: nil,
                windows: [],
                resetCredits: nil,
                updatedAt: Date(),
                source: "bundle",
                errorMessage: "Quota monitor engine was not found. Please reinstall TraceFence.",
                setupHint: nil,
                isSetupNotice: false)]
        }

        let scopedAccess = ProviderQuotaSecurityScopedAccess()
        scopedAccess.start()
        defer { scopedAccess.stop() }

        let configs = readProviderConfigs(from: executable)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = quotaDateDecodingStrategy()
        let autoPayloads = readProviderPayloads(from: executable, configs: configs)
        var payloads = payloadsByMergingCodexSources(
            autoPayloads,
            with: readCodexAutoPayloads(from: executable, decoder: decoder)
        )
        payloads = payloadsByMergingCodexSources(
            payloads,
            with: readCodexOAuthPayloads(from: executable, decoder: decoder)
        )
        if !codexPayloadsHaveCompleteSupplementalData(payloads) {
            payloads = payloadsByMergingCodexSources(
                payloads,
                with: readCodexWebPayloads(from: executable, decoder: decoder)
            )
        }
        var snapshots = payloads.compactMap { payload -> ProviderQuotaSnapshot? in
            if let snapshot = makeSnapshot(from: payload, configs: configs) {
                return snapshot
            }
            return nil
        }
        if SandboxPaths.isDirectDistribution,
           isProviderLikelyInstalled("claude"),
           !snapshots.contains(where: {
               $0.providerName.caseInsensitiveCompare("Claude") == .orderedSame
                   && $0.hasReadableQuotaData
           })
        {
            switch ClaudeDesktopQuotaReader().fetchSnapshot() {
            case .snapshot(let desktopSnapshot):
                snapshots.removeAll {
                    $0.providerName.caseInsensitiveCompare("Claude") == .orderedSame
                        && !$0.hasReadableQuotaData
                }
                snapshots.append(desktopSnapshot)
                logger.info(
                    "Claude Desktop quota fallback returned \(desktopSnapshot.windows.count, privacy: .public) windows"
                )
            case .unavailable(let reason):
                logger.info("Claude Desktop quota fallback unavailable: \(reason, privacy: .public)")
            }
        }
        let codexSnapshots = snapshots.filter { $0.providerName.caseInsensitiveCompare("Codex") == .orderedSame }
        let sparkWindowCount = codexSnapshots.reduce(into: 0) { count, snapshot in
            count += snapshot.windows.filter(isCodexSparkWindow).count
        }
        let resetKnown = codexSnapshots.contains { $0.resetCredits != nil }
        logger.info(
            "Codex presentation snapshot: accounts=\(codexSnapshots.count, privacy: .public), spark-windows=\(sparkWindowCount, privacy: .public), reset-known=\(resetKnown, privacy: .public)"
        )
        if snapshots.isEmpty {
            return [ProviderQuotaSnapshot(
                id: "provider-engine-empty",
                providerName: "TraceFence",
                planName: nil,
                accountLabel: nil,
                credits: nil,
                windows: [],
                resetCredits: nil,
                updatedAt: Date(),
                source: "cli",
                errorMessage: "No quota data is available yet. Log in or enable the Agent you want to monitor.",
                setupHint: "Installed Agents such as Codex, Claude, and Cursor will show actionable diagnostics here.",
                isSetupNotice: false)]
        }
        return snapshots
    }

    private func findExecutable() -> URL? {
        let fileManager = FileManager.default
        let bundleURL = Bundle.main.bundleURL
        let helperExecutable = bundleURL
            .appendingPathComponent("Contents/Helpers/CodexBarHelper.app/Contents/MacOS/codexbar")
        let bundledCandidates = [
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("codexbar"),
            Bundle.main.url(forResource: "codexbar", withExtension: nil),
            helperExecutable
        ].compactMap(\.self)
        let candidates = bundledCandidates
            + (TraceFenceDistributionPolicy.currentChannel.isDirect
                ? directDistributionCodexBarCandidates()
                : [])

        return candidates.first { url in
            fileManager.isExecutableFile(atPath: url.path)
        }
    }

    private func directDistributionCodexBarCandidates() -> [URL] {
        let homeApplications = URL(fileURLWithPath: SandboxPaths.realHomeDirectory)
            .appendingPathComponent("Applications/TraceFence.app")
        let appCandidates = [
            URL(fileURLWithPath: "/Applications/TraceFence.app"),
            homeApplications
        ]

        return appCandidates.compactMap { appURL in
            guard let bundle = Bundle(url: appURL),
                  bundle.bundleIdentifier == SandboxPaths.directDistributionBundleID else {
                return nil
            }
            return appURL.appendingPathComponent("Contents/Resources/codexbar")
        }
    }

    private func readProviderPayloads(
        from executable: URL,
        configs: [String: CodexBarProviderConfigPayload]
    ) -> [CodexBarProviderPayload] {
        let providerIDs = quotaProviderIDs(configs: configs)
        guard !providerIDs.isEmpty else { return [] }

        let group = DispatchGroup()
        let lock = NSLock()
        var indexedPayloads: [(offset: Int, payloads: [CodexBarProviderPayload])] = []

        for (offset, providerID) in providerIDs.enumerated() {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let payloads = self.readSingleProviderPayload(
                    providerID,
                    from: executable,
                    configs: configs
                )
                lock.lock()
                indexedPayloads.append((offset, payloads))
                lock.unlock()
                group.leave()
            }
        }

        group.wait()
        return indexedPayloads
            .sorted { $0.offset < $1.offset }
            .flatMap(\.payloads)
    }

    private func readSingleProviderPayload(
        _ providerID: String,
        from executable: URL,
        configs: [String: CodexBarProviderConfigPayload]
    ) -> [CodexBarProviderPayload] {
        do {
            let data = try runCodexBarCommand(
                at: executable,
                arguments: [
                    "usage",
                    "--provider", providerID,
                    "--format", "json",
                    "--source", "auto"
                ],
                timeout: providerID == "codex" || providerID == "grok" ? 12 : 4
            )
            let providerDecoder = JSONDecoder()
            providerDecoder.dateDecodingStrategy = quotaDateDecodingStrategy()
            do {
                let payloads = try providerDecoder.decode([CodexBarProviderPayload].self, from: data)
                let readableCount = payloads.filter { $0.usage != nil || $0.credits != nil }.count
                let diagnostic = providerDiagnosticCategory(for: payloads)
                logger.info("Provider \(providerID, privacy: .public) returned \(payloads.count, privacy: .public) payloads, readable=\(readableCount, privacy: .public), diagnostic=\(diagnostic, privacy: .public)")
                return payloads
            } catch {
                logger.error("Provider \(providerID, privacy: .public) returned undecodable JSON")
                return [providerReadFailurePayload(
                    providerID,
                    error: CodexBarQuotaError.commandFailed("\(displayName(for: providerID)) quota response could not be decoded.")
                )]
            }
        } catch {
            logger.error("Provider \(providerID, privacy: .public) command failed")
            guard shouldSurfaceProviderReadFailure(providerID, config: configs[providerID]) else {
                return []
            }
            return [providerReadFailurePayload(providerID, error: error)]
        }
    }

    private func providerDiagnosticCategory(for payloads: [CodexBarProviderPayload]) -> String {
        let messages = payloads.compactMap { $0.error?.message.lowercased() }
        guard !messages.isEmpty else { return "none" }
        if messages.contains(where: { $0.contains("timed out") || $0.contains("读取超时") }) {
            return "timeout"
        }
        if messages.contains(where: { $0.contains("cookie") || $0.contains("session") || $0.contains("log in") || $0.contains("login") }) {
            return "login-session"
        }
        if messages.contains(where: { $0.contains("api key") || $0.contains("credential") }) {
            return "credentials"
        }
        if messages.contains(where: { $0.contains("not installed") || $0.contains("not on path") || $0.contains("cli") }) {
            return "cli-unavailable"
        }
        if messages.contains(where: { $0.contains("no available fetch strategy") }) {
            return "no-fetch-strategy"
        }
        return "other"
    }

    private func quotaProviderIDs(configs: [String: CodexBarProviderConfigPayload]) -> [String] {
        let configured = configs.values
            .filter { $0.enabled || $0.defaultEnabled }
            .map(\.provider)
        let installed = configs.keys.filter { isProviderLikelyInstalled($0) }
        let fallbackInstalled = [
            "codex", "claude", "cursor", "grok", "gemini", "openrouter",
            "qwen", "amp", "opencode", "goose", "aider"
        ].filter(isProviderLikelyInstalled)
        return stableUnique(["codex"] + configured + installed + fallbackInstalled)
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private func shouldSurfaceProviderReadFailure(
        _ providerID: String,
        config: CodexBarProviderConfigPayload?
    ) -> Bool {
        providerID == "codex" || config?.enabled == true || isProviderLikelyInstalled(providerID)
    }

    private func providerReadFailurePayload(_ providerID: String, error: Error) -> CodexBarProviderPayload {
        let raw = sanitizedMessage(error.localizedDescription)
        let message = raw.lowercased().contains("timed out")
            ? "\(displayName(for: providerID)) 额度读取超时，TraceFence 已跳过该 Provider，其它额度会继续显示。"
            : raw
        return CodexBarProviderPayload(
            provider: providerID,
            account: nil,
            version: nil,
            source: "auto",
            usage: nil,
            credits: nil,
            error: CodexBarErrorPayload(message: message)
        )
    }

    private func readCodexOAuthPayloads(
        from executable: URL,
        decoder: JSONDecoder
    ) -> [CodexBarProviderPayload] {
        do {
            let data = try runCodexBarCommand(
                at: executable,
                arguments: [
                    "usage",
                    "--provider", "codex",
                    "--format", "json",
                    "--source", "oauth",
                    "--all-accounts"
                ],
                timeout: 20
            )
            let payloads = try decoder.decode([CodexBarProviderPayload].self, from: data)
            logCodexSupplementalPayloads(payloads, source: "oauth")
            return payloads
        } catch {
            logger.error("Codex supplemental source oauth failed")
            return []
        }
    }

    private func readCodexAutoPayloads(
        from executable: URL,
        decoder: JSONDecoder
    ) -> [CodexBarProviderPayload] {
        do {
            let data = try runCodexBarCommand(
                at: executable,
                arguments: [
                    "usage",
                    "--provider", "codex",
                    "--format", "json",
                    "--source", "auto",
                    "--all-accounts"
                ],
                timeout: 20
            )
            let payloads = try decoder.decode([CodexBarProviderPayload].self, from: data)
            logCodexSupplementalPayloads(payloads, source: "auto")
            return payloads
        } catch {
            logger.error("Codex supplemental source auto failed")
            return []
        }
    }

    private func readCodexWebPayloads(
        from executable: URL,
        decoder: JSONDecoder
    ) -> [CodexBarProviderPayload] {
        do {
            let data = try runCodexBarCommand(
                at: executable,
                arguments: [
                    "usage",
                    "--provider", "codex",
                    "--format", "json",
                    "--source", "web",
                    "--all-accounts"
                ],
                timeout: 20
            )
            let payloads = try decoder.decode([CodexBarProviderPayload].self, from: data)
            logCodexSupplementalPayloads(payloads, source: "web")
            return payloads
        } catch {
            logger.error("Codex supplemental source web failed")
            return []
        }
    }

    private func logCodexSupplementalPayloads(
        _ payloads: [CodexBarProviderPayload],
        source: String
    ) {
        let codexPayloads = payloads.filter { $0.provider.lowercased() == "codex" }
        let knownExtraCount = codexPayloads.reduce(into: 0) { count, payload in
            count += (payload.usage?.extraRateWindows ?? []).filter(\.usageKnown).count
        }
        let resetKnown = codexPayloads.contains { $0.usage?.codexResetCredits != nil }
        let resetAvailable = codexPayloads.compactMap { $0.usage?.codexResetCredits?.availableCount }.max()
        logger.info(
            "Codex supplemental source \(source, privacy: .public) returned \(codexPayloads.count, privacy: .public) payloads, known-extra=\(knownExtraCount, privacy: .public), reset-known=\(resetKnown, privacy: .public), reset-available=\(resetAvailable ?? -1, privacy: .private)"
        )
    }

    private func payloadsByMergingCodexSources(
        _ basePayloads: [CodexBarProviderPayload],
        with supplementalPayloads: [CodexBarProviderPayload]
    ) -> [CodexBarProviderPayload] {
        let codexSupplementalPayloads = supplementalPayloads.filter { payload in
            payload.provider.lowercased() == "codex"
                && (payload.usage != nil || payload.credits != nil || payload.error != nil)
        }
        guard codexSupplementalPayloads.contains(where: { $0.usage != nil || $0.credits != nil }) else {
            return basePayloads
        }

        var merged = basePayloads
        for supplemental in codexSupplementalPayloads {
            if let index = matchingCodexPayloadIndex(for: supplemental, in: merged) {
                merged[index] = mergedCodexPayload(merged[index], supplemental)
            } else {
                merged.append(supplemental)
            }
        }
        return merged
    }

    private func matchingCodexPayloadIndex(
        for supplemental: CodexBarProviderPayload,
        in payloads: [CodexBarProviderPayload]
    ) -> Int? {
        let codexIndexes = payloads.indices.filter { payloads[$0].provider.lowercased() == "codex" }
        let key = codexMergeKey(for: supplemental)
        if let index = codexIndexes.first(where: { codexMergeKey(for: payloads[$0]) == key }) {
            return index
        }
        return codexIndexes.count == 1 ? codexIndexes.first : nil
    }

    private func codexMergeKey(for payload: CodexBarProviderPayload) -> String {
        normalizedSnapshotIDPart(accountLabel(from: payload) ?? "codex")
    }

    private func mergedCodexPayload(
        _ base: CodexBarProviderPayload,
        _ supplemental: CodexBarProviderPayload
    ) -> CodexBarProviderPayload {
        let usage = mergedCodexUsage(base.usage, supplemental.usage)
        let credits = base.credits ?? supplemental.credits
        return CodexBarProviderPayload(
            provider: base.provider,
            account: base.account ?? supplemental.account,
            version: base.version ?? supplemental.version,
            source: base.source,
            usage: usage,
            credits: credits,
            error: usage == nil && credits == nil ? (base.error ?? supplemental.error) : nil
        )
    }

    private func mergedCodexUsage(
        _ base: CodexBarUsagePayload?,
        _ supplemental: CodexBarUsagePayload?
    ) -> CodexBarUsagePayload? {
        guard let base else { return supplemental }
        guard let supplemental else { return base }

        let hasCleanOfficialSource = [base, supplemental].contains {
            $0.hasOfficialWindowFields && !$0.hasMalformedOfficialWindow
        }

        return CodexBarUsagePayload(
            primary: base.primary ?? supplemental.primary,
            secondary: base.secondary ?? supplemental.secondary,
            tertiary: base.tertiary ?? supplemental.tertiary,
            extraRateWindows: mergedExtraRateWindows(base.extraRateWindows, supplemental.extraRateWindows),
            codexResetCredits: richerResetCredits(base.codexResetCredits, supplemental.codexResetCredits),
            updatedAt: max(base.updatedAt, supplemental.updatedAt),
            identity: base.identity ?? supplemental.identity,
            accountEmail: base.accountEmail ?? supplemental.accountEmail,
            loginMethod: base.loginMethod ?? supplemental.loginMethod,
            hasOfficialWindowFields: base.hasOfficialWindowFields || supplemental.hasOfficialWindowFields,
            hasMalformedOfficialWindow: !hasCleanOfficialSource
                && (base.hasMalformedOfficialWindow || supplemental.hasMalformedOfficialWindow)
        )
    }

    private func mergedExtraRateWindows(
        _ base: [CodexBarNamedRateWindowPayload]?,
        _ supplemental: [CodexBarNamedRateWindowPayload]?
    ) -> [CodexBarNamedRateWindowPayload]? {
        var windows = base ?? []
        for candidate in supplemental ?? [] {
            if let index = windows.firstIndex(where: { normalizedExtraWindowKey($0) == normalizedExtraWindowKey(candidate) }) {
                if !windows[index].usageKnown && candidate.usageKnown {
                    windows[index] = candidate
                }
            } else {
                windows.append(candidate)
            }
        }
        return windows.isEmpty ? nil : windows
    }

    private func normalizedExtraWindowKey(_ window: CodexBarNamedRateWindowPayload) -> String {
        let raw = window.id.isEmpty ? window.title : window.id
        return raw.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private func richerResetCredits(
        _ base: ProviderQuotaResetCredits?,
        _ supplemental: ProviderQuotaResetCredits?
    ) -> ProviderQuotaResetCredits? {
        guard let base else { return supplemental }
        guard let supplemental else { return base }
        if supplemental.availableCount > base.availableCount { return supplemental }
        if supplemental.credits.count > base.credits.count { return supplemental }
        return base.updatedAt >= supplemental.updatedAt ? base : supplemental
    }

    private func codexPayloadsHaveCompleteSupplementalData(_ payloads: [CodexBarProviderPayload]) -> Bool {
        let codexPayloads = payloads.filter {
            $0.provider.lowercased() == "codex" && $0.usage != nil
        }
        guard !codexPayloads.isEmpty else { return false }

        return codexPayloads.allSatisfy { payload in
            guard let usage = payload.usage else { return false }
            let hasSparkWindow = (usage.extraRateWindows ?? []).contains { window in
                guard window.usageKnown else { return false }
                let normalized = "\(window.id) \(window.title)"
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .lowercased()
                return normalized.contains("codex") && normalized.contains("spark")
            }
            return hasSparkWindow && usage.codexResetCredits != nil
        }
    }

    private func isCodexSparkWindow(_ window: ProviderQuotaWindow) -> Bool {
        let normalized = "\(window.id) \(window.title)"
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
        return normalized.contains("codex") && normalized.contains("spark")
    }

    private func readProviderConfigs(from executable: URL) -> [String: CodexBarProviderConfigPayload] {
        do {
            let data = try runCodexBarCommand(
                at: executable,
                arguments: ["config", "providers", "--format", "json"],
                timeout: 8
            )
            let configs = try JSONDecoder().decode([CodexBarProviderConfigPayload].self, from: data)
            return Dictionary(uniqueKeysWithValues: configs.map { ($0.provider, $0) })
        } catch {
            return [:]
        }
    }

    private func runCodexBarCommand(
        at executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        process.environment = processEnvironment(for: executable)

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        var didTimeOut = false
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            didTimeOut = true
            process.terminate()
            let terminateDeadline = Date().addingTimeInterval(1.5)
            while process.isRunning, Date() < terminateDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if didTimeOut {
            throw CodexBarQuotaError.commandFailed("Quota monitor engine timed out. TraceFence stopped this read automatically.")
        }
        if !data.isEmpty {
            return data
        }
        if process.terminationReason != .exit || process.terminationStatus != 0 {
            let fallback = "Quota monitor engine stopped before returning data. Please update or reinstall TraceFence."
            let value = (message?.isEmpty == false) ? message! : fallback
            throw CodexBarQuotaError.commandFailed(sanitizedMessage(value))
        }

        let value = (message?.isEmpty == false) ? message! : "Quota monitor engine produced no output."
        throw CodexBarQuotaError.commandFailed(sanitizedMessage(value))
    }

    private func makeSnapshot(
        from payload: CodexBarProviderPayload,
        configs: [String: CodexBarProviderConfigPayload]
    ) -> ProviderQuotaSnapshot? {
        let now = Date()
        let usage = payload.usage
        let windowBuild = makeWindows(from: usage, provider: payload.provider)
        let windows = windowBuild.windows
        let resetCredits = normalizedResetCredits(usage?.codexResetCredits)
        let errorMessage = displayErrorMessage(for: payload)
        let config = configs[payload.provider]
        let isCodex = payload.provider.caseInsensitiveCompare("codex") == .orderedSame
        let quotaReadSucceeded = isCodex
            ? windowBuild.officialTopologyIsAuthoritative
            : (!windows.isEmpty || payload.credits != nil || resetCredits != nil)

        guard !windows.isEmpty
                || payload.credits != nil
                || resetCredits != nil
                || (isCodex && windowBuild.officialTopologyIsAuthoritative)
                || shouldShowDiagnostic(for: payload, config: config)
        else {
            return nil
        }

        return ProviderQuotaSnapshot(
            id: snapshotID(from: payload),
            providerName: displayName(for: payload.provider),
            planName: planName(from: payload),
            accountLabel: accountLabel(from: payload),
            credits: payload.credits?.remaining,
            windows: windows,
            resetCredits: resetCredits,
            updatedAt: usage?.updatedAt ?? payload.credits?.updatedAt ?? resetCredits?.updatedAt ?? now,
            source: payload.source,
            errorMessage: windows.isEmpty && resetCredits == nil ? errorMessage : nil,
            setupHint: windows.isEmpty && resetCredits == nil ? setupHint(for: payload) : nil,
            isSetupNotice: false,
            refreshErrorMessage: quotaReadSucceeded ? nil : (windowBuild.diagnostic ?? errorMessage),
            quotaReadSucceeded: quotaReadSucceeded)
    }

    private func setupNotice(count: Int) -> ProviderQuotaSnapshot {
        ProviderQuotaSnapshot(
            id: "provider-setup-notice",
            providerName: "Other Providers",
            planName: nil,
            accountLabel: "Optional setup",
            credits: nil,
            windows: [],
            resetCredits: nil,
            updatedAt: Date(),
            source: "setup",
            errorMessage: "\(count) inactive providers are collapsed.",
            setupHint: "Install or log in to the matching Agent, or enable its provider to show detailed diagnostics.",
            isSetupNotice: true)
    }

    private func shouldShowDiagnostic(
        for payload: CodexBarProviderPayload,
        config: CodexBarProviderConfigPayload?
    ) -> Bool {
        guard payload.error != nil else { return false }
        if config?.enabled == true { return true }
        return isProviderLikelyInstalled(payload.provider)
    }

    private func setupHint(for payload: CodexBarProviderPayload) -> String? {
        let provider = payload.provider.lowercased()
        let message = payload.error?.message.lowercased() ?? ""
        if provider == "grok", message.contains("no available fetch strategy") {
            return "Grok is installed, but its login data is not readable. Authorize your Home or ~/.grok folder in TraceFence, then refresh. If it still fails, run `grok login`."
        }
        if message.contains("api key") {
            return "Configure the \(displayName(for: provider)) API key or account credentials, then refresh the TraceFence provider monitor."
        }
        if message.contains("timed out") || message.contains("读取超时") {
            return "\(displayName(for: provider)) 本次读取超时，TraceFence 已跳过它，不影响其它 Provider 显示。稍后可刷新，或检查该 CLI 是否能正常启动。"
        }
        if message.contains("cli is not installed") || message.contains("not on path") {
            if isProviderLikelyInstalled(provider) {
                return "\(displayName(for: provider)) appears to be installed, but the quota reader cannot run its CLI. Reinstall or repair the \(displayName(for: provider)) CLI so it works directly in Terminal."
            }
            return "This provider is enabled, but its CLI was not found. Install the \(displayName(for: provider)) CLI and make sure it is on PATH."
        }
        if message.contains("session") || message.contains("log in") || message.contains("cookies") {
            return "The related Agent was detected, but no readable login session was found. Log in to \(displayName(for: provider)), authorize its data folder in TraceFence, then refresh the quota monitor."
        }
        if provider == "cursor" {
            return "Cursor was detected, but no usable session was found. Log in to Cursor, authorize the matching data folder in TraceFence, then refresh the quota monitor."
        }
        if provider == "claude" {
            return "Claude was detected. Make sure the Claude CLI runs, then finish signing in to Claude."
        }
        return "\(displayName(for: provider)) may be installed, but login, API key, or dependency setup is still missing."
    }

    private func displayErrorMessage(for payload: CodexBarProviderPayload) -> String? {
        guard let rawMessage = payload.error?.message else { return nil }
        let provider = payload.provider.lowercased()
        let message = rawMessage.lowercased()
        if message.contains("api key") {
            return "\(displayName(for: provider)) API key is not configured"
        }
        if message.contains("timed out") || message.contains("读取超时") {
            return "\(displayName(for: provider)) 额度读取超时"
        }
        if message.contains("cli is not installed") || message.contains("not on path") {
            return isProviderLikelyInstalled(provider)
                ? "\(displayName(for: provider)) CLI is temporarily unavailable"
                : "\(displayName(for: provider)) CLI is not installed"
        }
        if provider == "cursor", message.contains("session") {
            return "No Cursor login session found"
        }
        if message.contains("cookies") || message.contains("log in") || message.contains("session") {
            return "No usable \(displayName(for: provider)) login session found"
        }
        if message.contains("no available fetch strategy") {
            return "No available fetch strategy for \(displayName(for: provider))"
        }
        return sanitizedMessage(rawMessage)
    }

    private func isProviderLikelyInstalled(_ provider: String) -> Bool {
        AgentIntegrationCatalog.isProviderLikelyInstalled(provider)
    }

    private func processEnvironment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let homeURL = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
        let fallbackPath = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            homeURL.appendingPathComponent(".local/bin").path,
            homeURL.appendingPathComponent(".grok/bin").path,
            homeURL.appendingPathComponent(".mavis/bin").path
        ].joined(separator: ":")
        environment["PATH"] = fallbackPath
        environment["HOME"] = SandboxPaths.realHomeDirectory
        if environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            environment["CODEX_HOME"] = homeURL.appendingPathComponent(".codex", isDirectory: true).path
        }
        // Foundation resolves homeDirectoryForCurrentUser to the app container inside
        // a sandboxed helper. Codex and Grok honor explicit home variables, so point
        // them at user-authorized data directories instead of the container's empty homes.
        if environment["GROK_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            environment["GROK_HOME"] = homeURL.appendingPathComponent(".grok", isDirectory: true).path
        }
        environment["USER"] = NSUserName()
        environment["LOGNAME"] = NSUserName()
        [
            "TRACEFENCE",
            "TRACEFENCE_GEO_PROFILE_ENABLED",
            "TRACEFENCE_GEO_PROFILE_NAME",
            "TRACEFENCE_GEO_PROFILE_DIR",
            "TRACEFENCE_GEO_BIN_DIR",
            "TRACEFENCE_GEO_SHELL_DIR",
            "TRACEFENCE_PROFILE_URL",
            "TRACEFENCE_PROFILE_CONTEXT_URL",
            "TRACEFENCE_RAW_PROFILE_URL",
            "TRACEFENCE_PROFILE_PATH",
            "TRACEFENCE_PROFILE_CONTEXT_PATH",
            "TRACEFENCE_RAW_PROFILE_PATH",
            "TRACEFENCE_SKIP_PROXY",
            "TRACEFENCE_GROK_MANAGED_SHIM",
            "GROK_TRACEFENCE_PROFILE_URL",
            "GROK_TRACEFENCE_PROFILE_CONTEXT_URL",
            "ZDOTDIR",
            "BASH_ENV",
            "ENV",
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "http_proxy",
            "https_proxy",
            "all_proxy",
            "TZ",
            "LANG",
            "LC_ALL",
            "LC_CTYPE",
            "LC_MESSAGES",
            "LANGUAGE",
            "AppleLocale",
            "AppleLanguages"
        ].forEach { environment.removeValue(forKey: $0) }
        if isDirectDistributionCodexBar(executable) {
            environment.removeValue(forKey: "APP_SANDBOX_CONTAINER_ID")
            environment["TRACEFENCE_PROVIDER_ENGINE"] = "direct-distribution"
        }
        return environment
    }

    private func isDirectDistributionCodexBar(_ executable: URL) -> Bool {
        directDistributionCodexBarCandidates()
            .contains { $0.standardizedFileURL.path == executable.standardizedFileURL.path }
    }

    private func makeWindows(
        from usage: CodexBarUsagePayload?,
        provider: String
    ) -> ProviderQuotaWindowBuildResult {
        guard let usage else {
            return ProviderQuotaWindowBuildResult(
                windows: [],
                officialTopologyIsAuthoritative: false,
                diagnostic: "The quota response did not include a usage payload."
            )
        }

        let officialCandidates: [(slot: String, fallback: String, payload: CodexBarRateWindowPayload)] = [
            usage.primary.map { ("primary", "Current window", $0) },
            usage.secondary.map { ("secondary", "Long-term window", $0) },
            usage.tertiary.map { ("tertiary", "Additional window", $0) }
        ].compactMap { $0 }

        var windows: [ProviderQuotaWindow] = []
        var authoritative = true
        var diagnostic: String?

        if provider.caseInsensitiveCompare("codex") == .orderedSame {
            let classification = CodexOfficialWindowNormalizer.normalize(
                windowMinutes: officialCandidates.map { $0.payload.windowMinutes },
                hasWindowFields: usage.hasOfficialWindowFields,
                hasMalformedWindow: usage.hasMalformedOfficialWindow
            )
            authoritative = classification.isAuthoritative

            if let index = classification.fiveHourIndex {
                let candidate = officialCandidates[index]
                windows.append(makeExactCodexWindow(
                    id: "primary",
                    title: "5-hour quota",
                    kind: .fiveHour,
                    payload: candidate.payload
                ))
            }
            if let index = classification.sevenDayIndex {
                let candidate = officialCandidates[index]
                windows.append(makeExactCodexWindow(
                    id: "secondary",
                    title: "Weekly quota",
                    kind: .weekly,
                    payload: candidate.payload
                ))
            }
            for index in classification.untrustedIndexes {
                let candidate = officialCandidates[index]
                windows.append(makeUnclassifiedCodexWindow(candidate))
            }

            diagnostic = codexWindowDiagnostic(
                classification,
                hasWindowFields: usage.hasOfficialWindowFields,
                hasMalformedWindow: usage.hasMalformedOfficialWindow
            )
        } else {
            for candidate in officialCandidates {
                windows.append(makeWindow(
                    id: candidate.slot,
                    title: title(for: candidate.payload, fallback: candidate.fallback),
                    payload: candidate.payload
                ))
            }
        }

        // Named extra windows are a separate protocol surface. Keep their
        // existing behavior (including Codex Spark) independent from official
        // Codex primary/secondary/tertiary topology validation.
        for extra in usage.extraRateWindows ?? [] where extra.usageKnown {
            windows.append(makeWindow(id: extra.id, title: extra.title, payload: extra.window))
        }
        return ProviderQuotaWindowBuildResult(
            windows: windows,
            officialTopologyIsAuthoritative: authoritative,
            diagnostic: diagnostic
        )
    }

    private func makeExactCodexWindow(
        id: String,
        title: String,
        kind: ProviderQuotaWindow.Kind,
        payload: CodexBarRateWindowPayload
    ) -> ProviderQuotaWindow {
        ProviderQuotaWindow(
            id: id,
            kind: kind,
            title: title,
            usedPercent: max(0, min(100, payload.usedPercent)),
            resetsAt: payload.resetsAt,
            windowMinutes: payload.windowMinutes
        )
    }

    private func makeUnclassifiedCodexWindow(
        _ candidate: (slot: String, fallback: String, payload: CodexBarRateWindowPayload)
    ) -> ProviderQuotaWindow {
        let duration = candidate.payload.windowMinutes.map { " · \($0) min" } ?? ""
        return ProviderQuotaWindow(
            id: "codex-official-unclassified-\(candidate.slot)",
            kind: .extra,
            title: "\(candidate.fallback) · unclassified\(duration)",
            usedPercent: max(0, min(100, candidate.payload.usedPercent)),
            resetsAt: candidate.payload.resetsAt,
            windowMinutes: candidate.payload.windowMinutes
        )
    }

    private func codexWindowDiagnostic(
        _ classification: CodexOfficialWindowClassification,
        hasWindowFields: Bool,
        hasMalformedWindow: Bool
    ) -> String? {
        var reasons: [String] = []
        if !hasWindowFields { reasons.append("official window fields were missing") }
        if hasMalformedWindow { reasons.append("an official window was malformed") }
        if classification.fiveHourMatchCount > 1 { reasons.append("the 300-minute window was duplicated") }
        if classification.sevenDayMatchCount > 1 { reasons.append("the 10080-minute window was duplicated") }
        if classification.fiveHourMatchCount == 0 { reasons.append("the 300-minute window was missing") }
        if classification.sevenDayMatchCount == 0 { reasons.append("the 10080-minute window was missing") }
        if !classification.untrustedIndexes.isEmpty,
           classification.fiveHourMatchCount <= 1,
           classification.sevenDayMatchCount <= 1 {
            reasons.append("an official window had an unknown or missing duration")
        }
        guard !reasons.isEmpty else { return nil }
        return "Codex quota topology was not authoritative because \(reasons.joined(separator: ", "))."
    }

    private func normalizedResetCredits(
        _ resetCredits: ProviderQuotaResetCredits?
    ) -> ProviderQuotaResetCredits? {
        guard let resetCredits, resetCredits.availableCount >= 0 else { return nil }
        return resetCredits
    }

    private func makeWindow(id: String, title: String, payload: CodexBarRateWindowPayload) -> ProviderQuotaWindow {
        ProviderQuotaWindow(
            id: id,
            kind: kind(for: payload.windowMinutes),
            title: title,
            usedPercent: max(0, min(100, payload.usedPercent)),
            resetsAt: payload.resetsAt,
            windowMinutes: payload.windowMinutes)
    }

    private func kind(for minutes: Int?) -> ProviderQuotaWindow.Kind {
        guard let minutes else { return .extra }
        if minutes <= 300 { return .fiveHour }
        if minutes <= 10_080 { return .weekly }
        if minutes <= 45_000 { return .monthly }
        return .extra
    }

    private func title(for window: CodexBarRateWindowPayload, fallback: String) -> String {
        guard let minutes = window.windowMinutes else { return fallback }
        if minutes <= 300 { return "5-hour quota" }
        if minutes <= 10_080 { return "Weekly quota" }
        if minutes <= 45_000 { return "Monthly quota" }
        return fallback
    }

    private func displayName(for provider: String) -> String {
        let names = [
            "codex": "Codex",
            "openai": "OpenAI",
            "claude": "Claude",
            "cursor": "Cursor",
            "gemini": "Gemini",
            "grok": "Grok",
            "perplexity": "Perplexity",
            "openrouter": "OpenRouter",
            "poe": "Poe",
            "mistral": "Mistral",
            "deepseek": "DeepSeek",
            "manus": "Manus",
            "amp": "Amp",
            "factory": "Factory",
            "kiro": "Kiro",
            "bedrock": "Bedrock",
            "vertexai": "Vertex AI"
        ]
        if let name = names[provider.lowercased()] {
            return name
        }
        return provider
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func planName(from payload: CodexBarProviderPayload) -> String? {
        payload.usage?.identity?.loginMethod ?? payload.usage?.loginMethod ?? payload.version
    }

    private func accountLabel(from payload: CodexBarProviderPayload) -> String? {
        payload.usage?.identity?.accountEmail
            ?? payload.usage?.accountEmail
            ?? payload.account
            ?? payload.source
    }

    private func snapshotID(from payload: CodexBarProviderPayload) -> String {
        let account = accountLabel(from: payload) ?? "unknown-account"
        let plan = planName(from: payload) ?? "unknown-plan"
        return [
            payload.provider,
            payload.source,
            account,
            plan
        ]
        .map(normalizedSnapshotIDPart)
        .filter { !$0.isEmpty }
        .joined(separator: "-")
    }

    private func normalizedSnapshotIDPart(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar).lowercased() : "-"
        }
        .joined()
        .split(separator: "-")
        .joined(separator: "-")
    }

    private func quotaDateDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
        .custom { @Sendable decoder in
            try Self.decodeDate(from: decoder)
        }
    }

    private static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
    }
}

private struct ClaudeDesktopQuotaReader {
    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    enum ReadResult {
        case snapshot(ProviderQuotaSnapshot)
        case unavailable(String)
    }

    private struct Organization: Decodable {
        let uuid: String?
        let id: String?

        private enum CodingKeys: String, CodingKey {
            case uuid
            case id
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            uuid = try? container.decodeIfPresent(String.self, forKey: .uuid)
            if let stringID = try? container.decodeIfPresent(String.self, forKey: .id) {
                id = stringID
            } else if let integerID = try? container.decodeIfPresent(Int64.self, forKey: .id) {
                id = String(integerID)
            } else {
                id = nil
            }
        }

        var identifier: String? {
            let candidate = uuid ?? id
            guard let candidate, !candidate.isEmpty else { return nil }
            return candidate
        }
    }

    private struct UsageWindow: Decodable {
        let utilization: Double?
        let resetsAt: String?

        private enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    private struct UsageLimitScope: Decodable {
        struct Model: Decodable {
            let displayName: String?

            private enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        let model: Model?
    }

    private struct UsageLimit: Decodable {
        let group: String?
        let kind: String?
        let percent: Double?
        let resetsAt: String?
        let scope: UsageLimitScope?

        private enum CodingKeys: String, CodingKey {
            case group
            case kind
            case percent
            case resetsAt = "resets_at"
            case scope
        }
    }

    private struct UsageResponse: Decodable {
        let fiveHour: UsageWindow?
        let sevenDay: UsageWindow?
        let sevenDaySonnet: UsageWindow?
        let sevenDayOpus: UsageWindow?
        let sevenDayCowork: UsageWindow?
        let sevenDayOAuthApps: UsageWindow?
        let limits: [UsageLimit]?

        private enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDaySonnet = "seven_day_sonnet"
            case sevenDayOpus = "seven_day_opus"
            case sevenDayCowork = "seven_day_cowork"
            case sevenDayOAuthApps = "seven_day_oauth_apps"
            case limits
        }
    }

    private enum ReaderError: Error {
        case cookieDatabaseUnavailable
        case safeStorageKeyUnavailable
        case sessionCookieUnavailable
        case desktopUserAgentUnavailable
        case organizationsUnavailable
        case activeOrganizationUnavailable
        case usageUnavailable
        case requestTimedOut
        case httpStatus(Int)

        var diagnosticCode: String {
            switch self {
            case .cookieDatabaseUnavailable: return "cookie-db-unavailable"
            case .safeStorageKeyUnavailable: return "safe-storage-key-unavailable"
            case .sessionCookieUnavailable: return "session-cookie-unavailable"
            case .desktopUserAgentUnavailable: return "desktop-user-agent-unavailable"
            case .organizationsUnavailable: return "organizations-unavailable"
            case .activeOrganizationUnavailable: return "active-organization-unavailable"
            case .usageUnavailable: return "usage-unavailable"
            case .requestTimedOut: return "request-timeout"
            case .httpStatus(let status): return "http-\(status)"
            }
        }
    }

    private static let allowedCookieNames = Set([
        "sessionKey",
        "sessionKeyLC",
        "cf_clearance",
        "routingHint",
        "__cf_bm",
        "__ssid",
        "lastActiveOrg",
        "anthropic-device-id"
    ])

    func fetchSnapshot() -> ReadResult {
        do {
            let cookies = try readCookies()
            guard cookies["sessionKey"]?.hasPrefix("sk-ant-") == true else {
                throw ReaderError.sessionCookieUnavailable
            }
            guard let userAgent = claudeDesktopUserAgent() else {
                throw ReaderError.desktopUserAgentUnavailable
            }
            let cookieHeader = Self.allowedCookieNames
                .sorted()
                .compactMap { name -> String? in
                    guard let value = cookies[name], !value.isEmpty else { return nil }
                    return "\(name)=\(value)"
                }
                .joined(separator: "; ")

            let organizationsData = try requestJSON(
                URL(string: "https://claude.ai/api/organizations")!,
                cookieHeader: cookieHeader,
                userAgent: userAgent
            )
            guard let organizations = try? JSONDecoder().decode([Organization].self, from: organizationsData),
                  !organizations.isEmpty else {
                throw ReaderError.organizationsUnavailable
            }

            let activeCookie = cookies["lastActiveOrg"]?.removingPercentEncoding ?? ""
            let organization = organizations.first(where: { organization in
                guard let identifier = organization.identifier else { return false }
                return activeCookie.contains(identifier)
            }) ?? organizations[0]
            guard let organizationID = organization.identifier,
                  let encodedID = organizationID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let usageURL = URL(string: "https://claude.ai/api/organizations/\(encodedID)/usage") else {
                throw ReaderError.activeOrganizationUnavailable
            }

            let usageData = try requestJSON(
                usageURL,
                cookieHeader: cookieHeader,
                userAgent: userAgent
            )
            guard let usage = try? JSONDecoder().decode(UsageResponse.self, from: usageData) else {
                throw ReaderError.usageUnavailable
            }
            let windows = Self.makeWindows(from: usage)
            guard !windows.isEmpty else { throw ReaderError.usageUnavailable }

            return .snapshot(ProviderQuotaSnapshot(
                id: "claude-desktop-current",
                providerName: "Claude",
                planName: nil,
                accountLabel: "Claude Desktop",
                credits: nil,
                windows: windows,
                resetCredits: nil,
                updatedAt: Date(),
                source: "claude-desktop",
                errorMessage: nil,
                setupHint: nil,
                isSetupNotice: false,
                quotaReadSucceeded: true
            ))
        } catch let error as ReaderError {
            return .unavailable(error.diagnosticCode)
        } catch {
            return .unavailable("unexpected-error")
        }
    }

    static func debugSelfTestFailures() -> [String] {
        let organizationFixture = Data("[{\"uuid\":\"org-test\",\"id\":123}]".utf8)
        guard let organizations = try? JSONDecoder().decode([Organization].self, from: organizationFixture),
              organizations.first?.identifier == "org-test" else {
            return ["Claude Desktop organization IDs did not decode"]
        }
        let fixture = Data("""
        {
          "five_hour": {
            "utilization": 34,
            "resets_at": "2026-07-26T13:19:59.308945+00:00"
          },
          "limits": [
            {
              "group": "session",
              "kind": "session",
              "percent": 34,
              "resets_at": "2026-07-26T13:19:59.308945+00:00",
              "scope": null
            },
            {
              "group": "weekly",
              "kind": "weekly_scoped",
              "percent": 17,
              "resets_at": "2026-07-26T17:59:59.309307+00:00",
              "scope": {"model": {"display_name": "Fable"}}
            }
          ]
        }
        """.utf8)
        guard let usage = try? JSONDecoder().decode(UsageResponse.self, from: fixture) else {
            return ["Claude Desktop quota fixture did not decode"]
        }
        let windows = makeWindows(from: usage)
        var failures: [String] = []
        if windows.filter({ $0.id == "primary" }).count != 1 {
            failures.append("Claude Desktop session quota was duplicated or missing")
        }
        if windows.first(where: { $0.id == "primary" })?.usedPercent != 34 {
            failures.append("Claude Desktop session utilization was not preserved")
        }
        if !windows.contains(where: {
            $0.id == "claude-weekly-fable" && $0.usedPercent == 17 && $0.resetsAt != nil
        }) {
            failures.append("Claude Desktop model-scoped weekly quota was not preserved")
        }
        if let fable = windows.first(where: { $0.id == "claude-weekly-fable" }) {
            if !fable.isAllowanceWindow || !fable.isScopedWeeklyAllowanceWindow {
                failures.append("Claude Desktop Fable quota was not classified as a visible allowance")
            }
            if fable.scopedWeeklyAllowanceDisplayName != "Fable" {
                failures.append("Claude Desktop Fable quota display name was not preserved")
            }
        }
        return failures
    }

    private func readCookies() throws -> [String: String] {
        let home = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
        let databaseURL = home.appendingPathComponent("Library/Application Support/Claude/Cookies")
        guard FileManager.default.isReadableFile(atPath: databaseURL.path) else {
            throw ReaderError.cookieDatabaseUnavailable
        }
        guard let safeStoragePassword = readSafeStoragePassword() else {
            throw ReaderError.safeStorageKeyUnavailable
        }
        guard let key = deriveCookieKey(from: safeStoragePassword) else {
            throw ReaderError.safeStorageKeyUnavailable
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close_v2(database) }
            throw ReaderError.cookieDatabaseUnavailable
        }
        defer { sqlite3_close_v2(database) }
        sqlite3_busy_timeout(database, 500)

        let names = Self.allowedCookieNames
            .sorted()
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ",")
        let sql = """
        SELECT host_key, name, value, encrypted_value, expires_utc
        FROM cookies
        WHERE host_key IN ('.claude.ai', 'claude.ai')
          AND name IN (\(names))
        ORDER BY CASE WHEN host_key = '.claude.ai' THEN 0 ELSE 1 END,
                 expires_utc DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ReaderError.cookieDatabaseUnavailable
        }
        defer { sqlite3_finalize(statement) }

        let chromeEpochOffset: TimeInterval = 11_644_473_600
        let nowChromeMicroseconds = Int64((Date().timeIntervalSince1970 + chromeEpochOffset) * 1_000_000)
        var cookies: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let expiresAt = sqlite3_column_int64(statement, 4)
            if expiresAt != 0, expiresAt <= nowChromeMicroseconds { continue }
            guard let hostPointer = sqlite3_column_text(statement, 0),
                  let namePointer = sqlite3_column_text(statement, 1) else { continue }
            let host = String(cString: hostPointer)
            let name = String(cString: namePointer)
            guard cookies[name] == nil else { continue }

            let plainValue = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            if !plainValue.isEmpty {
                cookies[name] = plainValue
                continue
            }
            guard let blob = sqlite3_column_blob(statement, 3) else { continue }
            let byteCount = Int(sqlite3_column_bytes(statement, 3))
            guard byteCount > 3 else { continue }
            let encrypted = Data(bytes: blob, count: byteCount)
            if let value = decryptCookie(encrypted, host: host, key: key), !value.isEmpty {
                cookies[name] = value
            }
        }
        guard cookies["sessionKey"] != nil else { throw ReaderError.sessionCookieUnavailable }
        return cookies
    }

    private func readSafeStoragePassword() -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              !data.isEmpty else { return nil }
        return data
    }

    private func deriveCookieKey(from password: Data) -> Data? {
        let salt = Data("saltysalt".utf8)
        var derived = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let derivedCount = derived.count
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                derived.withUnsafeMutableBytes { derivedBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(derived)
    }

    private func decryptCookie(_ encrypted: Data, host: String, key: Data) -> String? {
        guard encrypted.count > 3,
              encrypted.prefix(3) == Data("v10".utf8)
                || encrypted.prefix(3) == Data("v11".utf8) else { return nil }
        let ciphertext = Data(encrypted.dropFirst(3))
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var outputLength = 0
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                ciphertext.withUnsafeBytes { inputBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputBytes.count,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        var plaintext = Data(output.prefix(outputLength))
        let hostDigest = sha256(Data(host.utf8))
        if plaintext.starts(with: hostDigest) {
            plaintext.removeFirst(hostDigest.count)
        }
        return String(data: plaintext, encoding: .utf8)
    }

    private func sha256(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { inputBytes in
            digest.withUnsafeMutableBytes { digestBytes in
                _ = CC_SHA256(
                    inputBytes.baseAddress,
                    CC_LONG(data.count),
                    digestBytes.bindMemory(to: UInt8.self).baseAddress
                )
            }
        }
        return Data(digest)
    }

    private func requestJSON(
        _ url: URL,
        cookieHeader: String,
        userAgent: String
    ) throws -> Data {
        guard url.scheme == "https", url.host == "claude.ai" else {
            throw ReaderError.usageUnavailable
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(
            configuration: configuration,
            delegate: NoRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var responseData: Data?
        var responseStatus: Int?
        var responseError: Error?
        let task = session.dataTask(with: request) { data, response, error in
            lock.lock()
            responseData = data
            responseStatus = (response as? HTTPURLResponse)?.statusCode
            responseError = error
            lock.unlock()
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 13) == .success else {
            task.cancel()
            throw ReaderError.requestTimedOut
        }
        lock.lock()
        let data = responseData
        let status = responseStatus
        let error = responseError
        lock.unlock()
        if error != nil { throw ReaderError.usageUnavailable }
        guard let status else { throw ReaderError.usageUnavailable }
        guard (200..<300).contains(status) else { throw ReaderError.httpStatus(status) }
        guard let data, !data.isEmpty else { throw ReaderError.usageUnavailable }
        return data
    }

    private static let cachedClaudeDesktopUserAgent: String? = resolveClaudeDesktopUserAgent()

    private func claudeDesktopUserAgent() -> String? {
        Self.cachedClaudeDesktopUserAgent
    }

    private static func resolveClaudeDesktopUserAgent() -> String? {
        let homeApplications = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
            .appendingPathComponent("Applications/Claude.app", isDirectory: true)
        let candidates = [URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true), homeApplications]
        guard let appURL = candidates.first(where: {
            Bundle(url: $0)?.bundleIdentifier == "com.anthropic.claudefordesktop"
        }),
        let appBundle = Bundle(url: appURL),
        let appVersion = appBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }

        let frameworkURL = appURL.appendingPathComponent(
            "Contents/Frameworks/Electron Framework.framework/Versions/A",
            isDirectory: true
        )
        let frameworkInfoURL = frameworkURL.appendingPathComponent("Resources/Info.plist")
        guard let frameworkInfoData = try? Data(contentsOf: frameworkInfoURL),
              let frameworkInfo = try? PropertyListSerialization.propertyList(
                from: frameworkInfoData,
                options: [],
                format: nil
              ) as? [String: Any],
              let electronVersion = frameworkInfo["CFBundleVersion"] as? String,
              let chromeVersion = chromeVersion(
                in: frameworkURL.appendingPathComponent("Electron Framework")
              ) else { return nil }

        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Claude/\(appVersion) Chrome/\(chromeVersion) "
            + "Electron/\(electronVersion) Safari/537.36"
    }

    private static func chromeVersion(in executableURL: URL) -> String? {
        guard let data = try? Data(contentsOf: executableURL, options: [.mappedIfSafe]) else { return nil }
        let marker = Data("Chrome/".utf8)
        var searchStart = data.startIndex
        while searchStart < data.endIndex,
              let range = data.range(of: marker, in: searchStart..<data.endIndex) {
            let limit = min(data.endIndex, range.upperBound + 40)
            let versionBytes = data[range.upperBound..<limit].prefix { byte in
                (byte >= 48 && byte <= 57) || byte == 46
            }
            if let version = String(data: versionBytes, encoding: .utf8),
               version.split(separator: ".").count == 4 {
                return version
            }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func makeWindows(from usage: UsageResponse) -> [ProviderQuotaWindow] {
        var windows: [ProviderQuotaWindow] = []

        func appendWindow(
            id: String,
            title: String,
            kind: ProviderQuotaWindow.Kind,
            minutes: Int?,
            payload: UsageWindow?
        ) {
            guard let payload, let utilization = payload.utilization else { return }
            windows.append(ProviderQuotaWindow(
                id: id,
                kind: kind,
                title: title,
                usedPercent: max(0, min(100, utilization)),
                resetsAt: parseDate(payload.resetsAt),
                windowMinutes: minutes
            ))
        }

        appendWindow(
            id: "primary",
            title: "5-hour quota",
            kind: .fiveHour,
            minutes: 300,
            payload: usage.fiveHour
        )
        appendWindow(
            id: "secondary",
            title: "Weekly quota",
            kind: .weekly,
            minutes: 10_080,
            payload: usage.sevenDay
        )
        appendWindow(
            id: "claude-weekly-sonnet",
            title: "Current week (Sonnet)",
            kind: .extra,
            minutes: 10_080,
            payload: usage.sevenDaySonnet
        )
        appendWindow(
            id: "claude-weekly-opus",
            title: "Current week (Opus)",
            kind: .extra,
            minutes: 10_080,
            payload: usage.sevenDayOpus
        )
        appendWindow(
            id: "claude-weekly-cowork",
            title: "Current week (Cowork)",
            kind: .extra,
            minutes: 10_080,
            payload: usage.sevenDayCowork
        )
        appendWindow(
            id: "claude-weekly-oauth-apps",
            title: "Current week (OAuth apps)",
            kind: .extra,
            minutes: 10_080,
            payload: usage.sevenDayOAuthApps
        )

        for limit in usage.limits ?? [] {
            guard let percent = limit.percent else { continue }
            let normalizedKind = limit.kind?.lowercased() ?? ""
            let normalizedGroup = limit.group?.lowercased() ?? ""
            if normalizedKind == "session" || normalizedGroup == "session" {
                guard !windows.contains(where: { $0.id == "primary" }) else { continue }
                windows.append(ProviderQuotaWindow(
                    id: "primary",
                    kind: .fiveHour,
                    title: "5-hour quota",
                    usedPercent: max(0, min(100, percent)),
                    resetsAt: parseDate(limit.resetsAt),
                    windowMinutes: 300
                ))
                continue
            }

            let modelName = limit.scope?.model?.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedKind == "weekly_scoped", let modelName, !modelName.isEmpty {
                let slug = modelName.lowercased()
                    .unicodeScalars
                    .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
                    .map(String.init)
                    .joined()
                    .split(separator: "-")
                    .joined(separator: "-")
                let id = "claude-weekly-\(slug)"
                guard !windows.contains(where: { $0.id == id }) else { continue }
                windows.append(ProviderQuotaWindow(
                    id: id,
                    kind: .extra,
                    title: "Current week (\(modelName))",
                    usedPercent: max(0, min(100, percent)),
                    resetsAt: parseDate(limit.resetsAt),
                    windowMinutes: 10_080
                ))
                continue
            }

            if normalizedKind.contains("weekly") || normalizedGroup == "weekly" {
                guard !windows.contains(where: { $0.id == "secondary" }) else { continue }
                windows.append(ProviderQuotaWindow(
                    id: "secondary",
                    kind: .weekly,
                    title: "Weekly quota",
                    usedPercent: max(0, min(100, percent)),
                    resetsAt: parseDate(limit.resetsAt),
                    windowMinutes: 10_080
                ))
            }
        }
        return windows
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private func sanitizedMessage(_ message: String) -> String {
    let value = message
        .replacingOccurrences(of: "CodexBar", with: "TraceFence")
        .replacingOccurrences(of: "codexbar", with: "TraceFence")
    return value
}

private enum CodexBarQuotaError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}

private final class ProviderQuotaSecurityScopedAccess {
    private var activeURLs: [URL] = []
    private let logger = Logger(subsystem: "com.tracefence.app", category: "provider-quota")

    func start() {
        guard SandboxPaths.isSandboxed || !SandboxPaths.isDirectDistribution else { return }

        let bookmarkFiles = [
            SandboxPaths.shared.bookmarksPath,
            SandboxPaths.shared.scanBookmarksPath,
            SandboxPaths.shared.tokenScopeBookmarksPath
        ]
        var seen = Set<String>()
        var staleCount = 0

        for bookmarkFile in bookmarkFiles {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: bookmarkFile)),
                  let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
                continue
            }

            for (_, bookmark) in bookmarks {
                var stale = false
                guard let url = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) else {
                    continue
                }
                if stale { staleCount += 1 }
                let path = url.standardizedFileURL.path
                guard !seen.contains(path) else { continue }
                if url.startAccessingSecurityScopedResource() {
                    seen.insert(path)
                    activeURLs.append(url)
                }
            }
        }

        let home = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true).standardizedFileURL.path
        let grokPath = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".grok", isDirectory: true)
            .standardizedFileURL.path
        let grokCovered = activeURLs.contains { url in
            let root = url.standardizedFileURL.path
            return root == home || root == grokPath || grokPath.hasPrefix(root + "/")
        }
        logger.info("Quota data access: active=\(self.activeURLs.count, privacy: .public), stale=\(staleCount, privacy: .public), grok-covered=\(grokCovered, privacy: .public)")
    }

    func stop() {
        activeURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        activeURLs.removeAll()
    }
}

private struct CodexBarProviderPayload: Decodable {
    let provider: String
    let account: String?
    let version: String?
    let source: String
    let usage: CodexBarUsagePayload?
    let credits: CodexBarCreditsPayload?
    let error: CodexBarErrorPayload?
}

private struct CodexBarProviderConfigPayload: Decodable {
    let provider: String
    let displayName: String
    let enabled: Bool
    let defaultEnabled: Bool
}

private struct CodexBarUsagePayload: Decodable {
    let primary: CodexBarRateWindowPayload?
    let secondary: CodexBarRateWindowPayload?
    let tertiary: CodexBarRateWindowPayload?
    let extraRateWindows: [CodexBarNamedRateWindowPayload]?
    let codexResetCredits: ProviderQuotaResetCredits?
    let updatedAt: Date
    let identity: CodexBarIdentityPayload?
    let accountEmail: String?
    let loginMethod: String?
    let hasOfficialWindowFields: Bool
    let hasMalformedOfficialWindow: Bool

    private enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case tertiary
        case extraRateWindows
        case codexResetCredits
        case updatedAt
        case identity
        case accountEmail
        case loginMethod
    }

    init(
        primary: CodexBarRateWindowPayload?,
        secondary: CodexBarRateWindowPayload?,
        tertiary: CodexBarRateWindowPayload?,
        extraRateWindows: [CodexBarNamedRateWindowPayload]?,
        codexResetCredits: ProviderQuotaResetCredits?,
        updatedAt: Date,
        identity: CodexBarIdentityPayload?,
        accountEmail: String?,
        loginMethod: String?,
        hasOfficialWindowFields: Bool = true,
        hasMalformedOfficialWindow: Bool = false
    ) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.extraRateWindows = extraRateWindows
        self.codexResetCredits = codexResetCredits
        self.updatedAt = updatedAt
        self.identity = identity
        self.accountEmail = accountEmail
        self.loginMethod = loginMethod
        self.hasOfficialWindowFields = hasOfficialWindowFields
        self.hasMalformedOfficialWindow = hasMalformedOfficialWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var malformedWindow = false

        func decodeWindow(_ key: CodingKeys) -> CodexBarRateWindowPayload? {
            do {
                return try container.decodeIfPresent(CodexBarRateWindowPayload.self, forKey: key)
            } catch {
                malformedWindow = true
                return nil
            }
        }

        primary = decodeWindow(.primary)
        secondary = decodeWindow(.secondary)
        tertiary = decodeWindow(.tertiary)
        extraRateWindows = try container.decodeIfPresent([CodexBarNamedRateWindowPayload].self, forKey: .extraRateWindows)
        codexResetCredits = try container.decodeIfPresent(ProviderQuotaResetCredits.self, forKey: .codexResetCredits)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        identity = try container.decodeIfPresent(CodexBarIdentityPayload.self, forKey: .identity)
        accountEmail = try container.decodeIfPresent(String.self, forKey: .accountEmail)
        loginMethod = try container.decodeIfPresent(String.self, forKey: .loginMethod)
        hasOfficialWindowFields = container.contains(.primary)
            || container.contains(.secondary)
            || container.contains(.tertiary)
        hasMalformedOfficialWindow = malformedWindow
    }
}

private struct CodexBarRateWindowPayload: Decodable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let resetDescription: String?
}

private struct CodexBarNamedRateWindowPayload: Decodable {
    let id: String
    let title: String
    let window: CodexBarRateWindowPayload
    let usageKnown: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case window
        case usageKnown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        window = try container.decode(CodexBarRateWindowPayload.self, forKey: .window)
        usageKnown = try container.decodeIfPresent(Bool.self, forKey: .usageKnown) ?? true
    }
}

private struct CodexBarIdentityPayload: Decodable {
    let accountEmail: String?
    let loginMethod: String?
}

private struct CodexBarCreditsPayload: Decodable {
    let remaining: Double
    let updatedAt: Date
}

private struct CodexBarErrorPayload: Decodable {
    let message: String
}
