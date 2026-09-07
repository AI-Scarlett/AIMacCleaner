import Combine
import XCTest
@testable import QuotaMonitorPlugin

final class QuotaMonitorLifecycleTests: XCTestCase {
    @MainActor
    func testStopDiscardsPendingCallbacksAndDoesNotAccumulateSubscriptions() async {
        let publisher = ObservableObjectPublisher()
        let subscriptions = ProviderQuotaSubscriptions()
        var retiredCallbacks = 0
        subscriptions.observe(publisher) { retiredCallbacks += 1 }
        publisher.send()
        subscriptions.cancel()

        var currentCallbacks = 0
        for expectedCount in 1...3 {
            subscriptions.observe(publisher) { currentCallbacks += 1 }
            publisher.send()
            await drainMainQueue()
            XCTAssertEqual(currentCallbacks, expectedCount)
            subscriptions.cancel()
            publisher.send()
            await drainMainQueue()
            XCTAssertEqual(currentCallbacks, expectedCount)
        }
        XCTAssertEqual(retiredCallbacks, 0, "queued callbacks from a stopped lifecycle must be ignored")
    }

    @MainActor
    func testQuotaReconciliationRegressions() {
        XCTAssertEqual(ProviderQuotaService.debugQuotaSelfTestFailures(), [])
    }

    func testMigrationWorkerHonorsTimeout() async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let succeeded = await Task.detached {
            LegacyBetterTouchToolWidgetCleanup.runProcess(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1
            )
        }.value
        XCTAssertFalse(succeeded)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, 2)
    }

    func testMigrationWorkerHonorsCancellation() async throws {
        let worker = Task.detached {
            LegacyBetterTouchToolWidgetCleanup.runProcess(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 8
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        let startedAt = ProcessInfo.processInfo.systemUptime
        worker.cancel()
        let succeeded = await worker.value
        XCTAssertFalse(succeeded)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, 2)
    }

    func testMigrationWorkerPreservesExitStatus() async {
        let results = await Task.detached {
            ["/usr/bin/true", "/usr/bin/false"].map {
                LegacyBetterTouchToolWidgetCleanup.runProcess(
                    executable: URL(fileURLWithPath: $0), arguments: [], timeout: 2
                )
            }
        }.value
        XCTAssertEqual(results, [true, false])
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
