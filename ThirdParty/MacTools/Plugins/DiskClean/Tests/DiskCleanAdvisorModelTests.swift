import XCTest
@testable import DiskCleanPlugin

@MainActor
final class DiskCleanAdvisorModelTests: XCTestCase {
    func testAdvisorCompletesWithBoundedInventoryAndKeepsAgentFilesOutOfUserRows() async throws {
        let root = try makeTemporaryDirectory()
        let cache = URL(fileURLWithPath: root).appendingPathComponent("cache", isDirectory: true)
        let documents = URL(fileURLWithPath: root).appendingPathComponent("Documents", isDirectory: true)
        let agent = URL(fileURLWithPath: root).appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agent, withIntermediateDirectories: true)

        let userFile = documents.appendingPathComponent("large-document.pdf")
        try Data(repeating: 0x41, count: 128 * 1_024).write(to: userFile)
        let protectedAgentFile = agent.appendingPathComponent("session.jsonl")
        try Data(repeating: 0x42, count: 128 * 1_024).write(to: protectedAgentFile)

        let model = DiskCleanAdvisorModel(
            cacheDirectory: cache,
            homeDirectory: root,
            isSandboxed: false
        )
        model.scan()

        let deadline = Date().addingTimeInterval(10)
        while model.stage != .completed, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(model.stage, .completed)
        XCTAssertNotNil(model.storageSummary)
        XCTAssertNotNil(model.inventorySummary)
        XCTAssertTrue(model.files.contains {
            $0.path == userFile.standardizedFileURL.path
        })
        XCTAssertFalse(
            model.files.contains { $0.path == protectedAgentFile.standardizedFileURL.path },
            "Agent history may contribute aggregate statistics but must never become a user-file cleanup row"
        )
        XCTAssertLessThanOrEqual(model.files.count, 2_000)

        let restored = DiskCleanAdvisorModel(
            cacheDirectory: cache,
            homeDirectory: root,
            isSandboxed: false
        )
        let restoreDeadline = Date().addingTimeInterval(3)
        while !restored.hasResult, Date() < restoreDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(restored.hasResult)
        XCTAssertTrue(restored.isRestoredFromCache)
        XCTAssertEqual(restored.files.map(\.path), model.files.map(\.path))
    }

    private func makeTemporaryDirectory() throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diskclean-advisor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return DiskCleanPhysicalPath.realpath(of: url.path) ?? url.path
    }
}
