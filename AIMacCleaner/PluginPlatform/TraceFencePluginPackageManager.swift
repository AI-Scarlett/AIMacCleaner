import AppKit
import CryptoKit
import Foundation

struct TraceFenceInstalledPluginRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { catalogPluginID }

    let catalogPluginID: String
    let packagePluginID: String
    var activeVersion: String
    var previousVersion: String?
    var enabled: Bool
    var restartRequired: Bool
    var installedAt: Date
    var sourceURL: URL
    var sha256: String
}

struct TraceFencePluginManifest: Codable, Sendable {
    struct Capabilities: Codable, Sendable {
        let primaryPanel: Bool
        let componentPanel: Bool
        let settings: String
    }

    let id: String
    let displayName: String
    let version: String
    let minHostVersion: String
    let pluginKitVersion: Int
    let bundleRelativePath: String
    let factoryClass: String?
    let capabilities: Capabilities
    let permissions: [String]
}

private struct TraceFenceValidatedPluginPackage: Sendable {
    let manifest: TraceFencePluginManifest
    let packageURL: URL
}

@MainActor
final class TraceFencePluginPackageManager: ObservableObject {
    static let shared = TraceFencePluginPackageManager()
    nonisolated static let supportedPluginKitVersion = 4

    @Published private(set) var states: [String: TraceFencePluginInstallationState] = [:]
    @Published private(set) var records: [String: TraceFenceInstalledPluginRecord] = [:]

    private let worker = TraceFencePluginPackageWorker()

    private init() {
        refresh(catalog: TraceFenceMarketplaceCatalogRuntime.activeCatalog)
    }

    func refresh(catalog: TraceFenceMarketplaceCatalog) {
        var loadedRecords: [String: TraceFenceInstalledPluginRecord] = [:]
        for plugin in catalog.plugins where plugin.delivery == .package {
            guard let record = Self.loadRecord(pluginID: plugin.id),
                  Self.installedPackageURL(record: record).map({ FileManager.default.fileExists(atPath: $0.path) }) == true else {
                if !isBusy(states[plugin.id]) {
                    states[plugin.id] = .notInstalled
                }
                continue
            }
            loadedRecords[plugin.id] = record
            if record.activeVersion.compare(plugin.version, options: .numeric) == .orderedAscending {
                states[plugin.id] = .updateAvailable(
                    installedVersion: record.activeVersion,
                    targetVersion: plugin.version,
                    enabled: record.enabled
                )
            } else {
                states[plugin.id] = .installed(
                    version: record.activeVersion,
                    enabled: record.enabled,
                    restartRequired: record.restartRequired
                )
            }
        }
        records = loadedRecords
    }

    func state(for plugin: TraceFencePluginDescriptor) -> TraceFencePluginInstallationState {
        states[plugin.id] ?? .notInstalled
    }

    func record(pluginID: String) -> TraceFenceInstalledPluginRecord? {
        records[pluginID]
    }

    func activePackageURL(pluginID: String) -> URL? {
        records[pluginID].flatMap(Self.installedPackageURL(record:))
    }

    func install(plugin: TraceFencePluginDescriptor) async {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect,
              plugin.delivery == .package,
              plugin.package != nil else {
            states[plugin.id] = .failed(
                message: "This package is unavailable in the current distribution channel.",
                installedVersion: records[plugin.id]?.activeVersion
            )
            return
        }
        guard TraceFenceMarketplaceCatalogRuntime.activeCatalog.isCompatible(
            plugin,
            hostVersion: Self.hostVersion
        ) else {
            states[plugin.id] = .failed(
                message: "This plugin requires a newer TraceFence host.",
                installedVersion: records[plugin.id]?.activeVersion
            )
            return
        }
        switch TraceFencePluginEntitlementService.shared.accessState(pluginID: plugin.id) {
        case .locked:
            states[plugin.id] = .failed(
                message: "A valid plugin entitlement is required before installation.",
                installedVersion: records[plugin.id]?.activeVersion
            )
            return
        case .free, .allAccess, .licensed, .trial:
            break
        }
        guard !isBusy(states[plugin.id]) else { return }

        let previousRecord = records[plugin.id]
        states[plugin.id] = .downloading(targetVersion: plugin.version)
        do {
            let validated = try await worker.downloadAndValidate(plugin: plugin)
            states[plugin.id] = .installing(targetVersion: plugin.version)
            let record = try await worker.install(
                validated,
                plugin: plugin,
                previousRecord: previousRecord
            )
            records[plugin.id] = record
            states[plugin.id] = .installed(
                version: record.activeVersion,
                enabled: record.enabled,
                restartRequired: record.restartRequired
            )
        } catch {
            states[plugin.id] = .failed(
                message: error.localizedDescription,
                installedVersion: previousRecord?.activeVersion
            )
        }
    }

#if DEBUG
    func installLocalPackageForTesting(plugin: TraceFencePluginDescriptor, archiveURL: URL) async {
        let previousRecord = records[plugin.id]
        states[plugin.id] = .installing(targetVersion: plugin.version)
        do {
            let validated = try await worker.validateLocalArchive(archiveURL, plugin: plugin)
            let record = try await worker.install(
                validated,
                plugin: plugin,
                previousRecord: previousRecord
            )
            records[plugin.id] = record
            states[plugin.id] = .installed(
                version: record.activeVersion,
                enabled: record.enabled,
                restartRequired: record.restartRequired
            )
        } catch {
            states[plugin.id] = .failed(
                message: error.localizedDescription,
                installedVersion: previousRecord?.activeVersion
            )
        }
    }
#endif

    func setEnabled(_ enabled: Bool, pluginID: String) {
        guard var record = records[pluginID] else { return }
        record.enabled = enabled
        do {
            try Self.saveRecord(record)
            records[pluginID] = record
            states[pluginID] = .installed(
                version: record.activeVersion,
                enabled: enabled,
                restartRequired: record.restartRequired
            )
        } catch {
            states[pluginID] = .failed(
                message: error.localizedDescription,
                installedVersion: record.activeVersion
            )
        }
    }

    func markRestartRequired(pluginID: String) {
        guard var record = records[pluginID] else { return }
        record.restartRequired = true
        try? Self.saveRecord(record)
        records[pluginID] = record
        states[pluginID] = .installed(
            version: record.activeVersion,
            enabled: record.enabled,
            restartRequired: true
        )
    }

    func rollback(pluginID: String) async {
        guard var record = records[pluginID], let previousVersion = record.previousVersion else { return }
        let previousURL = Self.installedPackageDirectory(pluginID: pluginID, version: previousVersion)
        guard FileManager.default.fileExists(atPath: previousURL.path) else {
            states[pluginID] = .failed(
                message: "The previous known-good plugin version is no longer available.",
                installedVersion: record.activeVersion
            )
            return
        }
        let currentVersion = record.activeVersion
        record.activeVersion = previousVersion
        record.previousVersion = currentVersion
        record.restartRequired = true
        do {
            try Self.saveRecord(record)
            records[pluginID] = record
            states[pluginID] = .installed(
                version: previousVersion,
                enabled: record.enabled,
                restartRequired: true
            )
        } catch {
            states[pluginID] = .failed(
                message: error.localizedDescription,
                installedVersion: currentVersion
            )
        }
    }

    func uninstall(pluginID: String) async {
        guard let record = records[pluginID] else { return }
        do {
            try await worker.uninstall(pluginID: pluginID)
            records.removeValue(forKey: pluginID)
            states[pluginID] = .notInstalled
        } catch {
            states[pluginID] = .failed(
                message: error.localizedDescription,
                installedVersion: record.activeVersion
            )
        }
    }

    func reveal(pluginID: String) {
        guard let url = activePackageURL(pluginID: pluginID),
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func isBusy(_ state: TraceFencePluginInstallationState?) -> Bool {
        switch state {
        case .downloading, .installing: true
        default: false
        }
    }

    nonisolated static var hostVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    nonisolated static var rootDirectory: URL {
#if DEBUG
        if let override = ProcessInfo.processInfo.environment["TRACEFENCE_PLUGIN_ROOT"],
           override.hasPrefix("/") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
#endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support
            .appendingPathComponent("TraceFence", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    nonisolated static var downloadsDirectory: URL {
        rootDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    nonisolated static var stagingDirectory: URL {
        rootDirectory.appendingPathComponent("Staging", isDirectory: true)
    }

    nonisolated static var installedDirectory: URL {
        rootDirectory.appendingPathComponent("Installed", isDirectory: true)
    }

    nonisolated static var stateDirectory: URL {
        rootDirectory.appendingPathComponent("State", isDirectory: true)
    }

    nonisolated static var dataDirectory: URL {
        rootDirectory.appendingPathComponent("Data", isDirectory: true)
    }

    nonisolated static var cachesDirectory: URL {
        rootDirectory.appendingPathComponent("Caches", isDirectory: true)
    }

    nonisolated static var temporaryDirectory: URL {
        rootDirectory.appendingPathComponent("Temporary", isDirectory: true)
    }

    nonisolated static func installedPackageDirectory(pluginID: String, version: String) -> URL {
        installedDirectory
            .appendingPathComponent(pluginID, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathExtension("mactoolsplugin")
    }

    nonisolated static func installedPackageURL(record: TraceFenceInstalledPluginRecord) -> URL? {
        installedPackageDirectory(pluginID: record.catalogPluginID, version: record.activeVersion)
    }

    nonisolated private static func stateURL(pluginID: String) -> URL {
        stateDirectory.appendingPathComponent(pluginID, isDirectory: false).appendingPathExtension("json")
    }

    nonisolated private static func loadRecord(pluginID: String) -> TraceFenceInstalledPluginRecord? {
        guard let data = try? Data(contentsOf: stateURL(pluginID: pluginID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TraceFenceInstalledPluginRecord.self, from: data)
    }

    nonisolated fileprivate static func saveRecord(_ record: TraceFenceInstalledPluginRecord) throws {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: stateURL(pluginID: record.catalogPluginID), options: .atomic)
    }
}

private actor TraceFencePluginPackageWorker {
    private let fileManager = FileManager.default
    private let allowedRedirectHosts = ["github.com", "release-assets.githubusercontent.com"]

    func downloadAndValidate(plugin: TraceFencePluginDescriptor) async throws -> TraceFenceValidatedPluginPackage {
        guard let descriptor = plugin.package else { throw PackageError.missingDescriptor }
        let rawPluginID = try packagePluginID(for: plugin.id)
        let expectedPath = "/AI-Scarlett/TraceFence/releases/download/plugin-\(rawPluginID)-v\(plugin.version)/\(rawPluginID)-\(plugin.version).mactoolsplugin.zip"
        guard descriptor.url.scheme?.lowercased() == "https",
              descriptor.url.host?.lowercased() == "github.com",
              descriptor.url.path == expectedPath,
              descriptor.url.query == nil,
              descriptor.url.fragment == nil else {
            throw PackageError.untrustedSource
        }

        let (downloadedURL, response) = try await URLSession.shared.download(from: descriptor.url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let finalURL = http.url,
              finalURL.scheme?.lowercased() == "https",
              isAllowedFinalHost(finalURL.host) else {
            throw PackageError.invalidResponse
        }

        return try validateArchive(downloadedURL, plugin: plugin, descriptor: descriptor)
    }

#if DEBUG
    func validateLocalArchive(
        _ archiveURL: URL,
        plugin: TraceFencePluginDescriptor
    ) throws -> TraceFenceValidatedPluginPackage {
        guard let descriptor = plugin.package else { throw PackageError.missingDescriptor }
        return try validateArchive(archiveURL, plugin: plugin, descriptor: descriptor)
    }
#endif

    private func validateArchive(
        _ sourceArchive: URL,
        plugin: TraceFencePluginDescriptor,
        descriptor: TraceFencePluginPackageDescriptor
    ) throws -> TraceFenceValidatedPluginPackage {
        let transactionDirectory = TraceFencePluginPackageManager.stagingDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: transactionDirectory, withIntermediateDirectories: true)
        do {
            let stagedArchive = transactionDirectory.appendingPathComponent("package.zip", isDirectory: false)
            try fileManager.copyItem(at: sourceArchive, to: stagedArchive)
            let size = try fileManager.attributesOfItem(atPath: stagedArchive.path)[.size] as? NSNumber
            guard size?.int64Value == descriptor.sizeBytes else { throw PackageError.sizeMismatch }
            guard try digest(of: stagedArchive) == descriptor.sha256 else { throw PackageError.digestMismatch }

            try validateArchivePaths(stagedArchive)
            let expanded = transactionDirectory.appendingPathComponent("Expanded", isDirectory: true)
            try fileManager.createDirectory(at: expanded, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", arguments: ["-x", "-k", stagedArchive.path, expanded.path])
            let packageURL = try singlePackage(in: expanded)
            try validateNoSymbolicLinks(in: packageURL)
            let manifest = try validatePackage(packageURL, plugin: plugin, descriptor: descriptor)

            let retained = TraceFencePluginPackageManager.stagingDirectory
                .appendingPathComponent("validated-\(UUID().uuidString)", isDirectory: true)
                .appendingPathExtension("mactoolsplugin")
            try fileManager.moveItem(at: packageURL, to: retained)
            try fileManager.removeItem(at: transactionDirectory)
            return TraceFenceValidatedPluginPackage(manifest: manifest, packageURL: retained)
        } catch {
            try? fileManager.removeItem(at: transactionDirectory)
            throw error
        }
    }

    func install(
        _ validated: TraceFenceValidatedPluginPackage,
        plugin: TraceFencePluginDescriptor,
        previousRecord: TraceFenceInstalledPluginRecord?
    ) throws -> TraceFenceInstalledPluginRecord {
        defer { try? fileManager.removeItem(at: validated.packageURL) }
        let pluginRoot = TraceFencePluginPackageManager.installedDirectory
            .appendingPathComponent(plugin.id, isDirectory: true)
        try fileManager.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let destination = TraceFencePluginPackageManager.installedPackageDirectory(
            pluginID: plugin.id,
            version: plugin.version
        )
        let pending = pluginRoot
            .appendingPathComponent(".\(UUID().uuidString).pending", isDirectory: true)
            .appendingPathExtension("mactoolsplugin")
        try fileManager.copyItem(at: validated.packageURL, to: pending)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: pending)
        } else {
            try fileManager.moveItem(at: pending, to: destination)
        }

        let record = TraceFenceInstalledPluginRecord(
            catalogPluginID: plugin.id,
            packagePluginID: validated.manifest.id,
            activeVersion: plugin.version,
            previousVersion: previousRecord?.activeVersion == plugin.version ? previousRecord?.previousVersion : previousRecord?.activeVersion,
            enabled: previousRecord?.enabled ?? true,
            restartRequired: previousRecord != nil,
            installedAt: Date(),
            sourceURL: plugin.package!.url,
            sha256: plugin.package!.sha256
        )
        try TraceFencePluginPackageManager.saveRecord(record)
        pruneVersions(for: record)
        return record
    }

    func uninstall(pluginID: String) throws {
        let packageRoot = TraceFencePluginPackageManager.installedDirectory
            .appendingPathComponent(pluginID, isDirectory: true)
        let stateURL = TraceFencePluginPackageManager.stateDirectory
            .appendingPathComponent(pluginID, isDirectory: false)
            .appendingPathExtension("json")
        if fileManager.fileExists(atPath: packageRoot.path) {
            try fileManager.removeItem(at: packageRoot)
        }
        if fileManager.fileExists(atPath: stateURL.path) {
            try fileManager.removeItem(at: stateURL)
        }
    }

    private func pruneVersions(for record: TraceFenceInstalledPluginRecord) {
        let root = TraceFencePluginPackageManager.installedDirectory
            .appendingPathComponent(record.catalogPluginID, isDirectory: true)
        let keep = Set([record.activeVersion, record.previousVersion].compactMap { $0 })
        guard let values = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for value in values where value.pathExtension == "mactoolsplugin" {
            let version = value.deletingPathExtension().lastPathComponent
            if !keep.contains(version) { try? fileManager.removeItem(at: value) }
        }
    }

    private func validatePackage(
        _ packageURL: URL,
        plugin: TraceFencePluginDescriptor,
        descriptor: TraceFencePluginPackageDescriptor
    ) throws -> TraceFencePluginManifest {
        let manifestData = try Data(contentsOf: packageURL.appendingPathComponent("plugin.json"))
        let manifest = try JSONDecoder().decode(TraceFencePluginManifest.self, from: manifestData)
        let expectedPackageID = try packagePluginID(for: plugin.id)
        guard manifest.id == expectedPackageID,
              manifest.version == plugin.version,
              manifest.bundleRelativePath == descriptor.entryPoint,
              manifest.pluginKitVersion == plugin.pluginKitVersion,
              manifest.pluginKitVersion == TraceFencePluginPackageManager.supportedPluginKitVersion,
              Set(manifest.permissions) == Set(plugin.permissions),
              Self.isVersion(TraceFencePluginPackageManager.hostVersion, atLeast: plugin.minimumHostVersion) else {
            throw PackageError.identityMismatch
        }
        let bundleURL = packageURL.appendingPathComponent(manifest.bundleRelativePath, isDirectory: true)
        guard fileManager.fileExists(atPath: bundleURL.path) else { throw PackageError.identityMismatch }
        try validateSystemCompatibility(bundleURL, expectedMinimum: plugin.minimumSystemVersion)
        _ = try run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", "--verbose=2", bundleURL.path])
        let details = try run("/usr/bin/codesign", arguments: ["-d", "--verbose=4", bundleURL.path]).combinedOutput
        var fields: [String: String] = [:]
        for line in details.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2, ["Identifier", "TeamIdentifier"].contains(pair[0]) { fields[pair[0]] = pair[1] }
        }
        guard fields["Identifier"] == descriptor.bundleIdentifier,
              fields["TeamIdentifier"] == descriptor.teamIdentifier else {
            throw PackageError.invalidSignature
        }
        return manifest
    }

    private func validateSystemCompatibility(_ bundleURL: URL, expectedMinimum: String) throws {
        guard let bundle = Bundle(url: bundleURL),
              let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String else {
            throw PackageError.identityMismatch
        }
        guard minimum == expectedMinimum else { throw PackageError.identityMismatch }
        guard Self.isVersion(ProcessInfo.processInfo.operatingSystemVersionString.numericVersion, atLeast: minimum) else {
            throw PackageError.incompatibleSystem(minimum)
        }
    }

    private static func isVersion(_ current: String, atLeast required: String) -> Bool {
        current.compare(required, options: .numeric) != .orderedAscending
    }

    private func packagePluginID(for catalogPluginID: String) throws -> String {
        let prefix = "tracefence.tools."
        guard catalogPluginID.hasPrefix(prefix) else { throw PackageError.identityMismatch }
        return String(catalogPluginID.dropFirst(prefix.count))
    }

    private func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func validateArchivePaths(_ archive: URL) throws {
        let listing = try run("/usr/bin/unzip", arguments: ["-Z1", archive.path]).output
        let paths = listing.split(whereSeparator: \.isNewline).map(String.init)
        guard !paths.isEmpty else { throw PackageError.invalidArchive }
        for path in paths {
            if path.hasPrefix("/") || NSString(string: path).pathComponents.contains("..") || path.contains("\0") {
                throw PackageError.invalidArchive
            }
        }
    }

    private func singlePackage(in directory: URL) throws -> URL {
        let values = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let packages = values.filter { $0.pathExtension == "mactoolsplugin" }
        guard packages.count == 1 else { throw PackageError.invalidArchive }
        return packages[0]
    }

    private func validateNoSymbolicLinks(in packageURL: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        ) else { throw PackageError.invalidArchive }
        for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw PackageError.invalidArchive
        }
    }

    private func isAllowedFinalHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return allowedRedirectHosts.contains(host) || host.hasSuffix(".githubusercontent.com")
    }

    @discardableResult
    private func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw PackageError.commandFailed(error.isEmpty ? output : error)
        }
        return CommandResult(output: output, error: error)
    }

    private struct CommandResult {
        let output: String
        let error: String
        var combinedOutput: String { output + "\n" + error }
    }

    private enum PackageError: LocalizedError {
        case missingDescriptor
        case untrustedSource
        case invalidResponse
        case sizeMismatch
        case digestMismatch
        case invalidArchive
        case identityMismatch
        case invalidSignature
        case incompatibleSystem(String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingDescriptor: "The signed catalog does not contain a package descriptor."
            case .untrustedSource: "The package source is not the expected immutable TraceFence plugin release."
            case .invalidResponse: "The package download returned an invalid response."
            case .sizeMismatch: "The downloaded size does not match the signed catalog."
            case .digestMismatch: "The downloaded SHA-256 does not match the signed catalog."
            case .invalidArchive: "The plugin archive has an unsafe or invalid layout."
            case .identityMismatch: "The plugin manifest does not match the signed catalog or supported PluginKit ABI."
            case .invalidSignature: "The plugin signature is invalid or belongs to another developer."
            case let .incompatibleSystem(version): "This plugin requires macOS \(version) or later."
            case let .commandFailed(message): message.isEmpty ? "Plugin package validation failed." : message
            }
        }
    }
}

private extension String {
    var numericVersion: String {
        let pattern = #"[0-9]+(?:\.[0-9]+){1,2}"#
        guard let range = range(of: pattern, options: .regularExpression) else { return "0.0.0" }
        return String(self[range])
    }
}
