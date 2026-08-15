import CryptoKit
import Darwin
import Foundation

enum CodexMediaRepairExecutionMode: Sendable {
    case inProcess
    case isolated(workerExecutable: URL)
}

struct CodexMediaRepairEngine: Sendable {
    private struct TransformState: Equatable {
        var staleReplacements = 0
        var effectiveRestorations = 0
        var createdMediaObjects = 0
        var reboundLocalPaths = 0
        var reclaimedBytes: Int64 = 0

        var changed: Bool {
            staleReplacements > 0 || effectiveRestorations > 0 || reboundLocalPaths > 0
        }
    }

    private struct PreparedFile {
        let temporaryURL: URL
        let originalSHA256: String
        let repairedSHA256: String
        let originalMode: Int16
        let state: TransformState
    }

    let processMonitor: any CodexProcessMonitoring
    let executionMode: CodexMediaRepairExecutionMode

    init(
        processMonitor: any CodexProcessMonitoring = CodexProcessMonitor(),
        executionMode: CodexMediaRepairExecutionMode = .inProcess
    ) {
        self.processMonitor = processMonitor
        self.executionMode = executionMode
    }

    func perform(
        _ operation: CodexMediaOperation,
        configuration: CodexMediaCleanupConfiguration,
        progress: @Sendable (CodexMediaProgress) -> Void = { _ in }
    ) async throws -> CodexMediaRepairReport {
        if processMonitor.isCodexRunning() {
            try await processMonitor.waitUntilCodexStops()
        }

        try removeAbandonedTemporaryFiles(configuration: configuration)
        let files = try CodexSessionDiscovery.sessionFiles(configuration: configuration)
        let runID = Self.runID()
        let startedAt = Date()
        let runBackupRoot = configuration.backupRoot.appendingPathComponent(runID, isDirectory: true)
        let runReportRoot = configuration.reportRoot.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: runBackupRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: runReportRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var results: [CodexMediaRepairReport.FileResult] = []
        var skipped: [String] = []
        let checkpointURL = runReportRoot.appendingPathComponent("\(operation.rawValue)-progress.json")
        for (index, file) in files.enumerated() {
            if Task.isCancelled { throw CodexMediaCleanupError.cancelled }
            progress(.init(completed: index, total: files.count, currentPath: file.path))
            do {
                if processMonitor.isCodexRunning() {
                    try await processMonitor.waitUntilCodexStops()
                }
                if processMonitor.fileHasOpenHandle(file) {
                    throw CodexMediaCleanupError.fileIsOpen(file.path)
                }
                let result: CodexMediaRepairReport.FileResult?
                switch executionMode {
                case .inProcess:
                    result = try autoreleasepool {
                        try repairFile(
                            file,
                            operation: operation,
                            configuration: configuration,
                            backupRoot: runBackupRoot
                        )
                    }
                case let .isolated(workerExecutable):
                    result = try repairFileUsingWorker(
                        workerExecutable: workerExecutable,
                        file: file,
                        operation: operation,
                        configuration: configuration,
                        backupRoot: runBackupRoot
                    )
                }
                if let result { results.append(result) }
            } catch CodexMediaCleanupError.cancelled {
                throw CodexMediaCleanupError.cancelled
            } catch {
                skipped.append("\(file.path): \(error.localizedDescription)")
            }
            _ = malloc_zone_pressure_relief(nil, 0)
            try writeReport(
                operation: operation,
                runID: runID,
                startedAt: startedAt,
                results: results,
                skipped: skipped,
                reportURL: checkpointURL
            )
        }

        let reportURL = runReportRoot.appendingPathComponent("\(operation.rawValue)-report.json")
        let report = try writeReport(
            operation: operation,
            runID: runID,
            startedAt: startedAt,
            results: results,
            skipped: skipped,
            reportURL: reportURL
        )
        try? FileManager.default.removeItem(at: checkpointURL)
        progress(.init(completed: files.count, total: files.count, currentPath: ""))
        return report
    }

    func repairFile(
        _ file: URL,
        operation: CodexMediaOperation,
        configuration: CodexMediaCleanupConfiguration,
        backupRoot: URL
    ) throws -> CodexMediaRepairReport.FileResult? {
        let prepared = try prepare(
            file: file,
            mediaRoot: configuration.mediaRoot,
            operation: operation
        )
        guard prepared.state.changed else {
            try? FileManager.default.removeItem(at: prepared.temporaryURL)
            return nil
        }
        defer { try? FileManager.default.removeItem(at: prepared.temporaryURL) }

        if processMonitor.isCodexRunning() || processMonitor.fileHasOpenHandle(file) {
            throw CodexMediaCleanupError.fileIsOpen(file.path)
        }

        let relative = relativePath(of: file, under: configuration.codexHome)
        let backup = backupRoot.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: backup.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try cloneOrCopy(file, to: backup)
        guard try sha256File(backup) == prepared.originalSHA256 else {
            throw CodexMediaCleanupError.backupVerificationFailed(backup.path)
        }

        do {
            try atomicReplace(prepared.temporaryURL, destination: file, mode: prepared.originalMode)
            let invalidEffectiveURLs = try verifyEffectiveHistory(file, mediaRoot: configuration.mediaRoot)
            guard try sha256File(file) == prepared.repairedSHA256,
                  (!operation.performsRepair || invalidEffectiveURLs == 0) else {
                throw CodexMediaCleanupError.outputVerificationFailed(file.path)
            }
        } catch {
            try? restoreBackup(backup, destination: file, mode: prepared.originalMode)
            throw error
        }

        return .init(
            path: file.path,
            backupPath: backup.path,
            originalSHA256: prepared.originalSHA256,
            repairedSHA256: prepared.repairedSHA256,
            replacedStaleDataURLs: prepared.state.staleReplacements,
            restoredEffectiveImageURLs: prepared.state.effectiveRestorations,
            createdMediaObjects: prepared.state.createdMediaObjects,
            reboundLocalPaths: prepared.state.reboundLocalPaths,
            reclaimedBytes: prepared.state.reclaimedBytes
        )
    }

    private func prepare(
        file: URL,
        mediaRoot: URL,
        operation: CodexMediaOperation
    ) throws -> PreparedFile {
        let layout = try CodexJSONL.layout(of: file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.int16Value ?? 0o600
        let originalSHA256 = try sha256File(file)
        let temporary = file.deletingLastPathComponent()
            .appendingPathComponent(".\(file.lastPathComponent).\(UUID().uuidString).tracefence.tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw CodexMediaCleanupError.atomicReplaceFailed(file.path)
        }

        var state = TransformState()
        var pendingReferencePaths: [String: String] = [:]
        do {
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? output.close() }
            try CodexJSONL.forEachLine(at: file) { lineNumber, rawData in
                if Task.isCancelled { throw CodexMediaCleanupError.cancelled }
                let record = try CodexJSONL.decodeRecord(rawData, path: file.path, line: lineNumber)
                let transformed = try transformRecord(
                    record,
                    lineNumber: lineNumber,
                    layout: layout,
                    mediaRoot: mediaRoot,
                    operation: operation,
                    pendingReferencePaths: &pendingReferencePaths,
                    state: &state
                )
                if transformed.changed {
                    try output.write(contentsOf: CodexJSONL.encodeRecord(transformed.record))
                } else {
                    var normalized = rawData
                    if normalized.last != 0x0A { normalized.append(0x0A) }
                    try output.write(contentsOf: normalized)
                }
            }
            try output.synchronize()
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: temporary.path)

            let outputLayout = try CodexJSONL.layout(of: temporary)
            guard outputLayout.lineCount == layout.lineCount else {
                throw CodexMediaCleanupError.outputVerificationFailed(file.path)
            }
            let repairedSHA256 = try sha256File(temporary)
            return PreparedFile(
                temporaryURL: temporary,
                originalSHA256: originalSHA256,
                repairedSHA256: repairedSHA256,
                originalMode: mode,
                state: state
            )
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func transformRecord(
        _ record: [String: Any],
        lineNumber: Int,
        layout: CodexJSONL.Layout,
        mediaRoot: URL,
        operation: CodexMediaOperation,
        pendingReferencePaths: inout [String: String],
        state: inout TransformState
    ) throws -> (record: [String: Any], changed: Bool) {
        var output = record
        let before = state
        let type = record["type"] as? String
        let lineReferencePaths = try collectReferencePaths(
            in: record,
            mediaRoot: mediaRoot,
            state: &state
        )
        if type != "event_msg", !lineReferencePaths.isEmpty {
            output = rewriteGeneratedPaths(
                output,
                replacements: lineReferencePaths,
                state: &state
            ) as? [String: Any] ?? output
        }
        if type == "response_item", !lineReferencePaths.isEmpty {
            pendingReferencePaths = lineReferencePaths
        } else if type == "event_msg",
                  let payload = record["payload"] as? [String: Any],
                  payload["type"] as? String == "user_message" {
            var replacements = pendingReferencePaths
            replacements.merge(lineReferencePaths) { _, new in new }
            output = rewriteUserEventPaths(output, replacements: replacements, state: &state)
            pendingReferencePaths.removeAll(keepingCapacity: true)
        }

        if lineNumber == layout.lastCompactionLine,
           type == "compacted",
           var payload = output["payload"] as? [String: Any],
           let history = payload["replacement_history"] {
            payload["replacement_history"] = try transformValue(
                history,
                isEffective: true,
                mediaRoot: mediaRoot,
                operation: operation,
                state: &state
            )
            output["payload"] = payload
        } else if type == "response_item",
                  layout.lastCompactionLine == nil || lineNumber > layout.lastCompactionLine!,
                  let payload = output["payload"] {
            output["payload"] = try transformValue(
                payload,
                isEffective: true,
                mediaRoot: mediaRoot,
                operation: operation,
                state: &state
            )
        } else {
            output = try transformValue(
                output,
                isEffective: false,
                mediaRoot: mediaRoot,
                operation: operation,
                state: &state
            ) as? [String: Any] ?? output
        }
        return (output, before != state)
    }

    private func collectReferencePaths(
        in value: Any,
        mediaRoot: URL,
        state: inout TransformState
    ) throws -> [String: String] {
        var replacements: [String: String] = [:]
        try collectReferencePaths(
            in: value,
            mediaRoot: mediaRoot,
            replacements: &replacements,
            state: &state
        )
        return replacements
    }

    private func collectReferencePaths(
        in value: Any,
        mediaRoot: URL,
        replacements: inout [String: String],
        state: inout TransformState
    ) throws {
        if let array = value as? [Any] {
            for item in array {
                try collectReferencePaths(
                    in: item,
                    mediaRoot: mediaRoot,
                    replacements: &replacements,
                    state: &state
                )
            }
            return
        }
        guard let dictionary = value as? [String: Any] else { return }

        if let content = dictionary["content"] as? [[String: Any]] {
            for (index, item) in content.enumerated()
            where item["type"] as? String == "input_image" {
                guard let rawURL = item["image_url"] as? String,
                      let canonical = try canonicalReference(
                        rawURL,
                        mediaRoot: mediaRoot,
                        ensureObject: false,
                        state: &state
                      ) else { continue }
                var oldPaths = Set<String>()
                for candidateIndex in max(0, index - 3)..<index {
                    guard content[candidateIndex]["type"] as? String == "input_text",
                          let text = content[candidateIndex]["text"] as? String else { continue }
                    oldPaths.formUnion(imageWrapperPaths(in: text))
                }
                if !oldPaths.isEmpty {
                    _ = try canonicalReference(
                        rawURL,
                        mediaRoot: mediaRoot,
                        ensureObject: true,
                        state: &state
                    )
                    for oldPath in oldPaths { replacements[oldPath] = canonical.path }
                }
            }
        }

        if let images = dictionary["images"] as? [String],
           let localImages = dictionary["local_images"] as? [String],
           images.count == localImages.count {
            for (rawURL, oldPath) in zip(images, localImages) {
                guard let canonical = try canonicalReference(
                    rawURL,
                    mediaRoot: mediaRoot,
                    ensureObject: true,
                    state: &state
                ) else { continue }
                replacements[oldPath] = canonical.path
            }
        }

        for item in dictionary.values {
            try collectReferencePaths(
                in: item,
                mediaRoot: mediaRoot,
                replacements: &replacements,
                state: &state
            )
        }
    }

    private func canonicalReference(
        _ rawURL: String,
        mediaRoot: URL,
        ensureObject: Bool,
        state: inout TransformState
    ) throws -> URL? {
        if let image = try CodexDataImage.parse(rawURL) {
            if ensureObject {
                let stored = try CodexMediaObjectStore.ensureObject(for: image, mediaRoot: mediaRoot)
                if stored.created { state.createdMediaObjects += 1 }
                return stored.url
            }
            return CodexMediaObjectStore.canonicalURL(for: image, mediaRoot: mediaRoot)
        }
        guard rawURL.hasPrefix("file://"), let url = URL(string: rawURL) else { return nil }
        _ = try CodexDataImage.fromCanonicalFile(url, mediaRoot: mediaRoot)
        return url.standardizedFileURL
    }

    private func imageWrapperPaths(in text: String) -> Set<String> {
        guard let expression = try? NSRegularExpression(
            pattern: #"<image\b[^>\n]*\bpath=([\"'])(.*?)\1"#
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(expression.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 2), in: text) else { return nil }
            return String(text[valueRange])
        })
    }

    private func rewriteGeneratedPaths(
        _ value: Any,
        replacements: [String: String],
        state: inout TransformState
    ) -> Any {
        if let string = value as? String {
            var output = string
            for (oldPath, newPath) in replacements {
                output = output.replacingOccurrences(of: oldPath, with: newPath)
            }
            if output != string { state.reboundLocalPaths += 1 }
            return output
        }
        if let array = value as? [Any] {
            return array.map { rewriteGeneratedPaths($0, replacements: replacements, state: &state) }
        }
        guard var dictionary = value as? [String: Any] else { return value }
        for (key, item) in dictionary {
            // image_url itself is handled by the compatibility/dedup transform.
            if key == "image_url" { continue }
            dictionary[key] = rewriteGeneratedPaths(item, replacements: replacements, state: &state)
        }
        return dictionary
    }

    private func rewriteUserEventPaths(
        _ record: [String: Any],
        replacements: [String: String],
        state: inout TransformState
    ) -> [String: Any] {
        guard !replacements.isEmpty, var payload = record["payload"] as? [String: Any] else {
            return record
        }
        var output = record
        if let message = payload["message"] as? String {
            let rewritten = rewriteGeneratedPaths(message, replacements: replacements, state: &state)
            payload["message"] = rewritten
        }
        if let localImages = payload["local_images"] as? [String] {
            let rewritten = localImages.map { replacements[$0] ?? $0 }
            state.reboundLocalPaths += zip(localImages, rewritten).filter { $0.0 != $0.1 }.count
            payload["local_images"] = rewritten
        }
        output["payload"] = payload
        return output
    }

    private func transformValue(
        _ value: Any,
        isEffective: Bool,
        mediaRoot: URL,
        operation: CodexMediaOperation,
        state: inout TransformState
    ) throws -> Any {
        if let string = value as? String {
            guard let image = try CodexDataImage.parse(string) else { return string }
            if isEffective || !operation.performsCleanup { return string }
            let stored = try CodexMediaObjectStore.ensureObject(for: image, mediaRoot: mediaRoot)
            if stored.created { state.createdMediaObjects += 1 }
            state.staleReplacements += 1
            let reference = stored.url.absoluteString
            state.reclaimedBytes += Int64(max(0, image.originalCharacterCount - reference.utf8.count))
            return reference
        }
        if let array = value as? [Any] {
            return try array.map {
                try transformValue(
                    $0,
                    isEffective: isEffective,
                    mediaRoot: mediaRoot,
                    operation: operation,
                    state: &state
                )
            }
        }
        guard var dictionary = value as? [String: Any] else { return value }

        var handledImageURL = false
        if operation.performsRepair,
           isEffective,
           dictionary["type"] as? String == "input_image",
           let rawURL = dictionary["image_url"] as? String,
           rawURL.hasPrefix("file://") {
            guard let url = URL(string: rawURL) else {
                throw CodexMediaCleanupError.unsafeMediaReference(rawURL)
            }
            let image = try CodexDataImage.fromCanonicalFile(url, mediaRoot: mediaRoot)
            dictionary["image_url"] = image.dataURL
            state.effectiveRestorations += 1
            handledImageURL = true
        }

        for (key, item) in dictionary {
            if handledImageURL && key == "image_url" { continue }
            dictionary[key] = try transformValue(
                item,
                isEffective: isEffective,
                mediaRoot: mediaRoot,
                operation: operation,
                state: &state
            )
        }
        return dictionary
    }

    private func verifyEffectiveHistory(_ file: URL, mediaRoot: URL) throws -> Int {
        let layout = try CodexJSONL.layout(of: file)
        var invalid = 0
        try CodexJSONL.forEachLine(at: file) { lineNumber, data in
            if lineNumber == layout.lastCompactionLine {
                guard data.range(of: Data("\"compacted\"".utf8)) != nil else { return }
            } else {
                guard layout.lastCompactionLine == nil || lineNumber > layout.lastCompactionLine!,
                      data.range(of: Data("\"response_item\"".utf8)) != nil else { return }
            }
            let record = try CodexJSONL.decodeRecord(data, path: file.path, line: lineNumber)
            guard let root = CodexJSONL.effectiveRoot(in: record, lineNumber: lineNumber, layout: layout) else {
                return
            }
            countInvalidEffectiveURLs(root, invalid: &invalid)
        }
        return invalid
    }

    private func countInvalidEffectiveURLs(_ value: Any, invalid: inout Int) {
        if let array = value as? [Any] {
            for item in array { countInvalidEffectiveURLs(item, invalid: &invalid) }
            return
        }
        guard let dictionary = value as? [String: Any] else { return }
        if dictionary["type"] as? String == "input_image",
           let imageURL = dictionary["image_url"] as? String,
           imageURL.hasPrefix("file://") {
            invalid += 1
        }
        for item in dictionary.values { countInvalidEffectiveURLs(item, invalid: &invalid) }
    }

    private func relativePath(of file: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return file.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func cloneOrCopy(_ source: URL, to destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                clonefile(sourcePath, destinationPath, 0)
            }
        }
        if result != 0 {
            try FileManager.default.copyItem(at: source, to: destination)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    private func restoreBackup(_ backup: URL, destination: URL, mode: Int16) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).restore.\(UUID().uuidString).tmp")
        try cloneOrCopy(backup, to: temporary)
        try atomicReplace(temporary, destination: destination, mode: mode)
    }

    private func atomicReplace(_ source: URL, destination: URL, mode: Int16) throws {
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: source.path)
        let status = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard status == 0 else { throw CodexMediaCleanupError.atomicReplaceFailed(destination.path) }
        let directoryFD = open(destination.deletingLastPathComponent().path, O_RDONLY)
        if directoryFD >= 0 {
            _ = fsync(directoryFD)
            close(directoryFD)
        }
    }

    private func sha256File(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func repairFileUsingWorker(
        workerExecutable: URL,
        file: URL,
        operation: CodexMediaOperation,
        configuration: CodexMediaCleanupConfiguration,
        backupRoot: URL
    ) throws -> CodexMediaRepairReport.FileResult? {
        let worker = workerExecutable.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: worker.path) else {
            throw CodexMediaCleanupError.workerUnavailable(worker.path)
        }

        let process = Process()
        process.executableURL = worker
        process.arguments = [
            "--file", file.path,
            "--operation", operation.rawValue,
            "--codex-home", configuration.codexHome.path,
            "--support-directory", configuration.supportDirectory.path,
            "--backup-root", backupRoot.path
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        var cancellationStartedAt: Date?
        while process.isRunning {
            if Task.isCancelled {
                if cancellationStartedAt == nil {
                    cancellationStartedAt = Date()
                    process.terminate()
                } else if Date().timeIntervalSince(cancellationStartedAt!) > 2 {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        if Task.isCancelled { throw CodexMediaCleanupError.cancelled }

        let response = try? JSONDecoder().decode(CodexMediaWorkerResponse.self, from: outputData)
        if process.terminationStatus == 0,
           let response,
           response.error == nil {
            return response.result
        }

        let detail: String
        if let responseError = response?.error, !responseError.isEmpty {
            detail = responseError
        } else if process.terminationReason == .uncaughtSignal {
            detail = "signal \(process.terminationStatus)"
        } else if let stderrText = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
                  !stderrText.isEmpty {
            detail = String(stderrText.prefix(1_000))
        } else {
            detail = "exit \(process.terminationStatus)"
        }
        throw CodexMediaCleanupError.workerFailed(path: file.path, detail: detail)
    }

    @discardableResult
    private func writeReport(
        operation: CodexMediaOperation,
        runID: String,
        startedAt: Date,
        results: [CodexMediaRepairReport.FileResult],
        skipped: [String],
        reportURL: URL
    ) throws -> CodexMediaRepairReport {
        let report = CodexMediaRepairReport(
            runID: runID,
            operation: operation,
            startedAt: startedAt,
            completedAt: Date(),
            files: results,
            skippedFiles: skipped,
            reportPath: reportURL.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var encoded = try encoder.encode(report)
        encoded.append(0x0A)
        try encoded.write(to: reportURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)
        return report
    }

    private func removeAbandonedTemporaryFiles(
        configuration: CodexMediaCleanupConfiguration,
        now: Date = Date()
    ) throws {
        for root in configuration.sessionRoots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.lastPathComponent.hasPrefix("."),
                      url.lastPathComponent.hasSuffix(".tracefence.tmp") else { continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard values?.isRegularFile == true,
                      let modified = values?.contentModificationDate,
                      now.timeIntervalSince(modified) >= 60 else { continue }
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func runID() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
    }
}
