import XCTest
@testable import MacTools

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testInitialIsEnabledReflectsServiceStatus() {
        let service = FakeLaunchAtLoginService(initialRegistered: true)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertNil(controller.lastErrorMessage)
    }

    func testSetEnabledTrueCallsRegisterAndUpdatesState() {
        let service = FakeLaunchAtLoginService(initialRegistered: false)
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertNil(controller.lastErrorMessage)
    }

    func testSetEnabledFalseCallsUnregisterAndUpdatesState() {
        let service = FakeLaunchAtLoginService(initialRegistered: true)
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(false)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertNil(controller.lastErrorMessage)
    }

    func testSetEnabledNoopWhenAlreadyInDesiredState() {
        let service = FakeLaunchAtLoginService(initialRegistered: true)
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testSetEnabledTrueFailureSetsErrorAndRollsBack() {
        let service = FakeLaunchAtLoginService(initialRegistered: false)
        service.registerError = FakeError.systemRefused
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertNotNil(controller.lastErrorMessage)
    }

    func testSetEnabledFalseFailureSetsErrorAndRollsBack() {
        let service = FakeLaunchAtLoginService(initialRegistered: true)
        service.unregisterError = FakeError.systemRefused
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(false)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertNotNil(controller.lastErrorMessage)
    }

    func testRefreshStatusPicksUpExternalChange() {
        let service = FakeLaunchAtLoginService(initialRegistered: false)
        let controller = LaunchAtLoginController(service: service)

        service.simulateExternalChange(registered: true)
        controller.refreshStatus()

        XCTAssertTrue(controller.isEnabled)
    }

    func testClearErrorRemovesLastErrorMessage() {
        let service = FakeLaunchAtLoginService(initialRegistered: false)
        service.registerError = FakeError.systemRefused
        let controller = LaunchAtLoginController(service: service)
        controller.setEnabled(true)
        XCTAssertNotNil(controller.lastErrorMessage)

        controller.clearError()

        XCTAssertNil(controller.lastErrorMessage)
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    var registerError: Error?
    var unregisterError: Error?
    private var registered: Bool

    init(initialRegistered: Bool) {
        self.registered = initialRegistered
    }

    var isRegistered: Bool { registered }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        registered = true
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        registered = false
    }

    func simulateExternalChange(registered: Bool) {
        self.registered = registered
    }
}

private enum FakeError: Error {
    case systemRefused
}
