import AppKit
import Foundation
import Security

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
    var trialRemainingSeconds: TimeInterval {
        max(0, trialSnapshot.expiresAt.timeIntervalSinceNow)
    }
    var purchaseURL: URL? {
        let rawValue = (Bundle.main.object(forInfoDictionaryKey: "TraceFenceCheckoutURL") as? String)
            ?? UserDefaults.standard.string(forKey: "traceFenceCheckoutURL")
        guard let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(string: rawValue)
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

    func openPurchasePage() {
        guard let purchaseURL else {
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
