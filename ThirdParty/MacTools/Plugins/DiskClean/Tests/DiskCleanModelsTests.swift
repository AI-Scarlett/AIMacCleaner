import XCTest
@testable import MacTools
@testable import DiskCleanPlugin
import MacToolsPluginKit

final class DiskCleanModelsTests: XCTestCase {
    func testExternalTargetsHaveNoPanelChoice() {
        let external = DiskCleanRuleCatalogV2.current.targets.filter(\.isExternallyDiscovered)
        XCTAssertFalse(external.isEmpty)
        for target in external {
            XCTAssertNil(
                DiskCleanChoice(legacyRuleID: target.legacyRuleID),
                "P2 target \(target.id) must not have a panel mapping, or regular scans would include it"
            )
        }
    }

    /// Category cannot replace legacy prefix for scope: some targets have category and panel
    /// from different sources (`browser.service-worker.editors` is developer category;
    /// `aiTools` spans both cache.* and developer.*).
    func testCandidateWithoutSizeResultIsNotCleanable() {
        XCTAssertFalse(makeCandidate(sizeResult: nil).isCleanable)
    }

    func testCandidateWithPartialSizeIsNotCleanable() {
        let reasons: [DiskCleanScanCompleteness.PartialReason] = [
            .timedOut, .permissionDenied, .unsupportedVolume, .crossedMountPoint, .walkError
        ]
        for reason in reasons {
            XCTAssertFalse(
                makeCandidate(sizeResult: .testPartial(reasons: [reason], identity: .test())).isCleanable,
                "partial(\(reason)) candidates are not cleanable"
            )
        }
    }

    func testCandidateWithoutRootIdentityIsNotCleanable() {
        let result = DiskCleanSizeResult(
            estimatedBytes: 100,
            fileCount: 1,
            completeness: .complete,
            rootIdentity: nil,
            observedAt: Date()
        )

        XCTAssertFalse(makeCandidate(sizeResult: result).isCleanable)
    }

    func testCandidateWithBlockedSafetyIsNotCleanable() {
        XCTAssertFalse(
            makeCandidate(safety: .inUse(processName: "Docker"), sizeResult: .testComplete()).isCleanable
        )
    }

    func testCompleteAndAllowedCandidateIsCleanable() {
        XCTAssertTrue(makeCandidate(sizeResult: .testComplete()).isCleanable)
    }

    func testCompleteZeroAllocationCandidateIsNotCleanable() {
        XCTAssertFalse(makeCandidate(sizeResult: .testComplete(bytes: 0)).isCleanable)
    }

    func testCompleteZeroAllocationCandidateIsHiddenFromCleanupReview() {
        let groups = DiskCleanCategoryGroup.groups(
            candidates: [makeCandidate(sizeResult: .testComplete(bytes: 0))],
            selection: .empty
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testCategoryGroupKeepsCleanableTotalWhenNothingIsSelected() throws {
        let candidate = makeCandidate(sizeResult: .testComplete(bytes: 168_200_000))
        let selection = DiskCleanSelectionProjection(
            selectedIDs: [],
            selectableIDs: [candidate.id],
            selectedEstimatedBytes: 0,
            categoryStates: [.appCaches: .noneSelected]
        )

        let group = try XCTUnwrap(DiskCleanCategoryGroup.groups(
            candidates: [candidate],
            selection: selection
        ).first)

        XCTAssertEqual(group.selectableCount, 1)
        XCTAssertEqual(group.selectedCount, 0)
        XCTAssertEqual(group.cleanableEstimatedBytes, 168_200_000)
        XCTAssertEqual(group.selectedEstimatedBytes, 0)
    }

    func testSelectionSummarySeparatesCleanableAndSelectedBytes() {
        let candidate = makeCandidate(sizeResult: .testComplete(bytes: 168_200_000))
        let result = DiskCleanScanResult(
            scope: .installers,
            candidates: [candidate],
            scannedAt: Date(timeIntervalSince1970: 0)
        )
        let selection = DiskCleanSelectionProjection(
            selectedIDs: [],
            selectableIDs: [candidate.id],
            selectedEstimatedBytes: 0,
            categoryStates: [.appCaches: .noneSelected]
        )
        let snapshot = DiskCleanControllerSnapshot(
            phase: .scanned,
            scope: .installers,
            scanResult: result,
            executionResult: nil,
            isResultStale: false,
            errorMessage: nil,
            selection: selection
        )

        let summary = DiskCleanFormat.selectionSummary(
            snapshot,
            localization: PluginLocalization(bundle: .main)
        )

        XCTAssertTrue(summary.contains(DiskCleanFormat.bytes(168_200_000)))
        XCTAssertTrue(summary.contains("0 B"))
        XCTAssertFalse(summary.contains("Zero KB"))
    }

    func testZeroBytesUsesStableNumericLabel() {
        XCTAssertEqual(DiskCleanFormat.bytes(0), "0 B")
    }

    // MARK: - Scan result projection

    func testScanResultTotalsOnlyCleanableCandidates() {
        let result = DiskCleanScanResult(
            scope: .rules(choices: [.cache]),
            candidates: [
                makeCandidate(id: "a", path: "/tmp/a", sizeResult: .testComplete(bytes: 10)),
                makeCandidate(
                    id: "b",
                    path: "/tmp/b",
                    safety: .protected(reason: "protected"),
                    sizeResult: .testComplete(bytes: 20)
                ),
                makeCandidate(id: "c", path: "/tmp/c", sizeResult: nil)
            ],
            scannedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(result.cleanableSizeBytes, 10)
        XCTAssertEqual(result.cleanableCandidates.map(\.id), ["a"])
    }

    func testExpiryDeadlineIsNilWithoutCleanableCandidates() {
        let result = DiskCleanScanResult(
            scope: .rules(choices: [.cache]),
            candidates: [makeCandidate(sizeResult: nil)],
            scannedAt: Date()
        )

        XCTAssertNil(result.expiryDeadline)
    }

    func testExpiryDeadlineUsesCompletedScanTime() {
        let base = Date(timeIntervalSince1970: 10_000)
        let result = DiskCleanScanResult(
            scope: .rules(choices: [.cache]),
            candidates: [
                makeCandidate(id: "a", path: "/tmp/a", sizeResult: .testComplete(observedAt: base)),
                makeCandidate(
                    id: "b",
                    path: "/tmp/b",
                    sizeResult: .testComplete(observedAt: base.addingTimeInterval(60))
                )
            ],
            scannedAt: base.addingTimeInterval(120)
        )

        XCTAssertEqual(
            result.expiryDeadline,
            base.addingTimeInterval(120 + DiskCleanScanFreshness.window)
        )
    }

    private func makeCandidate(
        id: String = "a",
        path: String = "/tmp/a",
        safety: DiskCleanSafetyStatus = .allowed,
        sizeResult: DiskCleanSizeResult?
    ) -> DiskCleanCandidate {
        DiskCleanCandidate(
            id: id,
            targetID: "cache.test",
            legacyRuleID: "cache.test",
            category: .appCaches,
            path: path,
            risk: .low,
            safety: safety,
            sizeResult: sizeResult
        )
    }
}
