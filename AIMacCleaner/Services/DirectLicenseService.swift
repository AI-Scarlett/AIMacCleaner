import AppKit
import CryptoKit
import Foundation
import Security
import StoreKit

enum TraceFenceDistributionChannel: String, Codable {
    case appStore
    case direct

    var title: String {
        switch self {
        case .appStore: return "Mac App Store"
        case .direct: return "TraceFence Website"
        }
    }

    var isAppStore: Bool { self == .appStore }
    var isDirect: Bool { self == .direct }
}

enum TraceFenceSubscriptionTier: String, Codable, CaseIterable {
    case none
    case appStoreStandard
    case directStandard

    var title: String {
        switch self {
        case .none: return "Free"
        case .appStoreStandard: return "TraceFence Standard"
        case .directStandard: return "TraceFence Standard"
        }
    }

    var priceLine: String {
        switch self {
        case .none:
            return "Limited local monitoring"
        case .appStoreStandard:
            return "$9.99/month or $79.99/year"
        case .directStandard:
            let monthly = TraceFenceMarketplaceCatalogRuntime.standardOffer(for: .monthly)?.displayPriceWithPeriod
                ?? "$9.99/month"
            let annual = TraceFenceMarketplaceCatalogRuntime.standardOffer(for: .annual)?.displayPriceWithPeriod
                ?? "$79.99/year"
            return "\(monthly) or \(annual)"
        }
    }

    var featureLine: String {
        switch self {
        case .none:
            return "Basic local status, limited history, no remote approvals."
        case .appStoreStandard:
            return "Agent timeline, AI reports, iPhone remote control, and hook-based approvals within App Store limits."
        case .directStandard:
            return "The current website feature set, with monthly or annual billing through Dodo Payments."
        }
    }

    var isPaid: Bool {
        switch self {
        case .none: return false
        default: return true
        }
    }

}

struct TraceFenceSubscriptionPlan: Identifiable, Equatable {
    let id: TraceFenceSubscriptionTier
    let channel: TraceFenceDistributionChannel
    let title: String
    let priceLine: String
    let featureLine: String
    let isRecommended: Bool
}

enum TraceFenceCheckoutPlan: String, CaseIterable {
    case monthly
    case annual

    var priceLine: String {
        if let price = TraceFenceMarketplaceCatalogRuntime.standardOffer(for: self)?.displayPriceWithPeriod {
            return price
        }
        switch self {
        case .monthly: return "$9.99 / month"
        case .annual: return "$79.99 / year"
        }
    }

    var marketplaceOfferID: String {
        switch self {
        case .monthly: return "standard.monthly"
        case .annual: return "standard.annual"
        }
    }
}

enum TraceFenceDodoEnvironment: String {
    case test
    case live

    var checkoutHost: String {
        switch self {
        case .test: return "test.checkout.dodopayments.com"
        case .live: return "checkout.dodopayments.com"
        }
    }

    var licenseBaseURL: URL {
        switch self {
        case .test: return URL(string: "https://test.dodopayments.com/licenses")!
        case .live: return URL(string: "https://live.dodopayments.com/licenses")!
        }
    }
}

enum TraceFenceRemoteAccessMode: String, CaseIterable, Identifiable {
    case localNetwork
    case tailnetVPN
    case publicEndpoint
    case reverseTunnel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localNetwork: return "Same Wi-Fi or LAN"
        case .tailnetVPN: return "Private VPN / Tailnet"
        case .publicEndpoint: return "Port forwarding + DDNS"
        case .reverseTunnel: return "User-owned reverse tunnel"
        }
    }

    var requirement: String {
        switch self {
        case .localNetwork:
            return "Mac and iPhone must be on the same network. No router changes are needed."
        case .tailnetVPN:
            return "Install and sign in to a private mesh VPN such as Tailscale, ZeroTier, WireGuard, or a company VPN on both devices."
        case .publicEndpoint:
            return "User configures router port forwarding, firewall rules, and a stable hostname through DDNS or a static IP."
        case .reverseTunnel:
            return "User runs their own relay or tunnel, such as Cloudflare Tunnel, frp, SSH reverse tunnel, or a VPS they control."
        }
    }

    var securityNote: String {
        switch self {
        case .localNetwork:
            return "Best for home or office. Remote control stops working when the phone leaves that network."
        case .tailnetVPN:
            return "Recommended for Internet remote control without a TraceFence backend."
        case .publicEndpoint:
            return "Power-user option. Requires strong pairing tokens, TLS, and careful firewall rules."
        case .reverseTunnel:
            return "Flexible but user-operated. TraceFence should explain that the tunnel provider is outside TraceFence."
        }
    }
}

enum TraceFenceDistributionPolicy {
    static let dodoEnvironmentDefaultsKey = "traceFenceDodoEnvironment"
    static let dodoBusinessIDDefaultsKey = "traceFenceDodoBusinessID"
    static let dodoMonthlyProductIDDefaultsKey = "traceFenceDodoMonthlyProductID"
    static let dodoAnnualProductIDDefaultsKey = "traceFenceDodoAnnualProductID"

    static var allowsDodoRuntimeOverrides: Bool {
#if DEBUG
        currentChannel.isDirect
#else
        false
#endif
    }

    static var currentChannel: TraceFenceDistributionChannel {
        if let bundled = Bundle.main.object(forInfoDictionaryKey: "TraceFenceDistributionChannel") as? String,
           let channel = TraceFenceDistributionChannel(rawValue: bundled),
           channel.isAppStore {
            return .appStore
        }
        if let override = debugOverride(forKey: "traceFenceDistributionChannel"),
           let channel = TraceFenceDistributionChannel(rawValue: override) {
            return channel
        }
        if let bundled = Bundle.main.object(forInfoDictionaryKey: "TraceFenceDistributionChannel") as? String,
           let channel = TraceFenceDistributionChannel(rawValue: bundled) {
            return channel
        }
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        if bundleId == "com.aimaccleaner.app" || bundleId.contains("appstore") {
            return .appStore
        }
        return .direct
    }

    static var appStoreProductIDs: [String] {
        let monthly = (Bundle.main.object(forInfoDictionaryKey: "TraceFenceAppStoreMonthlyProductID") as? String)
            ?? "com.tracefence.standard.monthly"
        let yearly = (Bundle.main.object(forInfoDictionaryKey: "TraceFenceAppStoreYearlyProductID") as? String)
            ?? "com.tracefence.standard.yearly"
        return [monthly, yearly].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static let privacyPolicyURL = URL(string: "https://ai-scarlett.github.io/TraceFence/privacy-policy.html")!
    static let standardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var directPlans: [TraceFenceSubscriptionPlan] {
        [
            TraceFenceSubscriptionPlan(
                id: .directStandard,
                channel: .direct,
                title: TraceFenceSubscriptionTier.directStandard.title,
                priceLine: TraceFenceSubscriptionTier.directStandard.priceLine,
                featureLine: TraceFenceSubscriptionTier.directStandard.featureLine,
                isRecommended: true
            )
        ]
    }

    static var appStorePlans: [TraceFenceSubscriptionPlan] {
        [
            TraceFenceSubscriptionPlan(
                id: .appStoreStandard,
                channel: .appStore,
                title: TraceFenceSubscriptionTier.appStoreStandard.title,
                priceLine: TraceFenceSubscriptionTier.appStoreStandard.priceLine,
                featureLine: TraceFenceSubscriptionTier.appStoreStandard.featureLine,
                isRecommended: true
            )
        ]
    }

    static func checkoutURL(for plan: TraceFenceCheckoutPlan) -> URL? {
        guard currentChannel.isDirect, let returnURL = checkoutReturnURL else {
            return nil
        }
        if let dynamic = TraceFenceMarketplaceCatalogRuntime.checkoutURL(
            offerID: plan.marketplaceOfferID,
            environment: dodoEnvironment,
            returnURL: returnURL
        ) {
            return dynamic
        }
        guard let productID = bundledDodoProductID(for: plan),
              var components = URLComponents(string: "https://\(dodoEnvironment.checkoutHost)/buy/\(productID)") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "quantity", value: "1"),
            URLQueryItem(name: "showDiscounts", value: "false"),
            URLQueryItem(name: "redirect_url", value: returnURL.absoluteString)
        ]
        return components.url
    }

    static var dodoEnvironment: TraceFenceDodoEnvironment {
        guard let rawValue = configuredValue(
            infoKey: "TraceFenceDodoEnvironment",
            defaultsKey: dodoEnvironmentDefaultsKey
        ), let environment = TraceFenceDodoEnvironment(rawValue: rawValue.lowercased()) else {
            return .test
        }
        return environment
    }

    static func dodoProductID(for plan: TraceFenceCheckoutPlan) -> String? {
        guard currentChannel.isDirect else { return nil }
        if let dynamic = TraceFenceMarketplaceCatalogRuntime.standardProductID(
            for: plan,
            environment: dodoEnvironment
        ) {
            return dynamic
        }
        return bundledDodoProductID(for: plan)
    }

    private static func bundledDodoProductID(for plan: TraceFenceCheckoutPlan) -> String? {
        let infoKey: String
        let defaultsKey: String
        switch plan {
        case .monthly:
            infoKey = "TraceFenceDodoMonthlyProductID"
            defaultsKey = dodoMonthlyProductIDDefaultsKey
        case .annual:
            infoKey = "TraceFenceDodoAnnualProductID"
            defaultsKey = dodoAnnualProductIDDefaultsKey
        }
        guard let value = configuredValue(infoKey: infoKey, defaultsKey: defaultsKey),
              value.range(of: #"^pdt_[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    static var dodoStandardProductIDs: Set<String> {
        var values = TraceFenceMarketplaceCatalogRuntime.acceptedStandardProductIDs(
            environment: dodoEnvironment
        )
        values.formUnion(TraceFenceCheckoutPlan.allCases.compactMap(bundledDodoProductID(for:)))
        return values
    }

    static var dodoBusinessID: String? {
        guard currentChannel.isDirect,
              let value = configuredValue(
            infoKey: "TraceFenceDodoBusinessID",
            defaultsKey: dodoBusinessIDDefaultsKey
        ), value.range(of: #"^bus_[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    static var bundledDodoBusinessID: String? {
        let candidates = [
            Bundle.main.object(forInfoDictionaryKey: "TraceFenceDodoBusinessID") as? String,
            "bus_0Nj3ve514BLr8z2wT3duj"
        ]
        for candidate in candidates {
            let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.range(of: #"^bus_[A-Za-z0-9]+$"#, options: .regularExpression) != nil {
                return value
            }
        }
        return nil
    }

    static func isSupportedDodoProductID(_ productID: String) -> Bool {
        dodoStandardProductIDs.contains(productID)
    }

    static func isSupportedDodoBusinessID(_ businessID: String) -> Bool {
        businessID == dodoBusinessID
    }

    static var checkoutReturnURL: URL? {
        guard currentChannel.isDirect,
              let rawValue = configuredValue(
            infoKey: "TraceFenceCheckoutReturnURL",
            defaultsKey: "traceFenceCheckoutReturnURL"
              ) else { return nil }
        guard let url = URL(string: rawValue), url.scheme == "https" else { return nil }
        return url
    }

    private static func configuredValue(infoKey: String, defaultsKey: String) -> String? {
        let candidates = [
            debugOverride(forKey: defaultsKey),
            Bundle.main.object(forInfoDictionaryKey: infoKey) as? String
        ]
        for candidate in candidates {
            let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty, !value.contains("$(") {
                return value
            }
        }
        return nil
    }

    private static func debugOverride(forKey key: String) -> String? {
#if DEBUG
        UserDefaults.standard.string(forKey: key)
#else
        nil
#endif
    }

    static func tier(from snapshot: DirectLicenseSnapshot) -> TraceFenceSubscriptionTier {
        guard snapshot.status == .licensed else { return .none }
        return .directStandard
    }
}

enum AppStoreSubscriptionError: LocalizedError {
    case unverified

    var errorDescription: String? {
        switch self {
        case .unverified:
            return "The App Store transaction could not be verified."
        }
    }
}

enum AppStoreSubscriptionNotice: Equatable {
    case productsUnavailable
    case subscriptionActive
    case purchaseCancelled
    case purchasePending
    case purchaseStateUnknown
    case subscriptionRestored
    case noActiveSubscription
    case requestFailed
}

extension Notification.Name {
    static let traceFenceEntitlementDidChange = Notification.Name("traceFenceEntitlementDidChange")
}

@MainActor
final class AppStoreSubscriptionService: ObservableObject {
    static let shared = AppStoreSubscriptionService()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSubscribed = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var notice: AppStoreSubscriptionNotice?

    var canUseCoreFeatures: Bool { isSubscribed }
    var canUseProFeatures: Bool { isSubscribed }

    private var productIDs: [String] { TraceFenceDistributionPolicy.appStoreProductIDs }
    private var transactionUpdatesTask: Task<Void, Never>?
    private var expirationRefreshTask: Task<Void, Never>?

    private init() {}

    func refresh() async {
        startTransactionListenerIfNeeded()
        await loadProducts()
        await refreshEntitlements()
    }

    func startTransactionListenerIfNeeded() {
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                guard let transaction = try? self.checkVerified(result),
                      self.productIDs.contains(transaction.productID) else {
                    continue
                }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }

    func loadProducts() async {
        guard !productIDs.isEmpty else { return }
        isLoading = true
        notice = nil
        defer { isLoading = false }
        do {
            products = try await Product.products(for: productIDs).sorted { lhs, rhs in
                lhs.price < rhs.price
            }
            if products.isEmpty {
                notice = .productsUnavailable
            }
        } catch {
            if products.isEmpty {
                notice = .requestFailed
            }
        }
    }

    func purchase(_ product: Product) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                notice = .subscriptionActive
            case .userCancelled:
                notice = .purchaseCancelled
            case .pending:
                notice = .purchasePending
            @unknown default:
                notice = .purchaseStateUnknown
            }
        } catch {
            notice = .requestFailed
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            notice = isSubscribed ? .subscriptionRestored : .noActiveSubscription
        } catch {
            notice = .requestFailed
        }
    }

    func refreshEntitlements() async {
        var foundActive = false
        var foundProductID: String?
        var foundExpiration: Date?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else {
                continue
            }
            foundActive = true
            foundProductID = transaction.productID
            foundExpiration = transaction.expirationDate
        }

        isSubscribed = foundActive
        activeProductID = foundProductID
        expiresAt = foundExpiration
        scheduleExpirationRefresh(for: foundExpiration)
        NotificationCenter.default.post(
            name: .traceFenceEntitlementDidChange,
            object: nil,
            userInfo: ["canUseProFeatures": foundActive]
        )
    }

    private func scheduleExpirationRefresh(for expirationDate: Date?) {
        expirationRefreshTask?.cancel()
        guard let expirationDate else {
            expirationRefreshTask = nil
            return
        }
        let delay = max(1, expirationDate.timeIntervalSinceNow + 1)
        expirationRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.expirationRefreshTask = nil
            await self.refreshEntitlements()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw AppStoreSubscriptionError.unverified
        }
    }
}

@MainActor
enum TraceFenceEntitlementPolicy {
    static var canUseCoreFeatures: Bool {
        if TraceFenceDistributionPolicy.currentChannel.isAppStore {
            return AppStoreSubscriptionService.shared.canUseCoreFeatures
        }
        return DirectLicenseService.shared.canUseCoreFeatures
    }

    static var canUseProFeatures: Bool {
        if TraceFenceDistributionPolicy.currentChannel.isAppStore {
            return AppStoreSubscriptionService.shared.canUseProFeatures
        }
        return DirectLicenseService.shared.canUseProFeatures
    }

    static func refresh() async {
        if TraceFenceDistributionPolicy.currentChannel.isAppStore {
            await AppStoreSubscriptionService.shared.refresh()
        } else {
            DirectLicenseService.shared.refreshTrialState()
            // The signed marketplace catalog carries the accepted subscription
            // product set. Finish loading it before deciding whether a stored
            // website license belongs to this build.
            await TraceFenceMarketplaceCatalogService.shared.refresh()
            await DirectLicenseService.shared.validateCurrentLicense()
        }
    }

    static func canUsePlugin(_ pluginID: String) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("--tracefence-ui-preview") ||
            Bundle.main.bundleIdentifier == "com.tracefence.uipreview" {
            return true
        }
        guard TraceFenceDistributionPolicy.currentChannel.isDirect else {
            return canUseProFeatures
        }
        switch TraceFencePluginEntitlementService.shared.accessState(pluginID: pluginID) {
        case .free, .allAccess, .licensed, .trial:
            return true
        case .locked:
            return false
        }
    }
}

enum DirectLicenseStatus: String, Codable {
    case unlicensed
    case licensed
    case expired
    case disabled
    case inactive
    case validating
    case error
}

struct DirectLicenseSnapshot: Codable {
    var status: DirectLicenseStatus
    var licenseKeySuffix: String?
    var instanceId: String?
    var customerName: String?
    var customerEmail: String?
    var businessID: String?
    var productID: String?
    var productName: String?
    var expiresAt: String?
    var activationLimit: Int?
    var activationUsage: Int?
    var lastValidatedAt: Date?
    var message: String?

    static let empty = DirectLicenseSnapshot(status: .unlicensed)
}

struct DirectTrialSnapshot: Codable {
    var startedAt: Date
    var expiresAt: Date

    static let empty = DirectTrialSnapshot(startedAt: .distantPast, expiresAt: .distantPast)
}

@MainActor
final class DirectLicenseService: ObservableObject {
    static let shared = DirectLicenseService()

    @Published private(set) var snapshot: DirectLicenseSnapshot
    @Published private(set) var trialSnapshot: DirectTrialSnapshot
    @Published private(set) var isBusy = false
    @Published private(set) var licenseSyncedThisRun = false

    var isLicensed: Bool {
        snapshot.status == .licensed &&
            snapshot.lastValidatedAt.map { Date().timeIntervalSince($0) <= offlineGraceDuration } == true
    }
    var trialDuration: TimeInterval { 48 * 60 * 60 }
    var isTrialActive: Bool { !isLicensed && trialSnapshot.expiresAt > Date() }
    var isTrialExpired: Bool { !isLicensed && trialSnapshot.expiresAt <= Date() }
    var canUseCoreFeatures: Bool { isLicensed || isTrialActive }
    var canUseProFeatures: Bool { isLicensed }
    var currentTier: TraceFenceSubscriptionTier { isLicensed ? .directStandard : .none }
    var trialRemainingSeconds: TimeInterval {
        max(0, trialSnapshot.expiresAt.timeIntervalSinceNow)
    }
    var purchaseURL: URL? {
        TraceFenceDistributionPolicy.checkoutURL(for: .monthly)
    }

    private var dodoLicenseBaseURL: URL { TraceFenceDistributionPolicy.dodoEnvironment.licenseBaseURL }
    private let offlineGraceDuration: TimeInterval = 72 * 60 * 60
    private let snapshotKey = "traceFenceLicenseSnapshot"
    private let snapshotSignatureKey = "traceFenceLicenseSnapshotSignature"
    private let trialStartedKey = "traceFenceTrialStartedAt"
    private let serviceName: String
    private let licenseDefaults: UserDefaults
    private let licenseAccount = "license_key"
    private let instanceAccount = "instance_id"
    private let businessAccount = "business_id"
    private let productAccount = "product_id"
    private let snapshotSigningKeyAccount = "snapshot_signing_key"
    private let decoder = JSONDecoder()
    private let dateCodec = ISO8601DateFormatter()

    private enum SecretReadResult {
        case value(Data)
        case missing
        case unavailable(OSStatus)
    }

    private enum SecretStringReadResult {
        case value(String)
        case missing
        case unavailable(OSStatus)
    }

    /// UI preview builds are intentionally unsigned and use a different bundle
    /// identity. They must never touch the production license Keychain items,
    /// otherwise macOS repeatedly asks the user to re-authorize access while we
    /// are only validating layout and appearance.
    private var allowsLicenseKeychainAccess: Bool {
        !ProcessInfo.processInfo.arguments.contains("--tracefence-ui-preview") &&
            Bundle.main.bundleIdentifier != "com.tracefence.uipreview"
    }

    private init() {
#if DEBUG
        // Debug and UI-preview binaries may use the same bundle identifier as a
        // production build. Keep both Keychain and defaults storage isolated so
        // a test-environment product check can never invalidate a live license.
        serviceName = "TraceFence.DirectLicense.Debug"
        licenseDefaults = UserDefaults(suiteName: "com.tracefence.app.debug-license")!
#else
        serviceName = "TraceFence.DirectLicense"
        licenseDefaults = .standard
#endif
        snapshot = .empty
        trialSnapshot = .empty
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        snapshot = loadVerifiedSnapshot()
        trialSnapshot = loadOrStartTrial()
    }

    func openPurchasePage(for plan: TraceFenceCheckoutPlan = .monthly) {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect,
              let purchaseURL = TraceFenceDistributionPolicy.checkoutURL(for: plan) else {
            snapshot.message = "Dodo Payments product ID is not configured for this billing period."
            persistSnapshot()
            return
        }
        NSWorkspace.shared.open(purchaseURL)
    }

    func refreshTrialState() {
        trialSnapshot = loadOrStartTrial()
    }

    func activate(licenseKey rawLicenseKey: String) async {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect else { return }
        let licenseKey = rawLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !licenseKey.isEmpty else {
            snapshot.message = "Enter a license key first."
            persistSnapshot()
            return
        }

        isBusy = true
        defer { isBusy = false }
        snapshot.status = .validating
        snapshot.message = nil
        persistSnapshot()

        do {
            let response: DodoLicenseActivationResponse = try await postDodo(
                endpoint: "activate",
                fields: [
                    "license_key": licenseKey,
                    "name": instanceName()
                ]
            )
            guard let expectedBusinessID = TraceFenceDistributionPolicy.dodoBusinessID else {
                await rollbackRejectedActivation(licenseKey: licenseKey, instanceID: response.id)
                throw DirectLicenseError.missingBusinessID
            }
            guard response.businessId == expectedBusinessID else {
                await rollbackRejectedActivation(licenseKey: licenseKey, instanceID: response.id)
                throw DirectLicenseError.unexpectedBusiness(response.businessId)
            }
            guard TraceFenceDistributionPolicy.isSupportedDodoProductID(response.product.productId) else {
                await rollbackRejectedActivation(licenseKey: licenseKey, instanceID: response.id)
                throw DirectLicenseError.unexpectedProduct(response.product.productId)
            }
            saveSecret(licenseKey, account: licenseAccount)
            saveSecret(response.id, account: instanceAccount)
            saveSecret(response.businessId, account: businessAccount)
            saveSecret(response.product.productId, account: productAccount)
            apply(dodoResponse: response, fallbackKey: licenseKey)
        } catch {
            snapshot.status = .error
            snapshot.licenseKeySuffix = licenseKey.suffixText
            snapshot.message = activationFailureMessage(for: error)
            persistSnapshot()
        }
    }

    func validateCurrentLicense() async {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect else { return }
        let previousSnapshot = snapshot
        let licenseKey: String
        switch readSecretStringResult(account: licenseAccount) {
        case .value(let value):
            licenseKey = value
        case .missing:
            snapshot = .empty
            licenseSyncedThisRun = false
            persistSnapshot()
            return
        case .unavailable:
            preserveCachedLicenseAfterCredentialReadFailure(previousSnapshot)
            return
        }

        let businessResult = readSecretStringResult(account: businessAccount)
        let productResult = readSecretStringResult(account: productAccount)
        if case .unavailable = businessResult {
            preserveCachedLicenseAfterCredentialReadFailure(previousSnapshot)
            return
        }
        if case .unavailable = productResult {
            preserveCachedLicenseAfterCredentialReadFailure(previousSnapshot)
            return
        }
        guard case .value(let businessID) = businessResult,
              TraceFenceDistributionPolicy.isSupportedDodoBusinessID(businessID),
              case .value(let productID) = productResult else {
            snapshot.status = .inactive
            snapshot.message = "The stored license does not match this TraceFence Dodo Payments business and product configuration. Activate it again with a supported TraceFence Standard key."
            licenseSyncedThisRun = false
            persistSnapshot()
            return
        }
        if !TraceFenceDistributionPolicy.isSupportedDodoProductID(productID) {
            let canUseVerifiedCache = !TraceFenceMarketplaceCatalogRuntime.isUsingVerifiedRemoteCatalog &&
                previousSnapshot.status == .licensed &&
                previousSnapshot.businessID == businessID &&
                previousSnapshot.productID == productID &&
                previousSnapshot.lastValidatedAt.map {
                    Date().timeIntervalSince($0) <= offlineGraceDuration
                } == true
            guard !canUseVerifiedCache else {
                snapshot = previousSnapshot
                snapshot.status = .licensed
                snapshot.message = "The signed marketplace catalog is temporarily unavailable. Cached authorization remains active during the 72-hour offline grace period."
                licenseSyncedThisRun = false
                persistSnapshot()
                return
            }
            snapshot.status = .inactive
            snapshot.message = "The stored license does not match this TraceFence Dodo Payments product configuration. Activate it again with a supported TraceFence Standard key."
            licenseSyncedThisRun = false
            persistSnapshot()
            return
        }
        isBusy = true
        defer { isBusy = false }
        snapshot.status = .validating
        snapshot.message = nil
        persistSnapshot()

        do {
            var fields = ["license_key": licenseKey]
            if let instanceId = readSecret(account: instanceAccount) {
                fields["license_key_instance_id"] = instanceId
            }
            let response: DodoLicenseValidationResponse = try await postDodo(
                endpoint: "validate",
                fields: fields
            )
            apply(dodoValidation: response, previousSnapshot: previousSnapshot)
        } catch {
            applyValidationFailure(error, previousSnapshot: previousSnapshot)
        }
    }

    func deactivateCurrentLicense() async {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect else { return }
        guard let licenseKey = readSecret(account: licenseAccount),
              let instanceId = readSecret(account: instanceAccount) else {
            clearLicense()
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            try await postDodoWithoutResponse(endpoint: "deactivate", fields: [
                "license_key": licenseKey,
                "license_key_instance_id": instanceId
            ])
            clearLicense()
        } catch {
            snapshot.message = error.localizedDescription
            persistSnapshot()
        }
    }

    func clearLicense() {
        deleteSecret(account: licenseAccount)
        deleteSecret(account: instanceAccount)
        deleteSecret(account: businessAccount)
        deleteSecret(account: productAccount)
        snapshot = .empty
        licenseSyncedThisRun = false
        refreshTrialState()
        persistSnapshot()
    }

    private func postDodo<T: Decodable>(endpoint: String, fields: [String: String]) async throws -> T {
        let data = try await postDodoData(endpoint: endpoint, fields: fields)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw DirectLicenseError.invalidResponse
        }
    }

    private func postDodoWithoutResponse(endpoint: String, fields: [String: String]) async throws {
        _ = try await postDodoData(endpoint: endpoint, fields: fields)
    }

    private func rollbackRejectedActivation(licenseKey: String, instanceID: String) async {
        try? await postDodoWithoutResponse(endpoint: "deactivate", fields: [
            "license_key": licenseKey,
            "license_key_instance_id": instanceID
        ])
    }

    private func postDodoData(endpoint: String, fields: [String: String]) async throws -> Data {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect else {
            throw DirectLicenseError.directDistributionRequired
        }
        var request = URLRequest(url: dodoLicenseBaseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("TraceFence/3.2", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)
        return data
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DirectLicenseError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DirectLicenseError.http(
                statusCode: httpResponse.statusCode,
                message: serverMessage(from: data, statusCode: httpResponse.statusCode)
            )
        }
    }

    private func apply(dodoResponse response: DodoLicenseActivationResponse, fallbackKey: String) {
        snapshot = DirectLicenseSnapshot(
            status: .licensed,
            licenseKeySuffix: fallbackKey.suffixText,
            instanceId: response.id,
            customerName: response.customer?.name,
            customerEmail: response.customer?.email,
            businessID: response.businessId,
            productID: response.product.productId,
            productName: response.product.name,
            lastValidatedAt: Date(),
            message: nil
        )
        licenseSyncedThisRun = true
        persistSnapshot()
    }

    private func apply(dodoValidation response: DodoLicenseValidationResponse, previousSnapshot: DirectLicenseSnapshot) {
        snapshot = previousSnapshot
        snapshot.status = response.valid ? .licensed : .inactive
        snapshot.lastValidatedAt = Date()
        snapshot.message = response.valid ? nil : "This Dodo Payments license is no longer valid."
        licenseSyncedThisRun = true
        persistSnapshot()
    }

    private func applyValidationFailure(_ error: Error, previousSnapshot: DirectLicenseSnapshot) {
        snapshot = previousSnapshot
        licenseSyncedThisRun = false

        let isWithinGracePeriod = previousSnapshot.status == .licensed &&
            previousSnapshot.lastValidatedAt.map { Date().timeIntervalSince($0) <= offlineGraceDuration } == true
        if isTransientValidationError(error), isWithinGracePeriod {
            snapshot.status = .licensed
            snapshot.message = "The license service is temporarily unreachable. Cached authorization remains active during the 72-hour offline grace period."
        } else {
            snapshot.status = isDefinitiveLicenseFailure(error) ? .inactive : .error
            snapshot.message = error.localizedDescription
        }
        persistSnapshot()
    }

    private func preserveCachedLicenseAfterCredentialReadFailure(_ previousSnapshot: DirectLicenseSnapshot) {
        snapshot = previousSnapshot
        licenseSyncedThisRun = false
        let isWithinGracePeriod = previousSnapshot.status == .licensed &&
            previousSnapshot.lastValidatedAt.map { Date().timeIntervalSince($0) <= offlineGraceDuration } == true
        if isWithinGracePeriod {
            snapshot.status = .licensed
            snapshot.message = "The macOS Keychain is temporarily unavailable. Cached authorization remains active during the 72-hour offline grace period."
        } else {
            snapshot.status = .error
            snapshot.message = "The macOS Keychain is temporarily unavailable. Unlock the Mac and try again."
        }
        persistSnapshot()
    }

    private func activationFailureMessage(for error: Error) -> String {
        if let directError = error as? DirectLicenseError {
            switch directError {
            case .http(let statusCode, _) where (400..<500).contains(statusCode):
                return "The license key was not recognized. Check the key from Dodo Payments and try again."
            default:
                return directError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private func isTransientValidationError(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let directError = error as? DirectLicenseError else { return true }
        return directError.isTransient
    }

    private func isDefinitiveLicenseFailure(_ error: Error) -> Bool {
        guard let directError = error as? DirectLicenseError else { return false }
        return directError.isDefinitiveLicenseFailure
    }

    private func serverMessage(from data: Data, statusCode: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error", "detail"] {
                if let value = object[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return String(text.prefix(500))
        }
        return "HTTP \(statusCode)"
    }

    private func instanceName() -> String {
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return "TraceFence on \(host)"
    }

    private func loadOrStartTrial() -> DirectTrialSnapshot {
        if let rawStartedAt = licenseDefaults.string(forKey: trialStartedKey),
           let startedAt = dateCodec.date(from: rawStartedAt) {
            return DirectTrialSnapshot(startedAt: startedAt, expiresAt: startedAt.addingTimeInterval(trialDuration))
        }

        let startedAt = Date()
        licenseDefaults.set(dateCodec.string(from: startedAt), forKey: trialStartedKey)
        return DirectTrialSnapshot(startedAt: startedAt, expiresAt: startedAt.addingTimeInterval(trialDuration))
    }

    private func persistSnapshot() {
        guard let data = try? JSONEncoder().encode(snapshot),
              let signingKey = snapshotSigningKey() else {
            // Keychain access can be temporarily unavailable while macOS is
            // unlocking or migrating an app. Do not destroy a previously valid
            // cache merely because it cannot be signed during that moment.
            return
        }
        let signature = Data(HMAC<SHA256>.authenticationCode(
            for: data,
            using: SymmetricKey(data: signingKey)
        ))
        licenseDefaults.set(data, forKey: snapshotKey)
        licenseDefaults.set(signature, forKey: snapshotSignatureKey)
    }

    private func loadVerifiedSnapshot() -> DirectLicenseSnapshot {
        let defaults = licenseDefaults
        guard let data = defaults.data(forKey: snapshotKey),
              let decoded = try? JSONDecoder().decode(DirectLicenseSnapshot.self, from: data) else {
            defaults.removeObject(forKey: snapshotKey)
            defaults.removeObject(forKey: snapshotSignatureKey)
            return .empty
        }

        if let storedSignature = defaults.data(forKey: snapshotSignatureKey) {
            guard let signingKey = readSecretData(account: snapshotSigningKeyAccount) else {
                // Fail closed for this process, but retain the signed cache so a
                // later launch can recover after transient Keychain failures.
                return .empty
            }
            let expectedSignature = Data(HMAC<SHA256>.authenticationCode(
                for: data,
                using: SymmetricKey(data: signingKey)
            ))
            guard constantTimeEqual(storedSignature, expectedSignature) else {
                defaults.removeObject(forKey: snapshotKey)
                defaults.removeObject(forKey: snapshotSignatureKey)
                return .empty
            }
            return decoded
        }

        // Versions before 1.2.6 stored this cache without a signature. Only migrate
        // a licensed cache when matching credentials already exist in Keychain.
        guard decoded.status != .licensed || hasMatchingLicenseCredentials(for: decoded) else {
            defaults.removeObject(forKey: snapshotKey)
            return .empty
        }
        return decoded
    }

    private func hasMatchingLicenseCredentials(for cachedSnapshot: DirectLicenseSnapshot) -> Bool {
        guard readSecret(account: licenseAccount)?.isEmpty == false,
              let storedBusinessID = readSecret(account: businessAccount),
              TraceFenceDistributionPolicy.isSupportedDodoBusinessID(storedBusinessID),
              let storedProductID = readSecret(account: productAccount),
              TraceFenceDistributionPolicy.isSupportedDodoProductID(storedProductID),
              cachedSnapshot.businessID == storedBusinessID,
              cachedSnapshot.productID == storedProductID,
              cachedSnapshot.lastValidatedAt.map({ Date().timeIntervalSince($0) <= offlineGraceDuration }) == true else {
            return false
        }
        return true
    }

    private func snapshotSigningKey() -> Data? {
        if let existing = readSecretData(account: snapshotSigningKeyAccount), existing.count == 32 {
            return existing
        }

        var generated = Data(count: 32)
        let status = generated.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, bytes.count, baseAddress)
        }
        guard status == errSecSuccess,
              saveSecretData(generated, account: snapshotSigningKeyAccount),
              readSecretData(account: snapshotSigningKeyAccount) == generated else {
            return nil
        }
        return generated
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }

    private func saveSecret(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        _ = saveSecretData(data, account: account)
    }

    @discardableResult
    private func saveSecretData(_ data: Data, account: String) -> Bool {
        guard allowsLicenseKeychainAccess else { return false }
        deleteSecret(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func readSecret(account: String) -> String? {
        guard let data = readSecretData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func readSecretStringResult(account: String) -> SecretStringReadResult {
        switch readSecretDataResult(account: account) {
        case .value(let data):
            guard let value = String(data: data, encoding: .utf8) else {
                return .unavailable(errSecDecode)
            }
            return .value(value)
        case .missing:
            return .missing
        case .unavailable(let status):
            return .unavailable(status)
        }
    }

    private func readSecretData(account: String) -> Data? {
        guard case .value(let data) = readSecretDataResult(account: account) else { return nil }
        return data
    }

    private func readSecretDataResult(account: String) -> SecretReadResult {
        guard allowsLicenseKeychainAccess else { return .unavailable(errSecInteractionNotAllowed) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return .missing
        }
        guard status == errSecSuccess, let data = item as? Data else {
            return .unavailable(status)
        }
        return .value(data)
    }

    private func deleteSecret(account: String) {
        guard allowsLicenseKeychainAccess else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

}

private struct DodoLicenseActivationResponse: Decodable {
    var businessId: String
    var id: String
    var customer: DodoLicenseCustomer?
    var product: DodoLicenseProduct
}

private struct DodoLicenseCustomer: Decodable {
    var name: String?
    var email: String?
}

private struct DodoLicenseProduct: Decodable {
    var productId: String
    var name: String?
}

private struct DodoLicenseValidationResponse: Decodable {
    var valid: Bool
}

private enum DirectLicenseError: LocalizedError {
    case invalidResponse
    case directDistributionRequired
    case http(statusCode: Int, message: String)
    case missingBusinessID
    case unexpectedBusiness(String)
    case unexpectedProduct(String)

    var isTransient: Bool {
        switch self {
        case .invalidResponse, .directDistributionRequired:
            return true
        case .http(let statusCode, _):
            return statusCode == 408 || statusCode == 429 || statusCode >= 500
        case .missingBusinessID, .unexpectedBusiness, .unexpectedProduct:
            return false
        }
    }

    var isDefinitiveLicenseFailure: Bool {
        switch self {
        case .http(let statusCode, _):
            return (400..<500).contains(statusCode) && statusCode != 408 && statusCode != 429
        case .missingBusinessID, .unexpectedBusiness, .unexpectedProduct:
            return true
        case .invalidResponse, .directDistributionRequired:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The license server returned an invalid response."
        case .directDistributionRequired:
            return "Website license activation is unavailable in the Mac App Store build."
        case .http(let statusCode, let message):
            return "License server error (HTTP \(statusCode)): \(message)"
        case .missingBusinessID:
            return "The TraceFence Dodo Payments business ID is not configured."
        case .unexpectedBusiness(let businessID):
            return "This key belongs to an unsupported Dodo Payments business (\(businessID))."
        case .unexpectedProduct(let productID):
            return "This key belongs to an unsupported product (\(productID)). Use a TraceFence Standard monthly or annual license."
        }
    }
}

private extension String {
    var suffixText: String {
        guard count > 8 else { return self }
        return "•••• \(suffix(8))"
    }
}
