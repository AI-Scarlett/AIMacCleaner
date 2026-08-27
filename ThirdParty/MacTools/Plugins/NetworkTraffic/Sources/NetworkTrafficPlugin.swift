import AppKit
import Foundation
import SwiftUI
import MacToolsPluginKit

public final class NetworkTrafficPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        NetworkTrafficPluginProvider(context: context)
    }
}

@MainActor
private struct NetworkTrafficPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [NetworkTrafficPlugin(context: context)]
    }
}

@MainActor
final class NetworkTrafficPlugin: MacToolsPlugin, PluginPrimaryPanel, PluginSettingsPresenting {
    private enum ControlID {
        static let open = "execute"
    }

    let metadata: PluginMetadata
    let primaryPanelDescriptor: PluginPrimaryPanelDescriptor
    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?
    var requestSettingsPresentation: (() -> Void)?

    private let viewModel: NetworkTrafficViewModel
    private let localization: PluginLocalization

    init(
        context: PluginRuntimeContext = PluginRuntimeContext(pluginID: "network-traffic"),
        viewModel: NetworkTrafficViewModel? = nil,
        localization: PluginLocalization? = nil
    ) {
        let localization = localization ?? PluginLocalization(bundle: context.resourceBundle)
        self.localization = localization
        self.viewModel = viewModel ?? NetworkTrafficViewModel(storage: context.storage)
        self.metadata = PluginMetadata(
            id: "network-traffic",
            title: localization.string("metadata.title", defaultValue: "网络流量监控"),
            iconName: "waveform.path.ecg.rectangle",
            iconTint: Color(nsColor: .systemTeal),
            order: 13,
            defaultDescription: localization.string(
                "metadata.description",
                defaultValue: "按网卡、进程、连接和协议查看实时网络流量"
            )
        )
        self.primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
            controlStyle: .button,
            menuActionBehavior: .dismissBeforeHandling,
            buttonTitleProvider: {
                localization.string("panel.open", defaultValue: "打开")
            }
        )
        self.viewModel.onStateChange = { [weak self] in self?.onStateChange?() }
    }

    func activate(context: PluginRuntimeContext) {
        viewModel.refreshInterfaces()
    }

    func deactivate(reason: PluginDeactivationReason) {
        viewModel.stopCapture()
    }

    func refresh() {
        viewModel.refreshInterfaces()
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: panelSubtitle,
            isOn: viewModel.isRunning,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: nil,
            errorMessage: viewModel.lastError
        )
    }

    var settingsPage: PluginSettingsPage? {
        .workspace(description: metadata.defaultDescription, scrolling: .selfManaged) { _ in
            NetworkTrafficDashboardView(viewModel: self.viewModel, localization: self.localization)
        }
    }

    func handleAction(_ action: PluginPanelAction) {
        guard case let .invokeAction(controlID) = action, controlID == ControlID.open else { return }
        requestSettingsPresentation?()
    }

    private var panelSubtitle: String {
        if viewModel.isRunning {
            return "↓ \(NetworkTrafficFormatter.speed(viewModel.currentReceivedRate))  ↑ \(NetworkTrafficFormatter.speed(viewModel.currentSentRate))"
        }
        if case .importing = viewModel.captureState {
            return localization.string("panel.importing", defaultValue: "正在分析 PCAP…")
        }
        return localization.string("panel.ready", defaultValue: "安全连接监控与 PCAP 分析")
    }
}
