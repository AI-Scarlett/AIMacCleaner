import Foundation
import XCTest
@testable import MacTools

@MainActor
final class PluginInvocationGuardTests: XCTestCase {
    func testRunCatchesObjectiveCException() {
        let result = PluginInvocationGuard.run(operation: "test exception") {
            raiseTestPluginException(reason: "boom")
        }

        switch result {
        case .success:
            XCTFail("Expected Objective-C exception to be caught")
        case let .failure(.objectiveCException(name, reason)):
            XCTAssertEqual(name, "TestPluginException")
            XCTAssertEqual(reason, "boom")
        case let .failure(failure):
            XCTFail("Unexpected failure: \(failure.localizedDescription)")
        }
    }
}

func raiseTestPluginException(reason: String) {
    NSException(
        name: NSExceptionName("TestPluginException"),
        reason: reason,
        userInfo: nil
    ).raise()
}
