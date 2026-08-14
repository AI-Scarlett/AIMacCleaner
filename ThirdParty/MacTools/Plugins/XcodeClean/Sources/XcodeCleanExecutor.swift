import Foundation

protocol XcodeCleanExecuting: Sendable {
    func clean(
        candidates: [XcodeCleanCandidate],
        selectedCandidateIDs: Set<XcodeCleanCandidate.ID>
    ) async throws -> XcodeCleanExecutionResult
}

struct XcodeCleanExecutor: XcodeCleanExecuting {
    let fileSystem: XcodeCleanFileSystemProviding
    let allowedRoots: [String]

    init(
        fileSystem: XcodeCleanFileSystemProviding = LocalXcodeCleanFileSystem(),
        allowedRoots: [String]? = nil
    ) {
        self.fileSystem = fileSystem
        self.allowedRoots = (allowedRoots ?? Self.defaultAllowedRoots()).map { Self.ensureTrailingSlash($0) }
    }

    func clean(
        candidates: [XcodeCleanCandidate],
        selectedCandidateIDs: Set<XcodeCleanCandidate.ID>
    ) async throws -> XcodeCleanExecutionResult {
        var itemResults: [XcodeCleanExecutionItemResult] = []

        for candidate in candidates where selectedCandidateIDs.contains(candidate.id) {
            try Task.checkCancellation()
            itemResults.append(clean(candidate))
        }

        return XcodeCleanExecutionResult(itemResults: itemResults)
    }

    private func clean(_ candidate: XcodeCleanCandidate) -> XcodeCleanExecutionItemResult {
        guard candidate.safety.isCleanable else {
            return XcodeCleanExecutionItemResult(
                candidateID: candidate.id,
                path: candidate.path,
                outcome: .skipped(candidate.safety)
            )
        }

        if !isPathAllowed(candidate.path) {
            return XcodeCleanExecutionItemResult(
                candidateID: candidate.id,
                path: candidate.path,
                outcome: .skipped(.outsideAllowedRoot)
            )
        }

        guard fileSystem.itemExists(at: candidate.path) else {
            return XcodeCleanExecutionItemResult(
                candidateID: candidate.id,
                path: candidate.path,
                outcome: .skipped(.missing)
            )
        }

        do {
            try fileSystem.removeItem(at: candidate.path)
            return XcodeCleanExecutionItemResult(
                candidateID: candidate.id,
                path: candidate.path,
                outcome: .removed(reclaimedBytes: candidate.sizeBytes)
            )
        } catch {
            return XcodeCleanExecutionItemResult(
                candidateID: candidate.id,
                path: candidate.path,
                outcome: .failed(message: error.localizedDescription)
            )
        }
    }

    private func isPathAllowed(_ path: String) -> Bool {
        allowedRoots.contains { path.hasPrefix($0) }
    }

    private static func defaultAllowedRoots() -> [String] {
        let home = NSHomeDirectory()
        return XcodeCleanRuleCatalog.allowedRootPrefixes.map { prefix in
            prefix.hasPrefix("~/") ? home + String(prefix.dropFirst()) : prefix
        }
    }

    private static func ensureTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }
}
