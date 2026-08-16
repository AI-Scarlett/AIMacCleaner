import AppKit
import CryptoKit
import Foundation
import Security

enum TraceFenceMarketplaceOfferKind: String, Codable, Sendable {
    case oneTime = "one_time"
    case subscription
}

enum TraceFenceMarketplaceBillingInterval: String, Codable, Sendable {
    case day
    case week
    case month
    case year
}

enum TraceFencePluginDelivery: String, Codable, Sendable {
    case builtIn = "built_in"
    case package
}

/// Runtime placement is derived from capabilities, not from where the plugin
/// was purchased. A plugin can participate in more than one host surface.
enum TraceFencePluginUseSurface: String, Hashable, Sendable {
    case workspace
    case menuBarQuickPanel
    case utilityWindow
    case background
}

/// The catalog describes what should be shown first on each host surface.
/// Plugin versions remain independent from this host-owned placement policy.
enum TraceFencePluginWorkspaceLanding: String, Codable, Equatable, Sendable {
    case quickControl = "quick_control"
    case dataPanel = "data_panel"
    case workspace
    case settings
}

enum TraceFencePluginMenuBarMode: String, Codable, Equatable, Sendable {
    case quickControl = "quick_control"
    case status
}

struct TraceFencePluginPresentationDescriptor: Codable, Equatable, Sendable {
    let workspaceDefault: TraceFencePluginWorkspaceLanding
    let menuBar: TraceFencePluginMenuBarMode?
}

/// Placement eligibility is catalog policy, not a side effect of having a UI
/// capability. A plugin may provide a panel without being appropriate for a
/// compact overview or menu-bar surface.
struct TraceFencePluginPlacementDescriptor: Codable, Equatable, Sendable {
    let overview: Bool
    let pluginTab: Bool
    let menuBarPluginTab: Bool
}

struct TraceFenceMarketplaceDodoProducts: Codable, Equatable, Sendable {
    let liveProductID: String?
    let testProductID: String?
    let acceptedLegacyProductIDs: [String]

    init(
        liveProductID: String?,
        testProductID: String?,
        acceptedLegacyProductIDs: [String] = []
    ) {
        self.liveProductID = liveProductID
        self.testProductID = testProductID
        self.acceptedLegacyProductIDs = acceptedLegacyProductIDs
    }

    func productID(for environment: TraceFenceDodoEnvironment) -> String? {
        switch environment {
        case .live: return liveProductID
        case .test: return testProductID
        }
    }

    var allProductIDs: Set<String> {
        Set([liveProductID, testProductID].compactMap { $0 } + acceptedLegacyProductIDs)
    }
}

struct TraceFenceMarketplaceOffer: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: TraceFenceMarketplaceOfferKind
    let currency: String
    let amountMinor: Int64
    let billingInterval: TraceFenceMarketplaceBillingInterval?
    let billingIntervalCount: Int?
    let trialHours: Int?
    let grantsAllPlugins: Bool
    let active: Bool
    let dodo: TraceFenceMarketplaceDodoProducts

    var displayPrice: String {
        TraceFenceMarketplacePriceFormatter.displayPrice(
            amountMinor: amountMinor,
            currency: currency
        )
    }

    var displayPriceWithPeriod: String {
        guard kind == .subscription,
              let billingInterval,
              let billingIntervalCount else {
            return displayPrice
        }
        let suffix: String
        switch (billingIntervalCount, billingInterval) {
        case (1, .month): suffix = "/month"
        case (1, .year): suffix = "/year"
        case (1, .week): suffix = "/week"
        case (1, .day): suffix = "/day"
        default: suffix = "/\(billingIntervalCount) \(billingInterval.rawValue)s"
        }
        return displayPrice + suffix
    }
}

struct TraceFencePluginPackageDescriptor: Codable, Equatable, Sendable {
    let url: URL
    let sha256: String
    let sizeBytes: Int64
    let bundleIdentifier: String
    let teamIdentifier: String
    let entryPoint: String
}

struct TraceFencePluginLocalizedMetadata: Codable, Equatable, Sendable {
    let displayName: String
    let summary: String
}

struct TraceFencePluginDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let version: String
    let name: String
    let summary: String
    let localizedMetadata: [String: TraceFencePluginLocalizedMetadata]?
    let category: String
    let systemImage: String
    let delivery: TraceFencePluginDelivery
    let minimumHostVersion: String
    let minimumSystemVersion: String
    let pluginKitVersion: Int
    let capabilities: [String]
    let presentation: TraceFencePluginPresentationDescriptor?
    let placements: TraceFencePluginPlacementDescriptor?
    let permissions: [String]
    let isFree: Bool
    let includedInAllAccess: Bool
    let standaloneOfferID: String?
    let trialHours: Int?
    let featured: Bool
    let package: TraceFencePluginPackageDescriptor?

    func localizedName(preferredLanguages: [String]? = nil) -> String {
        localizedValue(preferredLanguages: preferredLanguages ?? Self.activePreferredLanguages)?.displayName ?? name
    }

    func localizedSummary(preferredLanguages: [String]? = nil) -> String {
        localizedValue(preferredLanguages: preferredLanguages ?? Self.activePreferredLanguages)?.summary ?? summary
    }

    private static var activePreferredLanguages: [String] {
        [UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue]
    }

    private func localizedValue(preferredLanguages: [String]) -> TraceFencePluginLocalizedMetadata? {
        guard let localizedMetadata else { return nil }
        for language in preferredLanguages {
            if let exact = localizedMetadata[language] { return exact }
            let normalized = language.replacingOccurrences(of: "_", with: "-")
            if let exact = localizedMetadata[normalized] { return exact }
            if normalized.lowercased().hasPrefix("zh-hant"), let value = localizedMetadata["zh-Hant"] {
                return value
            }
            if normalized.lowercased().hasPrefix("zh"), let value = localizedMetadata["zh-Hans"] {
                return value
            }
            let base = normalized.split(separator: "-").first.map(String.init) ?? normalized
            if let value = localizedMetadata[base] { return value }
        }
        return localizedMetadata["en"]
    }

    var useSurfaces: Set<TraceFencePluginUseSurface> {
        var surfaces: Set<TraceFencePluginUseSurface> = []
        if supportsPluginTab {
            surfaces.insert(.workspace)
        }
        if supportsMenuBarPluginTab {
            surfaces.insert(.menuBarQuickPanel)
        }
        if capabilities.contains("presentation.window") {
            surfaces.insert(.utilityWindow)
        }
        if capabilities.contains("runtime.background") {
            surfaces.insert(.background)
        }
        return surfaces
    }

    var supportsMenuBarQuickPanel: Bool {
        useSurfaces.contains(.menuBarQuickPanel)
    }

    var supportsOverview: Bool {
        resolvedPlacements.overview
    }

    var supportsPluginTab: Bool {
        resolvedPlacements.pluginTab
    }

    var supportsMenuBarPluginTab: Bool {
        resolvedPlacements.menuBarPluginTab && menuBarMode != nil
    }

    var resolvedPlacements: TraceFencePluginPlacementDescriptor {
        placements ?? TraceFenceLegacyPluginPlacementPolicy.placements(for: self)
    }

    var workspaceLanding: TraceFencePluginWorkspaceLanding {
        if let presentation {
            return presentation.workspaceDefault
        }
        if capabilities.contains("tools.component-panel") {
            return .dataPanel
        }
        if capabilities.contains("tools.settings.workspace") {
            return .workspace
        }
        if capabilities.contains("tools.primary-panel") {
            return .quickControl
        }
        return .settings
    }

    var menuBarMode: TraceFencePluginMenuBarMode? {
        if let presentation {
            return presentation.menuBar
        }
        if capabilities.contains("tools.primary-panel") {
            return .quickControl
        }
        if capabilities.contains("tools.component-panel") {
            return .status
        }
        return nil
    }
}

/// Revision 7 catalogs predate explicit placement fields. Keep one bounded
/// migration map so current signed catalogs behave deterministically until the
/// next externally signed revision is published.
private enum TraceFenceLegacyPluginPlacementPolicy {
    private static let overviewPluginIDs: Set<String> = [
        "tracefence.tools.activity-bar",
        "tracefence.tools.battery-charge-limit",
        "tracefence.tools.device-battery",
        "tracefence.tools.fan-control",
        "tracefence.tools.ip-overview",
        "tracefence.tools.system-status",
    ]

    private static let menuBarPluginIDs: Set<String> = [
        "tracefence.tools.activity-bar",
        "tracefence.tools.app-volume",
        "tracefence.tools.appearance",
        "tracefence.tools.auto-hide-dock",
        "tracefence.tools.auto-hide-menu-bar",
        "tracefence.tools.battery-charge-limit",
        "tracefence.tools.calendar",
        "tracefence.tools.clipboard-clear",
        "tracefence.tools.device-battery",
        "tracefence.tools.display-brightness",
        "tracefence.tools.display-resolution",
        "tracefence.tools.display-sleep",
        "tracefence.tools.display-true-color",
        "tracefence.tools.eject-disk",
        "tracefence.tools.fan-control",
        "tracefence.tools.hide-notch",
        "tracefence.tools.ip-overview",
        "tracefence.tools.keep-awake",
        "tracefence.tools.lock-screen",
        "tracefence.tools.microphone-mute",
        "tracefence.tools.night-shift",
        "tracefence.tools.physical-clean-mode",
        "tracefence.tools.quit-apps",
        "tracefence.tools.sidecar",
        "tracefence.tools.stage-manager",
        "tracefence.tools.system-mute",
        "tracefence.tools.system-status",
        "tracefence.tools.translator",
    ]

    static func placements(for plugin: TraceFencePluginDescriptor) -> TraceFencePluginPlacementDescriptor {
        guard plugin.delivery == .package else {
            return .init(overview: false, pluginTab: false, menuBarPluginTab: false)
        }
        return .init(
            overview: overviewPluginIDs.contains(plugin.id),
            pluginTab: true,
            menuBarPluginTab: menuBarPluginIDs.contains(plugin.id)
        )
    }
}

struct TraceFenceMarketplaceCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let revision: Int64
    let publishedAt: Date
    let expiresAt: Date
    let businessID: String
    let offers: [TraceFenceMarketplaceOffer]
    let plugins: [TraceFencePluginDescriptor]

    func offer(id: String) -> TraceFenceMarketplaceOffer? {
        offers.first { $0.id == id && $0.active }
    }

    func plugin(id: String) -> TraceFencePluginDescriptor? {
        plugins.first { $0.id == id }
    }

    func isCompatible(_ plugin: TraceFencePluginDescriptor, hostVersion: String) -> Bool {
        hostVersion.compare(plugin.minimumHostVersion, options: .numeric) != .orderedAscending
    }
}

struct TraceFenceMarketplaceSignatureEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let keyID: String
    let algorithm: String
    let contentSHA256: String
    let signature: String
}

struct TraceFenceMarketplaceRefreshReport: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case skipped
        case unchanged
        case updated
        case failed
    }

    let status: Status
    let previousRevision: Int64
    let currentRevision: Int64
    let message: String
}

enum TraceFenceMarketplaceCatalogRuntime {
    static let catalogURL = URL(
        string: "https://raw.githubusercontent.com/AI-Scarlett/TraceFence/main/catalog/storefront-v1.json"
    )!
    static let signatureURL = URL(
        string: "https://raw.githubusercontent.com/AI-Scarlett/TraceFence/main/catalog/storefront-v1.json.sig"
    )!

    static let maximumCatalogBytes = 512 * 1_024
    static let maximumSignatureBytes = 8 * 1_024
    private static let state = State()

    static var activeCatalog: TraceFenceMarketplaceCatalog {
        state.snapshot().catalog
    }

    static var activeRevision: Int64 {
        activeCatalog.revision
    }

    static var isUsingVerifiedRemoteCatalog: Bool {
        state.snapshot().isVerifiedRemote
    }

    static func offer(id: String) -> TraceFenceMarketplaceOffer? {
        activeCatalog.offer(id: id)
    }

    static func plugin(id: String) -> TraceFencePluginDescriptor? {
        activeCatalog.plugin(id: id)
    }

    static func standardOffer(for plan: TraceFenceCheckoutPlan) -> TraceFenceMarketplaceOffer? {
        offer(id: plan.marketplaceOfferID).flatMap { $0.grantsAllPlugins ? $0 : nil }
    }

    static func standardProductID(
        for plan: TraceFenceCheckoutPlan,
        environment: TraceFenceDodoEnvironment
    ) -> String? {
        standardOffer(for: plan)?.dodo.productID(for: environment)
    }

    static func acceptedStandardProductIDs(environment: TraceFenceDodoEnvironment) -> Set<String> {
        var values = Set<String>()
        for offer in activeCatalog.offers where offer.grantsAllPlugins && offer.active {
            if let selected = offer.dodo.productID(for: environment) {
                values.insert(selected)
            }
            values.formUnion(offer.dodo.acceptedLegacyProductIDs)
        }
        return values
    }

    static func pluginProductID(
        pluginID: String,
        environment: TraceFenceDodoEnvironment
    ) -> String? {
        guard let plugin = plugin(id: pluginID),
              let offerID = plugin.standaloneOfferID,
              let offer = offer(id: offerID),
              offer.kind == .oneTime,
              !offer.grantsAllPlugins else {
            return nil
        }
        return offer.dodo.productID(for: environment)
    }

    static func checkoutURL(
        offerID: String,
        environment: TraceFenceDodoEnvironment,
        returnURL: URL
    ) -> URL? {
        guard let offer = offer(id: offerID),
              let productID = offer.dodo.productID(for: environment),
              Self.isSafeDodoProductID(productID),
              var components = URLComponents(
                string: "https://\(environment.checkoutHost)/buy/\(productID)"
              ) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "quantity", value: "1"),
            URLQueryItem(name: "showDiscounts", value: "false"),
            URLQueryItem(name: "redirect_url", value: returnURL.absoluteString)
        ]
        return components.url
    }

    static func installVerified(
        catalogData: Data,
        signatureData: Data,
        now: Date = Date()
    ) throws -> TraceFenceMarketplaceCatalog {
        let validated = try decodeAndVerify(
            catalogData: catalogData,
            signatureData: signatureData,
            now: now
        )
        let previous = state.snapshot()
        guard validated.catalog.revision >= previous.catalog.revision else {
            throw ValidationError.rollbackAttempt
        }
        try Store.save(catalogData: catalogData, signatureData: signatureData)
        state.install(.init(catalog: validated.catalog, isVerifiedRemote: true))
        return validated.catalog
    }

    static func decodeAndVerify(
        catalogData: Data,
        signatureData: Data,
        now: Date = Date()
    ) throws -> ValidatedCatalog {
        guard !catalogData.isEmpty, catalogData.count <= maximumCatalogBytes else {
            throw ValidationError.invalidSize
        }
        guard !signatureData.isEmpty, signatureData.count <= maximumSignatureBytes else {
            throw ValidationError.invalidSignatureEnvelope
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: TraceFenceMarketplaceSignatureEnvelope
        let catalog: TraceFenceMarketplaceCatalog
        do {
            envelope = try decoder.decode(TraceFenceMarketplaceSignatureEnvelope.self, from: signatureData)
            catalog = try decoder.decode(TraceFenceMarketplaceCatalog.self, from: catalogData)
        } catch {
            throw ValidationError.invalidJSON
        }

        guard envelope.schemaVersion == 1,
              envelope.algorithm.lowercased() == "ed25519",
              let publicKeyData = TrustStore.publicKeys[envelope.keyID],
              let signature = Data(base64Encoded: envelope.signature),
              signature.count == 64 else {
            throw ValidationError.invalidSignatureEnvelope
        }

        let digest = SHA256.hash(data: catalogData).map { String(format: "%02x", $0) }.joined()
        guard envelope.contentSHA256 == digest else {
            throw ValidationError.digestMismatch
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        } catch {
            throw ValidationError.invalidSignatureEnvelope
        }
        guard publicKey.isValidSignature(signature, for: catalogData) else {
            throw ValidationError.invalidSignature
        }

        try validate(catalog, now: now)
        return ValidatedCatalog(catalog: catalog, contentSHA256: digest, keyID: envelope.keyID)
    }

    static func debugSelfTestFailures(
        catalogData: Data,
        signatureData: Data,
        now: Date = Date()
    ) -> [String] {
        var failures: [String] = []
        do {
            let result = try decodeAndVerify(
                catalogData: catalogData,
                signatureData: signatureData,
                now: now
            )
            if result.catalog.offers.isEmpty { failures.append("catalog offers are empty") }
            if result.catalog.plugins.isEmpty { failures.append("catalog plugins are empty") }
        } catch {
            failures.append("signed catalog validation failed: \(error.localizedDescription)")
        }

        var tampered = catalogData
        if !tampered.isEmpty {
            tampered[tampered.startIndex] ^= 0x01
            if (try? decodeAndVerify(catalogData: tampered, signatureData: signatureData, now: now)) != nil {
                failures.append("tampered catalog was accepted")
            }
        }
        return failures
    }

    private static func validate(_ catalog: TraceFenceMarketplaceCatalog, now: Date) throws {
        guard catalog.schemaVersion == 1,
              catalog.revision > 0,
              catalog.publishedAt <= now.addingTimeInterval(24 * 60 * 60),
              catalog.expiresAt > now,
              catalog.expiresAt > catalog.publishedAt,
              catalog.expiresAt.timeIntervalSince(catalog.publishedAt) <= 370 * 24 * 60 * 60 else {
            throw ValidationError.invalidDocument
        }
        guard let expectedBusinessID = TraceFenceDistributionPolicy.bundledDodoBusinessID,
              catalog.businessID == expectedBusinessID else {
            throw ValidationError.unexpectedBusiness
        }
        guard !catalog.offers.isEmpty, catalog.offers.count <= 256,
              !catalog.plugins.isEmpty, catalog.plugins.count <= 512 else {
            throw ValidationError.invalidCount
        }

        var offerIDs = Set<String>()
        var productOwners: [String: String] = [:]
        for offer in catalog.offers {
            guard isSafeID(offer.id), offerIDs.insert(offer.id).inserted,
                  1...100 ~= offer.name.count,
                  offer.currency.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil,
                  0...100_000_000 ~= offer.amountMinor,
                  offer.trialHours.map({ 1...720 ~= $0 }) ?? true else {
                throw ValidationError.invalidOffer
            }
            switch offer.kind {
            case .oneTime:
                guard offer.billingInterval == nil, offer.billingIntervalCount == nil else {
                    throw ValidationError.invalidOffer
                }
            case .subscription:
                guard let count = offer.billingIntervalCount,
                      1...120 ~= count,
                      offer.billingInterval != nil else {
                    throw ValidationError.invalidOffer
                }
            }
            if offer.active {
                guard offer.amountMinor > 0,
                      offer.dodo.liveProductID.map(isSafeDodoProductID) ?? false else {
                    throw ValidationError.invalidOffer
                }
            }
            for productID in offer.dodo.allProductIDs {
                guard isSafeDodoProductID(productID) else { throw ValidationError.invalidOffer }
                if let owner = productOwners[productID], owner != offer.id {
                    throw ValidationError.duplicateProduct
                }
                productOwners[productID] = offer.id
            }
        }

        var pluginIDs = Set<String>()
        var standaloneOfferOwners: [String: String] = [:]
        for plugin in catalog.plugins {
            guard isSafeID(plugin.id), pluginIDs.insert(plugin.id).inserted,
                  isSafeVersion(plugin.version), isSafeVersion(plugin.minimumHostVersion),
                  isSafeSystemVersion(plugin.minimumSystemVersion),
                  0...TraceFencePluginPackageManager.supportedPluginKitVersion ~= plugin.pluginKitVersion,
                  1...100 ~= plugin.name.count,
                  1...500 ~= plugin.summary.count,
                  isSafeShortText(plugin.category),
                  isSafeShortText(plugin.systemImage),
                  plugin.capabilities.count <= 64,
                  Set(plugin.capabilities).count == plugin.capabilities.count,
                  plugin.capabilities.allSatisfy(isSafeCapability),
                  isValidPresentation(plugin),
                  isValidPlacements(plugin),
                  plugin.permissions.count <= 32,
                  Set(plugin.permissions).count == plugin.permissions.count,
                  plugin.permissions.allSatisfy(isSafeCapability),
                  isSafeLocalizedMetadata(plugin.localizedMetadata),
                  plugin.trialHours.map({ 1...720 ~= $0 }) ?? true else {
                throw ValidationError.invalidPlugin
            }
            if plugin.isFree {
                guard plugin.standaloneOfferID == nil else { throw ValidationError.invalidPlugin }
            } else {
                guard plugin.includedInAllAccess || plugin.standaloneOfferID != nil else {
                    throw ValidationError.invalidPlugin
                }
            }
            if let offerID = plugin.standaloneOfferID {
                guard let offer = catalog.offer(id: offerID),
                      offer.kind == .oneTime,
                      !offer.grantsAllPlugins else {
                    throw ValidationError.invalidPlugin
                }
                if let owner = standaloneOfferOwners[offerID], owner != plugin.id {
                    throw ValidationError.sharedStandaloneOffer
                }
                standaloneOfferOwners[offerID] = plugin.id
            }
            switch plugin.delivery {
            case .builtIn:
                guard plugin.package == nil, plugin.pluginKitVersion == 0 else {
                    throw ValidationError.invalidPackage
                }
            case .package:
                guard let package = plugin.package,
                      plugin.pluginKitVersion > 0,
                      plugin.trialHours == nil,
                      isAllowedPackageURL(package.url, pluginID: plugin.id, version: plugin.version),
                      package.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                      1...2_147_483_648 ~= package.sizeBytes,
                      package.bundleIdentifier.hasPrefix("com.tracefence.plugin."),
                      package.teamIdentifier == "UQ87N2WZ76",
                      package.entryPoint.range(of: #"^[A-Za-z0-9._-]{1,120}$"#, options: .regularExpression) != nil else {
                    throw ValidationError.invalidPackage
                }
            }
        }
    }

    private static func isSafeID(_ value: String) -> Bool {
        value.range(of: #"^[a-z0-9][a-z0-9._-]{2,79}$"#, options: .regularExpression) != nil
    }

    private static func isValidPresentation(_ plugin: TraceFencePluginDescriptor) -> Bool {
        guard let presentation = plugin.presentation else { return true }
        switch presentation.workspaceDefault {
        case .quickControl:
            guard plugin.capabilities.contains("tools.primary-panel") else { return false }
        case .dataPanel:
            guard plugin.capabilities.contains("tools.component-panel") else { return false }
        case .workspace:
            guard plugin.capabilities.contains("tools.settings.workspace") else { return false }
        case .settings:
            guard plugin.capabilities.contains(where: { $0.hasPrefix("tools.settings.") }) else { return false }
        }
        switch presentation.menuBar {
        case .quickControl:
            return plugin.capabilities.contains("tools.primary-panel")
        case .status:
            return plugin.capabilities.contains("tools.component-panel")
        case nil:
            return true
        }
    }

    private static func isValidPlacements(_ plugin: TraceFencePluginDescriptor) -> Bool {
        guard let placements = plugin.placements else { return true }
        if placements.overview && !placements.pluginTab {
            return false
        }
        if placements.menuBarPluginTab && plugin.menuBarMode == nil {
            return false
        }
        return true
    }

    private static func isSafeVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$"#, options: .regularExpression) != nil
    }

    private static func isSafeSystemVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+(?:\.[0-9]+){1,2}$"#, options: .regularExpression) != nil
    }

    private static func isSafeShortText(_ value: String) -> Bool {
        1...80 ~= value.count && !value.contains("\n") && !value.contains("\r")
    }

    private static func isSafeCapability(_ value: String) -> Bool {
        value.range(of: #"^[a-z][a-z0-9._-]{1,79}$"#, options: .regularExpression) != nil
    }

    private static func isSafeLocalizedMetadata(
        _ metadata: [String: TraceFencePluginLocalizedMetadata]?
    ) -> Bool {
        guard let metadata else { return true }
        guard metadata.count <= 32 else { return false }
        return metadata.allSatisfy { locale, value in
            locale.range(of: #"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$"#, options: .regularExpression) != nil
                && 1...100 ~= value.displayName.count
                && 1...500 ~= value.summary.count
                && !value.displayName.contains("\n")
                && !value.summary.contains("\r")
        }
    }

    private static func isSafeDodoProductID(_ value: String) -> Bool {
        value.range(of: #"^pdt_[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isAllowedPackageURL(_ url: URL, pluginID: String, version: String) -> Bool {
        guard pluginID.hasPrefix("tracefence.tools.") else { return false }
        let rawPluginID = String(pluginID.dropFirst("tracefence.tools.".count))
        let expectedPath = "/AI-Scarlett/TraceFence/releases/download/plugin-\(rawPluginID)-v\(version)/\(rawPluginID)-\(version).mactoolsplugin.zip"
        return url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "github.com"
            && url.path == expectedPath
            && url.query == nil
            && url.fragment == nil
    }

    struct ValidatedCatalog: Sendable {
        let catalog: TraceFenceMarketplaceCatalog
        let contentSHA256: String
        let keyID: String
    }

    fileprivate struct ActiveState: Sendable {
        let catalog: TraceFenceMarketplaceCatalog
        let isVerifiedRemote: Bool
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var value: ActiveState

        init() {
            let bundled = ActiveState(catalog: BuiltIn.catalog, isVerifiedRemote: false)
            if let cached = try? Store.loadVerified(),
               cached.catalog.revision >= bundled.catalog.revision {
                value = .init(catalog: cached.catalog, isVerifiedRemote: true)
            } else {
                value = bundled
            }
        }

        func snapshot() -> ActiveState {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func install(_ newValue: ActiveState) {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    struct Metadata: Codable, Sendable {
        let revision: Int64
        let contentSHA256: String
        let etag: String?
        let lastModified: String?
        let lastCheckedAt: Date
    }

    enum Store {
        static func loadVerified() throws -> ValidatedCatalog {
            guard let catalogData = try boundedData(
                at: catalogFileURL,
                maximumBytes: maximumCatalogBytes
            ), let signatureData = try boundedData(
                at: signatureFileURL,
                maximumBytes: maximumSignatureBytes
            ) else {
                throw ValidationError.invalidSize
            }
            return try decodeAndVerify(catalogData: catalogData, signatureData: signatureData)
        }

        static func save(catalogData: Data, signatureData: Data) throws {
            try ensureDirectory()
            try catalogData.write(to: catalogFileURL, options: .atomic)
            try signatureData.write(to: signatureFileURL, options: .atomic)
            try secure(catalogFileURL)
            try secure(signatureFileURL)
        }

        static func loadMetadata() -> Metadata? {
            guard let data = try? Data(contentsOf: metadataFileURL),
                  let value = try? JSONDecoder().decode(Metadata.self, from: data) else {
                return nil
            }
            return value
        }

        static func saveMetadata(_ value: Metadata) throws {
            try ensureDirectory()
            let data = try JSONEncoder().encode(value)
            try data.write(to: metadataFileURL, options: .atomic)
            try secure(metadataFileURL)
        }

        private static func boundedData(at url: URL, maximumBytes: Int) throws -> Data? {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize,
                  size > 0,
                  size <= maximumBytes else {
                return nil
            }
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        }

        private static func ensureDirectory() throws {
            try FileManager.default.createDirectory(
                at: catalogFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        private static func secure(_ url: URL) throws {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }

        private static var catalogFileURL: URL {
            URL(fileURLWithPath: SandboxPaths.shared.marketplaceCatalogPath)
        }

        private static var signatureFileURL: URL {
            URL(fileURLWithPath: SandboxPaths.shared.marketplaceCatalogSignaturePath)
        }

        private static var metadataFileURL: URL {
            URL(fileURLWithPath: SandboxPaths.shared.marketplaceCatalogMetadataPath)
        }
    }

    private enum TrustStore {
        static let publicKeys: [String: Data] = [
            "catalog-2026-01": Data(base64Encoded: "To2lPOjn2E2wdrWQvs9NGdKAEHfsBA2J3o1DAUjXcJc=")!
        ]
    }

    private enum BuiltIn {
        static let catalog = TraceFenceMarketplaceCatalog(
            schemaVersion: 1,
            revision: 2,
            publishedAt: Date(timeIntervalSince1970: 1_786_671_000),
            expiresAt: .distantFuture,
            businessID: TraceFenceDistributionPolicy.bundledDodoBusinessID ?? "",
            offers: [
                TraceFenceMarketplaceOffer(
                    id: "standard.monthly",
                    name: "TraceFence Standard Monthly",
                    kind: .subscription,
                    currency: "USD",
                    amountMinor: 999,
                    billingInterval: .month,
                    billingIntervalCount: 1,
                    trialHours: 48,
                    grantsAllPlugins: true,
                    active: true,
                    dodo: .init(
                        liveProductID: "pdt_0Nj4q5PqaHwgy17MmjlAk",
                        testProductID: "pdt_0Nj4pRs43qM7S5NM2yl2D"
                    )
                ),
                TraceFenceMarketplaceOffer(
                    id: "standard.annual",
                    name: "TraceFence Standard Annual",
                    kind: .subscription,
                    currency: "USD",
                    amountMinor: 7_999,
                    billingInterval: .year,
                    billingIntervalCount: 1,
                    trialHours: 48,
                    grantsAllPlugins: true,
                    active: true,
                    dodo: .init(
                        liveProductID: "pdt_0Nj4rXdh9EI3A7uzyYWpk",
                        testProductID: "pdt_0Nj4pnQWqPMk14yHT9Q1i"
                    )
                ),
                TraceFenceMarketplaceOffer(
                    id: "plugin.agent-guard.lifetime",
                    name: "TraceFence Standard - 1",
                    kind: .oneTime,
                    currency: "USD",
                    amountMinor: 90,
                    billingInterval: nil,
                    billingIntervalCount: nil,
                    trialHours: nil,
                    grantsAllPlugins: false,
                    active: true,
                    dodo: .init(
                        liveProductID: "pdt_0NlLDDcejZUSrZ0bRNosp",
                        testProductID: nil
                    )
                )
            ],
            plugins: [
                builtInPlugin(
                    id: "tracefence.agent-monitor",
                    name: "Agent Monitor",
                    summary: "Live local status and activity for supported AI agents.",
                    category: "Agent",
                    systemImage: "waveform.path.ecg",
                    capabilities: ["agent.status", "agent.activity"],
                    isFree: true,
                    includedInAllAccess: true,
                    featured: true
                ),
                builtInPlugin(
                    id: "tracefence.agent-guard",
                    name: "Agent Guard",
                    summary: "Review local agent operations, approvals, and safety events.",
                    category: "Security",
                    systemImage: "shield.checkered",
                    capabilities: ["agent.audit", "agent.approval"],
                    isFree: false,
                    includedInAllAccess: true,
                    standaloneOfferID: "plugin.agent-guard.lifetime",
                    featured: true
                ),
                builtInPlugin(
                    id: "tracefence.token-usage",
                    name: "Token & Usage",
                    summary: "Cached multi-agent token totals, model ranking, and cost estimates.",
                    category: "Analytics",
                    systemImage: "number.circle.fill",
                    capabilities: ["usage.tokens", "usage.cost"],
                    isFree: false,
                    includedInAllAccess: true,
                    featured: true
                ),
                builtInPlugin(
                    id: "tracefence.disk-advisor",
                    name: "Disk Advisor",
                    summary: "Bounded storage analysis for agent history, build output, and large files.",
                    category: "Storage",
                    systemImage: "internaldrive.fill",
                    capabilities: ["storage.scan", "storage.review"],
                    isFree: true,
                    includedInAllAccess: true,
                    featured: true
                ),
                builtInPlugin(
                    id: "tracefence.ios-remote",
                    name: "iOS Remote Pairing",
                    summary: "Pair TraceFence Sentinel and control supported local agent sessions.",
                    category: "Remote",
                    systemImage: "iphone.gen3.radiowaves.left.and.right",
                    capabilities: ["remote.pairing", "remote.control"],
                    isFree: false,
                    includedInAllAccess: true,
                    featured: true
                )
            ]
        )

        private static func builtInPlugin(
            id: String,
            name: String,
            summary: String,
            category: String,
            systemImage: String,
            capabilities: [String],
            isFree: Bool,
            includedInAllAccess: Bool,
            standaloneOfferID: String? = nil,
            featured: Bool
        ) -> TraceFencePluginDescriptor {
            TraceFencePluginDescriptor(
                id: id,
                version: "1.0.0",
                name: name,
                summary: summary,
                localizedMetadata: nil,
                category: category,
                systemImage: systemImage,
                delivery: .builtIn,
                minimumHostVersion: "1.1.9",
                minimumSystemVersion: "13.0",
                pluginKitVersion: 0,
                capabilities: capabilities,
                presentation: nil,
                placements: .init(overview: false, pluginTab: false, menuBarPluginTab: false),
                permissions: [],
                isFree: isFree,
                includedInAllAccess: includedInAllAccess,
                standaloneOfferID: standaloneOfferID,
                trialHours: isFree ? nil : 24,
                featured: featured,
                package: nil
            )
        }
    }

    enum ValidationError: LocalizedError {
        case invalidSize
        case invalidJSON
        case invalidSignatureEnvelope
        case digestMismatch
        case invalidSignature
        case invalidDocument
        case unexpectedBusiness
        case invalidCount
        case invalidOffer
        case duplicateProduct
        case invalidPlugin
        case invalidPackage
        case sharedStandaloneOffer
        case rollbackAttempt

        var errorDescription: String? {
            switch self {
            case .invalidSize: return "The marketplace catalog has an invalid size."
            case .invalidJSON: return "The marketplace catalog or signature is invalid JSON."
            case .invalidSignatureEnvelope: return "The marketplace signature envelope is invalid."
            case .digestMismatch: return "The marketplace catalog digest does not match its signature envelope."
            case .invalidSignature: return "The marketplace catalog signature is invalid."
            case .invalidDocument: return "The marketplace catalog version or validity period is invalid."
            case .unexpectedBusiness: return "The marketplace catalog belongs to an unexpected Dodo business."
            case .invalidCount: return "The marketplace catalog contains an invalid number of entries."
            case .invalidOffer: return "The marketplace catalog contains an invalid offer."
            case .duplicateProduct: return "A Dodo product is assigned to more than one offer."
            case .invalidPlugin: return "The marketplace catalog contains an invalid plugin."
            case .invalidPackage: return "The marketplace catalog contains an unsafe plugin package."
            case .sharedStandaloneOffer: return "A standalone offer cannot unlock multiple plugins without a binding service."
            case .rollbackAttempt: return "The marketplace catalog revision is older than the active catalog."
            }
        }
    }
}

enum TraceFenceMarketplacePriceFormatter {
    static func displayPrice(amountMinor: Int64, currency: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = locale
        let fractionDigits = formatter.maximumFractionDigits
        let divisor = pow(10.0, Double(fractionDigits))
        let value = NSDecimalNumber(value: Double(amountMinor) / divisor)
        return formatter.string(from: value) ?? "\(currency) \(value.stringValue)"
    }
}

private final class TraceFenceMarketplaceNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

actor TraceFenceMarketplaceCatalogUpdateService {
    static let shared = TraceFenceMarketplaceCatalogUpdateService()

    private static let minimumRefreshInterval: TimeInterval = 15 * 60
    private static let failedAttemptBackoff: TimeInterval = 60
    private let delegate = TraceFenceMarketplaceNoRedirectDelegate()
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
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func refreshIfNeeded(force: Bool = false) async -> TraceFenceMarketplaceRefreshReport {
        let previousRevision = TraceFenceMarketplaceCatalogRuntime.activeRevision
        guard SandboxPaths.isDirectDistribution else {
            return report(.skipped, previous: previousRevision, message: "The marketplace is limited to the website build.")
        }
        guard UserDefaults.standard.string(forKey: "networkMode") ?? "internet" == "internet" else {
            return report(.skipped, previous: previousRevision, message: "Marketplace refresh is disabled in the current network mode.")
        }

        let now = Date()
        if !force,
           let lastAttemptAt,
           now.timeIntervalSince(lastAttemptAt) < Self.failedAttemptBackoff {
            return report(.skipped, previous: previousRevision, message: "A marketplace refresh was attempted recently.")
        }
        let storedMetadata = TraceFenceMarketplaceCatalogRuntime.Store.loadMetadata()
        if !force,
           let storedMetadata,
           now.timeIntervalSince(storedMetadata.lastCheckedAt) < Self.minimumRefreshInterval {
            return report(.skipped, previous: previousRevision, message: "The verified marketplace cache is still fresh.")
        }
        lastAttemptAt = now

        do {
            var catalogRequest = secureRequest(url: TraceFenceMarketplaceCatalogRuntime.catalogURL)
            if let etag = storedMetadata?.etag {
                catalogRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = storedMetadata?.lastModified {
                catalogRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }

            let (catalogData, catalogResponse) = try await session.data(for: catalogRequest)
            guard let catalogHTTP = catalogResponse as? HTTPURLResponse,
                  Self.isAllowedFinalURL(catalogHTTP.url, expected: TraceFenceMarketplaceCatalogRuntime.catalogURL) else {
                throw RefreshError.invalidResponse
            }
            if catalogHTTP.statusCode == 304 {
                guard TraceFenceMarketplaceCatalogRuntime.isUsingVerifiedRemoteCatalog else {
                    throw RefreshError.invalidResponse
                }
                try TraceFenceMarketplaceCatalogRuntime.Store.saveMetadata(.init(
                    revision: TraceFenceMarketplaceCatalogRuntime.activeRevision,
                    contentSHA256: storedMetadata?.contentSHA256 ?? "",
                    etag: storedMetadata?.etag,
                    lastModified: storedMetadata?.lastModified,
                    lastCheckedAt: now
                ))
                return report(.unchanged, previous: previousRevision, message: "The signed GitHub marketplace catalog has not changed.")
            }
            guard catalogHTTP.statusCode == 200,
                  !catalogData.isEmpty,
                  catalogData.count <= TraceFenceMarketplaceCatalogRuntime.maximumCatalogBytes else {
                throw RefreshError.invalidResponse
            }

            let signatureRequest = secureRequest(url: TraceFenceMarketplaceCatalogRuntime.signatureURL)
            let (signatureData, signatureResponse) = try await session.data(for: signatureRequest)
            guard let signatureHTTP = signatureResponse as? HTTPURLResponse,
                  signatureHTTP.statusCode == 200,
                  Self.isAllowedFinalURL(signatureHTTP.url, expected: TraceFenceMarketplaceCatalogRuntime.signatureURL),
                  !signatureData.isEmpty,
                  signatureData.count <= TraceFenceMarketplaceCatalogRuntime.maximumSignatureBytes else {
                throw RefreshError.invalidResponse
            }

            let installed = try TraceFenceMarketplaceCatalogRuntime.installVerified(
                catalogData: catalogData,
                signatureData: signatureData,
                now: now
            )
            let digest = SHA256.hash(data: catalogData).map { String(format: "%02x", $0) }.joined()
            try TraceFenceMarketplaceCatalogRuntime.Store.saveMetadata(.init(
                revision: installed.revision,
                contentSHA256: digest,
                etag: catalogHTTP.value(forHTTPHeaderField: "ETag"),
                lastModified: catalogHTTP.value(forHTTPHeaderField: "Last-Modified"),
                lastCheckedAt: now
            ))
            return report(
                installed.revision == previousRevision ? .unchanged : .updated,
                previous: previousRevision,
                message: "Installed a verified GitHub marketplace catalog."
            )
        } catch {
            return report(.failed, previous: previousRevision, message: error.localizedDescription)
        }
    }

    private func secureRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TraceFence Marketplace Catalog", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func report(
        _ status: TraceFenceMarketplaceRefreshReport.Status,
        previous: Int64,
        message: String
    ) -> TraceFenceMarketplaceRefreshReport {
        TraceFenceMarketplaceRefreshReport(
            status: status,
            previousRevision: previous,
            currentRevision: TraceFenceMarketplaceCatalogRuntime.activeRevision,
            message: message
        )
    }

    private static func isAllowedFinalURL(_ actual: URL?, expected: URL) -> Bool {
        guard let actual else { return false }
        return actual.scheme?.lowercased() == "https"
            && actual.host?.lowercased() == "raw.githubusercontent.com"
            && actual.path == expected.path
            && actual.query == nil
            && actual.fragment == nil
    }

    private enum RefreshError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            "The marketplace endpoint returned an invalid response."
        }
    }
}

@MainActor
final class TraceFenceMarketplaceCatalogService: ObservableObject {
    static let shared = TraceFenceMarketplaceCatalogService()

    @Published private(set) var catalog = TraceFenceMarketplaceCatalogRuntime.activeCatalog
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastReport: TraceFenceMarketplaceRefreshReport?

    private init() {}

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let report = await TraceFenceMarketplaceCatalogUpdateService.shared.refreshIfNeeded(force: force)
        catalog = TraceFenceMarketplaceCatalogRuntime.activeCatalog
        lastReport = report
        isRefreshing = false
    }
}

private struct TraceFenceMarketplaceInstallStatsSnapshot: Codable, Sendable {
    let fetchedAt: Date
    let countsByAssetURL: [String: Int]
}

private actor TraceFenceMarketplaceInstallStatsFetcher {
    static let shared = TraceFenceMarketplaceInstallStatsFetcher()

    private struct Release: Decodable, Sendable {
        let assets: [Asset]
    }

    private struct Asset: Decodable, Sendable {
        let browserDownloadURL: URL
        let downloadCount: Int

        private enum CodingKeys: String, CodingKey {
            case browserDownloadURL = "browser_download_url"
            case downloadCount = "download_count"
        }
    }

    private let delegate = TraceFenceMarketplaceNoRedirectDelegate()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func fetch() async throws -> TraceFenceMarketplaceInstallStatsSnapshot {
        var countsByAssetURL: [String: Int] = [:]
        for page in 1...3 {
            var components = URLComponents(string: "https://api.github.com/repos/AI-Scarlett/TraceFence/releases")!
            components.queryItems = [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page))
            ]
            guard let url = components.url else { throw FetchError.invalidResponse }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("TraceFence Marketplace Install Stats", forHTTPHeaderField: "User-Agent")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  http.url?.scheme?.lowercased() == "https",
                  http.url?.host?.lowercased() == "api.github.com",
                  http.url?.path == "/repos/AI-Scarlett/TraceFence/releases",
                  data.count <= 4 * 1_024 * 1_024 else {
                throw FetchError.invalidResponse
            }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            for release in releases {
                for asset in release.assets {
                    countsByAssetURL[asset.browserDownloadURL.absoluteString] = max(0, asset.downloadCount)
                }
            }
            if releases.count < 100 { break }
        }
        return TraceFenceMarketplaceInstallStatsSnapshot(
            fetchedAt: Date(),
            countsByAssetURL: countsByAssetURL
        )
    }

    private enum FetchError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            "GitHub did not return valid plugin download statistics."
        }
    }
}

/// GitHub already counts downloads for each signed plugin Release asset. That
/// gives the marketplace a credential-free, tamper-resistant approximation of
/// installs without embedding a GitHub write token or collecting device IDs.
/// Updates and reinstalls are downloads too, so the UI states that exact scope.
@MainActor
final class TraceFenceMarketplaceInstallStatsService: ObservableObject {
    static let shared = TraceFenceMarketplaceInstallStatsService()

    @Published private(set) var countsByPluginID: [String: Int] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastErrorMessage: String?

    private static let cacheKey = "traceFence.marketplace.githubInstallStats.v1"
    private static let minimumRefreshInterval: TimeInterval = 6 * 60 * 60
    private var snapshot: TraceFenceMarketplaceInstallStatsSnapshot?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(TraceFenceMarketplaceInstallStatsSnapshot.self, from: data) {
            snapshot = cached
            lastUpdatedAt = cached.fetchedAt
        }
    }

    func count(for plugin: TraceFencePluginDescriptor) -> Int? {
        countsByPluginID[plugin.id]
    }

    func refresh(catalog: TraceFenceMarketplaceCatalog, force: Bool = false) async {
        apply(snapshot: snapshot, catalog: catalog)
        guard SandboxPaths.isDirectDistribution,
              (UserDefaults.standard.string(forKey: "networkMode") ?? "internet") == "internet",
              !isRefreshing else { return }
        if !force,
           let snapshot,
           Date().timeIntervalSince(snapshot.fetchedAt) < Self.minimumRefreshInterval {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await TraceFenceMarketplaceInstallStatsFetcher.shared.fetch()
            snapshot = fresh
            lastUpdatedAt = fresh.fetchedAt
            lastErrorMessage = nil
            if let data = try? JSONEncoder().encode(fresh) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
            apply(snapshot: fresh, catalog: catalog)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func apply(
        snapshot: TraceFenceMarketplaceInstallStatsSnapshot?,
        catalog: TraceFenceMarketplaceCatalog
    ) {
        guard let snapshot else { return }
        countsByPluginID = Dictionary(uniqueKeysWithValues: catalog.plugins.compactMap { plugin in
            guard let assetURL = plugin.package?.url.absoluteString,
                  let count = snapshot.countsByAssetURL[assetURL] else { return nil }
            return (plugin.id, count)
        })
    }
}

enum TraceFencePluginAccessState: Equatable {
    case free
    case allAccess
    case licensed
    case trial(expiresAt: Date)
    case locked
}

struct TraceFencePluginGrantSnapshot: Codable, Equatable, Identifiable {
    var id: String { pluginID }
    let pluginID: String
    var status: DirectLicenseStatus
    var licenseKeySuffix: String?
    var instanceID: String?
    var productID: String?
    var licenseKeyID: String?
    var lastValidatedAt: Date?
    var message: String?
}

@MainActor
final class TraceFencePluginEntitlementService: ObservableObject {
    static let shared = TraceFencePluginEntitlementService()

    @Published private(set) var grants: [String: TraceFencePluginGrantSnapshot]
    @Published private(set) var busyPluginIDs: Set<String> = []

    private let snapshotKey = "traceFencePluginGrantSnapshotsV1"
    private let keychainService = "TraceFence.PluginEntitlement"
    private let offlineGraceDuration: TimeInterval = 72 * 60 * 60
    private let dateCodec = ISO8601DateFormatter()
    private var trialExpiryTasks: [String: Task<Void, Never>] = [:]
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private init() {
        if let data = UserDefaults.standard.data(forKey: snapshotKey),
           let values = try? JSONDecoder().decode([String: TraceFencePluginGrantSnapshot].self, from: data) {
            grants = values
        } else {
            grants = [:]
        }
        for plugin in TraceFenceMarketplaceCatalogRuntime.activeCatalog.plugins {
            if let expiresAt = trialExpiresAt(pluginID: plugin.id), expiresAt > Date() {
                scheduleTrialExpiry(pluginID: plugin.id, expiresAt: expiresAt)
            }
        }
    }

    func accessState(pluginID: String, now: Date = Date()) -> TraceFencePluginAccessState {
        guard let plugin = TraceFenceMarketplaceCatalogRuntime.plugin(id: pluginID) else { return .locked }
        guard TraceFenceMarketplaceCatalogRuntime.activeCatalog.isCompatible(
            plugin,
            hostVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        ) else {
            return .locked
        }
        if plugin.isFree { return .free }
        if plugin.includedInAllAccess && DirectLicenseService.shared.isLicensed { return .allAccess }
        if grants[pluginID]?.status == .licensed { return .licensed }
        if let expiresAt = trialExpiresAt(pluginID: pluginID), expiresAt > now {
            return .trial(expiresAt: expiresAt)
        }
        return .locked
    }

    func beginTrial(pluginID: String, now: Date = Date()) {
        guard let plugin = TraceFenceMarketplaceCatalogRuntime.plugin(id: pluginID),
              !plugin.isFree,
              plugin.trialHours != nil,
              readSecret(account: trialAccount(pluginID)) == nil else {
            return
        }
        saveSecret(dateCodec.string(from: now), account: trialAccount(pluginID))
        if let expiresAt = trialExpiresAt(pluginID: pluginID) {
            scheduleTrialExpiry(pluginID: pluginID, expiresAt: expiresAt)
        }
        objectWillChange.send()
        notifyEntitlementChanged(pluginID: pluginID)
    }

    func trialExpiresAt(pluginID: String) -> Date? {
        guard let plugin = TraceFenceMarketplaceCatalogRuntime.plugin(id: pluginID),
              let hours = plugin.trialHours,
              let raw = readSecret(account: trialAccount(pluginID)),
              let startedAt = dateCodec.date(from: raw) else {
            return nil
        }
        return startedAt.addingTimeInterval(TimeInterval(hours) * 60 * 60)
    }

    func openCheckout(pluginID: String) {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect,
              let plugin = TraceFenceMarketplaceCatalogRuntime.plugin(id: pluginID),
              let offerID = plugin.standaloneOfferID,
              let returnURL = TraceFenceDistributionPolicy.checkoutReturnURL,
              let url = TraceFenceMarketplaceCatalogRuntime.checkoutURL(
                offerID: offerID,
                environment: TraceFenceDistributionPolicy.dodoEnvironment,
                returnURL: returnURL
              ) else {
            updateMessage(pluginID: pluginID, message: "This plugin does not have an active standalone checkout offer yet.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func activate(pluginID: String, licenseKey rawLicenseKey: String) async {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect,
              let expectedBusinessID = TraceFenceDistributionPolicy.dodoBusinessID,
              let expectedProductID = TraceFenceMarketplaceCatalogRuntime.pluginProductID(
                pluginID: pluginID,
                environment: TraceFenceDistributionPolicy.dodoEnvironment
              ) else {
            updateMessage(pluginID: pluginID, message: "This plugin is not configured for standalone activation.")
            return
        }
        let licenseKey = rawLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !licenseKey.isEmpty else {
            updateMessage(pluginID: pluginID, message: "Enter a license key first.")
            return
        }

        busyPluginIDs.insert(pluginID)
        defer { busyPluginIDs.remove(pluginID) }
        do {
            let response: MarketplaceDodoActivationResponse = try await postDodo(
                endpoint: "activate",
                fields: ["license_key": licenseKey, "name": instanceName(pluginID: pluginID)]
            )
            guard response.businessId == expectedBusinessID,
                  response.product.productId == expectedProductID else {
                try? await postDodoWithoutResponse(endpoint: "deactivate", fields: [
                    "license_key": licenseKey,
                    "license_key_instance_id": response.id
                ])
                throw PluginEntitlementError.unexpectedProduct
            }
            saveSecret(licenseKey, account: licenseAccount(pluginID))
            saveSecret(response.id, account: instanceAccount(pluginID))
            grants[pluginID] = TraceFencePluginGrantSnapshot(
                pluginID: pluginID,
                status: .licensed,
                licenseKeySuffix: maskedSuffix(licenseKey),
                instanceID: response.id,
                productID: response.product.productId,
                licenseKeyID: response.licenseKeyId,
                lastValidatedAt: Date(),
                message: nil
            )
            persist()
            notifyEntitlementChanged(pluginID: pluginID)
        } catch {
            grants[pluginID] = TraceFencePluginGrantSnapshot(
                pluginID: pluginID,
                status: .error,
                licenseKeySuffix: maskedSuffix(licenseKey),
                instanceID: nil,
                productID: nil,
                licenseKeyID: nil,
                lastValidatedAt: nil,
                message: error.localizedDescription
            )
            persist()
        }
    }

    func validate(pluginID: String) async {
        guard let licenseKey = readSecret(account: licenseAccount(pluginID)),
              let snapshot = grants[pluginID] else {
            return
        }
        busyPluginIDs.insert(pluginID)
        defer { busyPluginIDs.remove(pluginID) }
        do {
            var fields = ["license_key": licenseKey]
            if let instanceID = readSecret(account: instanceAccount(pluginID)) {
                fields["license_key_instance_id"] = instanceID
            }
            let response: MarketplaceDodoValidationResponse = try await postDodo(
                endpoint: "validate",
                fields: fields
            )
            var updated = snapshot
            updated.status = response.valid ? .licensed : .inactive
            updated.lastValidatedAt = Date()
            updated.message = response.valid ? nil : "This plugin license is no longer valid."
            grants[pluginID] = updated
        } catch {
            var updated = snapshot
            let isWithinGrace = snapshot.status == .licensed
                && snapshot.lastValidatedAt.map { Date().timeIntervalSince($0) <= offlineGraceDuration } == true
            updated.status = isWithinGrace ? .licensed : .error
            updated.message = isWithinGrace
                ? "The license service is unavailable. Cached plugin access remains active during the offline grace period."
                : error.localizedDescription
            grants[pluginID] = updated
        }
        persist()
        notifyEntitlementChanged(pluginID: pluginID)
    }

    func deactivate(pluginID: String) async {
        if let licenseKey = readSecret(account: licenseAccount(pluginID)),
           let instanceID = readSecret(account: instanceAccount(pluginID)) {
            busyPluginIDs.insert(pluginID)
            defer { busyPluginIDs.remove(pluginID) }
            do {
                try await postDodoWithoutResponse(endpoint: "deactivate", fields: [
                    "license_key": licenseKey,
                    "license_key_instance_id": instanceID
                ])
            } catch {
                updateMessage(pluginID: pluginID, message: error.localizedDescription)
                return
            }
        }
        deleteSecret(account: licenseAccount(pluginID))
        deleteSecret(account: instanceAccount(pluginID))
        grants.removeValue(forKey: pluginID)
        persist()
        notifyEntitlementChanged(pluginID: pluginID)
    }

    private func postDodo<T: Decodable>(endpoint: String, fields: [String: String]) async throws -> T {
        let data = try await postDodoData(endpoint: endpoint, fields: fields)
        guard let response = try? decoder.decode(T.self, from: data) else {
            throw PluginEntitlementError.invalidResponse
        }
        return response
    }

    private func postDodoWithoutResponse(endpoint: String, fields: [String: String]) async throws {
        _ = try await postDodoData(endpoint: endpoint, fields: fields)
    }

    private func postDodoData(endpoint: String, fields: [String: String]) async throws -> Data {
        var request = URLRequest(
            url: TraceFenceDistributionPolicy.dodoEnvironment.licenseBaseURL.appendingPathComponent(endpoint)
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("TraceFence Marketplace/1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PluginEntitlementError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw PluginEntitlementError.http(http.statusCode)
        }
        return data
    }

    private func instanceName(pluginID: String) -> String {
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return "TraceFence \(pluginID) on \(host)"
    }

    private func updateMessage(pluginID: String, message: String) {
        var snapshot = grants[pluginID] ?? TraceFencePluginGrantSnapshot(
            pluginID: pluginID,
            status: .unlicensed,
            licenseKeySuffix: nil,
            instanceID: nil,
            productID: nil,
            licenseKeyID: nil,
            lastValidatedAt: nil,
            message: nil
        )
        snapshot.message = message
        grants[pluginID] = snapshot
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(grants) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    private func licenseAccount(_ pluginID: String) -> String { "\(pluginID).license_key" }
    private func instanceAccount(_ pluginID: String) -> String { "\(pluginID).instance_id" }
    private func trialAccount(_ pluginID: String) -> String { "\(pluginID).trial_started_at" }

    private func saveSecret(_ value: String, account: String) {
        deleteSecret(account: account)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func readSecret(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteSecret(account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }

    private func maskedSuffix(_ value: String) -> String {
        let suffix = value.suffix(4)
        return suffix.isEmpty ? "" : "••••\(suffix)"
    }

    private func notifyEntitlementChanged(pluginID: String) {
        NotificationCenter.default.post(
            name: .traceFenceEntitlementDidChange,
            object: nil,
            userInfo: ["pluginID": pluginID]
        )
    }

    private func scheduleTrialExpiry(pluginID: String, expiresAt: Date) {
        trialExpiryTasks[pluginID]?.cancel()
        trialExpiryTasks[pluginID] = Task { [weak self] in
            let remaining = max(0, expiresAt.timeIntervalSinceNow)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(min(remaining, 30 * 24 * 60 * 60) * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            self.trialExpiryTasks[pluginID] = nil
            self.objectWillChange.send()
            self.notifyEntitlementChanged(pluginID: pluginID)
        }
    }
}

private struct MarketplaceDodoActivationResponse: Decodable {
    let businessId: String
    let id: String
    let licenseKeyId: String?
    let product: MarketplaceDodoProduct
}

private struct MarketplaceDodoProduct: Decodable {
    let productId: String
    let name: String?
}

private struct MarketplaceDodoValidationResponse: Decodable {
    let valid: Bool
}

private enum PluginEntitlementError: LocalizedError {
    case invalidResponse
    case unexpectedProduct
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The plugin license server returned an invalid response."
        case .unexpectedProduct: return "This license key is not bound to the selected TraceFence plugin."
        case .http(let status): return "Plugin license server error (HTTP \(status))."
        }
    }
}
