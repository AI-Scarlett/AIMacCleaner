import XCTest
@testable import MacTools
@testable import XcodeCleanPlugin

final class XcodeCleanExecutorTests: XCTestCase {
    func testRemovesAllowedCandidate() async throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let target = temp.appendingPathComponent("Project-abc")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data([0]).write(to: target.appendingPathComponent("a"))

        let executor = XcodeCleanExecutor(allowedRoots: [temp.path])
        let candidate = XcodeCleanCandidate(
            id: "c",
            category: .derivedData,
            path: target.path,
            sizeBytes: 1,
            safety: .allowed
        )

        let result = try await executor.clean(candidates: [candidate], selectedCandidateIDs: ["c"])

        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.reclaimedBytes, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testSkipsNonAllowedSafety() async throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let target = temp.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let executor = XcodeCleanExecutor(allowedRoots: [temp.path])
        let candidate = XcodeCleanCandidate(
            id: "c",
            category: .derivedData,
            path: target.path,
            sizeBytes: 0,
            safety: .outsideAllowedRoot
        )

        let result = try await executor.clean(candidates: [candidate], selectedCandidateIDs: ["c"])

        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testSkipsPathsOutsideAllowedRootsEvenIfMarkedAllowed() async throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let outside = temp.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data([0]).write(to: outside.appendingPathComponent("a"))

        let allowedRoot = temp.appendingPathComponent("allowed")
        try FileManager.default.createDirectory(at: allowedRoot, withIntermediateDirectories: true)

        let executor = XcodeCleanExecutor(allowedRoots: [allowedRoot.path])
        let candidate = XcodeCleanCandidate(
            id: "c",
            category: .derivedData,
            path: outside.path,
            sizeBytes: 1,
            safety: .allowed
        )

        let result = try await executor.clean(candidates: [candidate], selectedCandidateIDs: ["c"])

        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testSkipsCandidatesNotInSelectedSet() async throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let target = temp.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let executor = XcodeCleanExecutor(allowedRoots: [temp.path])
        let candidate = XcodeCleanCandidate(
            id: "c",
            category: .derivedData,
            path: target.path,
            sizeBytes: 1,
            safety: .allowed
        )

        let result = try await executor.clean(candidates: [candidate], selectedCandidateIDs: [])

        XCTAssertEqual(result.itemResults.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xcode-clean-executor-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
