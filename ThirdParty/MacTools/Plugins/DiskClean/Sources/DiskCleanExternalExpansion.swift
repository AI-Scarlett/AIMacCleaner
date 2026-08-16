import Foundation
import MacToolsPluginKit

// MARK: - Expansion product

/// Product of one non-rules expansion (design §10).
///
/// Shape deliberately matches the rules-expansion stage—hits + reserved roots + limitations + logs—so the engine's later
/// ownership, safety, sizing, and artifact cast all run unchanged; P2 candidates cannot skip a step.
struct DiskCleanExternalExpansion: Sendable {
    var hits: [DiskCleanTargetHit] = []
    var reservedRootPaths: [String] = []
    var limitations: [DiskCleanScanLimitation] = []
    var logMessages: [DiskCleanScanLogMessage] = []

    init() {}
}

/// Adapter seam from a specialized scanner into the unified pipeline.
///
/// The engine only knows this protocol, so tests can feed arbitrary candidates into the full pipeline without touching the filesystem
/// (sizing → completeness → artifact → Planner → executor), validating the pipeline rather than the scanner.
protocol DiskCleanExternalExpanding: Sendable {
    /// `catalog` resolves synthetic targets by targetID. Unknown targetIDs are dropped and logged—
    /// a candidate that cannot attach to a target would be rejected at `makePlan` anyway; drop early and say so.
    func expand(
        scope: DiskCleanScanScope,
        catalog: DiskCleanRuleCatalogV2,
        localization: PluginLocalization
    ) async -> DiskCleanExternalExpansion
}

// MARK: - Purge / development products

/// `DiskCleanPurgeScanner` → unified pipeline (design §10.1).
struct DiskCleanDeveloperArtifactExpansion: DiskCleanExternalExpanding {
    private let scanner: DiskCleanPurgeScanner

    init(scanner: DiskCleanPurgeScanner = DiskCleanPurgeScanner()) {
        self.scanner = scanner
    }

    func expand(
        scope: DiskCleanScanScope,
        catalog: DiskCleanRuleCatalogV2,
        localization: PluginLocalization
    ) async -> DiskCleanExternalExpansion {
        var expansion = DiskCleanExternalExpansion()
        let roots = scope.developerArtifactRoots
        guard !roots.isEmpty else { return expansion }

        // **Every configured root enters the reserved set**, whether or not traversal succeeded.
        //
        // Semantics: "the root itself is not a delete target, and any part of the root not covered by a candidate was never reviewed." Ancestor assertions therefore
        // reject any plan path that has a root as a descendant (e.g. `~` or a root's parent), while candidates **inside** a root
        // are unaffected—they are descendants of the root, not ancestors. Depth cap 6 and unexplored regions left by hit-and-prune
        // are covered by the same rule.
        expansion.reservedRootPaths = roots

        let result = await scanner.scan(roots: roots)
        for report in result.reports {
            switch report.status {
            case let .unreadable(reason):
                // A root that cannot open at all must be distinguished from "scanned with no candidates", or the user sees a dishonest empty list.
                expansion.limitations.append(
                    .scanRootUnreadable(path: report.root, reason: reason)
                )

            case let .traversed(completeness):
                // Partial subtree skips only affect discovery completeness, not deletability of already-found candidates (the root is already reserved).
                // So only log; do not escalate to a limitation—the list is already in front of the user, and when a root is unreadable
                // the user already has a stronger signal.
                guard case let .partial(reasons) = completeness else { break }
                expansion.logMessages.append(
                    DiskCleanScanLogMessage(
                        text: localization.format(
                            "scanLog.purge.partialRoot",
                            defaultValue: "%@ 有子目录未能读取（%@），可能漏报部分产物",
                            report.root,
                            DiskCleanFormat.partialReasons(reasons, localization: localization)
                        ),
                        tone: .warning
                    )
                )
            }

            for candidate in report.candidates {
                guard let target = catalog.target(id: candidate.kind.targetID) else {
                    expansion.logMessages.append(Self.missingTargetLog(candidate.kind.targetID, localization: localization))
                    continue
                }
                expansion.hits.append(
                    DiskCleanTargetHit(
                        target: target,
                        item: DiskCleanFileItem(
                            path: candidate.path,
                            isDirectory: true,
                            isSymlink: false,
                            resolvedSymlinkTarget: nil
                        ),
                        specificity: 0,
                        facts: Self.facts(for: candidate)
                    )
                )
            }
        }

        return expansion
    }

    /// Dirty repo (including check failure) → keep the target's medium risk, not selected by default; everything else drops to low and is selected by default.
    static func facts(for candidate: DiskCleanPurgeCandidate) -> DiskCleanCandidateFacts {
        var notes: [DiskCleanCandidateNote] = [
            .developerProject(path: candidate.projectPath, marker: candidate.projectMarker)
        ]
        if case let .dirty(repositoryPath, reason) = candidate.gitState {
            notes.append(.repositoryHasChanges(repositoryPath: repositoryPath, reason: reason))
        }
        return DiskCleanCandidateFacts(
            risk: candidate.isSelectedByDefault ? .low : nil,
            notes: notes
        )
    }

    private static func missingTargetLog(
        _ targetID: String,
        localization: PluginLocalization
    ) -> DiskCleanScanLogMessage {
        DiskCleanScanLogMessage(
            text: localization.format(
                "scanLog.missingTarget",
                defaultValue: "规则目录缺少 target %@，已跳过对应候选",
                targetID
            ),
            tone: .error
        )
    }
}

// MARK: - Leftover installers

/// `DiskCleanInstallerScanner` → unified pipeline (design §10.2).
struct DiskCleanInstallerExpansion: DiskCleanExternalExpanding {
    private let scanner: DiskCleanInstallerScanner

    init(scanner: DiskCleanInstallerScanner = DiskCleanInstallerScanner()) {
        self.scanner = scanner
    }

    func expand(
        scope: DiskCleanScanScope,
        catalog: DiskCleanRuleCatalogV2,
        localization: PluginLocalization
    ) async -> DiskCleanExternalExpansion {
        var expansion = DiskCleanExternalExpansion()
        // Scope is fixed; reserved roots come from the synthetic target's own declaration—same source as rule targets.
        // Five targets declare the same `~/Downloads`; after dedupe only one remains.
        var seenRoots: Set<String> = []
        expansion.reservedRootPaths = DiskCleanInstallerKind.allCases
            .compactMap { catalog.target(id: $0.targetID) }
            .flatMap { $0.expandedReservedRootPaths() }
            .filter { seenRoots.insert($0).inserted }

        switch await scanInBackground() {
        case let .denied(path):
            // TCC denial (`~/Downloads` is the kind that prompts). The directory may hold tens of GB;
            // reporting "nothing to clean" would be lying to the user.
            expansion.limitations.append(.scanRootUnreadable(path: path, reason: .permissionDenied))

        case let .unavailable(path, reason):
            expansion.limitations.append(.scanRootUnreadable(path: path, reason: reason))

        case let .scanned(candidates):
            for candidate in candidates {
                guard let target = catalog.target(id: candidate.kind.targetID) else {
                    expansion.logMessages.append(
                        DiskCleanScanLogMessage(
                            text: localization.format(
                                "scanLog.missingTarget",
                                defaultValue: "规则目录缺少 target %@，已跳过对应候选",
                                candidate.kind.targetID
                            ),
                            tone: .error
                        )
                    )
                    continue
                }
                expansion.hits.append(
                    DiskCleanTargetHit(
                        target: target,
                        item: DiskCleanFileItem(
                            path: candidate.path,
                            isDirectory: false,
                            isSymlink: false,
                            resolvedSymlinkTarget: nil
                        ),
                        specificity: 0,
                        facts: Self.facts(for: candidate)
                    )
                )
            }
        }

        return expansion
    }

    /// `.zip` and "downloaded within 7 days" keep the target's medium risk; everything else drops to low and is selected by default.
    static func facts(for candidate: DiskCleanInstallerCandidate) -> DiskCleanCandidateFacts {
        var notes: [DiskCleanCandidateNote] = []
        switch candidate.note {
        case .mayNotBeInstaller:
            notes.append(.mayNotBeInstaller)
        case .recentlyModified:
            notes.append(.recentlyDownloaded(modifiedAt: candidate.modifiedAt))
        case nil:
            break
        }
        return DiskCleanCandidateFacts(
            risk: candidate.isSelectedByDefault ? .low : nil,
            notes: notes
        )
    }

    /// The scan is blocking (one top-level `readdir` + per-entry `fstatat`) and must not occupy Swift concurrency's cooperative thread pool.
    /// The same call may also trigger the `~/Downloads` TCC prompt, which must not happen on a cooperative thread either.
    private func scanInBackground() async -> DiskCleanInstallerScanOutcome {
        let scanner = self.scanner
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: scanner.scan())
            }
        }
    }
}

// MARK: - User-selected inventory files

/// Bridges the advisor's metadata-only inventory back into the authoritative cleanup pipeline.
///
/// The scanner receives exact paths selected by the user; it never expands a directory or glob.
/// A selected file is still looked up afresh, physical-path normalized by the candidate assembler,
/// checked by `DiskCleanSafetyPolicy`, sized, identity-stamped, planned, staged, and audited.
struct DiskCleanUserFileExpansion: DiskCleanExternalExpanding {
    static let targetID = "inventory.user-file"
    static let maximumSelectionCount = 500

    private let fileSystem: any DiskCleanFileSystemProviding

    init(fileSystem: any DiskCleanFileSystemProviding = LocalDiskCleanFileSystem()) {
        self.fileSystem = fileSystem
    }

    func expand(
        scope: DiskCleanScanScope,
        catalog: DiskCleanRuleCatalogV2,
        localization: PluginLocalization
    ) async -> DiskCleanExternalExpansion {
        var expansion = DiskCleanExternalExpansion()
        guard case let .userFiles(rawPaths) = scope else { return expansion }
        guard let target = catalog.target(id: Self.targetID) else {
            expansion.logMessages.append(
                DiskCleanScanLogMessage(
                    text: localization.format(
                        "scanLog.missingTarget",
                        defaultValue: "规则目录缺少 target %@，已跳过对应候选",
                        Self.targetID
                    ),
                    tone: .error
                )
            )
            return expansion
        }

        var seen = Set<String>()
        let paths = rawPaths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { seen.insert($0).inserted }
            .sorted()

        if paths.count > Self.maximumSelectionCount {
            expansion.logMessages.append(
                DiskCleanScanLogMessage(
                    text: localization.format(
                        "scanLog.inventory.selectionLimited",
                        defaultValue: "一次最多安全检查 %d 个文件；其余文件留待下一批。",
                        Self.maximumSelectionCount
                    ),
                    tone: .warning
                )
            )
        }

        for path in paths.prefix(Self.maximumSelectionCount) {
            guard !Task.isCancelled else { break }
            do {
                guard let item = try fileSystem.itemInfo(at: path) else {
                    expansion.logMessages.append(
                        DiskCleanScanLogMessage(
                            text: localization.format(
                                "scanLog.inventory.fileMissing",
                                defaultValue: "文件已不存在：%@",
                                path
                            ),
                            tone: .warning
                        )
                    )
                    continue
                }
                guard !item.isDirectory else {
                    expansion.logMessages.append(
                        DiskCleanScanLogMessage(
                            text: localization.format(
                                "scanLog.inventory.directorySkipped",
                                defaultValue: "文件分析不清理目录：%@",
                                path
                            ),
                            tone: .warning
                        )
                    )
                    continue
                }
                expansion.hits.append(
                    DiskCleanTargetHit(
                        target: target,
                        item: item,
                        logicalPath: path,
                        specificity: path.count,
                        // Original user files remain high risk even though the inventory checkbox
                        // selected the batch. The cleanup list is a second, explicit review gate;
                        // nothing from Documents/Desktop should become preselected for deletion.
                        facts: .inherited
                    )
                )
            } catch {
                expansion.logMessages.append(
                    DiskCleanScanLogMessage(
                        text: localization.format(
                            "scanLog.inventory.fileFailed",
                            defaultValue: "无法检查 %@（%@）",
                            path,
                            error.localizedDescription
                        ),
                        tone: .warning
                    )
                )
            }
        }

        expansion.logMessages.append(
            DiskCleanScanLogMessage(
                text: localization.format(
                    "scanLog.inventory.prepared",
                    defaultValue: "已将 %d 个所选文件送入安全清理流程",
                    expansion.hits.count
                ),
                tone: expansion.hits.isEmpty ? .info : .success
            )
        )
        return expansion
    }
}

// MARK: - AI Disk Advisor findings

/// Sends the shared native advisor's exact historical-build and installer findings through the
/// same physical-path, safety, sizing, identity, plan, staging, and audit pipeline as Mac Cleanup.
/// Directories are accepted here because Xcode archives/results and versioned build outputs are
/// directories; unlike the developer sweep, this expansion never walks or infers a parent root.
struct DiskCleanAdvisorFindingExpansion: DiskCleanExternalExpanding {
    static let historicalBuildTargetID = "advisor.historical-build"
    static let installerArtifactTargetID = "advisor.installer-artifact"
    static let maximumSelectionCount = 500

    private let fileSystem: any DiskCleanFileSystemProviding

    init(fileSystem: any DiskCleanFileSystemProviding = LocalDiskCleanFileSystem()) {
        self.fileSystem = fileSystem
    }

    func expand(
        scope: DiskCleanScanScope,
        catalog: DiskCleanRuleCatalogV2,
        localization: PluginLocalization
    ) async -> DiskCleanExternalExpansion {
        var expansion = DiskCleanExternalExpansion()
        guard case let .advisorFindings(rawItems) = scope else { return expansion }

        var seenPaths = Set<String>()
        let items = rawItems
            .map {
                DiskCleanAdvisorFinding(
                    path: URL(fileURLWithPath: $0.path).standardizedFileURL.path,
                    kind: $0.kind
                )
            }
            .filter { seenPaths.insert($0.path).inserted }
            .sorted { $0.path < $1.path }

        if items.count > Self.maximumSelectionCount {
            expansion.logMessages.append(
                DiskCleanScanLogMessage(
                    text: localization.format(
                        "scanLog.inventory.selectionLimited",
                        defaultValue: "一次最多安全检查 %d 个文件；其余文件留待下一批。",
                        Self.maximumSelectionCount
                    ),
                    tone: .warning
                )
            )
        }

        for finding in items.prefix(Self.maximumSelectionCount) {
            guard !Task.isCancelled else { break }
            let targetID = Self.targetID(for: finding.kind)
            guard let target = catalog.target(id: targetID) else {
                expansion.logMessages.append(
                    DiskCleanScanLogMessage(
                        text: localization.format(
                            "scanLog.missingTarget",
                            defaultValue: "规则目录缺少 target %@，已跳过对应候选",
                            targetID
                        ),
                        tone: .error
                    )
                )
                continue
            }

            do {
                guard let item = try fileSystem.itemInfo(at: finding.path) else {
                    expansion.logMessages.append(
                        DiskCleanScanLogMessage(
                            text: localization.format(
                                "scanLog.inventory.fileMissing",
                                defaultValue: "文件已不存在：%@",
                                finding.path
                            ),
                            tone: .warning
                        )
                    )
                    continue
                }
                expansion.hits.append(
                    DiskCleanTargetHit(
                        target: target,
                        item: item,
                        logicalPath: finding.path,
                        specificity: finding.path.count,
                        facts: .inherited
                    )
                )
            } catch {
                expansion.logMessages.append(
                    DiskCleanScanLogMessage(
                        text: localization.format(
                            "scanLog.inventory.fileFailed",
                            defaultValue: "无法检查 %@（%@）",
                            finding.path,
                            error.localizedDescription
                        ),
                        tone: .warning
                    )
                )
            }
        }

        expansion.logMessages.append(
            DiskCleanScanLogMessage(
                text: localization.format(
                    "scanLog.inventory.prepared",
                    defaultValue: "已将 %d 个所选文件送入安全清理流程",
                    expansion.hits.count
                ),
                tone: expansion.hits.isEmpty ? .info : .success
            )
        )
        return expansion
    }

    private static func targetID(for kind: StorageCleanupItemKind) -> String {
        switch kind {
        case .historicalBuild:
            return historicalBuildTargetID
        case .installerArtifact:
            return installerArtifactTargetID
        }
    }
}
