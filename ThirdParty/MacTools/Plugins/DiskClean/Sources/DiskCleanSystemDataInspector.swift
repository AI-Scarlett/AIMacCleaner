import Foundation

protocol DiskCleanSystemDataInspecting: Sendable {
    func scan(homeDirectory: String) async -> SystemDataStorageSummary
}

/// Measures the main macOS "System Data" contributors with the same low-memory,
/// allocated-size walker used by the cleanup pipeline.
///
/// The old advisor implementation used `FileManager` enumeration with a 1.5 second /
/// 25,000-entry cap per root. On a developer Mac that routinely stopped inside the first
/// large subtree and made a multi-gigabyte source look almost empty. This implementation:
/// - uses `getattrlistbulk` + `ATTR_FILE_ALLOCSIZE` (APFS physical allocation);
/// - keeps a fixed three-job admission window and the shared resident worker pool;
/// - deduplicates hard links and never crosses a mount point;
/// - reports partial roots instead of presenting a timeout/permission gap as a complete zero;
/// - includes the system-wide CoreSimulator cache that Storage Settings commonly attributes
///   to System Data, while keeping it read-only in the advisor.
struct DiskCleanSystemDataInspector: DiskCleanSystemDataInspecting {
    struct Configuration: Sendable {
        var maximumConcurrentRoots = 3
        var perRootTimeout: TimeInterval = 30
        var globalTimeout: TimeInterval = 75
        var temporaryRootOverride: String?
        var systemDeveloperCacheRoots = [
            "/Library/Developer/CoreSimulator/Caches"
        ]
        var systemDiagnosticsRoot = "/private/var/db/diagnostics"
        var virtualMemoryRoot = "/private/var/vm"

        init() {}
    }

    private struct RootJob: Sendable {
        let index: Int
        let kind: SystemDataStorageKind
        let path: String
        let disposition: SystemDataStorageDisposition
    }

    private struct RootMeasurement: Sendable {
        let job: RootJob
        let result: DiskCleanSizeResult
    }

    private let sizer: any DiskCleanDirectorySizing
    private let executor: any DiskCleanSizingExecuting
    private let configuration: Configuration
    private let now: @Sendable () -> Date

    init(
        sizer: any DiskCleanDirectorySizing = DiskCleanFastWalker(),
        executor: any DiskCleanSizingExecuting = DiskCleanWorkerPool.shared,
        configuration: Configuration = Configuration(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.sizer = sizer
        self.executor = executor
        self.configuration = configuration
        self.now = now
    }

    func scan(homeDirectory: String) async -> SystemDataStorageSummary {
        let startedAt = now()
        let globalDeadline = startedAt.addingTimeInterval(configuration.globalTimeout)
        let jobs = definitions(homeDirectory: homeDirectory)
        var iterator = jobs.makeIterator()
        var measurements: [RootMeasurement] = []
        measurements.reserveCapacity(jobs.count)

        await withTaskGroup(of: RootMeasurement.self) { group in
            func submit(_ job: RootJob) {
                let deadline = min(
                    globalDeadline,
                    now().addingTimeInterval(configuration.perRootTimeout)
                )
                group.addTask {
                    let result = await executor.size(
                        ofItemAt: job.path,
                        using: sizer,
                        deadline: deadline
                    )
                    return RootMeasurement(job: job, result: result)
                }
            }

            for _ in 0..<max(configuration.maximumConcurrentRoots, 1) {
                guard let job = iterator.next() else { break }
                submit(job)
            }

            while let measurement = await group.next() {
                measurements.append(measurement)
                // `Task.isCancelled` can reflect cancellation inherited from an XCTest or
                // host refresh task even after already-admitted sizing jobs completed. The
                // worker-pool cancellation handler still stops those jobs safely; using it
                // here to gate admission, however, could silently omit every remaining root
                // and present a tiny partial total. The hard global deadline is the only
                // admission gate. Cancellation remains fail-closed in the worker pool.
                guard now() < globalDeadline else {
                    group.cancelAll()
                    continue
                }
                if let job = iterator.next() {
                    submit(job)
                }
            }
        }

        let grouped = Dictionary(grouping: measurements, by: { $0.job.kind })
        let orderedKinds: [SystemDataStorageKind] = [
            .caches,
            .temporary,
            .developer,
            .applicationSupport,
            .appContainers,
            .systemDiagnostics,
            .virtualMemory
        ]
        let buckets = orderedKinds.map { kind -> SystemDataStorageBucket in
            let values = (grouped[kind] ?? []).sorted { $0.job.index < $1.job.index }
            let partialReasons = values.reduce(into: Set<DiskCleanScanCompleteness.PartialReason>()) {
                $0.formUnion($1.result.completeness.partialReasons)
            }
            return SystemDataStorageBucket(
                kind: kind,
                path: values.map(\.job.path).joined(separator: "\n"),
                allocatedBytes: values.reduce(Int64(0)) { $0 + max($1.result.estimatedBytes, 0) },
                visitedEntryCount: values.reduce(0) { $0 + max($1.result.fileCount, 0) },
                unreadableEntryCount: partialReasons.intersection([
                    .permissionDenied,
                    .unsupportedVolume,
                    .walkError
                ]).count,
                disposition: values.first?.job.disposition ?? disposition(for: kind),
                wasTruncated: !partialReasons.isEmpty || values.isEmpty
            )
        }
        let completedAt = now()
        return SystemDataStorageSummary(
            buckets: buckets,
            measuredBytes: buckets.reduce(Int64(0)) { $0 + max($1.allocatedBytes, 0) },
            visitedEntryCount: buckets.reduce(0) { $0 + max($1.visitedEntryCount, 0) },
            unreadableEntryCount: buckets.reduce(0) { $0 + max($1.unreadableEntryCount, 0) },
            wasTruncated: buckets.contains(where: \.wasTruncated),
            scanDuration: completedAt.timeIntervalSince(startedAt),
            completedAt: completedAt
        )
    }

    private func definitions(homeDirectory: String) -> [RootJob] {
        // `/var` and `/tmp` are symlink aliases on macOS. Canonicalize the admitted
        // root itself before the no-symlink walker starts; descendants are still
        // opened with O_NOFOLLOW and remain protected from link traversal.
        let home = URL(fileURLWithPath: canonicalPath(homeDirectory), isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let temporary: URL
        if let override = configuration.temporaryRootOverride {
            temporary = URL(fileURLWithPath: canonicalPath(override), isDirectory: true)
        } else {
            temporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .resolvingSymlinksInPath()
                .deletingLastPathComponent()
        }

        var definitions: [(SystemDataStorageKind, String, SystemDataStorageDisposition)] = [
            (.caches, library.appendingPathComponent("Caches", isDirectory: true).path, .cleanable),
            (.temporary, temporary.path, .reviewRequired),
            (.developer, library.appendingPathComponent("Developer", isDirectory: true).path, .reviewRequired)
        ]
        definitions += configuration.systemDeveloperCacheRoots.map {
            (.developer, canonicalPath($0), .reviewRequired)
        }
        definitions += [
            (.applicationSupport, library.appendingPathComponent("Application Support", isDirectory: true).path, .reviewRequired),
            (.appContainers, library.appendingPathComponent("Containers", isDirectory: true).path, .reviewRequired),
            (.systemDiagnostics, canonicalPath(configuration.systemDiagnosticsRoot), .systemManaged),
            (.virtualMemory, canonicalPath(configuration.virtualMemoryRoot), .systemManaged)
        ]

        return definitions.enumerated().map { index, value in
            RootJob(index: index, kind: value.0, path: value.1, disposition: value.2)
        }
    }

    private func canonicalPath(_ path: String) -> String {
        DiskCleanPhysicalPath.realpath(of: path)
            ?? URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    private func disposition(for kind: SystemDataStorageKind) -> SystemDataStorageDisposition {
        switch kind {
        case .caches:
            return .cleanable
        case .temporary, .developer, .applicationSupport, .appContainers:
            return .reviewRequired
        case .systemDiagnostics, .virtualMemory:
            return .systemManaged
        }
    }
}
