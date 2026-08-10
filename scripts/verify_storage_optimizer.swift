import Foundation

@main
struct VerifyStorageOptimizer {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tracefence-storage-optimizer-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let sessions = root.appendingPathComponent(".codex/sessions", isDirectory: true)
        try fm.createDirectory(at: sessions, withIntermediateDirectories: true)
        let firstPayload = "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo="
        let secondPayload = "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo="
        let firstSession = [
            #"{"image_url":"data:image/png;base64,\#(firstPayload)"}"#,
            #"{"image_url":"data:image/png;base64,\#(firstPayload)"}"#
        ].joined(separator: "\n")
        let secondSession = [
            #"{"image_url":"data:image/png;base64,\#(firstPayload)"}"#,
            #"{"image_url":"data:image/png;base64,\#(secondPayload)"}"#
        ].joined(separator: "\n")
        let firstSessionURL = sessions.appendingPathComponent("one.jsonl")
        let secondSessionURL = sessions.appendingPathComponent("two.jsonl")
        let boundarySessionURL = sessions.appendingPathComponent("chunk-boundary.jsonl")
        try Data((firstSession + "\n").utf8).write(to: firstSessionURL)
        try Data((secondSession + "\n").utf8).write(to: secondSessionURL)
        let boundaryPayload = String(repeating: "A", count: 1_100_000)
        var boundarySession = Data(repeating: 32, count: 1_024 * 1_024 - 2)
        boundarySession.append(Data("data:image/png;base64,\(boundaryPayload)\n".utf8))
        try boundarySession.write(to: boundarySessionURL)

        let releases = root.appendingPathComponent("Documents/Demo/releases", isDirectory: true)
        try fm.createDirectory(at: releases, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for version in 1...5 {
            let directory = releases.appendingPathComponent("v\(version).0", isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let installer = directory.appendingPathComponent("Demo-v\(version).0.dmg")
            try Data(repeating: UInt8(version), count: 1_100_000).write(to: installer)
            let date = now.addingTimeInterval(TimeInterval(version - 6) * 24 * 60 * 60)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: installer.path)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: directory.path)
        }

        let xcodeArchives = root.appendingPathComponent("Library/Developer/Xcode/Archives/2033-05-18", isDirectory: true)
        try fm.createDirectory(at: xcodeArchives, withIntermediateDirectories: true)
        for version in 1...5 {
            let archive = xcodeArchives.appendingPathComponent("Demo \(version).xcarchive", isDirectory: true)
            try fm.createDirectory(at: archive, withIntermediateDirectories: true)
            let info: [String: Any] = [
                "ApplicationProperties": ["CFBundleIdentifier": "com.example.demo"]
            ]
            let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try infoData.write(to: archive.appendingPathComponent("Info.plist"))
            try Data(repeating: UInt8(version), count: 4_096).write(
                to: archive.appendingPathComponent("Demo.app")
            )
            let date = now.addingTimeInterval(TimeInterval(version - 6) * 12 * 60 * 60)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: archive.path)
        }

        let xcodeLogs = root.appendingPathComponent(
            "Library/Developer/Xcode/DerivedData/Demo-abcdefghijklmnopqrst/Logs/Test",
            isDirectory: true
        )
        try fm.createDirectory(at: xcodeLogs, withIntermediateDirectories: true)
        for run in 1...5 {
            let result = xcodeLogs.appendingPathComponent("Run-\(run).xcresult", isDirectory: true)
            try fm.createDirectory(at: result, withIntermediateDirectories: true)
            try Data(repeating: UInt8(run), count: 2_048).write(to: result.appendingPathComponent("result.data"))
            let activity = xcodeLogs.appendingPathComponent("Run-\(run).xcactivitylog")
            try Data(repeating: UInt8(run), count: 2_048).write(to: activity)
            let date = now.addingTimeInterval(TimeInterval(run - 6) * 6 * 60 * 60)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: result.path)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: activity.path)
        }

        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        let installerExtensions = [
            "dmg", "pkg", "xip", "iso", "ipa", "apk", "aab", "exe", "msi", "msix",
            "appx", "appxbundle", "deb", "rpm", "snap"
        ]
        for ext in installerExtensions {
            let file = downloads.appendingPathComponent("manual-output.\(ext)")
            try Data(repeating: 7, count: 1_100_000).write(to: file)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-86_400)], ofItemAtPath: file.path)
        }
        let qwenData = root.appendingPathComponent(".qwen/projects", isDirectory: true)
        try fm.createDirectory(at: qwenData, withIntermediateDirectories: true)
        try Data(repeating: 6, count: 1_100_000).write(to: qwenData.appendingPathComponent("conversation-export.dmg"))

        let cache = root.appendingPathComponent("cache/storage_optimizer_cache_v1.json")
        let first = StorageOptimizationCore.scan(
            homeDirectory: root.path,
            isSandboxed: false,
            cacheURL: cache,
            retainBuildCount: 3,
            now: now
        )

        try expect(first.summary.agentSessionFileCount == 3, "expected three Agent session files")
        try expect(first.summary.hashedFileCount == 3, "first scan should hash every Agent file")
        try expect(first.summary.cacheHitCount == 0, "first scan should have no cache hits")
        try expect(first.summary.embeddedMediaOccurrences == 5, "expected five embedded media occurrences")
        try expect(first.summary.uniqueMediaCount == 3, "expected three unique media payloads")
        try expect(
            first.summary.duplicateMediaBytes == Int64(firstPayload.utf8.count * 2),
            "exact duplicate media bytes are incorrect"
        )
        try expect(
            first.summary.withinSessionDuplicateBytes == Int64(firstPayload.utf8.count),
            "within-session duplicate bytes are incorrect"
        )
        try expect(
            first.summary.crossSessionDuplicateBytes == Int64(firstPayload.utf8.count),
            "cross-session duplicate bytes are incorrect"
        )

        let historical = first.cleanupItems.filter { $0.kind == .historicalBuild }
        let installers = first.cleanupItems.filter { $0.kind == .installerArtifact }
        let oldVersionedBuilds = historical.filter { $0.path.contains("/Documents/Demo/releases/") }
        let oldArchives = historical.filter { URL(fileURLWithPath: $0.path).pathExtension == "xcarchive" }
        let oldTestResults = historical.filter { URL(fileURLWithPath: $0.path).pathExtension == "xcresult" }
        let oldActivityLogs = historical.filter { URL(fileURLWithPath: $0.path).pathExtension == "xcactivitylog" }
        try expect(oldVersionedBuilds.count == 2, "five versioned builds should retain three and list two")
        try expect(oldArchives.count == 2, "five Xcode archives should retain three and list two")
        try expect(oldTestResults.count == 2, "five Xcode test results should retain three and list two")
        try expect(oldActivityLogs.count == 2, "five Xcode activity logs should retain three and list two")
        try expect(first.summary.retainedBuildCount >= 12, "expected the newest three items in each build-history group to remain protected")
        try expect(
            installers.count == installerExtensions.count + 3,
            "expected every supported standalone installer plus three retained-version DMGs"
        )
        try expect(historical.allSatisfy { !$0.path.contains("v4.0") && !$0.path.contains("v5.0") }, "newest builds must stay protected")
        let firstCacheData = try Data(contentsOf: cache)

        let second = StorageOptimizationCore.scan(
            homeDirectory: root.path,
            isSandboxed: false,
            cacheURL: cache,
            retainBuildCount: 3,
            now: now.addingTimeInterval(10)
        )
        try expect(second.summary.cacheHitCount == 3, "second scan should reuse every fingerprint")
        try expect(second.summary.hashedFileCount == 0, "second scan should not re-read unchanged sessions")
        try expect(second.summary.duplicateMediaBytes == first.summary.duplicateMediaBytes, "cached scan changed duplicate totals")
        let secondCacheData = try Data(contentsOf: cache)
        try expect(firstCacheData == secondCacheData, "an unchanged warm scan should not rewrite the fingerprint cache")

        let appendedLine = #"{"image_url":"data:image/png;base64,\#(secondPayload)"}"# + "\n"
        let handle = try FileHandle(forWritingTo: firstSessionURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appendedLine.utf8))
        try handle.close()
        let third = StorageOptimizationCore.scan(
            homeDirectory: root.path,
            isSandboxed: false,
            cacheURL: cache,
            retainBuildCount: 3,
            now: now.addingTimeInterval(20)
        )
        try expect(third.summary.cacheHitCount == 2, "append scan should reuse the unchanged sessions")
        try expect(third.summary.hashedFileCount == 1, "append scan should read only the changed session tail")
        try expect(third.summary.fingerprintedBytes == Int64(appendedLine.utf8.count), "append scan read more than the appended bytes")
        try expect(
            third.summary.duplicateMediaBytes == first.summary.duplicateMediaBytes + Int64(secondPayload.utf8.count),
            "append scan did not merge the new duplicate payload"
        )

        let replacement = Array(repeating: appendedLine, count: 10).joined()
        let rewriteHandle = try FileHandle(forWritingTo: firstSessionURL)
        try rewriteHandle.truncate(atOffset: 0)
        try rewriteHandle.write(contentsOf: Data(replacement.utf8))
        try rewriteHandle.close()
        let fourth = StorageOptimizationCore.scan(
            homeDirectory: root.path,
            isSandboxed: false,
            cacheURL: cache,
            retainBuildCount: 3,
            now: now.addingTimeInterval(30)
        )
        try expect(fourth.summary.cacheHitCount == 2, "rewrite scan should still reuse the unchanged sessions")
        try expect(fourth.summary.hashedFileCount == 1, "rewrite scan should re-read the changed file")
        try expect(
            fourth.summary.fingerprintedBytes == Int64(replacement.utf8.count),
            "rewrite continuity guard failed to force a full re-read (expected \(replacement.utf8.count), got \(fourth.summary.fingerprintedBytes))"
        )

        let protectedAgentArtifacts = StorageOptimizationCore.scan(
            homeDirectory: root.path,
            authorizedRoots: [qwenData.path],
            isSandboxed: true,
            cacheURL: root.appendingPathComponent("cache/protected_agent_storage_cache_v1.json"),
            retainBuildCount: 3,
            now: now.addingTimeInterval(240)
        )
        try expect(
            protectedAgentArtifacts.cleanupItems.isEmpty,
            "Agent source data must never be surfaced as installer or build cleanup candidates"
        )

        print("STORAGE_OPTIMIZER_OK sessions=3 duplicate=\(first.summary.duplicateMediaBytes) history=\(historical.count) installers=\(installers.count) cache_hits=\(second.summary.cacheHitCount) append_bytes=\(third.summary.fingerprintedBytes) rewrite_bytes=\(fourth.summary.fingerprintedBytes)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw NSError(domain: "TraceFenceStorageOptimizerTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
