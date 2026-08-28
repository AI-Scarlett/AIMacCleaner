import XCTest
@testable import DiskCleanPlugin

final class DiskCleanDuplicateScannerTests: XCTestCase {
    func testFindsOnlyContentIdenticalFilesAndExcludesHardLinks() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appendingPathComponent("first.bin")
        let second = root.appendingPathComponent("second.bin")
        let different = root.appendingPathComponent("different.bin")
        let hardLink = root.appendingPathComponent("first-hardlink.bin")
        let duplicateData = Data(repeating: 0x41, count: 2 * 1_024 * 1_024)
        try duplicateData.write(to: first)
        try duplicateData.write(to: second)
        try Data(repeating: 0x42, count: duplicateData.count).write(to: different)
        try FileManager.default.linkItem(at: first, to: hardLink)

        let candidates = try [first, second, different, hardLink].map(record)
        let result = DiskCleanDuplicateScanner.scan(
            candidates: candidates,
            cacheURL: root.appendingPathComponent("hash-cache.json"),
            candidateWasTruncated: false
        )

        XCTAssertEqual(result.groups.count, 1)
        let paths = Set(result.groups[0].files.map(\.path))
        XCTAssertTrue(paths.contains(second.path))
        XCTAssertEqual(paths.intersection([first.path, hardLink.path]).count, 1)
        XCTAssertEqual(result.summary.duplicateFileCount, 2)
        XCTAssertGreaterThan(result.summary.reclaimableBytes, 0)
        XCTAssertFalse(result.summary.wasTruncated)
    }

    func testSecondScanUsesHashCache() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appendingPathComponent("a.bin")
        let second = root.appendingPathComponent("b.bin")
        let data = Data(repeating: 0x2A, count: 2 * 1_024 * 1_024)
        try data.write(to: first)
        try data.write(to: second)
        let cacheURL = root.appendingPathComponent("hash-cache.json")
        let candidates = try [first, second].map(record)

        let initial = DiskCleanDuplicateScanner.scan(
            candidates: candidates,
            cacheURL: cacheURL,
            candidateWasTruncated: false
        )
        let cached = DiskCleanDuplicateScanner.scan(
            candidates: candidates,
            cacheURL: cacheURL,
            candidateWasTruncated: false
        )

        XCTAssertEqual(initial.groups, cached.groups)
        XCTAssertEqual(initial.summary.hashedFileCount, 2)
        XCTAssertEqual(cached.summary.hashedFileCount, 0)
    }

    private func record(_ url: URL) throws -> DiskFileRecord {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey
        ])
        return DiskFileRecord(
            id: url.path,
            name: url.lastPathComponent,
            path: url.path,
            fileExtension: url.pathExtension,
            category: .other,
            size: Int64(values.fileAllocatedSize ?? values.fileSize ?? 0),
            logicalSize: Int64(values.fileSize ?? 0),
            creationDate: values.creationDate,
            modifiedDate: values.contentModificationDate,
            accessedDate: values.contentAccessDate,
            lastOpenedDate: nil
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diskclean-duplicates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
