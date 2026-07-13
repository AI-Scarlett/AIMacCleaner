import CryptoKit
import Darwin
import Foundation

private let updaterVersion = "1.0.1"
private let expectedBundleIdentifier = "com.tracefence.agent-core.bundle"
private let maximumManifestBytes = 1 * 1_024 * 1_024
private let maximumPackageBytes = 250 * 1_024 * 1_024

private struct UpdateConfiguration: Decodable {
    let enabled: Bool
    let automaticInstall: Bool
    let channel: String
    let manifestURL: String
    let trustedTeamID: String
    let checkIntervalSeconds: Int?
    let allowLocalPackages: Bool?
    let allowAdHocForLocalTesting: Bool?
}

private struct UpdateManifest: Codable {
    let schemaVersion: Int
    let channel: String
    let version: String
    let build: Int
    let minimumProtocolVersion: Int
    let packageURL: String
    let packageSHA256: String
    let packageSize: Int?
    let bundleIdentifier: String
    let publishedAt: String
}

private struct UpdateStatus: Codable {
    let state: String
    let currentVersion: String
    let currentBuild: Int
    let latestVersion: String?
    let latestBuild: Int?
    let checkedAt: String
    let installedAt: String?
    let error: String?
}

private enum UpdaterError: LocalizedError {
    case invalidArguments(String)
    case invalidConfiguration(String)
    case invalidManifest(String)
    case insecureURL
    case downloadFailed(String)
    case packageTooLarge
    case checksumMismatch
    case unsafeArchive
    case extractionFailed(String)
    case invalidBundle(String)
    case signatureInvalid(String)
    case teamMismatch(expected: String, actual: String)
    case installFailed(String)
    case healthCheckFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let value): return "invalid_arguments:\(value)"
        case .invalidConfiguration(let value): return "invalid_configuration:\(value)"
        case .invalidManifest(let value): return "invalid_manifest:\(value)"
        case .insecureURL: return "update_urls_must_use_https"
        case .downloadFailed(let value): return "download_failed:\(value)"
        case .packageTooLarge: return "update_package_too_large"
        case .checksumMismatch: return "update_package_checksum_mismatch"
        case .unsafeArchive: return "unsafe_update_archive"
        case .extractionFailed(let value): return "update_extraction_failed:\(value)"
        case .invalidBundle(let value): return "invalid_core_bundle:\(value)"
        case .signatureInvalid(let value): return "core_bundle_signature_invalid:\(value)"
        case .teamMismatch(let expected, let actual): return "core_bundle_team_mismatch:expected_\(expected):actual_\(actual)"
        case .installFailed(let value): return "core_install_failed:\(value)"
        case .healthCheckFailed: return "updated_core_health_check_failed"
        }
    }
}

private final class ProcessOutputCapture: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var value = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.readData(ofLength: 64 * 1_024)
            if chunk.isEmpty { break }
            lock.lock()
            let available = max(0, limit - value.count)
            if available > 0 { value.append(chunk.prefix(available)) }
            lock.unlock()
        }
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: value, encoding: .utf8) ?? ""
    }
}

private final class DownloadResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURL: URL?
    private var storedResponse: URLResponse?
    private var storedError: Error?

    func set(url: URL?, response: URLResponse?, error: Error?) {
        lock.lock()
        storedURL = url
        storedResponse = response
        storedError = error
        lock.unlock()
    }

    func value() -> (URL?, URLResponse?, Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (storedURL, storedResponse, storedError)
    }
}

private final class CoreUpdater {
    private let configuration: UpdateConfiguration
    private let installRoot: URL
    private let statusURL: URL
    private let socketPath: String
    private let fileManager = FileManager.default
    private let isoFormatter = ISO8601DateFormatter()

    init(configuration: UpdateConfiguration, installRoot: URL, socketPath: String) {
        self.configuration = configuration
        self.installRoot = installRoot.standardizedFileURL
        statusURL = installRoot.appendingPathComponent("update-status.json")
        self.socketPath = socketPath
    }

    func checkAndInstall(currentVersion: String, currentBuild: Int, forceInstall: Bool) throws -> [String: Any] {
        guard configuration.enabled else {
            writeStatus(state: "disabled", currentVersion: currentVersion, currentBuild: currentBuild)
            return ["state": "disabled", "version": currentVersion]
        }
        guard let manifestURL = URL(string: configuration.manifestURL) else {
            throw UpdaterError.invalidConfiguration("manifest_url")
        }
        try validateRemoteURL(manifestURL)
        writeStatus(state: "checking", currentVersion: currentVersion, currentBuild: currentBuild)

        do {
            let manifestData = try loadSmallResource(from: manifestURL, maximumBytes: maximumManifestBytes)
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: manifestData)
            try validate(manifest: manifest)
            guard isNewer(manifest: manifest, thanVersion: currentVersion, build: currentBuild) else {
                writeStatus(
                    state: "up_to_date",
                    currentVersion: currentVersion,
                    currentBuild: currentBuild,
                    latest: manifest
                )
                return ["state": "up_to_date", "version": currentVersion, "build": currentBuild]
            }

            guard configuration.automaticInstall || forceInstall else {
                writeStatus(
                    state: "update_available",
                    currentVersion: currentVersion,
                    currentBuild: currentBuild,
                    latest: manifest
                )
                return ["state": "update_available", "version": manifest.version, "build": manifest.build]
            }

            let packageURL = try resolvedPackageURL(manifest: manifest, relativeTo: manifestURL)
            try install(
                manifest: manifest,
                packageURL: packageURL,
                currentVersion: currentVersion,
                currentBuild: currentBuild
            )
            return ["state": "installed", "version": manifest.version, "build": manifest.build]
        } catch {
            if case .healthCheckFailed? = error as? UpdaterError {
                // install() already recorded a successful rollback.
            } else {
                writeStatus(
                    state: "failed",
                    currentVersion: currentVersion,
                    currentBuild: currentBuild,
                    error: error.localizedDescription
                )
            }
            throw error
        }
    }

    func verify(bundleURL: URL, manifest: UpdateManifest, packageWasLocal: Bool) throws {
        try verifyBundle(bundleURL, manifest: manifest, packageWasLocal: packageWasLocal)
    }

    private func install(
        manifest: UpdateManifest,
        packageURL: URL,
        currentVersion: String,
        currentBuild: Int
    ) throws {
        let packageWasLocal = packageURL.isFileURL
        if packageWasLocal {
            guard configuration.allowLocalPackages == true else { throw UpdaterError.insecureURL }
        } else {
            try validateRemoteURL(packageURL)
        }

        writeStatus(
            state: "downloading",
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            latest: manifest
        )
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("TraceFenceCoreUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let package = try downloadPackage(from: packageURL, into: workspace)
        let attributes = try fileManager.attributesOfItem(atPath: package.path)
        let packageSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard packageSize > 0, packageSize <= maximumPackageBytes else { throw UpdaterError.packageTooLarge }
        if let expectedSize = manifest.packageSize, expectedSize != packageSize {
            throw UpdaterError.downloadFailed("package_size_mismatch")
        }
        guard try sha256(of: package).caseInsensitiveCompare(manifest.packageSHA256) == .orderedSame else {
            throw UpdaterError.checksumMismatch
        }

        try validateArchive(package)
        let extracted = workspace.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        let extraction = runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", package.path, extracted.path],
            timeout: 60
        )
        guard extraction.status == 0 else { throw UpdaterError.extractionFailed(extraction.output) }

        let bundle = extracted.appendingPathComponent("TraceFenceAgentCore.bundle", isDirectory: true)
        try verifyBundle(bundle, manifest: manifest, packageWasLocal: packageWasLocal)
        writeStatus(
            state: "installing",
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            latest: manifest
        )

        let previous = try stageAndSwitch(bundle: bundle, manifest: manifest)
        restartServices()
        guard waitForHealthyCore(version: manifest.version, timeout: 20) else {
            if let previous {
                try switchCurrent(to: previous)
                restartServices()
                _ = waitForHealthyCore(version: currentVersion, timeout: 20)
            }
            writeStatus(
                state: "rolled_back",
                currentVersion: currentVersion,
                currentBuild: currentBuild,
                latest: manifest,
                error: UpdaterError.healthCheckFailed.localizedDescription
            )
            let failedRelease = installRoot
                .appendingPathComponent("releases", isDirectory: true)
                .appendingPathComponent("\(manifest.version)-\(manifest.build)", isDirectory: true)
            try? fileManager.removeItem(at: failedRelease)
            throw UpdaterError.healthCheckFailed
        }

        writeStatus(
            state: "installed",
            currentVersion: manifest.version,
            currentBuild: manifest.build,
            latest: manifest,
            installedAt: isoFormatter.string(from: Date())
        )
        pruneOldReleases(keeping: 3)
    }

    private func validate(manifest: UpdateManifest) throws {
        guard manifest.schemaVersion == 1 else { throw UpdaterError.invalidManifest("schema") }
        guard manifest.channel == configuration.channel else { throw UpdaterError.invalidManifest("channel") }
        guard manifest.bundleIdentifier == expectedBundleIdentifier else { throw UpdaterError.invalidManifest("bundle_identifier") }
        guard manifest.minimumProtocolVersion <= 1 else { throw UpdaterError.invalidManifest("protocol") }
        guard !manifest.version.isEmpty, manifest.build > 0 else { throw UpdaterError.invalidManifest("version") }
        let checksum = manifest.packageSHA256.lowercased()
        guard checksum.count == 64, checksum.allSatisfy({ $0.isHexDigit }) else {
            throw UpdaterError.invalidManifest("checksum")
        }
    }

    private func resolvedPackageURL(manifest: UpdateManifest, relativeTo manifestURL: URL) throws -> URL {
        guard let result = URL(string: manifest.packageURL, relativeTo: manifestURL)?.absoluteURL else {
            throw UpdaterError.invalidManifest("package_url")
        }
        return result
    }

    private func validateRemoteURL(_ url: URL) throws {
        if url.isFileURL {
            guard configuration.allowLocalPackages == true else { throw UpdaterError.insecureURL }
            return
        }
        guard url.scheme?.lowercased() == "https" else { throw UpdaterError.insecureURL }
    }

    private func loadSmallResource(from url: URL, maximumBytes: Int) throws -> Data {
        if url.isFileURL {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= maximumBytes else { throw UpdaterError.packageTooLarge }
            return data
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = DownloadResultBox()
        let session = secureSession()
        let task = session.downloadTask(with: url) { temporaryURL, response, error in
            var copiedURL: URL?
            if let temporaryURL {
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("TraceFenceManifest-\(UUID().uuidString).json")
                do {
                    try FileManager.default.copyItem(at: temporaryURL, to: destination)
                    copiedURL = destination
                } catch {
                    box.set(url: nil, response: response, error: error)
                    semaphore.signal()
                    return
                }
            }
            box.set(url: copiedURL, response: response, error: error)
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 35) == .success else {
            task.cancel()
            throw UpdaterError.downloadFailed("timeout")
        }
        let (temporaryURL, response, error) = box.value()
        defer { if let temporaryURL { try? fileManager.removeItem(at: temporaryURL) } }
        if let error { throw UpdaterError.downloadFailed(error.localizedDescription) }
        try validateHTTPResponse(response)
        guard let temporaryURL else { throw UpdaterError.downloadFailed("empty_response") }
        let data = try Data(contentsOf: temporaryURL, options: [.mappedIfSafe])
        guard data.count <= maximumBytes else { throw UpdaterError.packageTooLarge }
        return data
    }

    private func downloadPackage(from url: URL, into directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent("TraceFenceAgentCore.zip")
        if url.isFileURL {
            try fileManager.copyItem(at: url, to: destination)
            return destination
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = DownloadResultBox()
        let session = secureSession()
        let task = session.downloadTask(with: url) { temporaryURL, response, error in
            do {
                if let temporaryURL { try FileManager.default.copyItem(at: temporaryURL, to: destination) }
                box.set(url: temporaryURL == nil ? nil : destination, response: response, error: error)
            } catch {
                box.set(url: nil, response: response, error: error)
            }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 300) == .success else {
            task.cancel()
            throw UpdaterError.downloadFailed("timeout")
        }
        let (downloadedURL, response, error) = box.value()
        if let error { throw UpdaterError.downloadFailed(error.localizedDescription) }
        try validateHTTPResponse(response)
        guard let downloadedURL else { throw UpdaterError.downloadFailed("empty_response") }
        return downloadedURL
    }

    private func secureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "TraceFenceAgentCoreUpdater/\(updaterVersion)"]
        if #available(macOS 10.15, *) { configuration.tlsMinimumSupportedProtocolVersion = .TLSv12 }
        return URLSession(configuration: configuration)
    }

    private func validateHTTPResponse(_ response: URLResponse?) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.url?.scheme?.lowercased() == "https" else {
            throw UpdaterError.downloadFailed("invalid_https_response")
        }
    }

    private func validateArchive(_ package: URL) throws {
        let listing = runProcess(executable: "/usr/bin/unzip", arguments: ["-Z1", package.path], timeout: 20)
        guard listing.status == 0 else { throw UpdaterError.unsafeArchive }
        let entries = listing.output.split(whereSeparator: \.isNewline).map(String.init)
        guard !entries.isEmpty else { throw UpdaterError.unsafeArchive }
        for entry in entries {
            let normalized = entry.replacingOccurrences(of: "\\", with: "/")
            let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
            guard !normalized.hasPrefix("/"),
                  normalized.hasPrefix("TraceFenceAgentCore.bundle/"),
                  !components.contains("..") else { throw UpdaterError.unsafeArchive }
        }
    }

    private func verifyBundle(_ bundle: URL, manifest: UpdateManifest, packageWasLocal: Bool) throws {
        let infoURL = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == expectedBundleIdentifier,
              info["CFBundleShortVersionString"] as? String == manifest.version,
              Int(info["CFBundleVersion"] as? String ?? "") == manifest.build else {
            throw UpdaterError.invalidBundle("metadata")
        }

        let requiredExecutables = [
            "Contents/MacOS/TraceFenceAgentCore",
            "Contents/MacOS/TraceFenceAgentCoreUpdater",
            "Contents/Resources/adapters/TraceFenceClaudeAdapter",
            "Contents/Resources/adapters/TraceFenceUniversalAdapter"
        ]
        for relativePath in requiredExecutables {
            let path = bundle.appendingPathComponent(relativePath).path
            guard fileManager.isExecutableFile(atPath: path) else {
                throw UpdaterError.invalidBundle("missing_\((relativePath as NSString).lastPathComponent)")
            }
        }

        let adapterDirectory = bundle.appendingPathComponent("Contents/Resources/adapters", isDirectory: true)
        let manifestURLs = ((try? fileManager.contentsOfDirectory(at: adapterDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
        guard manifestURLs.count >= 18 else { throw UpdaterError.invalidBundle("adapter_catalog") }
        for url in manifestURLs {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String,
                  !id.isEmpty else { throw UpdaterError.invalidBundle("adapter_manifest") }
            if let executable = object["executable"] as? String,
               !["TraceFenceClaudeAdapter", "TraceFenceUniversalAdapter"].contains(executable) {
                throw UpdaterError.invalidBundle("adapter_executable")
            }
        }

        let verification = runProcess(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", "--verbose=2", bundle.path],
            timeout: 30
        )
        guard verification.status == 0 else { throw UpdaterError.signatureInvalid(verification.output) }
        let details = runProcess(
            executable: "/usr/bin/codesign",
            arguments: ["-d", "--verbose=4", bundle.path],
            timeout: 15
        ).output
        let team = lineValue(named: "TeamIdentifier", in: details) ?? "not set"
        if team != configuration.trustedTeamID {
            let localAdHocAllowed = packageWasLocal
                && configuration.allowAdHocForLocalTesting == true
                && details.contains("Signature=adhoc")
            guard localAdHocAllowed else {
                throw UpdaterError.teamMismatch(expected: configuration.trustedTeamID, actual: team)
            }
        }
    }

    private func stageAndSwitch(bundle: URL, manifest: UpdateManifest) throws -> String? {
        try fileManager.createDirectory(at: installRoot, withIntermediateDirectories: true)
        let releases = installRoot.appendingPathComponent("releases", isDirectory: true)
        try fileManager.createDirectory(at: releases, withIntermediateDirectories: true)
        let releaseName = "\(manifest.version)-\(manifest.build)"
        let releaseDirectory = releases.appendingPathComponent(releaseName, isDirectory: true)
        let targetBundle = releaseDirectory.appendingPathComponent("TraceFenceAgentCore.bundle", isDirectory: true)

        if pathExists(releaseDirectory.path) { try fileManager.removeItem(at: releaseDirectory) }
        let temporaryRelease = releases.appendingPathComponent(".installing-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRelease, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(
                at: bundle,
                to: temporaryRelease.appendingPathComponent("TraceFenceAgentCore.bundle", isDirectory: true)
            )
            guard rename(temporaryRelease.path, releaseDirectory.path) == 0 else {
                throw UpdaterError.installFailed(String(cString: strerror(errno)))
            }
        } catch {
            try? fileManager.removeItem(at: temporaryRelease)
            throw error
        }
        guard pathExists(targetBundle.path) else { throw UpdaterError.installFailed("staged_bundle_missing") }

        let current = installRoot.appendingPathComponent("current")
        let previous = try? fileManager.destinationOfSymbolicLink(atPath: current.path)
        try switchCurrent(to: "releases/\(releaseName)/TraceFenceAgentCore.bundle")
        try ensureCompatibilityLink(name: "TraceFenceAgentCore", destination: "current/Contents/MacOS/TraceFenceAgentCore")
        try ensureCompatibilityLink(name: "TraceFenceAgentCoreUpdater", destination: "current/Contents/MacOS/TraceFenceAgentCoreUpdater")
        try ensureCompatibilityLink(name: "adapters", destination: "current/Contents/Resources/adapters")
        return previous
    }

    private func switchCurrent(to destination: String) throws {
        let current = installRoot.appendingPathComponent("current")
        if pathExists(current.path), (try? fileManager.destinationOfSymbolicLink(atPath: current.path)) == nil {
            let legacy = installRoot.appendingPathComponent("legacy-current-\(Int(Date().timeIntervalSince1970))")
            try fileManager.moveItem(at: current, to: legacy)
        }
        let next = installRoot.appendingPathComponent(".current-\(UUID().uuidString)")
        try fileManager.createSymbolicLink(atPath: next.path, withDestinationPath: destination)
        guard rename(next.path, current.path) == 0 else {
            try? fileManager.removeItem(at: next)
            throw UpdaterError.installFailed("current_switch_\(String(cString: strerror(errno)))")
        }
    }

    private func ensureCompatibilityLink(name: String, destination: String) throws {
        let link = installRoot.appendingPathComponent(name)
        if let existing = try? fileManager.destinationOfSymbolicLink(atPath: link.path), existing == destination { return }
        if pathExists(link.path) {
            let legacy = installRoot.appendingPathComponent("legacy-\(name)-\(Int(Date().timeIntervalSince1970))")
            try fileManager.moveItem(at: link, to: legacy)
        }
        let next = installRoot.appendingPathComponent(".\(name)-\(UUID().uuidString)")
        try fileManager.createSymbolicLink(atPath: next.path, withDestinationPath: destination)
        guard rename(next.path, link.path) == 0 else {
            try? fileManager.removeItem(at: next)
            throw UpdaterError.installFailed("compatibility_link_\(name)")
        }
    }

    private func restartServices() {
        let domain = "gui/\(getuid())"
        _ = runProcess(
            executable: "/bin/launchctl",
            arguments: ["kickstart", "-k", "\(domain)/com.tracefence.adapter.claude"],
            timeout: 15
        )
        _ = runProcess(
            executable: "/bin/launchctl",
            arguments: ["kickstart", "-k", "\(domain)/com.tracefence.agent-core"],
            timeout: 15
        )
    }

    private func waitForHealthyCore(version: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if coreHealthVersion() == version { return true }
            usleep(350_000)
        }
        return false
    }

    private func coreHealthVersion() -> String? {
        guard fileManager.fileExists(atPath: socketPath) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = socketPath.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: bytes.count) { destination in
                _ = bytes.withUnsafeBufferPointer { source in
                    memcpy(destination, source.baseAddress, bytes.count)
                }
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }
        var request = Data("{\"id\":\"updater\",\"method\":\"health\",\"params\":{}}\n".utf8)
        guard request.withUnsafeMutableBytes({ raw in
            guard let base = raw.baseAddress else { return false }
            return Darwin.write(fd, base, raw.count) == raw.count
        }) else { return nil }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while response.count < 1_024 * 1_024, !response.contains(0x0A) {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0 else { return nil }
            response.append(contentsOf: buffer.prefix(count))
        }
        guard let newline = response.firstIndex(of: 0x0A),
              let object = try? JSONSerialization.jsonObject(with: response.prefix(upTo: newline)) as? [String: Any],
              object["ok"] as? Bool == true,
              let result = object["result"] as? [String: Any] else { return nil }
        return result["coreVersion"] as? String
    }

    private func pruneOldReleases(keeping count: Int) {
        let releases = installRoot.appendingPathComponent("releases", isDirectory: true)
        guard let values = try? fileManager.contentsOfDirectory(
            at: releases,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let currentDestination = (try? fileManager.destinationOfSymbolicLink(atPath: installRoot.appendingPathComponent("current").path)) ?? ""
        let sorted = values.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        for url in sorted.dropFirst(max(1, count)) where !currentDestination.contains("/\(url.lastPathComponent)/") {
            try? fileManager.removeItem(at: url)
        }
    }

    private func isNewer(manifest: UpdateManifest, thanVersion currentVersion: String, build currentBuild: Int) -> Bool {
        let comparison = compareVersions(manifest.version, currentVersion)
        return comparison == .orderedDescending || (comparison == .orderedSame && manifest.build > currentBuild)
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func lineValue(named name: String, in text: String) -> String? {
        text.split(whereSeparator: \.isNewline).compactMap { raw -> String? in
            let line = String(raw)
            let prefix = name + "="
            guard line.hasPrefix(prefix) else { return nil }
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }.first
    }

    private func pathExists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    private func writeStatus(
        state: String,
        currentVersion: String,
        currentBuild: Int,
        latest: UpdateManifest? = nil,
        installedAt: String? = nil,
        error: String? = nil
    ) {
        let status = UpdateStatus(
            state: state,
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            latestVersion: latest?.version,
            latestBuild: latest?.build,
            checkedAt: isoFormatter.string(from: Date()),
            installedAt: installedAt,
            error: error
        )
        guard let data = try? JSONEncoder().encode(status) else { return }
        try? fileManager.createDirectory(at: installRoot, withIntermediateDirectories: true)
        try? data.write(to: statusURL, options: [.atomic])
        chmod(statusURL.path, S_IRUSR | S_IWUSR)
    }

    private func runProcess(executable: String, arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let outputCapture = ProcessOutputCapture(limit: 4 * 1_024 * 1_024)
        let errorCapture = ProcessOutputCapture(limit: 4 * 1_024 * 1_024)
        let readers = DispatchGroup()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            outputCapture.drain(stdout.fileHandleForReading)
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errorCapture.drain(stderr.fileHandleForReading)
            readers.leave()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                _ = kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        _ = readers.wait(timeout: .now() + 2)
        return (process.terminationStatus, outputCapture.string() + errorCapture.string())
    }
}

private func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

private func printJSON(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { return }
    print(text)
}

if CommandLine.arguments.contains("--version") {
    print(updaterVersion)
    exit(0)
}

guard let command = CommandLine.arguments.dropFirst().first,
      let configPath = argument("--config"),
      let installRootPath = argument("--install-root") else {
    fputs("Usage: TraceFenceAgentCoreUpdater check-and-install --config PATH --install-root PATH --current-version VERSION --current-build BUILD [--force]\n", stderr)
    exit(2)
}

do {
    let configData = try Data(contentsOf: URL(fileURLWithPath: configPath))
    let configuration = try JSONDecoder().decode(UpdateConfiguration.self, from: configData)
    let socketPath = argument("--socket") ?? URL(fileURLWithPath: installRootPath).appendingPathComponent("agent-core.sock").path
    let updater = CoreUpdater(
        configuration: configuration,
        installRoot: URL(fileURLWithPath: installRootPath, isDirectory: true),
        socketPath: socketPath
    )
    switch command {
    case "check-and-install":
        guard let currentVersion = argument("--current-version"),
              let buildText = argument("--current-build"),
              let currentBuild = Int(buildText) else {
            throw UpdaterError.invalidArguments("current_version_or_build")
        }
        let result = try updater.checkAndInstall(
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            forceInstall: CommandLine.arguments.contains("--force")
        )
        printJSON(["ok": true, "result": result])
    case "verify-bundle":
        guard let bundlePath = argument("--bundle"),
              let manifestPath = argument("--manifest") else {
            throw UpdaterError.invalidArguments("bundle_or_manifest")
        }
        let manifest = try JSONDecoder().decode(
            UpdateManifest.self,
            from: Data(contentsOf: URL(fileURLWithPath: manifestPath))
        )
        try updater.verify(
            bundleURL: URL(fileURLWithPath: bundlePath, isDirectory: true),
            manifest: manifest,
            packageWasLocal: true
        )
        printJSON(["ok": true, "result": ["verified": true]])
    default:
        throw UpdaterError.invalidArguments("unknown_command_\(command)")
    }
} catch {
    printJSON(["ok": false, "error": error.localizedDescription])
    exit(1)
}
