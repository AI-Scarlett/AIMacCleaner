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
        let duplicateOne = documents.appendingPathComponent("duplicate-one.bin")
        let duplicateTwo = documents.appendingPathComponent("duplicate-two.bin")
        let duplicateData = Data(repeating: 0x52, count: 2 * 1_024 * 1_024)
        try duplicateData.write(to: duplicateOne)
        try duplicateData.write(to: duplicateTwo)
        let protectedAgentFile = agent.appendingPathComponent("session.jsonl")
        try Data(repeating: 0x42, count: 128 * 1_024).write(to: protectedAgentFile)

        let model = DiskCleanAdvisorModel(
            cacheDirectory: cache,
            homeDirectory: root,
            isSandboxed: false,
            systemDataInspector: FakeDiskCleanSystemDataInspector()
        )
        model.scan()

        let deadline = Date().addingTimeInterval(10)
        while model.stage != .completed, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(model.stage, .completed)
        XCTAssertNotNil(model.storageSummary)
        XCTAssertEqual(model.systemDataSummary?.buckets.count, 7)
        XCTAssertNotNil(model.inventorySummary)
        XCTAssertTrue(model.files.contains {
            $0.path == userFile.standardizedFileURL.path
        })
        XCTAssertFalse(
            model.files.contains { $0.path == protectedAgentFile.standardizedFileURL.path },
            "Agent history may contribute aggregate statistics but must never become a user-file cleanup row"
        )
        XCTAssertLessThanOrEqual(model.files.count, 2_000)
        XCTAssertEqual(model.duplicateSummary?.duplicateGroupCount, 1)
        XCTAssertEqual(Set(model.duplicateGroups.first?.files.map(\.name) ?? []), Set([
            duplicateOne.lastPathComponent,
            duplicateTwo.lastPathComponent
        ]))

        let restored = DiskCleanAdvisorModel(
            cacheDirectory: cache,
            homeDirectory: root,
            isSandboxed: false,
            systemDataInspector: FakeDiskCleanSystemDataInspector()
        )
        let restoreDeadline = Date().addingTimeInterval(3)
        while !restored.hasResult, Date() < restoreDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(restored.hasResult)
        XCTAssertTrue(restored.isRestoredFromCache)
        XCTAssertEqual(restored.systemDataSummary, model.systemDataSummary)
        XCTAssertEqual(restored.files.map(\.path), model.files.map(\.path))
        XCTAssertEqual(restored.duplicateSummary, model.duplicateSummary)
        XCTAssertEqual(restored.duplicateGroups, model.duplicateGroups)
    }

    private func makeTemporaryDirectory() throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diskclean-advisor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return DiskCleanPhysicalPath.realpath(of: url.path) ?? url.path
    }
}

private struct FakeDiskCleanSystemDataInspector: DiskCleanSystemDataInspecting {
    func scan(homeDirectory: String) async -> SystemDataStorageSummary {
        let now = Date()
        let kinds: [(SystemDataStorageKind, SystemDataStorageDisposition)] = [
            (.caches, .cleanable),
            (.temporary, .reviewRequired),
            (.developer, .reviewRequired),
            (.applicationSupport, .reviewRequired),
            (.appContainers, .reviewRequired),
            (.systemDiagnostics, .systemManaged),
            (.virtualMemory, .systemManaged)
        ]
        return SystemDataStorageSummary(
            buckets: kinds.map {
                SystemDataStorageBucket(
                    kind: $0.0,
                    path: homeDirectory,
                    allocatedBytes: 0,
                    visitedEntryCount: 0,
                    unreadableEntryCount: 0,
                    disposition: $0.1,
                    wasTruncated: false
                )
            },
            measuredBytes: 0,
            visitedEntryCount: 0,
            unreadableEntryCount: 0,
            wasTruncated: false,
            scanDuration: 0,
            completedAt: now
        )
    }
}
