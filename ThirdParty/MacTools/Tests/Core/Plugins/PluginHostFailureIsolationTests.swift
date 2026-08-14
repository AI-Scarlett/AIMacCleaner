import AppKit
import SwiftUI
import XCTest
import MacToolsPluginKit
@testable import MacTools

@MainActor
final class PluginHostFailureIsolationTests: XCTestCase {
    func testPanelStateExceptionIsolatesFailingPluginAndKeepsHealthyPlugin() {
        let failingPlugin = ExceptionPrimaryPlugin(id: "bad", failurePoint: .panelState)
        let healthyPlugin = ExceptionPrimaryPlugin(id: "good", order: 2)
        let host = makePluginHostForTests(
            plugins: [failingPlugin, healthyPlugin],
            suiteName: "PluginHostFailureIsolationTests-state"
        )

        XCTAssertEqual(host.panelItems.map(\.id), ["good"])
        XCTAssertEqual(host.featureManagementItems.map(\.id), ["good"])
        XCTAssertEqual(failingPlugin.deactivationReasons, [.disabled])
    }

    func testActionExceptionIsolatesPluginAndStopsFutureCalls() {
        let plugin = ExceptionPrimaryPlugin(id: "bad", failurePoint: .action)
        let host = makePluginHostForTests(
            plugins: [plugin],
            suiteName: "PluginHostFailureIsolationTests-action"
        )

        XCTAssertEqual(host.panelItems.map(\.id), ["bad"])

        host.setSwitchValue(true, for: "bad")

        XCTAssertTrue(host.panelItems.isEmpty)
        XCTAssertTrue(host.featureManagementItems.isEmpty)
        XCTAssertEqual(plugin.handleActionCallCount, 1)
        XCTAssertEqual(plugin.deactivationReasons, [.disabled])

        host.setSwitchValue(false, for: "bad")

        XCTAssertEqual(plugin.handleActionCallCount, 1)
    }
}

@MainActor
private final class ExceptionPrimaryPlugin: MacToolsPlugin, PluginPrimaryPanel {
    enum FailurePoint {
        case action
        case panelState
    }

    let metadata: PluginMetadata
    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .switch,
        menuActionBehavior: .keepPresented
    )
    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?
    private let failurePoint: FailurePoint?
    private(set) var handleActionCallCount = 0
    private(set) var deactivationReasons: [PluginDeactivationReason] = []

    init(id: String, order: Int = 1, failurePoint: FailurePoint? = nil) {
        self.metadata = PluginMetadata(
            id: id,
            title: id,
            iconName: "sparkles",
            iconTint: Color(nsColor: .systemRed),
            order: order,
            defaultDescription: "Failure isolation \(id)"
        )
        self.failurePoint = failurePoint
    }

    var primaryPanelState: PluginPanelState {
        if failurePoint == .panelState {
            raiseTestPluginException(reason: "panel state failed")
        }

        return PluginPanelState(
            subtitle: "Ready",
            isOn: false,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: nil,
            errorMessage: nil
        )
    }

    func handleAction(_ action: PluginPanelAction) {
        handleActionCallCount += 1

        if failurePoint == .action {
            raiseTestPluginException(reason: "action failed")
        }
    }

    func deactivate(reason: PluginDeactivationReason) {
        deactivationReasons.append(reason)
    }
}
