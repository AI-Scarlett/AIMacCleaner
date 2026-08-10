import Darwin
import Foundation

@main
struct VerifyDiskFileInventory {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tracefence-file-inventory-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let fixtures: [(String, Int, Int)] = [
            ("photo.JPG", 130_000, 100),
            ("movie.MP4", 140_000, 45),
            ("report.pdf", 150_000, 10),
            ("backup.zip", 160_000, 2),
            ("release.IPA", 170_000, 120),
            ("source.swift", 180_000, 91),
            ("database.bin", 190_000, 31)
        ]
        for (name, size, ageDays) in fixtures {
            let url = root.appendingPathComponent(name)
            try Data(repeating: UInt8(size % 251), count: size).write(to: url)
            try setAccessAndModificationDate(
                now.addingTimeInterval(-TimeInterval(ageDays) * 86_400),
                for: url
            )
        }

        try Data(repeating: 1, count: 8_000).write(to: root.appendingPathComponent("small.txt"))
        let hidden = root.appendingPathComponent(".secret", isDirectory: true)
        try fm.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100_000).write(to: hidden.appendingPathComponent("hidden.mp4"))
        let dependencies = root.appendingPathComponent("node_modules", isDirectory: true)
        try fm.createDirectory(at: dependencies, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100_000).write(to: dependencies.appendingPathComponent("dependency.mp4"))
        try fm.createSymbolicLink(
            at: root.appendingPathComponent("photo-link.jpg"),
            withDestinationURL: root.appendingPathComponent("photo.JPG")
        )
        let agentSessions = root.appendingPathComponent(".codex/sessions", isDirectory: true)
        try fm.createDirectory(at: agentSessions, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 100_000).write(to: agentSessions.appendingPathComponent("source.jsonl"))
        let qwenData = root.appendingPathComponent(".qwen/projects", isDirectory: true)
        try fm.createDirectory(at: qwenData, withIntermediateDirectories: true)
        try Data(repeating: 8, count: 110_000).write(to: qwenData.appendingPathComponent("source.jsonl"))

        let cacheURL = root.appendingPathComponent("cache/disk_file_inventory_cache_v1.json")
        var providerCalls = 0
        let first = DiskFileInventoryCore.scan(
            homeDirectory: root.path,
            authorizedRoots: [root.path],
            isSandboxed: true,
            cacheURL: cacheURL,
            now: now,
            lastOpenedDateProvider: { url in
                providerCalls += 1
                return url.pathExtension.lowercased() == "ipa"
                    ? now.addingTimeInterval(-5 * 86_400)
                    : nil
            }
        )

        try expect(first.files.count == fixtures.count, "expected seven eligible user files")
        try expect(first.summary.metadataReadCount == fixtures.count, "first scan should read every file's metadata")
        try expect(first.summary.cacheHitCount == 0, "first scan should not report cache hits")
        try expect(providerCalls == fixtures.count, "last-opened provider should be queried once per eligible file")
        try expect(first.files.first?.name == "database.bin", "files should be returned largest first")
        let photo = try record(named: "photo.JPG", in: first)
        let movieRecord = try record(named: "movie.MP4", in: first)
        let report = try record(named: "report.pdf", in: first)
        let backup = try record(named: "backup.zip", in: first)
        let release = try record(named: "release.IPA", in: first)
        let source = try record(named: "source.swift", in: first)
        let database = try record(named: "database.bin", in: first)
        try expect(photo.category == .image, "JPG classification failed")
        try expect(movieRecord.category == .video, "MP4 classification failed")
        try expect(report.category == .document, "PDF classification failed")
        try expect(backup.category == .archive, "ZIP classification failed")
        try expect(release.category == .installer, "IPA classification failed")
        try expect(source.category == .code, "Swift classification failed")
        try expect(database.category == .other, "other classification failed")
        try expect(photo.activityMarker(at: now) == .days90, "100-day marker failed")
        try expect(movieRecord.activityMarker(at: now) == .days30, "45-day marker failed")
        try expect(report.activityMarker(at: now) == .days7, "10-day marker failed")
        try expect(backup.activityMarker(at: now) == .recent, "recent marker failed")
        try expect(release.activityMarker(at: now) == .recent, "last-opened date should override an old modified date")
        let firstCacheData = try Data(contentsOf: cacheURL)

        let second = DiskFileInventoryCore.scan(
            homeDirectory: root.path,
            authorizedRoots: [root.path],
            isSandboxed: true,
            cacheURL: cacheURL,
            now: now.addingTimeInterval(60),
            lastOpenedDateProvider: { _ in
                providerCalls += 1
                return nil
            }
        )
        try expect(second.summary.cacheHitCount == fixtures.count, "second scan should reuse all metadata records")
        try expect(second.summary.metadataReadCount == 0, "second scan should avoid Spotlight metadata reads")
        try expect(providerCalls == fixtures.count, "fresh cache should not call the last-opened provider")
        let secondCacheData = try Data(contentsOf: cacheURL)
        try expect(firstCacheData == secondCacheData, "an unchanged warm scan should not rewrite the metadata cache")

        let movie = root.appendingPathComponent("movie.MP4")
        let handle = try FileHandle(forWritingTo: movie)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 3, count: 4_096))
        try handle.close()
        try setAccessAndModificationDate(now.addingTimeInterval(-45 * 86_400), for: movie)

        let third = DiskFileInventoryCore.scan(
            homeDirectory: root.path,
            authorizedRoots: [root.path],
            isSandboxed: true,
            cacheURL: cacheURL,
            now: now.addingTimeInterval(120),
            lastOpenedDateProvider: { _ in
                providerCalls += 1
                return nil
            }
        )
        try expect(third.summary.cacheHitCount == fixtures.count - 1, "only the changed file should miss cache")
        try expect(third.summary.metadataReadCount == 1, "only the changed file should refresh metadata")

        providerCalls = 0
        let boundedCacheURL = root.appendingPathComponent("cache/bounded_inventory_cache_v1.json")
        let bounded = DiskFileInventoryCore.scan(
            homeDirectory: root.path,
            authorizedRoots: [root.path],
            isSandboxed: true,
            cacheURL: boundedCacheURL,
            now: now.addingTimeInterval(180),
            maximumReturnedFiles: 3,
            lastOpenedDateProvider: { _ in
                providerCalls += 1
                return nil
            }
        )
        try expect(bounded.summary.eligibleFileCount == fixtures.count, "bounded inventory must still count every eligible file")
        try expect(bounded.files.count == 3, "bounded inventory should retain only the requested largest files")
        try expect(bounded.summary.wasTruncated, "bounded inventory must report partial visible coverage")
        try expect(providerCalls == 3, "Spotlight should run only for files retained by the bounded inventory")
        try expect(bounded.summary.metadataReadCount == 3, "bounded inventory metadata count should match retained cache misses")

        let protectedRoot = DiskFileInventoryCore.scan(
            homeDirectory: root.path,
            authorizedRoots: [agentSessions.path],
            isSandboxed: true,
            cacheURL: root.appendingPathComponent("cache/protected_inventory_cache_v1.json"),
            now: now.addingTimeInterval(240)
        )
        try expect(protectedRoot.files.isEmpty, "directly authorized Agent state must not become a cleanup file list")
        try expect(protectedRoot.summary.eligibleFileCount == 0, "protected Agent state must remain outside inventory totals")

        let protectedQwenRoot = DiskFileInventoryCore.scan(
            homeDirectory: root.path,
            authorizedRoots: [qwenData.path],
            isSandboxed: true,
            cacheURL: root.appendingPathComponent("cache/protected_qwen_inventory_cache_v1.json"),
            now: now.addingTimeInterval(300)
        )
        try expect(protectedQwenRoot.files.isEmpty, "all supported Agent roots must share cleanup protection")

        print("DISK_FILE_INVENTORY_OK files=\(first.files.count) cache_hits=\(second.summary.cacheHitCount) refreshed=\(third.summary.metadataReadCount) bounded=\(bounded.files.count) protected=\(protectedRoot.files.count + protectedQwenRoot.files.count) categories=\(first.summary.categoryBreakdown.count)")
    }

    private static func record(
        named name: String,
        in result: DiskFileInventoryScanResult
    ) throws -> DiskFileRecord {
        guard let record = result.files.first(where: { $0.name == name }) else {
            throw NSError(
                domain: "TraceFenceDiskFileInventoryTest",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"]
            )
        }
        return record
    }

    private static func setAccessAndModificationDate(_ date: Date, for url: URL) throws {
        let seconds = Int(date.timeIntervalSince1970)
        var times = [
            timeval(tv_sec: seconds, tv_usec: 0),
            timeval(tv_sec: seconds, tv_usec: 0)
        ]
        let result = url.path.withCString { path in
            utimes(path, &times)
        }
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "utimes failed for \(url.path)"]
            )
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw NSError(
                domain: "TraceFenceDiskFileInventoryTest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
