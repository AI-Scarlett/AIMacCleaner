import AppKit
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
    case directEnhanced
    case legacy

    var title: String {
        switch self {
        case .none: return "Free"
        case .appStoreStandard: return "TraceFence Standard"
        case .directStandard: return "TraceFence Standard"
        case .directEnhanced: return "TraceFence Enhanced"
        case .legacy: return "Legacy License"
        }
    }

    var priceLine: String {
        switch self {
        case .none:
            return "Limited local monitoring"
        case .appStoreStandard, .directStandard:
            return "$9.99/month or $79.99/year"
        case .directEnhanced:
            return "Higher website-only tier"
        case .legacy:
            return "Existing purchased features"
        }
    }

    var featureLine: String {
        switch self {
        case .none:
            return "Basic local status, limited history, no remote approvals."
        case .appStoreStandard:
            return "Agent timeline, AI reports, iPhone remote control, and hook-based approvals within App Store limits."
        case .directStandard:
            return "Same feature and price level as the App Store subscription."
        case .directEnhanced:
            return "Website-only advanced policies, direct update channel, broader local diagnostics, and future system-extension firewall support."
        case .legacy:
            return "Existing customers keep the features they already bought; subscription upgrades unlock new v2 features."
        }
    }

    var isPaid: Bool {
        switch self {
        case .none: return false
        default: return true
        }
    }

    var includesEnhancedDirectFeatures: Bool {
        self == .directEnhanced
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

enum TraceFenceCheckoutPlan {
    case standard
    case enhanced
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
    static var currentChannel: TraceFenceDistributionChannel {
        if let override = UserDefaults.standard.string(forKey: "traceFenceDistributionChannel"),
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

    static var directPlans: [TraceFenceSubscriptionPlan] {
        [
            TraceFenceSubscriptionPlan(
                id: .directStandard,
                channel: .direct,
                title: TraceFenceSubscriptionTier.directStandard.title,
                priceLine: TraceFenceSubscriptionTier.directStandard.priceLine,
                featureLine: TraceFenceSubscriptionTier.directStandard.featureLine,
                isRecommended: true
            ),
            TraceFenceSubscriptionPlan(
                id: .directEnhanced,
                channel: .direct,
                title: TraceFenceSubscriptionTier.directEnhanced.title,
                priceLine: TraceFenceSubscriptionTier.directEnhanced.priceLine,
                featureLine: TraceFenceSubscriptionTier.directEnhanced.featureLine,
                isRecommended: false
            ),
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
        let key: String
        let defaultsKey: String
        switch plan {
        case .standard:
            key = "TraceFenceCheckoutURL"
            defaultsKey = "traceFenceCheckoutURL"
        case .enhanced:
            key = "TraceFenceEnhancedCheckoutURL"
            defaultsKey = "traceFenceEnhancedCheckoutURL"
        }

        let rawValue = (Bundle.main.object(forInfoDictionaryKey: key) as? String)
            ?? UserDefaults.standard.string(forKey: defaultsKey)
        guard let rawValue,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(string: rawValue)
    }

    static func tier(from snapshot: DirectLicenseSnapshot) -> TraceFenceSubscriptionTier {
        guard snapshot.status == .licensed else { return .none }
        let product = (snapshot.productName ?? "").lowercased()
        if product.contains("enhanced") ||
            product.contains("advanced") ||
            product.contains("firewall") ||
            product.contains("system extension") {
            return .directEnhanced
        }
        if product.contains("legacy") || product.contains("lifetime") {
            return .legacy
        }
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

@MainActor
final class AppStoreSubscriptionService: ObservableObject {
    static let shared = AppStoreSubscriptionService()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSubscribed = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var expiresAt: Date?
    @Published var message: String?

    var canUseCoreFeatures: Bool { isSubscribed }
    var canUseProFeatures: Bool { isSubscribed }

    private var productIDs: [String] { TraceFenceDistributionPolicy.appStoreProductIDs }

    private init() {}

    func refresh() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        guard !productIDs.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: productIDs).sorted { lhs, rhs in
                lhs.price < rhs.price
            }
            if products.isEmpty {
                message = "App Store subscription products are not configured yet."
            }
        } catch {
            message = error.localizedDescription
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
                message = "Subscription is active."
            case .userCancelled:
                message = "Purchase cancelled."
            case .pending:
                message = "Purchase is pending approval."
            @unknown default:
                message = "Purchase state is unknown."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isSubscribed ? "Subscription restored." : "No active subscription found."
        } catch {
            message = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var foundActive = false
        var foundProductID: String?
        var foundExpiration: Date?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else {
                continue
            }
            foundActive = true
            foundProductID = transaction.productID
            foundExpiration = transaction.expirationDate
        }

        isSubscribed = foundActive
        activeProductID = foundProductID
        expiresAt = foundExpiration
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

    var isLicensed: Bool { snapshot.status == .licensed }
    var trialDuration: TimeInterval { 48 * 60 * 60 }
    var isTrialActive: Bool { !isLicensed && trialSnapshot.expiresAt > Date() }
    var isTrialExpired: Bool { !isLicensed && trialSnapshot.expiresAt <= Date() }
    var canUseCoreFeatures: Bool { isLicensed || isTrialActive }
    var canUseProFeatures: Bool { isLicensed }
    var currentTier: TraceFenceSubscriptionTier { TraceFenceDistributionPolicy.tier(from: snapshot) }
    var canUseEnhancedFeatures: Bool { currentTier.includesEnhancedDirectFeatures }
    var trialRemainingSeconds: TimeInterval {
        max(0, trialSnapshot.expiresAt.timeIntervalSinceNow)
    }
    var purchaseURL: URL? {
        TraceFenceDistributionPolicy.checkoutURL(for: .standard)
    }

    private let licenseBaseURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!
    private let snapshotKey = "traceFenceLicenseSnapshot"
    private let trialStartedKey = "traceFenceTrialStartedAt"
    private let serviceName = "TraceFence.DirectLicense"
    private let licenseAccount = "license_key"
    private let instanceAccount = "instance_id"
    private let decoder = JSONDecoder()
    private let dateCodec = ISO8601DateFormatter()

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let data = UserDefaults.standard.data(forKey: snapshotKey),
           let decoded = try? JSONDecoder().decode(DirectLicenseSnapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = .empty
        }
        trialSnapshot = .empty
        trialSnapshot = loadOrStartTrial()
    }

    func openPurchasePage(for plan: TraceFenceCheckoutPlan = .standard) {
        guard let purchaseURL = TraceFenceDistributionPolicy.checkoutURL(for: plan) else {
            snapshot.message = "Purchase URL is not configured yet."
            persistSnapshot()
            return
        }
        NSWorkspace.shared.open(purchaseURL)
    }

    func refreshTrialState() {
        trialSnapshot = loadOrStartTrial()
    }

    func activate(licenseKey rawLicenseKey: String) async {
        let licenseKey = rawLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !licenseKey.isEmpty else {
            snapshot.message = "Enter a license key first."
            persistSnapshot()
            return
        }

        isBusy = true
        snapshot.status = .validating
        snapshot.message = nil
        persistSnapshot()

        do {
            let response = try await post(endpoint: "activate", fields: [
                "license_key": licenseKey,
                "instance_name": instanceName()
            ])
            if response.activated == true || response.valid == true {
                saveSecret(licenseKey, account: licenseAccount)
                if let instanceId = response.instance?.id {
                    saveSecret(instanceId, account: instanceAccount)
                }
                apply(response: response, fallbackKey: licenseKey)
            } else {
                snapshot = DirectLicenseSnapshot(
                    status: status(from: response.licenseKey?.status, valid: false),
                    licenseKeySuffix: licenseKey.suffixText,
                    message: response.error ?? "License activation failed."
                )
                persistSnapshot()
            }
        } catch {
            snapshot.status = .error
            snapshot.licenseKeySuffix = licenseKey.suffixText
            snapshot.message = error.localizedDescription
            persistSnapshot()
        }

        isBusy = false
    }

    func validateCurrentLicense() async {
        guard let licenseKey = readSecret(account: licenseAccount) else {
            snapshot = .empty
            licenseSyncedThisRun = false
            persistSnapshot()
            return
        }

        isBusy = true
        snapshot.status = .validating
        persistSnapshot()

        var fields = ["license_key": licenseKey]
        if let instanceId = readSecret(account: instanceAccount) {
            fields["instance_id"] = instanceId
        }

        do {
            let response = try await post(endpoint: "validate", fields: fields)
            apply(response: response, fallbackKey: licenseKey)
        } catch {
            snapshot.status = .error
            snapshot.message = error.localizedDescription
            licenseSyncedThisRun = false
            persistSnapshot()
        }

        isBusy = false
    }

    func deactivateCurrentLicense() async {
        guard let licenseKey = readSecret(account: licenseAccount),
              let instanceId = readSecret(account: instanceAccount) else {
            clearLicense()
            return
        }

        isBusy = true
        do {
            _ = try await post(endpoint: "deactivate", fields: [
                "license_key": licenseKey,
                "instance_id": instanceId
            ])
        } catch {
            snapshot.message = error.localizedDescription
            persistSnapshot()
        }
        clearLicense()
        isBusy = false
    }

    func clearLicense() {
        deleteSecret(account: licenseAccount)
        deleteSecret(account: instanceAccount)
        snapshot = .empty
        licenseSyncedThisRun = false
        refreshTrialState()
        persistSnapshot()
    }

    private func post(endpoint: String, fields: [String: String]) async throws -> LemonLicenseResponse {
        var request = URLRequest(url: licenseBaseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("TraceFence/3.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = fields
            .map { key, value in "\(urlEncode(key))=\(urlEncode(value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DirectLicenseError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw DirectLicenseError.server(message)
        }
        return try decoder.decode(LemonLicenseResponse.self, from: data)
    }

    private func apply(response: LemonLicenseResponse, fallbackKey: String) {
        let licenseKey = response.licenseKey
        let existingInstanceId = snapshot.instanceId
        snapshot = DirectLicenseSnapshot(
            status: status(from: licenseKey?.status, valid: response.valid ?? response.activated ?? false),
            licenseKeySuffix: licenseKey?.key?.suffixText ?? fallbackKey.suffixText,
            instanceId: response.instance?.id ?? existingInstanceId,
            customerName: response.meta?.customerName,
            customerEmail: response.meta?.customerEmail,
            productName: response.meta?.productName,
            expiresAt: licenseKey?.expiresAt,
            activationLimit: licenseKey?.activationLimit ?? licenseKey?.instanceLimit,
            activationUsage: licenseKey?.activationUsage ?? licenseKey?.instancesCount,
            lastValidatedAt: Date(),
            message: response.error
        )
        licenseSyncedThisRun = true
        persistSnapshot()
    }

    private func status(from rawStatus: String?, valid: Bool) -> DirectLicenseStatus {
        switch rawStatus?.lowercased() {
        case "active":
            return valid ? .licensed : .inactive
        case "expired":
            return .expired
        case "disabled":
            return .disabled
        case "inactive":
            return .inactive
        default:
            return valid ? .licensed : .unlicensed
        }
    }

    private func instanceName() -> String {
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return "TraceFence on \(host)"
    }

    private func loadOrStartTrial() -> DirectTrialSnapshot {
        if let rawStartedAt = UserDefaults.standard.string(forKey: trialStartedKey),
           let startedAt = dateCodec.date(from: rawStartedAt) {
            return DirectTrialSnapshot(startedAt: startedAt, expiresAt: startedAt.addingTimeInterval(trialDuration))
        }

        let startedAt = Date()
        UserDefaults.standard.set(dateCodec.string(from: startedAt), forKey: trialStartedKey)
        return DirectTrialSnapshot(startedAt: startedAt, expiresAt: startedAt.addingTimeInterval(trialDuration))
    }

    private func persistSnapshot() {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    private func saveSecret(_ value: String, account: String) {
        deleteSecret(account: account)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func readSecret(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private struct LemonLicenseResponse: Decodable {
    var activated: Bool?
    var valid: Bool?
    var error: String?
    var licenseKey: LemonLicenseKey?
    var instance: LemonLicenseInstance?
    var meta: LemonLicenseMeta?
}

private struct LemonLicenseKey: Decodable {
    var status: String?
    var key: String?
    var expiresAt: String?
    var activationLimit: Int?
    var activationUsage: Int?
    var instanceLimit: Int?
    var instancesCount: Int?
}

private struct LemonLicenseInstance: Decodable {
    var id: String?
    var name: String?
}

private struct LemonLicenseMeta: Decodable {
    var productName: String?
    var customerName: String?
    var customerEmail: String?
}

private enum DirectLicenseError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The license server returned an invalid response."
        case .server(let message):
            return message
        }
    }
}

private extension String {
    var suffixText: String {
        guard count > 8 else { return self }
        return "•••• \(suffix(8))"
    }
}
