import AppKit
import CryptoKit
import Darwin
import Foundation

struct DirectUpdateInfo: Equatable {
    var version: String
    var releaseName: String
    var notes: String
    var downloadURL: URL
    var checksumURL: URL?
    var fileName: String
    var size: Int?
}

@MainActor
final class DirectUpdateService: ObservableObject {
    static let shared = DirectUpdateService()

    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var isInstalling = false
    @Published private(set) var latestUpdate: DirectUpdateInfo?
    @Published private(set) var downloadedFileURL: URL?
    @Published private(set) var message: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var releaseAPIURL: URL {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "TraceFenceUpdateAPIURL") as? String)
            ?? UserDefaults.standard.string(forKey: "traceFenceUpdateAPIURL")
        let rawValue = configured?.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: rawValue?.isEmpty == false ? rawValue! : "https://api.github.com/repos/AI-Scarlett/TraceFence/releases/latest")!
    }

    private init() {}

    func checkForUpdates() async {
        guard !isInstalling else { return }
        isChecking = true
        message = nil
        downloadedFileURL = nil
        defer { isChecking = false }

        do {
            var request = URLRequest(url: releaseAPIURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("TraceFence/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw DirectUpdateError.invalidResponse
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
                throw DirectUpdateError.noDMGAsset
            }

            let latestVersion = release.normalizedVersion
            guard isVersion(latestVersion, newerThan: currentVersion) else {
                latestUpdate = nil
                message = "TraceFence 已是最新版本。"
                return
            }

            let checksumAsset = release.assets.first {
                $0.name == asset.name + ".sha256" || $0.name.lowercased().hasSuffix(".dmg.sha256")
            }
            latestUpdate = DirectUpdateInfo(
                version: latestVersion,
                releaseName: release.name ?? release.tagName,
                notes: release.body ?? "",
                downloadURL: asset.browserDownloadUrl,
                checksumURL: checksumAsset?.browserDownloadUrl,
                fileName: asset.name,
                size: asset.size
            )
            message = "发现 TraceFence \(latestVersion)，点击更新后将自动安装并重新启动。"
        } catch {
            latestUpdate = nil
            message = error.localizedDescription
        }
    }

    func downloadLatestUpdate() async {
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
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
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
            let (checksumData, checksumResponse) = try await URLSession.shared.data(for: checksumRequest)
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

    private func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
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
        }
    }
}
