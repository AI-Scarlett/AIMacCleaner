import CryptoKit
import Foundation

struct AgentUsageRemoteModelPrice: Equatable, Sendable {
    let inputPerMillion: Double
    let cachedInputPerMillion: Double
    let cacheWrite5mPerMillion: Double
    let cacheWrite1hPerMillion: Double
    let outputPerMillion: Double
    let longContextThreshold: Int64?
    let longContextInputMultiplier: Double
    let longContextOutputMultiplier: Double
}

struct AgentUsagePricingRefreshReport: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case skipped
        case unchanged
        case updated
        case failed
    }

    let status: Status
    let previousRevision: String
    let currentRevision: String
    let message: String

    var catalogChanged: Bool {
        status == .updated && previousRevision != currentRevision
    }
}

/// A validated, provider-neutral pricing layer. The direct-download build can
/// update this catalog independently of the application while the built-in
/// catalog remains the offline and first-launch fallback.
enum AgentUsageRemotePricingCatalog {
    static let publicCatalogURL = URL(
        string: "https://raw.githubusercontent.com/AI-Scarlett/TraceFence/main/pricing/model-pricing-v1.json"
    )!

    private static let builtInRevision = "builtin-2026-07-30.1"
    private static let maximumCatalogBytes = 256 * 1_024
    private static let state = State()

    static var revisionSignature: String {
        guard SandboxPaths.isDirectDistribution else { return builtInRevision }
        return state.snapshot()?.revision ?? builtInRevision
    }

    static var activeCatalogVersion: String? {
        guard SandboxPaths.isDirectDistribution else { return nil }
        return state.snapshot()?.document.catalogVersion
    }

    static func price(
        scope: AgentUsageScope,
        model: String?,
        at date: Date? = nil
    ) -> AgentUsageRemoteModelPrice? {
        guard SandboxPaths.isDirectDistribution, let model else { return nil }
        let providers: [Provider]
        switch scope {
        case .codex:
            providers = [.openAI]
        case .claude:
            providers = [.anthropic]
        case .openCode, .openClaw, .deepSeekHarness:
            providers = [.miniMax, .openAI, .anthropic]
        case .combined:
            return nil
        }
        guard let catalog = state.snapshot() else { return nil }
        return catalog.price(providers: providers, model: model, at: date ?? Date())
    }

    static func installValidatedCatalogData(_ data: Data) throws -> (previous: String, current: String) {
        let validated = try decodeAndValidate(data)
        if let current = state.snapshot(), validated.document.updatedAt < current.document.updatedAt {
            throw ValidationError.staleCatalog
        }
        let previous = revisionSignature
        try Store.saveCatalogData(data)
        state.install(validated)
        return (previous, revisionSignature)
    }

    static func decodeAndValidate(_ data: Data) throws -> ValidatedCatalog {
        guard !data.isEmpty, data.count <= maximumCatalogBytes else {
            throw ValidationError.invalidSize
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: Document
        do {
            document = try decoder.decode(Document.self, from: data)
        } catch {
            throw ValidationError.invalidJSON
        }

        guard document.schemaVersion == 1 else { throw ValidationError.unsupportedSchema }
        guard isSafeVersion(document.catalogVersion) else { throw ValidationError.invalidVersion }
        guard document.currency == "USD",
              document.unit == "USD_per_1M_tokens",
              document.serviceTier == "standard" else {
            throw ValidationError.unsupportedPriceBasis
        }
        guard document.updatedAt <= Date().addingTimeInterval(24 * 60 * 60) else {
            throw ValidationError.futureCatalog
        }
        guard !document.sources.isEmpty, document.sources.count <= 16 else {
            throw ValidationError.invalidSources
        }
        for source in document.sources {
            guard 1...160 ~= source.name.count,
                  let url = URL(string: source.url),
                  url.scheme?.lowercased() == "https",
                  url.host?.isEmpty == false else {
                throw ValidationError.invalidSources
            }
        }
        guard !document.entries.isEmpty, document.entries.count <= 512 else {
            throw ValidationError.invalidEntryCount
        }

        var validatedEntries: [ValidatedEntry] = []
        validatedEntries.reserveCapacity(document.entries.count)
        var aliasesByProvider: [Provider: [String: String]] = [:]
        for entry in document.entries {
            let model = entry.model.lowercased()
            guard model == entry.model,
                  isSafeModelID(model),
                  entry.aliases.count <= 24 else {
                throw ValidationError.invalidModel
            }
            let aliases = entry.aliases.map { $0.lowercased() }
            guard zip(entry.aliases, aliases).allSatisfy({ original, normalized in
                      original == normalized && isSafeModelID(normalized)
                  }),
                  Set(aliases).count == aliases.count else {
                throw ValidationError.invalidModel
            }
            if let from = entry.effectiveFrom, let until = entry.effectiveUntil, from >= until {
                throw ValidationError.invalidEffectiveRange
            }

            let rates = entry.rates
            let numericRates = [
                rates.inputPerMillion,
                rates.cachedInputPerMillion,
                rates.cacheWrite5mPerMillion,
                rates.cacheWrite1hPerMillion,
                rates.outputPerMillion,
                rates.longContextInputMultiplier,
                rates.longContextOutputMultiplier
            ].compactMap { $0 }
            guard numericRates.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 10_000 }),
                  rates.inputPerMillion > 0,
                  rates.outputPerMillion > 0 else {
                throw ValidationError.invalidRate
            }
            if let threshold = rates.longContextThreshold {
                guard threshold >= 1_000, threshold <= 10_000_000,
                      (rates.longContextInputMultiplier ?? 1) >= 1,
                      (rates.longContextOutputMultiplier ?? 1) >= 1 else {
                    throw ValidationError.invalidLongContext
                }
            } else if rates.longContextInputMultiplier != nil || rates.longContextOutputMultiplier != nil {
                throw ValidationError.invalidLongContext
            }

            var providerAliases = aliasesByProvider[entry.provider, default: [:]]
            for identifier in [model] + aliases {
                if let owner = providerAliases[identifier], owner != model {
                    throw ValidationError.ambiguousAlias
                }
                providerAliases[identifier] = model
            }
            aliasesByProvider[entry.provider] = providerAliases

            validatedEntries.append(ValidatedEntry(
                provider: entry.provider,
                model: model,
                aliases: aliases,
                effectiveFrom: entry.effectiveFrom,
                effectiveUntil: entry.effectiveUntil,
                price: AgentUsageRemoteModelPrice(
                    inputPerMillion: rates.inputPerMillion,
                    cachedInputPerMillion: rates.cachedInputPerMillion ?? rates.inputPerMillion,
                    cacheWrite5mPerMillion: rates.cacheWrite5mPerMillion ?? rates.inputPerMillion,
                    cacheWrite1hPerMillion: rates.cacheWrite1hPerMillion ?? rates.inputPerMillion,
                    outputPerMillion: rates.outputPerMillion,
                    longContextThreshold: rates.longContextThreshold,
                    longContextInputMultiplier: rates.longContextInputMultiplier ?? 1,
                    longContextOutputMultiplier: rates.longContextOutputMultiplier ?? 1
                )
            ))
        }

        let grouped = Dictionary(grouping: validatedEntries) { "\($0.provider.rawValue)|\($0.model)" }
        for entries in grouped.values {
            let sorted = entries.sorted { ($0.effectiveFrom ?? .distantPast) < ($1.effectiveFrom ?? .distantPast) }
            for index in 0..<max(0, sorted.count - 1) {
                let currentEnd = sorted[index].effectiveUntil ?? .distantFuture
                let nextStart = sorted[index + 1].effectiveFrom ?? .distantPast
                guard currentEnd <= nextStart else { throw ValidationError.overlappingRanges }
            }
        }

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ValidatedCatalog(
            document: document,
            entries: validatedEntries,
            contentSHA256: digest,
            revision: "remote-\(document.catalogVersion)-\(digest.prefix(16))"
        )
    }

    static func debugSelfTestFailures() -> [String] {
        var failures: [String] = []
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            if !value() { failures.append(message) }
        }

        let fixture = Data(#"""
        {
          "schemaVersion": 1,
          "catalogVersion": "test-2026-07-30.1",
          "currency": "USD",
          "unit": "USD_per_1M_tokens",
          "serviceTier": "standard",
          "updatedAt": "2026-07-30T00:00:00Z",
          "sources": [{"name": "OpenAI pricing", "url": "https://developers.openai.com/api/docs/pricing"}],
          "entries": [
            {
              "provider": "openai",
              "model": "gpt-test",
              "effectiveUntil": "2026-07-30T00:00:00Z",
              "rates": {"inputPerMillion": 2.5, "cachedInputPerMillion": 0.25, "outputPerMillion": 15}
            },
            {
              "provider": "openai",
              "model": "gpt-test",
              "effectiveFrom": "2026-07-30T00:00:00Z",
              "rates": {"inputPerMillion": 2, "cachedInputPerMillion": 0.2, "outputPerMillion": 12}
            }
          ]
        }
        """#.utf8)
        do {
            let catalog = try decodeAndValidate(fixture)
            let before = catalog.price(
                providers: [.openAI],
                model: "vendor/gpt-test",
                at: Date(timeIntervalSince1970: 1_785_369_599)
            )
            let after = catalog.price(
                providers: [.openAI],
                model: "gpt-test",
                at: Date(timeIntervalSince1970: 1_785_369_600)
            )
            expect(before?.inputPerMillion == 2.5 && before?.outputPerMillion == 15, "remote pricing must retain the pre-change historical tier")
            expect(after?.inputPerMillion == 2 && after?.outputPerMillion == 12, "remote pricing must switch tiers at the published effective date")
        } catch {
            failures.append("valid remote pricing fixture must decode: \(error.localizedDescription)")
        }

        let invalid = Data(#"""
        {"schemaVersion":1,"catalogVersion":"bad","currency":"USD","unit":"USD_per_1M_tokens","serviceTier":"standard","updatedAt":"2026-07-30T00:00:00Z","sources":[{"name":"source","url":"https://example.com"}],"entries":[{"provider":"openai","model":"gpt-test","aliases":[],"rates":{"inputPerMillion":-1,"outputPerMillion":12}}]}
        """#.utf8)
        expect((try? decodeAndValidate(invalid)) == nil, "remote pricing must reject negative rates")
        return failures
    }

    fileprivate static func currentCatalogInfo() -> CatalogInfo? {
        state.snapshot().map {
            CatalogInfo(
                catalogVersion: $0.document.catalogVersion,
                revision: $0.revision,
                contentSHA256: $0.contentSHA256,
                updatedAt: $0.document.updatedAt
            )
        }
    }

    fileprivate static var maximumDownloadBytes: Int { maximumCatalogBytes }

    fileprivate struct CatalogInfo: Sendable {
        let catalogVersion: String
        let revision: String
        let contentSHA256: String
        let updatedAt: Date
    }

    struct ValidatedCatalog: Sendable {
        fileprivate let document: Document
        fileprivate let entries: [ValidatedEntry]
        fileprivate let contentSHA256: String
        fileprivate let revision: String

        fileprivate func price(providers: [Provider], model: String, at date: Date) -> AgentUsageRemoteModelPrice? {
            let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { return nil }
            for provider in providers {
                let candidates: [(entry: ValidatedEntry, score: Int)] = entries.compactMap { entry in
                    guard entry.provider == provider,
                          let score = entry.matchScore(normalized),
                          entry.effectiveFrom.map({ $0 <= date }) ?? true,
                          entry.effectiveUntil.map({ date < $0 }) ?? true else { return nil }
                    return (entry, score)
                }
                if let selected = candidates.max(by: { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score < rhs.score }
                    return (lhs.entry.effectiveFrom ?? .distantPast) < (rhs.entry.effectiveFrom ?? .distantPast)
                }) {
                    return selected.entry.price
                }
            }
            return nil
        }
    }

    fileprivate struct Document: Codable, Sendable {
        let schemaVersion: Int
        let catalogVersion: String
        let currency: String
        let unit: String
        let serviceTier: String
        let updatedAt: Date
        let sources: [Source]
        let entries: [Entry]
    }

    fileprivate struct Source: Codable, Sendable {
        let name: String
        let url: String
    }

    fileprivate struct Entry: Codable, Sendable {
        let provider: Provider
        let model: String
        let aliases: [String]
        let effectiveFrom: Date?
        let effectiveUntil: Date?
        let rates: Rates
        let provenance: String?

        private enum CodingKeys: String, CodingKey {
            case provider, model, aliases, effectiveFrom, effectiveUntil, rates, provenance
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            provider = try container.decode(Provider.self, forKey: .provider)
            model = try container.decode(String.self, forKey: .model)
            aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
            effectiveFrom = try container.decodeIfPresent(Date.self, forKey: .effectiveFrom)
            effectiveUntil = try container.decodeIfPresent(Date.self, forKey: .effectiveUntil)
            rates = try container.decode(Rates.self, forKey: .rates)
            provenance = try container.decodeIfPresent(String.self, forKey: .provenance)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(provider, forKey: .provider)
            try container.encode(model, forKey: .model)
            if !aliases.isEmpty { try container.encode(aliases, forKey: .aliases) }
            try container.encodeIfPresent(effectiveFrom, forKey: .effectiveFrom)
            try container.encodeIfPresent(effectiveUntil, forKey: .effectiveUntil)
            try container.encode(rates, forKey: .rates)
            try container.encodeIfPresent(provenance, forKey: .provenance)
        }
    }

    fileprivate struct Rates: Codable, Sendable {
        let inputPerMillion: Double
        let cachedInputPerMillion: Double?
        let cacheWrite5mPerMillion: Double?
        let cacheWrite1hPerMillion: Double?
        let outputPerMillion: Double
        let longContextThreshold: Int64?
        let longContextInputMultiplier: Double?
        let longContextOutputMultiplier: Double?
    }

    fileprivate enum Provider: String, Codable, Sendable {
        case openAI = "openai"
        case anthropic
        case miniMax = "minimax"
    }

    fileprivate struct ValidatedEntry: Sendable {
        let provider: Provider
        let model: String
        let aliases: [String]
        let effectiveFrom: Date?
        let effectiveUntil: Date?
        let price: AgentUsageRemoteModelPrice

        func matchScore(_ value: String) -> Int? {
            let unnamespaced = value.split(separator: "/").last.map(String.init) ?? value
            var score: Int?
            for identifier in [model] + aliases {
                if unnamespaced == identifier {
                    score = max(score ?? 0, 2)
                } else if unnamespaced.hasPrefix(identifier + "-20") {
                    score = max(score ?? 0, 1)
                }
            }
            return score
        }
    }

    fileprivate enum ValidationError: LocalizedError {
        case invalidSize
        case invalidJSON
        case unsupportedSchema
        case invalidVersion
        case unsupportedPriceBasis
        case futureCatalog
        case invalidSources
        case invalidEntryCount
        case invalidModel
        case invalidRate
        case invalidLongContext
        case invalidEffectiveRange
        case overlappingRanges
        case ambiguousAlias
        case staleCatalog

        var errorDescription: String? {
            switch self {
            case .invalidSize: return "Pricing catalog size is invalid."
            case .invalidJSON: return "Pricing catalog JSON is invalid."
            case .unsupportedSchema: return "Pricing catalog schema is unsupported."
            case .invalidVersion: return "Pricing catalog version is invalid."
            case .unsupportedPriceBasis: return "Pricing catalog currency, unit, or service tier is unsupported."
            case .futureCatalog: return "Pricing catalog timestamp is in the future."
            case .invalidSources: return "Pricing catalog sources are invalid."
            case .invalidEntryCount: return "Pricing catalog entry count is invalid."
            case .invalidModel: return "Pricing catalog model identifier is invalid."
            case .invalidRate: return "Pricing catalog contains an invalid rate."
            case .invalidLongContext: return "Pricing catalog long-context tier is invalid."
            case .invalidEffectiveRange: return "Pricing catalog effective range is invalid."
            case .overlappingRanges: return "Pricing catalog effective ranges overlap."
            case .ambiguousAlias: return "Pricing catalog contains an ambiguous alias."
            case .staleCatalog: return "Pricing catalog is older than the active cached catalog."
            }
        }
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var catalog: ValidatedCatalog?

        init() {
            if let data = Store.loadCatalogData() {
                catalog = try? AgentUsageRemotePricingCatalog.decodeAndValidate(data)
            }
        }

        func snapshot() -> ValidatedCatalog? {
            lock.lock()
            defer { lock.unlock() }
            return catalog
        }

        func install(_ value: ValidatedCatalog) {
            lock.lock()
            catalog = value
            lock.unlock()
        }
    }

    fileprivate struct Metadata: Codable, Sendable {
        let catalogVersion: String
        let contentSHA256: String
        let etag: String?
        let lastModified: String?
        let lastCheckedAt: Date
    }

    fileprivate enum Store {
        static func loadCatalogData() -> Data? {
            let url = catalogURL
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize,
                  size > 0,
                  size <= maximumCatalogBytes else { return nil }
            return try? Data(contentsOf: url, options: [.mappedIfSafe])
        }

        static func saveCatalogData(_ data: Data) throws {
            try ensureDirectory()
            try data.write(to: catalogURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: catalogURL.path)
        }

        static func loadMetadata() -> Metadata? {
            guard let data = try? Data(contentsOf: metadataURL),
                  let decoded = try? JSONDecoder().decode(Metadata.self, from: data) else { return nil }
            return decoded
        }

        static func saveMetadata(_ metadata: Metadata) throws {
            try ensureDirectory()
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)
        }

        private static func ensureDirectory() throws {
            let directory = catalogURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }

        private static var catalogURL: URL {
            URL(fileURLWithPath: SandboxPaths.shared.agentUsagePricingCatalogPath)
        }

        private static var metadataURL: URL {
            URL(fileURLWithPath: SandboxPaths.shared.agentUsagePricingCatalogMetadataPath)
        }
    }

    private static func isSafeVersion(_ value: String) -> Bool {
        guard 1...80 ~= value.count else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isSafeModelID(_ value: String) -> Bool {
        guard 1...120 ~= value.count else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._/-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

actor AgentUsagePricingCatalogUpdateService {
    static let shared = AgentUsagePricingCatalogUpdateService()

    private static let minimumRefreshInterval: TimeInterval = 6 * 60 * 60
    private static let failedAttemptBackoff: TimeInterval = 15 * 60
    private let session: URLSession
    private var lastAttemptAt: Date?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        if #available(macOS 10.15, *) {
            configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        }
        session = URLSession(configuration: configuration)
    }

    func refreshIfNeeded(force: Bool = false) async -> AgentUsagePricingRefreshReport {
        let previousRevision = AgentUsageRemotePricingCatalog.revisionSignature
        guard SandboxPaths.isDirectDistribution else {
            return report(.skipped, previous: previousRevision, message: "Remote pricing is limited to the direct-download build.")
        }
        guard UserDefaults.standard.string(forKey: "networkMode") ?? "internet" == "internet" else {
            return report(.skipped, previous: previousRevision, message: "Remote pricing is disabled in the current network mode.")
        }

        let now = Date()
        if !force,
           let lastAttemptAt,
           now.timeIntervalSince(lastAttemptAt) < Self.failedAttemptBackoff {
            return report(.skipped, previous: previousRevision, message: "A pricing refresh was attempted recently.")
        }
        let currentInfo = AgentUsageRemotePricingCatalog.currentCatalogInfo()
        let storedMetadata = AgentUsageRemotePricingCatalog.Store.loadMetadata()
        if !force,
           let storedMetadata,
           storedMetadata.contentSHA256 == currentInfo?.contentSHA256,
           now.timeIntervalSince(storedMetadata.lastCheckedAt) < Self.minimumRefreshInterval {
            return report(.skipped, previous: previousRevision, message: "The cached pricing catalog is still fresh.")
        }
        lastAttemptAt = now

        var request = URLRequest(url: AgentUsageRemotePricingCatalog.publicCatalogURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TraceFence Pricing Catalog", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if storedMetadata?.contentSHA256 == currentInfo?.contentSHA256 {
            if let etag = storedMetadata?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let lastModified = storedMetadata?.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  Self.isAllowedFinalURL(http.url) else {
                throw RefreshError.invalidResponse
            }
            if http.statusCode == 304 {
                guard let currentInfo else { throw RefreshError.invalidResponse }
                try AgentUsageRemotePricingCatalog.Store.saveMetadata(.init(
                    catalogVersion: currentInfo.catalogVersion,
                    contentSHA256: currentInfo.contentSHA256,
                    etag: storedMetadata?.etag,
                    lastModified: storedMetadata?.lastModified,
                    lastCheckedAt: now
                ))
                return report(.unchanged, previous: previousRevision, message: "The GitHub pricing catalog has not changed.")
            }
            guard http.statusCode == 200,
                  data.count <= AgentUsageRemotePricingCatalog.maximumDownloadBytes else {
                throw RefreshError.invalidResponse
            }

            let installed = try AgentUsageRemotePricingCatalog.installValidatedCatalogData(data)
            guard let installedInfo = AgentUsageRemotePricingCatalog.currentCatalogInfo() else {
                throw RefreshError.invalidResponse
            }
            try AgentUsageRemotePricingCatalog.Store.saveMetadata(.init(
                catalogVersion: installedInfo.catalogVersion,
                contentSHA256: installedInfo.contentSHA256,
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                lastCheckedAt: now
            ))
            let status: AgentUsagePricingRefreshReport.Status = installed.previous == installed.current ? .unchanged : .updated
            return report(status, previous: installed.previous, message: status == .updated
                ? "Installed a newer GitHub pricing catalog."
                : "The downloaded pricing catalog matches the active catalog.")
        } catch {
            return report(.failed, previous: previousRevision, message: error.localizedDescription)
        }
    }

    nonisolated static func debugRunRemoteProbe(timeout: TimeInterval = 30) -> AgentUsagePricingRefreshReport {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ReportBox()
        Task.detached(priority: .utility) {
            let report = await AgentUsagePricingCatalogUpdateService.shared.refreshIfNeeded(force: true)
            box.set(report)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + max(1, timeout)) == .success,
              let report = box.get() else {
            let revision = AgentUsageRemotePricingCatalog.revisionSignature
            return AgentUsagePricingRefreshReport(
                status: .failed,
                previousRevision: revision,
                currentRevision: revision,
                message: "Remote pricing probe timed out."
            )
        }
        return report
    }

    private func report(
        _ status: AgentUsagePricingRefreshReport.Status,
        previous: String,
        message: String
    ) -> AgentUsagePricingRefreshReport {
        AgentUsagePricingRefreshReport(
            status: status,
            previousRevision: previous,
            currentRevision: AgentUsageRemotePricingCatalog.revisionSignature,
            message: message
        )
    }

    private static func isAllowedFinalURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "raw.githubusercontent.com"
            && url.path == "/AI-Scarlett/TraceFence/main/pricing/model-pricing-v1.json"
    }

    private enum RefreshError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            "The remote pricing endpoint returned an invalid response."
        }
    }

    private final class ReportBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: AgentUsagePricingRefreshReport?

        func set(_ value: AgentUsagePricingRefreshReport) {
            lock.lock()
            self.value = value
            lock.unlock()
        }

        func get() -> AgentUsagePricingRefreshReport? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
