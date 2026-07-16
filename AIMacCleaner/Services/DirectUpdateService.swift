import AppKit
import CryptoKit
import Darwin
import Foundation
@preconcurrency import UserNotifications

struct DirectUpdateInfo: Equatable {
    var version: String
    var releaseName: String
    var notes: String
    var downloadURL: URL
    var checksumURL: URL?
    var fileName: String
    var size: Int?
}

enum CLIUpdateStatus: Equatable, Sendable {
    case upToDate
    case updateAvailable
    case notInstalled
    case checkFailed(String)
}

struct CLIUpdateCheckResult: Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var commandName: String
    var packageName: String
    var packageURL: URL
    var updateCommand: String
    var installedVersion: String?
    var latestVersion: String?
    var installedPath: String?
    var status: CLIUpdateStatus

    var needsUpdate: Bool {
        status == .updateAvailable
    }

    var needsStrongReminder: Bool {
        if status == .updateAvailable { return true }
        if case .checkFailed = status {
            return installedPath != nil && installedVersion == nil
        }
        return false
    }
}

struct CLIUpdateAlert: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var message: String
    var dismissTitle: String
}

@MainActor
final class DirectUpdateService: ObservableObject {
    static let shared = DirectUpdateService()
    static let cliUpdateStrongReminderEnabledKey = "cliUpdateStrongReminderEnabled"
    private static let cliUpdateLastNotifiedSignatureKey = "traceFence.cliUpdateReminder.lastNotifiedSignature"

    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var isInstalling = false
    @Published private(set) var latestUpdate: DirectUpdateInfo?
    @Published private(set) var downloadedFileURL: URL?
    @Published private(set) var message: String?
    @Published private(set) var cliToolUpdates: [CLIUpdateCheckResult] = []
    @Published var cliUpdateAlert: CLIUpdateAlert?
    private let updateSession: URLSession

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private var releaseAPIURL: URL? {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect else { return nil }
        let configured = (Bundle.main.object(forInfoDictionaryKey: "TraceFenceUpdateAPIURL") as? String)
            ?? UserDefaults.standard.string(forKey: "traceFenceUpdateAPIURL")
        let rawValue = configured?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue, !rawValue.isEmpty else { return nil }
        return URL(string: rawValue)
    }

    private var releaseManifestURL: URL? {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect else { return nil }
        return URL(string: "https://github.com/AI-Scarlett/TraceFence/releases/latest/download/tracefence-update.json")
    }

    private var cliUpdateStrongReminderEnabled: Bool {
        guard UserDefaults.standard.object(forKey: Self.cliUpdateStrongReminderEnabledKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.cliUpdateStrongReminderEnabledKey)
    }

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        if #available(macOS 10.15, *) {
            configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        }
        updateSession = URLSession(configuration: configuration)
    }

    func checkForUpdates(userInitiated: Bool = false) async {
        guard !isInstalling else { return }
        guard TraceFenceDistributionPolicy.currentChannel.isDirect else {
            latestUpdate = nil
            downloadedFileURL = nil
            await refreshCLIToolUpdates(userInitiated: userInitiated, appUpdateMessage: nil)
            return
        }
        isChecking = true
        message = nil
        downloadedFileURL = nil
        defer { isChecking = false }

        var updateMessage: String?
        do {
            let update = try await loadLatestUpdateInfo()
            let latestVersion = update.version
            guard Self.isVersion(latestVersion, newerThan: currentVersion) else {
                latestUpdate = nil
                updateMessage = "TraceFence 已是最新版本。"
                await refreshCLIToolUpdates(userInitiated: userInitiated, appUpdateMessage: updateMessage)
                return
            }

            latestUpdate = update
            updateMessage = "发现 TraceFence \(latestVersion)，点击更新后将自动安装并重新启动。"
        } catch {
            latestUpdate = nil
            updateMessage = error.localizedDescription
        }
        await refreshCLIToolUpdates(userInitiated: userInitiated, appUpdateMessage: updateMessage)
    }

    func downloadLatestUpdate() async {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect else { return }
        guard let update = latestUpdate else {
            message = "当前没有可安装的更新。"
            return
        }
        guard !isDownloading, !isInstalling else { return }

        isDownloading = true
        message = "正在下载 TraceFence \(update.version)…"

        do {
            let installerURL = try await download(update)
            downloadedFileURL = installerURL
            isDownloading = false
            isInstalling = true
            message = "正在验证并准备安装，TraceFence 随后会自动重新启动。"

            let prepared = try await Task.detached(priority: .userInitiated) {
                try Self.prepareInstallation(update: update, installerURL: installerURL)
            }.value

            try Self.launchInstallerHelper(prepared)
            message = "更新已准备完成，正在重新启动…"

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.requestFullQuit()
                } else {
                    NSApp.terminate(nil)
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
                    Darwin.exit(0)
                }
            }
        } catch {
            isDownloading = false
            isInstalling = false
            message = error.localizedDescription
        }
    }

    func openDownloadedUpdate() {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect else { return }
        guard let downloadedFileURL else { return }
        NSWorkspace.shared.open(downloadedFileURL)
    }

    private func download(_ update: DirectUpdateInfo) async throws -> URL {
        let updateDirectory = URL(fileURLWithPath: SandboxPaths.shared.dataDirectory, isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: updateDirectory, withIntermediateDirectories: true)
        let destination = updateDirectory.appendingPathComponent(update.fileName)
        try? FileManager.default.removeItem(at: destination)

        var request = URLRequest(url: update.downloadURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("TraceFence/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let (temporaryURL, response) = try await download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DirectUpdateError.invalidResponse
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        if let checksumURL = update.checksumURL {
            var checksumRequest = URLRequest(url: checksumURL)
            checksumRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            checksumRequest.setValue("TraceFence/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            checksumRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            checksumRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")
            let (checksumData, checksumResponse) = try await data(for: checksumRequest)
            guard let httpResponse = checksumResponse as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let checksumText = String(data: checksumData, encoding: .utf8),
                  let expectedHash = checksumText.split(whereSeparator: { $0.isWhitespace }).first else {
                throw DirectUpdateError.invalidChecksum
            }
            let actualHash = try Self.sha256(of: destination)
            guard actualHash.caseInsensitiveCompare(String(expectedHash)) == .orderedSame else {
                throw DirectUpdateError.invalidChecksum
            }
        } else if let expectedSize = update.size {
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let downloadedSize = (attributes[.size] as? NSNumber)?.intValue
            guard downloadedSize == expectedSize else {
                throw DirectUpdateError.downloadSizeMismatch
            }
        }

        return destination
    }

    private func loadLatestUpdateInfo() async throws -> DirectUpdateInfo {
        do {
            return try await loadGitHubUpdateInfo()
        } catch {
            do {
                return try await loadManifestUpdateInfo()
            } catch let fallbackError {
                throw DirectUpdateError.networkFailed(Self.localizedNetworkFailure(primary: error, fallback: fallbackError))
            }
        }
    }

    private func loadGitHubUpdateInfo() async throws -> DirectUpdateInfo {
        guard let releaseAPIURL else { throw DirectUpdateError.invalidResponse }
        var request = URLRequest(url: releaseAPIURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TraceFence/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let (data, response) = try await data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DirectUpdateError.invalidResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
            throw DirectUpdateError.noDMGAsset
        }
        let checksumAsset = release.assets.first {
            $0.name == asset.name + ".sha256" || $0.name.lowercased().hasSuffix(".dmg.sha256")
        }
        return DirectUpdateInfo(
            version: release.normalizedVersion,
            releaseName: release.name ?? release.tagName,
            notes: release.body ?? "",
            downloadURL: asset.browserDownloadUrl,
            checksumURL: checksumAsset?.browserDownloadUrl,
            fileName: asset.name,
            size: asset.size
        )
    }

    private func loadManifestUpdateInfo() async throws -> DirectUpdateInfo {
        guard let releaseManifestURL else { throw DirectUpdateError.invalidResponse }
        var request = URLRequest(url: releaseManifestURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TraceFence/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let (data, response) = try await data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DirectUpdateError.invalidResponse
        }
        let manifest = try JSONDecoder().decode(DirectUpdateManifest.self, from: data)
        return manifest.updateInfo
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await updateSession.data(for: request)
            } catch {
                lastError = error
                guard attempt < 2, Self.isRetryableNetworkError(error) else { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000)
            }
        }
        throw lastError ?? DirectUpdateError.invalidResponse
    }

    private func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await updateSession.download(for: request)
            } catch {
                lastError = error
                guard attempt < 2, Self.isRetryableNetworkError(error) else { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 750_000_000)
            }
        }
        throw lastError ?? DirectUpdateError.invalidResponse
    }

    private nonisolated static func isRetryableNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .notConnectedToInternet,
             .dnsLookupFailed,
             .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }

    private nonisolated static func localizedNetworkFailure(primary: Error, fallback: Error) -> String {
        let reason = readableNetworkReason(primary) ?? readableNetworkReason(fallback)
        let suffix = reason.map {
            localized("（\($0)）", en: " (\($0))", zhHant: "（\($0)）", ja: "（\($0)）", ko: " (\($0))", mt: " (\($0))")
        } ?? ""
        return localized(
            "无法连接更新服务器\(suffix)。TraceFence 已自动重试并尝试备用更新源；请确认网络、VPN 或代理可以访问 GitHub，然后再点一次检查更新。",
            en: "Could not connect to the update server\(suffix). TraceFence retried and tried the fallback update source; check that your network, VPN, or proxy can reach GitHub, then try Check for Updates again.",
            zhHant: "無法連接更新伺服器\(suffix)。TraceFence 已自動重試並嘗試備用更新源；請確認網路、VPN 或代理可以存取 GitHub，然後再點一次檢查更新。",
            ja: "更新サーバーに接続できません\(suffix)。TraceFence は自動で再試行し、代替更新ソースも試しました。ネットワーク、VPN、またはプロキシが GitHub に接続できることを確認してから、もう一度アップデートを確認してください。",
            ko: "업데이트 서버에 연결할 수 없습니다\(suffix). TraceFence가 자동 재시도와 예비 업데이트 소스를 시도했습니다. 네트워크, VPN 또는 프록시가 GitHub에 연결되는지 확인한 뒤 다시 업데이트 확인을 눌러주세요.",
            mt: "Could not connect to the update server\(suffix). TraceFence retried and tried the fallback update source; check that your network, VPN, or proxy can reach GitHub, then try Check for Updates again."
        )
    }

    private nonisolated static func readableNetworkReason(_ error: Error) -> String? {
        guard let urlError = error as? URLError else { return nil }
        switch urlError.code {
        case .secureConnectionFailed:
            return localized("TLS 安全连接失败", en: "TLS secure connection failed", zhHant: "TLS 安全連線失敗", ja: "TLS セキュア接続に失敗", ko: "TLS 보안 연결 실패", mt: "TLS secure connection failed")
        case .timedOut:
            return localized("连接超时", en: "connection timed out", zhHant: "連線逾時", ja: "接続がタイムアウトしました", ko: "연결 시간 초과", mt: "connection timed out")
        case .notConnectedToInternet:
            return localized("网络不可用", en: "network is unavailable", zhHant: "網路不可用", ja: "ネットワークを利用できません", ko: "네트워크를 사용할 수 없음", mt: "network is unavailable")
        default:
            return urlError.localizedDescription
        }
    }

    private nonisolated static func localized(_ zh: String, en: String, zhHant: String? = nil, ja: String? = nil, ko: String? = nil, mt: String? = nil) -> String {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        switch AppLanguage(rawValue: raw) ?? .english {
        case .simplifiedChinese: return zh
        case .traditionalChinese: return zhHant ?? zh
        case .japanese: return ja ?? en
        case .korean: return ko ?? en
        case .maltese: return mt ?? en
        case .english: return en
        }
    }

    func dismissCLIUpdateAlert() {
        cliUpdateAlert = nil
    }

    private func refreshCLIToolUpdates(userInitiated: Bool, appUpdateMessage: String?) async {
        let results = await Task.detached(priority: .utility) {
            await Self.loadCLIToolResults()
        }.value
        cliToolUpdates = results

        let cliMessage = Self.cliUpdateSummary(for: results)
        message = [appUpdateMessage, cliMessage]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: "\n")

        let attention = results.filter(\.needsStrongReminder)
        guard cliUpdateStrongReminderEnabled else { return }
        guard !attention.isEmpty else { return }
        let alert = Self.makeCLIUpdateAlert(for: attention)
        if userInitiated {
            cliUpdateAlert = alert
        } else if shouldPostCLIUpdateNotification(for: attention) {
            postCLIUpdateNotification(alert: alert, outdated: attention)
        }
    }

    private nonisolated static func cliUpdateSummary(for results: [CLIUpdateCheckResult]) -> String? {
        guard !results.isEmpty else { return nil }
        let outdated = results.filter(\.needsUpdate)
        if !outdated.isEmpty {
            let names = outdated.map { $0.displayName }.joined(separator: "、")
            return localized(
                "发现 \(names) CLI 有新版本，建议立即升级。",
                en: "\(names) CLI update available. Upgrade as soon as possible.",
                zhHant: "發現 \(names) CLI 有新版本，建議立即升級。",
                ja: "\(names) CLI の新しいバージョンがあります。できるだけ早く更新してください。",
                ko: "\(names) CLI 업데이트가 있습니다. 가능한 한 빨리 업그레이드하세요.",
                mt: "\(names) CLI update available. Upgrade as soon as possible."
            )
        }

        let installed = results.filter { result in
            switch result.status {
            case .upToDate:
                return true
            default:
                return false
            }
        }
        if installed.count == results.count {
            return localized(
                "Codex / Claude CLI 已是最新版本。",
                en: "Codex / Claude CLI are up to date.",
                zhHant: "Codex / Claude CLI 已是最新版本。",
                ja: "Codex / Claude CLI は最新です。",
                ko: "Codex / Claude CLI가 최신 상태입니다.",
                mt: "Codex / Claude CLI are up to date."
            )
        }

        let failures = results.compactMap { result -> String? in
            if case .checkFailed = result.status { return result.displayName }
            return nil
        }
        if !failures.isEmpty {
            return localized(
                "部分 CLI 更新状态暂时无法确认：\(failures.joined(separator: "、"))。",
                en: "Some CLI update states could not be confirmed: \(failures.joined(separator: ", ")).",
                zhHant: "部分 CLI 更新狀態暫時無法確認：\(failures.joined(separator: "、"))。",
                ja: "一部 CLI の更新状態を確認できませんでした: \(failures.joined(separator: ", "))。",
                ko: "일부 CLI 업데이트 상태를 확인할 수 없습니다: \(failures.joined(separator: ", ")).",
                mt: "Some CLI update states could not be confirmed: \(failures.joined(separator: ", "))."
            )
        }
        return nil
    }

    private func shouldPostCLIUpdateNotification(for outdated: [CLIUpdateCheckResult]) -> Bool {
        let signature = outdated
            .map { "\($0.id):\($0.latestVersion ?? "unknown")" }
            .sorted()
            .joined(separator: "|")
        guard UserDefaults.standard.string(forKey: Self.cliUpdateLastNotifiedSignatureKey) != signature else {
            return false
        }
        UserDefaults.standard.set(signature, forKey: Self.cliUpdateLastNotifiedSignatureKey)
        return true
    }

    private nonisolated static func makeCLIUpdateAlert(for outdated: [CLIUpdateCheckResult]) -> CLIUpdateAlert {
        let body = outdated.map { result -> String in
            let installed = result.installedVersion ?? localized("未知", en: "unknown", zhHant: "未知", ja: "不明", ko: "알 수 없음", mt: "unknown")
            let latest = result.latestVersion ?? localized("未知", en: "unknown", zhHant: "未知", ja: "不明", ko: "알 수 없음", mt: "unknown")
            return "\(result.displayName): \(installed) → \(latest)\n\(result.updateCommand)"
        }.joined(separator: "\n\n")
        let signature = outdated
            .map { "\($0.id):\($0.latestVersion ?? "unknown")" }
            .sorted()
            .joined(separator: "|")
        return CLIUpdateAlert(
            id: "cli-update-\(signature)-\(Int(Date().timeIntervalSince1970))",
            title: localized(
                "AI CLI 安全更新提醒",
                en: "AI CLI Security Update",
                zhHant: "AI CLI 安全更新提醒",
                ja: "AI CLI セキュリティ更新",
                ko: "AI CLI 보안 업데이트",
                mt: "AI CLI Security Update"
            ),
            message: localized(
                "检测到 Codex / Claude 相关 CLI 不是最新版本。为了降低已知安全风险，请尽快升级：\n\n\(body)",
                en: "TraceFence found Codex / Claude related CLI tools that are not up to date. To reduce known security risk, upgrade soon:\n\n\(body)",
                zhHant: "偵測到 Codex / Claude 相關 CLI 不是最新版本。為了降低已知安全風險，請盡快升級：\n\n\(body)",
                ja: "Codex / Claude 関連 CLI が最新ではありません。既知のセキュリティリスクを下げるため、早めに更新してください:\n\n\(body)",
                ko: "Codex / Claude 관련 CLI가 최신 버전이 아닙니다. 알려진 보안 위험을 줄이려면 가능한 한 빨리 업그레이드하세요:\n\n\(body)",
                mt: "TraceFence found Codex / Claude related CLI tools that are not up to date. To reduce known security risk, upgrade soon:\n\n\(body)"
            ),
            dismissTitle: localized(
                "我知道了",
                en: "Got it",
                zhHant: "我知道了",
                ja: "了解",
                ko: "확인",
                mt: "Got it"
            )
        )
    }

    private func postCLIUpdateNotification(alert: CLIUpdateAlert, outdated: [CLIUpdateCheckResult]) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = outdated
            .map { "\($0.displayName) \($0.installedVersion ?? "?") → \($0.latestVersion ?? "?")" }
            .joined(separator: "；")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "tracefence.cli.update.\(alert.id)",
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    center.add(request)
                }
            default:
                break
            }
        }
    }

    private nonisolated static func loadCLIToolResults() async -> [CLIUpdateCheckResult] {
        let descriptors = cliToolDescriptors
        return await withTaskGroup(of: (String, CLIUpdateCheckResult).self) { group in
            for descriptor in descriptors {
                group.addTask {
                    let result = await checkCLITool(descriptor)
                    return (descriptor.id, result)
                }
            }

            var resultsByID: [String: CLIUpdateCheckResult] = [:]
            for await (id, result) in group {
                resultsByID[id] = result
            }
            return descriptors.compactMap { resultsByID[$0.id] }
        }
    }

    private nonisolated static var cliToolDescriptors: [CLIToolDescriptor] {
        [
            CLIToolDescriptor(
                id: "codex",
                displayName: "Codex",
                commandName: "codex",
                packageName: "@openai/codex",
                latestURL: URL(string: "https://registry.npmjs.org/@openai%2Fcodex/latest")!,
                packageURL: URL(string: "https://www.npmjs.com/package/%40openai/codex")!,
                updateCommand: "npm install -g @openai/codex@latest"
            ),
            CLIToolDescriptor(
                id: "claude",
                displayName: "Claude Code",
                commandName: "claude",
                packageName: "@anthropic-ai/claude-code",
                latestURL: URL(string: "https://registry.npmjs.org/@anthropic-ai%2Fclaude-code/latest")!,
                packageURL: URL(string: "https://www.npmjs.com/package/%40anthropic-ai/claude-code")!,
                updateCommand: "npm install -g @anthropic-ai/claude-code@latest"
            )
        ]
    }

    private nonisolated static func checkCLITool(_ descriptor: CLIToolDescriptor) async -> CLIUpdateCheckResult {
        let installation = detectInstalledCLI(descriptor)
        guard installation.isInstalled else {
            return result(
                for: descriptor,
                installedVersion: nil,
                latestVersion: nil,
                installedPath: nil,
                status: .notInstalled
            )
        }

        guard let installedVersion = installation.version else {
            let latestVersion = try? await fetchLatestNPMVersion(descriptor)
            return result(
                for: descriptor,
                installedVersion: nil,
                latestVersion: latestVersion,
                installedPath: installation.path,
                status: .checkFailed(localized(
                    "已找到 CLI，但无法读取版本。建议重装或升级到最新版本。",
                    en: "CLI was found, but its version could not be read. Reinstall or upgrade to the latest version.",
                    zhHant: "已找到 CLI，但無法讀取版本。建議重裝或升級到最新版本。",
                    ja: "CLI は見つかりましたが、バージョンを読み取れませんでした。再インストールまたは最新版への更新をおすすめします。",
                    ko: "CLI를 찾았지만 버전을 읽을 수 없습니다. 재설치하거나 최신 버전으로 업그레이드하세요.",
                    mt: "CLI was found, but its version could not be read. Reinstall or upgrade to the latest version."
                ))
            )
        }

        do {
            let latestVersion = try await fetchLatestNPMVersion(descriptor)
            let status: CLIUpdateStatus = isVersion(latestVersion, newerThan: installedVersion)
                ? .updateAvailable
                : .upToDate
            return result(
                for: descriptor,
                installedVersion: installedVersion,
                latestVersion: latestVersion,
                installedPath: installation.path,
                status: status
            )
        } catch {
            return result(
                for: descriptor,
                installedVersion: installedVersion,
                latestVersion: nil,
                installedPath: installation.path,
                status: .checkFailed(readableCLIUpdateError(error))
            )
        }
    }

    private nonisolated static func result(
        for descriptor: CLIToolDescriptor,
        installedVersion: String?,
        latestVersion: String?,
        installedPath: String?,
        status: CLIUpdateStatus
    ) -> CLIUpdateCheckResult {
        CLIUpdateCheckResult(
            id: descriptor.id,
            displayName: descriptor.displayName,
            commandName: descriptor.commandName,
            packageName: descriptor.packageName,
            packageURL: descriptor.packageURL,
            updateCommand: descriptor.updateCommand,
            installedVersion: installedVersion,
            latestVersion: latestVersion,
            installedPath: installedPath,
            status: status
        )
    }

    private nonisolated static func detectInstalledCLI(_ descriptor: CLIToolDescriptor) -> CLIInstallation {
        let command = descriptor.commandName
        let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        let preferredPATH = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin",
            "\(home)/.deno/bin",
            "\(home)/.cargo/bin",
            "\(home)/.volta/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")
        let script = """
        export PATH="\(preferredPATH):$PATH"
        if command -v \(command) >/dev/null 2>&1; then
          cli_path="$(command -v \(command))"
          cli_version="$({ \(command) --version || \(command) -v; } 2>&1 | /usr/bin/head -n 3)"
          printf '__TRACEFENCE_PATH__=%s\\n' "$cli_path"
          printf '__TRACEFENCE_VERSION__=%s\\n' "$cli_version"
        else
          exit 127
        fi
        """
        let shellResult = runShell(script, timeout: 8)
        guard shellResult.status == 0 else {
            return CLIInstallation(version: nil, path: nil)
        }
        let path = extractShellValue("__TRACEFENCE_PATH__", from: shellResult.output)
        let versionText = extractShellValue("__TRACEFENCE_VERSION__", from: shellResult.output) ?? shellResult.output
        return CLIInstallation(
            version: parseVersion(from: versionText),
            path: path
        )
    }

    private nonisolated static func fetchLatestNPMVersion(_ descriptor: CLIToolDescriptor) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: descriptor.latestURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TraceFence CLI Update Check", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DirectUpdateError.invalidResponse
        }
        let latest = try JSONDecoder().decode(NPMRegistryLatest.self, from: data)
        return latest.version
    }

    private nonisolated static func readableCLIUpdateError(_ error: Error) -> String {
        if let reason = readableNetworkReason(error) {
            return localized(
                "无法连接 npm registry：\(reason)",
                en: "Could not reach npm registry: \(reason)",
                zhHant: "無法連接 npm registry：\(reason)",
                ja: "npm registry に接続できません: \(reason)",
                ko: "npm registry에 연결할 수 없습니다: \(reason)",
                mt: "Could not reach npm registry: \(reason)"
            )
        }
        return error.localizedDescription
    }

    private nonisolated static func parseVersion(from text: String) -> String? {
        let pattern = #"v?(\d+(?:\.\d+){1,4}(?:[-+][0-9A-Za-z.-]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private nonisolated static func extractShellValue(_ key: String, from output: String) -> String? {
        let prefix = "\(key)="
        return output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private nonisolated static func runShell(_ script: String, timeout: TimeInterval) -> ShellResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, output: error.localizedDescription, timedOut: false)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        var timedOut = false
        if process.isRunning {
            timedOut = true
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return ShellResult(status: process.terminationStatus, output: text, timedOut: timedOut)
    }

    private nonisolated static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = normalizedVersionNumbers(lhs)
        let right = normalizedVersionNumbers(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    private nonisolated static func normalizedVersionNumbers(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                let digits = component.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }

    private nonisolated static func prepareInstallation(
        update: DirectUpdateInfo,
        installerURL: URL
    ) throws -> PreparedInstallation {
        let mountURL = try mountDMG(installerURL)
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mountURL.path, "-quiet"]) }

        let sourceApp = mountURL.appendingPathComponent("TraceFence.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            throw DirectUpdateError.appMissingFromDMG
        }

        let currentBundleID = Bundle.main.bundleIdentifier ?? "com.tracefence.app"
        let currentTeamID = try signingTeamIdentifier(at: Bundle.main.bundleURL)
        try validateApplication(
            sourceApp,
            expectedBundleID: currentBundleID,
            expectedTeamID: currentTeamID,
            expectedVersion: update.version
        )

        let destination = installationDestination()
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw DirectUpdateError.installLocationNotWritable
        }

        let stagedApp = parent.appendingPathComponent(".TraceFence-update-\(UUID().uuidString).app")
        try? FileManager.default.removeItem(at: stagedApp)
        _ = try run("/usr/bin/ditto", [sourceApp.path, stagedApp.path])
        try validateApplication(
            stagedApp,
            expectedBundleID: currentBundleID,
            expectedTeamID: currentTeamID,
            expectedVersion: update.version
        )

        try? FileManager.default.removeItem(at: installerURL)
        return PreparedInstallation(
            stagedApp: stagedApp,
            destinationApp: destination,
            parentPID: ProcessInfo.processInfo.processIdentifier,
            supportDirectory: URL(fileURLWithPath: SandboxPaths.shared.dataDirectory, isDirectory: true)
        )
    }

    private nonisolated static func installationDestination() -> URL {
        let current = Bundle.main.bundleURL.standardizedFileURL
        let path = current.path
        if !path.hasPrefix("/Volumes/") && !path.contains("/AppTranslocation/") {
            return current
        }

        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: systemApplications.path) {
            return systemApplications.appendingPathComponent("TraceFence.app", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("TraceFence.app", isDirectory: true)
    }

    private nonisolated static func mountDMG(_ dmgURL: URL) throws -> URL {
        let output = try run("/usr/bin/hdiutil", ["attach", dmgURL.path, "-nobrowse", "-readonly", "-plist"])
        guard let plist = try PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw DirectUpdateError.mountFailed
        }
        return URL(fileURLWithPath: mountPath, isDirectory: true)
    }

    private nonisolated static func validateApplication(
        _ appURL: URL,
        expectedBundleID: String,
        expectedTeamID: String,
        expectedVersion: String
    ) throws {
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
        _ = try run("/usr/sbin/spctl", ["--assess", "--type", "execute", appURL.path])

        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == expectedBundleID,
              (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) == expectedVersion else {
            throw DirectUpdateError.invalidApplicationIdentity
        }
        guard try signingTeamIdentifier(at: appURL) == expectedTeamID else {
            throw DirectUpdateError.invalidApplicationIdentity
        }
    }

    private nonisolated static func signingTeamIdentifier(at appURL: URL) throws -> String {
        let output = try run("/usr/bin/codesign", ["-d", "--verbose=4", appURL.path], includeStandardError: true)
        guard let text = String(data: output, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) else {
            throw DirectUpdateError.invalidApplicationIdentity
        }
        return String(line.dropFirst("TeamIdentifier=".count))
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1_048_576)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func run(
        _ executable: String,
        _ arguments: [String],
        includeStandardError: Bool = false
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DirectUpdateError.commandFailed(detail ?? executable)
        }
        return includeStandardError ? stdout + stderr : stdout
    }

    private static func launchInstallerHelper(_ prepared: PreparedInstallation) throws {
        let helperURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tracefence-update-\(UUID().uuidString).zsh")
        let logURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tracefence-update.log")
        try installerHelperScript.write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            helperURL.path,
            prepared.stagedApp.path,
            prepared.destinationApp.path,
            String(prepared.parentPID),
            prepared.supportDirectory.path,
            logURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static let installerHelperScript = #"""
#!/bin/zsh
set -u

staged_app="$1"
destination_app="$2"
parent_pid="$3"
support_dir="$4"
log_file="$5"
backup_app="${destination_app}.previous-${parent_pid}"
bookmark_backup="${support_dir}/UpdateBackups/pending-${parent_pid}"

exec >>"$log_file" 2>&1
echo "[$(date)] TraceFence update helper started"

wait_for_parent_exit() {
    local attempts="$1"
    for _ in $(seq 1 "$attempts"); do
        if ! kill -0 "$parent_pid" 2>/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

if ! wait_for_parent_exit 80; then
    echo "TraceFence still running; requesting termination"
    kill -TERM "$parent_pid" 2>/dev/null || true
fi

if ! wait_for_parent_exit 40; then
    echo "TraceFence still running after TERM; forcing termination"
    kill -KILL "$parent_pid" 2>/dev/null || true
fi

for _ in {1..50}; do
    if ! kill -0 "$parent_pid" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

if kill -0 "$parent_pid" 2>/dev/null; then
    echo "TraceFence did not terminate in time"
    rm -rf "$staged_app"
    exit 1
fi

mkdir -p "$bookmark_backup"
for name in bookmarks.json scan_bookmarks.json tokenscope_bookmarks.json; do
    if [[ -f "${support_dir}/${name}" ]]; then
        /usr/bin/ditto "${support_dir}/${name}" "${bookmark_backup}/${name}"
    fi
done

rm -rf "$backup_app"
if [[ -e "$destination_app" ]]; then
    if ! mv "$destination_app" "$backup_app"; then
        echo "Could not move the previous app"
        rm -rf "$staged_app"
        exit 1
    fi
fi

if ! mv "$staged_app" "$destination_app"; then
    echo "Could not install the staged app; restoring previous version"
    [[ -e "$backup_app" ]] && mv "$backup_app" "$destination_app"
    /usr/bin/open "$destination_app"
    exit 1
fi

for name in bookmarks.json scan_bookmarks.json tokenscope_bookmarks.json; do
    if [[ -f "${bookmark_backup}/${name}" ]]; then
        /usr/bin/ditto "${bookmark_backup}/${name}" "${support_dir}/${name}"
    fi
done

if ! /usr/bin/open "$destination_app"; then
    echo "Could not launch the new version; restoring previous version"
    rm -rf "$destination_app"
    [[ -e "$backup_app" ]] && mv "$backup_app" "$destination_app"
    /usr/bin/open "$destination_app"
    exit 1
fi

sleep 2
rm -rf "$backup_app"
rm -rf "$bookmark_backup"
rm -f "$0"
echo "[$(date)] TraceFence update completed"
"""#
}

private struct PreparedInstallation {
    let stagedApp: URL
    let destinationApp: URL
    let parentPID: Int32
    let supportDirectory: URL
}

private struct CLIToolDescriptor: Sendable {
    var id: String
    var displayName: String
    var commandName: String
    var packageName: String
    var latestURL: URL
    var packageURL: URL
    var updateCommand: String
}

private struct CLIInstallation: Sendable {
    var version: String?
    var path: String?

    var isInstalled: Bool {
        path != nil || version != nil
    }
}

private struct ShellResult: Sendable {
    var status: Int32
    var output: String
    var timedOut: Bool
}

private struct NPMRegistryLatest: Decodable {
    var version: String
}

private struct GitHubRelease: Decodable {
    var tagName: String
    var name: String?
    var body: String?
    var assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case assets
    }

    var normalizedVersion: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }
}

private struct GitHubReleaseAsset: Decodable {
    var name: String
    var browserDownloadUrl: URL
    var size: Int?

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

private struct DirectUpdateManifest: Decodable {
    var version: String
    var releaseName: String?
    var notes: String?
    var downloadURL: URL
    var checksumURL: URL?
    var fileName: String
    var size: Int?

    var updateInfo: DirectUpdateInfo {
        DirectUpdateInfo(
            version: version,
            releaseName: releaseName ?? "TraceFence v\(version)",
            notes: notes ?? "",
            downloadURL: downloadURL,
            checksumURL: checksumURL,
            fileName: fileName,
            size: size
        )
    }
}

private enum DirectUpdateError: LocalizedError {
    case invalidResponse
    case noDMGAsset
    case downloadSizeMismatch
    case invalidChecksum
    case mountFailed
    case appMissingFromDMG
    case invalidApplicationIdentity
    case installLocationNotWritable
    case commandFailed(String)
    case networkFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "更新服务器返回异常，请稍后重试。"
        case .noDMGAsset:
            return "最新 GitHub Release 没有找到 DMG 安装包。"
        case .downloadSizeMismatch:
            return "更新包下载不完整，请重新尝试。"
        case .invalidChecksum:
            return "更新包校验失败，安装已停止。"
        case .mountFailed:
            return "无法挂载更新安装包。"
        case .appMissingFromDMG:
            return "更新安装包中没有找到 TraceFence.app。"
        case .invalidApplicationIdentity:
            return "更新包签名、Bundle ID 或版本不匹配，安装已停止。"
        case .installLocationNotWritable:
            return "当前 TraceFence 安装位置不可写。请先将应用移动到“应用程序”或用户应用程序目录。"
        case .commandFailed(let detail):
            return "自动安装失败：\(detail)"
        case .networkFailed(let detail):
            return detail
        }
    }
}
