import AppKit
import Combine
import Foundation
import MacToolsPluginKit
import SwiftUI

public final class AgentProfilePluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        AgentProfilePluginProvider(context: context)
    }
}

@MainActor
private struct AgentProfilePluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        let localization = PluginLocalization(bundle: context.resourceBundle)
        let controller = AgentProfileController(context: context)
        return [AgentProfilePlugin(controller: controller, localization: localization)]
    }
}

@MainActor
final class AgentProfilePlugin: MacToolsPlugin, PluginPrimaryPanel,
    PluginSettingsPresenting, PluginRuntimeLocalizationRefreshing {
    private enum ControlID {
        static let diagnose = "agent-profile-diagnose"
        static let openSettings = "agent-profile-open-settings"
        static let generate = "agent-profile-generate"
    }

    private(set) var metadata: PluginMetadata
    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?
    var requestSettingsPresentation: (() -> Void)?

    private let controller: AgentProfileController
    private let localization: PluginLocalization
    private var isExpanded = false
    private var controllerCancellable: AnyCancellable?

    init(controller: AgentProfileController, localization: PluginLocalization) {
        self.controller = controller
        self.localization = localization
        self.metadata = Self.makeMetadata(localization: localization)
        controllerCancellable = controller.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.onStateChange?() }
        }
    }

    private static func makeMetadata(localization: PluginLocalization) -> PluginMetadata {
        PluginMetadata(
            id: "agent-profile",
            title: localization.string("metadata.title", defaultValue: "Agent 画像"),
            iconName: "globe.badge.chevron.backward",
            iconTint: Color(nsColor: .systemIndigo),
            order: 42,
            defaultDescription: localization.string(
                "metadata.description",
                defaultValue: "管理 Agent 的语言、时区和代理出口，并区分网络画像与 Provider 账号资格。"
            )
        )
    }

    func refreshLocalization() {
        metadata = Self.makeMetadata(localization: localization)
        onStateChange?()
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: panelSubtitle,
            isOn: controller.configuration.enabled,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: isExpanded ? panelDetail : nil,
            errorMessage: controller.diagnostic.status == .sameAsDirect
                ? localization.string("panel.sameEgressError", defaultValue: "代理出口与直连相同，不能标记为已保护。")
                : nil
        )
    }

    var settingsPage: PluginSettingsPage? {
        let controller = controller
        let localization = localization
        return .workspace(description: metadata.defaultDescription, scrolling: .host) { _ in
            AgentProfileSettingsView(controller: controller, localization: localization)
        }
    }

    func activate(context: PluginRuntimeContext) {
        if controller.configuration.enabled && controller.lastGeneratedAssets == nil {
            controller.generateAssets()
        }
    }

    func deactivate(reason: PluginDeactivationReason) {
        controller.cancelDiagnostics()
    }

    func refresh() {
        controller.runDiagnostics()
    }

    func handleAction(_ action: PluginPanelAction) {
        switch action {
        case let .setDisclosureExpanded(value):
            isExpanded = value
            onStateChange?()
        case let .invokeAction(controlID):
            switch controlID {
            case ControlID.diagnose: controller.runDiagnostics()
            case ControlID.openSettings: requestSettingsPresentation?()
            case ControlID.generate: controller.generateAssets()
            default: break
            }
        case .setSwitch, .setSelection, .setNavigationSelection,
             .clearNavigationSelection, .setDate, .setSlider:
            break
        }
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(_ action: PluginSettingsAction) {}
    func handleShortcutAction(id: String) {}

    private var panelSubtitle: String {
        if controller.isDiagnosing {
            return localization.string("panel.diagnosing", defaultValue: "正在核对直连与代理出口…")
        }
        switch controller.diagnostic.status {
        case .notTested:
            return localization.string("panel.notTested", defaultValue: "尚未检测；账号资格由 Provider 决定")
        case .proxyDisabled:
            return localization.string("panel.proxyDisabled", defaultValue: "未启用代理路由")
        case .proxyInvalid:
            return localization.string("panel.proxyInvalid", defaultValue: "代理地址无效")
        case .proxyUnavailable:
            return localization.string("panel.proxyUnavailable", defaultValue: "代理出口不可用")
        case .sameAsDirect:
            return localization.string("panel.sameEgress", defaultValue: "代理与直连出口相同")
        case .routed:
            return localization.string("panel.routed", defaultValue: "代理出口已切换 · 账号资格未推断")
        }
    }

    private var panelDetail: PluginPanelDetail {
        PluginPanelDetail(controls: [
            action(
                id: ControlID.diagnose,
                title: controller.isDiagnosing
                    ? localization.string("action.diagnosing", defaultValue: "检测中…")
                    : localization.string("action.diagnose", defaultValue: "检测网络画像"),
                icon: "network.badge.shield.half.filled",
                enabled: !controller.isDiagnosing
            ),
            action(
                id: ControlID.generate,
                title: localization.string("action.generate", defaultValue: "生成独立画像"),
                icon: "wand.and.stars",
                enabled: !controller.isGenerating,
                divider: true
            ),
            action(
                id: ControlID.openSettings,
                title: localization.string("action.open", defaultValue: "打开 Agent 画像"),
                icon: "arrow.up.right.square",
                enabled: true,
                divider: true,
                behavior: .dismissBeforeHandling
            )
        ])
    }

    private func action(
        id: String,
        title: String,
        icon: String,
        enabled: Bool,
        divider: Bool = false,
        behavior: PluginMenuActionBehavior = .keepPresented
    ) -> PluginPanelControl {
        PluginPanelControl(
            id: id,
            kind: .actionRow,
            options: [],
            selectedOptionID: nil,
            dateValue: nil,
            minimumDate: nil,
            displayedComponents: nil,
            datePickerStyle: nil,
            sectionTitle: nil,
            actionTitle: title,
            actionIconSystemName: icon,
            actionBehavior: behavior,
            showsLeadingDivider: divider,
            isEnabled: enabled
        )
    }
}
