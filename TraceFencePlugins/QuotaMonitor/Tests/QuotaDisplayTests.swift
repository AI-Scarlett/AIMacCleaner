import XCTest
import MacToolsPluginKit
@testable import QuotaMonitorPlugin

final class QuotaDisplayTests: XCTestCase {
    @MainActor
    func testItemsKeepProviderWindowTitlesAndLowestRemaining() {
        let snapshots = [
            ProviderQuotaSnapshot(
                id: "codex-a",
                providerName: "Codex",
                planName: "Plus",
                accountLabel: nil,
                credits: nil,
                windows: [
                    ProviderQuotaWindow(
                        id: "five",
                        kind: .fiveHour,
                        title: "Current 5h",
                        usedPercent: 28,
                        resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                        windowMinutes: 300
                    ),
                    ProviderQuotaWindow(
                        id: "week",
                        kind: .weekly,
                        title: "Current week (Opus)",
                        usedPercent: 61,
                        resetsAt: nil,
                        windowMinutes: 10_080
                    )
                ],
                resetCredits: nil,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                source: "oauth",
                errorMessage: nil,
                setupHint: nil,
                isSetupNotice: false,
                quotaReadSucceeded: true
            )
        ]

        let items = QuotaDisplay.items(
            from: snapshots,
            localization: PluginLocalization(bundle: Bundle(for: QuotaDisplayTests.self))
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].providerName, "GPT")
        XCTAssertEqual(items[0].metrics.map { $0.title }, ["Current 5h", "Current week (Opus)"])
        XCTAssertEqual(items[0].lowestRemaining, 39)
        XCTAssertEqual(items[0].metrics[0].resetsAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testProviderKeysCoverLocalSourcesWithoutConfusingGeminiAndAntigravity() {
        XCTAssertEqual(QuotaDisplay.providerKey(for: "Claude Code"), "claude")
        XCTAssertEqual(QuotaDisplay.providerKey(for: "Kimi Code"), "kimi")
        XCTAssertEqual(QuotaDisplay.providerKey(for: "Command Code"), "commandcode")
        XCTAssertEqual(QuotaDisplay.providerKey(for: "Google Antigravity"), "antigravity")
        XCTAssertEqual(QuotaDisplay.providerKey(for: "Kiro CLI"), "kiro")
        XCTAssertEqual(QuotaDisplay.providerKey(for: "Factory Droid"), "factory")
        XCTAssertNotEqual(QuotaDisplay.providerKey(for: "GitHub Desktop"), "copilot")
        XCTAssertEqual(QuotaDisplay.sanitizedProviderName("minimax"), "MiniMax")
    }

    @MainActor
    func testDirectDiscoveryAddsLocalCLIProvidersAndStillSkipsBrowserBackedCursor() {
        XCTAssertEqual(ProviderQuotaService.debugQuotaSelfTestFailures(), [])
    }
}
