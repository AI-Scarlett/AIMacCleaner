import Foundation
import XCTest
@testable import DiskCleanPlugin

final class DiskCleanSystemDataInspectorTests: XCTestCase {
    func testUsesAllocatedSizeAndIncludesSystemCoreSimulatorCacheInDeveloperBucket() async throws {
        let root = try makeTemporaryDirectory()
        let userCache = root.appendingPathComponent("Library/Caches/App/cache.bin")
        let userDeveloper = root.appendingPathComponent("Library/Developer/Xcode/index.bin")
        let systemSimulator = root.appendingPathComponent("SystemCoreSimulator/dyld/runtime.bin")
        let temporary = root.appendingPathComponent("Temporary/tmp.bin")
        let diagnostics = root.appendingPathComponent("Diagnostics/diag.bin")
        let virtualMemory = root.appendingPathComponent("VM/swap.bin")
        for url in [userCache, userDeveloper, systemSimulator, temporary, diagnostics, virtualMemory] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(repeating: 0x41, count: 8_192).write(to: url)
        }

        var configuration = DiskCleanSystemDataInspector.Configuration()
        configuration.maximumConcurrentRoots = 2
        configuration.perRootTimeout = 5
        configuration.globalTimeout = 20
        configuration.temporaryRootOverride = root.appendingPathComponent("Temporary").path
        configuration.systemDeveloperCacheRoots = [
            root.appendingPathComponent("SystemCoreSimulator").path
        ]
        configuration.systemDiagnosticsRoot = root.appendingPathComponent("Diagnostics").path
        configuration.virtualMemoryRoot = root.appendingPathComponent("VM").path
        let pool = DiskCleanWorkerPool(maxThreadCount: 2, abandonBudget: 1)
        addTeardownBlock { pool.shutDown() }

        let summary = await DiskCleanSystemDataInspector(
            executor: pool,
            configuration: configuration
        ).scan(homeDirectory: root.path)

        XCTAssertEqual(summary.buckets.count, 7)
        let developer = try XCTUnwrap(summary.buckets.first { $0.kind == .developer })
        XCTAssertTrue(developer.path.contains("Library/Developer"))
        XCTAssertTrue(developer.path.contains("SystemCoreSimulator"))
        XCTAssertGreaterThanOrEqual(developer.allocatedBytes, 16_384)
        XCTAssertFalse(developer.wasTruncated)
        XCTAssertGreaterThanOrEqual(summary.measuredBytes, 48_000)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diskclean-system-data-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return URL(fileURLWithPath: DiskCleanPhysicalPath.realpath(of: url.path) ?? url.path)
    }
}
