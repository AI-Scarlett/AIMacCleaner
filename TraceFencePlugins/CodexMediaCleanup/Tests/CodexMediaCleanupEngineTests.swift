import CryptoKit
import Foundation
import XCTest
import MacToolsPluginKit
@testable import CodexMediaCleanupPlugin

final class CodexMediaCleanupEngineTests: XCTestCase {
    private var root: URL!
    private var codexHome: URL!
    private var support: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexMediaCleanupTests-\(UUID().uuidString)", isDirectory: true)
        codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(
            at: codexHome.appendingPathComponent("sessions/2026/08/14", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        codexHome = nil
        support = nil
        super.tearDown()
    }

    func testScanAndRepairPreserveEffectiveBase64AndExternalizeOnlyStaleCopies() async throws {
        let imageBytes = Data("synthetic-image-content".utf8)
        let dataURL = "data:image/png;base64,\(imageBytes.base64EncodedString())"
        let image = try XCTUnwrap(try CodexDataImage.parse(dataURL))
        let mediaRoot = codexHome.appendingPathComponent("media_objects/sha256", isDirectory: true)
        let stored = try CodexMediaObjectStore.ensureObject(for: image, mediaRoot: mediaRoot)
        let fileURL = stored.url.absoluteString

        let session = codexHome.appendingPathComponent(
            "sessions/2026/08/14/rollout-test.jsonl"
        )
        let records: [[String: Any]] = [
            responseItem(imageURL: dataURL),
            [
                "type": "compacted",
                "payload": ["replacement_history": [[
                    "type": "message",
                    "content": [["type": "input_image", "image_url": fileURL]]
                ]]]
            ],
            responseItem(imageURL: fileURL),
            [
                "type": "event_msg",
                "payload": [
                    "type": "user_message",
                    "images": [dataURL],
                    "local_images": ["/tmp/original.png"],
                    "message": #"<image path="/tmp/original.png">"#
                ]
            ]
        ]
        try writeJSONL(records, to: session)
        let original = try Data(contentsOf: session)

        let configuration = CodexMediaCleanupConfiguration(
            codexHome: codexHome,
            supportDirectory: support,
            includeArchivedSessions: true
        )
        let before = try CodexMediaScanEngine().scan(configuration: configuration)
        XCTAssertEqual(before.scannedFiles, 1)
        XCTAssertEqual(before.affectedFiles, 1)
        XCTAssertEqual(before.reclaimableOccurrences, 2)
        XCTAssertEqual(before.invalidEffectiveFileURLs, 2)
        XCTAssertTrue(before.needsWork)

        let engine = CodexMediaRepairEngine(processMonitor: AlwaysStoppedProcessMonitor())
        let repair = try await engine.perform(.cleanupAndRepair, configuration: configuration)
        XCTAssertEqual(repair.operation, .cleanupAndRepair)
        XCTAssertEqual(repair.repairedFileCount, 1)
        XCTAssertEqual(repair.replacementCount, 2)
        XCTAssertEqual(repair.restorationCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repair.files[0].backupPath))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: repair.files[0].backupPath)), original)

        let repaired = try readJSONL(session)
        XCTAssertEqual(imageURL(in: repaired[0]), fileURL, "superseded response item should use canonical file")
        XCTAssertEqual(imageURLInCompaction(repaired[1]), dataURL, "effective compacted history must remain API-compatible")
        XCTAssertEqual(imageURL(in: repaired[2]), dataURL, "post-compaction response item must remain API-compatible")
        let eventImages = ((repaired[3]["payload"] as? [String: Any])?["images"] as? [String])
        XCTAssertEqual(eventImages, [fileURL], "non-model event duplicate should use canonical file")
        let localImages = ((repaired[3]["payload"] as? [String: Any])?["local_images"] as? [String])
        XCTAssertEqual(localImages, [stored.url.path], "local display metadata should point to the canonical original")

        let after = try CodexMediaScanEngine().scan(configuration: configuration)
        XCTAssertFalse(after.needsWork)
        XCTAssertEqual(after.invalidEffectiveFileURLs, 0)
        XCTAssertEqual(after.reclaimableOccurrences, 0)
        XCTAssertEqual(after.retainedEffectiveOccurrences, 2)

        let firstRepairBytes = try Data(contentsOf: session)
        let secondRepair = try await engine.perform(.cleanupAndRepair, configuration: configuration)
        XCTAssertEqual(secondRepair.repairedFileCount, 0, "a second run must be idempotent")
        XCTAssertEqual(try Data(contentsOf: session), firstRepairBytes)
    }

    func testCleanupOnlyExternalizesDuplicatesWithoutRepairingEffectiveImageURLs() async throws {
        let fixture = try makeMixedSession(named: "cleanup-only")
        let configuration = CodexMediaCleanupConfiguration(
            codexHome: codexHome,
            supportDirectory: support,
            includeArchivedSessions: false
        )

        let engine = CodexMediaRepairEngine(processMonitor: AlwaysStoppedProcessMonitor())
        let report = try await engine.perform(.cleanup, configuration: configuration)
        XCTAssertEqual(report.operation, .cleanup)
        XCTAssertEqual(report.replacementCount, 2)
        XCTAssertEqual(report.restorationCount, 0)

        let records = try readJSONL(fixture.session)
        XCTAssertEqual(imageURL(in: records[0]), fixture.fileURL)
        XCTAssertEqual(imageURLInCompaction(records[1]), fixture.fileURL)
        XCTAssertEqual(imageURL(in: records[2]), fixture.fileURL)

        let after = try CodexMediaScanEngine().scan(configuration: configuration)
        XCTAssertFalse(after.needsCleanup)
        XCTAssertTrue(after.needsRepair)
        XCTAssertEqual(after.invalidEffectiveFileURLs, 2)
    }

    func testRepairOnlyFixesEffectiveImageURLsWithoutCleaningDuplicates() async throws {
        let fixture = try makeMixedSession(named: "repair-only")
        let configuration = CodexMediaCleanupConfiguration(
            codexHome: codexHome,
            supportDirectory: support,
            includeArchivedSessions: false
        )

        let engine = CodexMediaRepairEngine(processMonitor: AlwaysStoppedProcessMonitor())
        let report = try await engine.perform(.repair, configuration: configuration)
        XCTAssertEqual(report.operation, .repair)
        XCTAssertEqual(report.replacementCount, 0)
        XCTAssertEqual(report.restorationCount, 2)

        let records = try readJSONL(fixture.session)
        XCTAssertEqual(imageURL(in: records[0]), fixture.dataURL)
        XCTAssertEqual(imageURLInCompaction(records[1]), fixture.dataURL)
        XCTAssertEqual(imageURL(in: records[2]), fixture.dataURL)

        let after = try CodexMediaScanEngine().scan(configuration: configuration)
        XCTAssertTrue(after.needsCleanup)
        XCTAssertFalse(after.needsRepair)
        XCTAssertEqual(after.reclaimableOccurrences, 2)
    }

    func testMalformedSessionIsReportedAndNeverModified() throws {
        let session = codexHome.appendingPathComponent("sessions/2026/08/14/broken.jsonl")
        let original = Data("{not-json}\n".utf8)
        try original.write(to: session)
        let configuration = CodexMediaCleanupConfiguration(
            codexHome: codexHome,
            supportDirectory: support,
            includeArchivedSessions: false
        )
        let report = try CodexMediaScanEngine().scan(configuration: configuration)
        XCTAssertEqual(report.malformedFiles, 1)
        XCTAssertEqual(try Data(contentsOf: session), original)
    }

    func testDataImageParserRejectsInvalidBase64() {
        XCTAssertThrowsError(try CodexDataImage.parse("data:image/png;base64,%%%"))
    }

    func testOpenSessionIsSkippedWithoutModification() async throws {
        let bytes = Data("open-session-image".utf8)
        let dataURL = "data:image/png;base64,\(bytes.base64EncodedString())"
        let session = codexHome.appendingPathComponent("sessions/2026/08/14/open.jsonl")
        try writeJSONL([responseItem(imageURL: dataURL), [
            "type": "compacted",
            "payload": ["replacement_history": []]
        ]], to: session)
        let original = try Data(contentsOf: session)
        let configuration = CodexMediaCleanupConfiguration(
            codexHome: codexHome,
            supportDirectory: support,
            includeArchivedSessions: false
        )
        let engine = CodexMediaRepairEngine(processMonitor: OpenFileProcessMonitor())
        let report = try await engine.perform(.cleanupAndRepair, configuration: configuration)
        XCTAssertEqual(report.repairedFileCount, 0)
        XCTAssertEqual(report.skippedFiles.count, 1)
        XCTAssertEqual(try Data(contentsOf: session), original)
    }

    @MainActor
    func testBuiltBundleExportsTraceFencePluginFactory() throws {
        let productsDirectory = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let pluginURL = productsDirectory.appendingPathComponent("CodexMediaCleanup.bundle", isDirectory: true)
        let bundle = try XCTUnwrap(Bundle(url: pluginURL))
        XCTAssertTrue(bundle.load(), "bundle did not load")
        let factory = NSClassFromString("CodexMediaCleanupPlugin.CodexMediaCleanupPluginFactory")
            as? MacToolsPluginBundleFactory.Type
        XCTAssertNotNil(factory)
    }

    private func responseItem(imageURL: String) -> [String: Any] {
        [
            "type": "response_item",
            "payload": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": #"<image path="/tmp/original.png">"#],
                    ["type": "input_image", "image_url": imageURL]
                ]
            ]
        ]
    }

    private func makeMixedSession(named name: String) throws -> (
        session: URL,
        dataURL: String,
        fileURL: String
    ) {
        let imageBytes = Data("\(name)-image-content".utf8)
        let dataURL = "data:image/png;base64,\(imageBytes.base64EncodedString())"
        let image = try XCTUnwrap(try CodexDataImage.parse(dataURL))
        let mediaRoot = codexHome.appendingPathComponent("media_objects/sha256", isDirectory: true)
        let stored = try CodexMediaObjectStore.ensureObject(for: image, mediaRoot: mediaRoot)
        let fileURL = stored.url.absoluteString
        let session = codexHome.appendingPathComponent("sessions/2026/08/14/\(name).jsonl")
        try writeJSONL([
            responseItem(imageURL: dataURL),
            [
                "type": "compacted",
                "payload": ["replacement_history": [[
                    "type": "message",
                    "content": [["type": "input_image", "image_url": fileURL]]
                ]]]
            ],
            responseItem(imageURL: fileURL),
            [
                "type": "event_msg",
                "payload": [
                    "type": "user_message",
                    "images": [dataURL],
                    "local_images": ["/tmp/original.png"],
                    "message": #"<image path="/tmp/original.png">"#
                ]
            ]
        ], to: session)
        return (session, dataURL, fileURL)
    }

    private func writeJSONL(_ records: [[String: Any]], to url: URL) throws {
        var data = Data()
        for record in records { data.append(try CodexJSONL.encodeRecord(record)) }
        try data.write(to: url)
    }

    private func readJSONL(_ url: URL) throws -> [[String: Any]] {
        var records: [[String: Any]] = []
        try CodexJSONL.forEachLine(at: url) { line, data in
            records.append(try CodexJSONL.decodeRecord(data, path: url.path, line: line))
        }
        return records
    }

    private func imageURL(in record: [String: Any]) -> String? {
        let payload = record["payload"] as? [String: Any]
        let content = payload?["content"] as? [[String: Any]]
        return content?.first(where: { $0["type"] as? String == "input_image" })?["image_url"] as? String
    }

    private func imageURLInCompaction(_ record: [String: Any]) -> String? {
        let payload = record["payload"] as? [String: Any]
        let history = payload?["replacement_history"] as? [[String: Any]]
        let content = history?.first?["content"] as? [[String: Any]]
        return content?.first?["image_url"] as? String
    }
}

private struct AlwaysStoppedProcessMonitor: CodexProcessMonitoring {
    func isCodexRunning() -> Bool { false }
    func waitUntilCodexStops() async throws {}
    func fileHasOpenHandle(_ url: URL) -> Bool { false }
}

private struct OpenFileProcessMonitor: CodexProcessMonitoring {
    func isCodexRunning() -> Bool { false }
    func waitUntilCodexStops() async throws {}
    func fileHasOpenHandle(_ url: URL) -> Bool { true }
}
