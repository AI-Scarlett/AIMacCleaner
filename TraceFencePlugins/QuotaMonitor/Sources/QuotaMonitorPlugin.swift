import Combine
import Foundation
import MacToolsPluginKit
import SwiftUI

public final class QuotaMonitorPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        QuotaMonitorPluginProvider(context: context)
    }
}

@MainActor
private struct QuotaMonitorPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        let localization = PluginLocalization(bundle: context.resourceBundle)
        let engineURL = context.resourceBundle.url(
            forResource: "codexbar",
            withExtension: nil,
            subdirectory: "Helpers"
        )
        return [QuotaMonitorPlugin(engineURL: engineURL, localization: localization)]
    }
}

@MainActor
final class QuotaMonitorPlugin: MacToolsPlugin, PluginPrimaryPanel,
    PluginQuotaMonitoring, PluginRuntimeLocalizationRefreshing {
    private enum ControlID {
        static let refresh = "quota-monitor-refresh"
    }

    private(set) var metadata: PluginMetadata
    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let service: ProviderQuotaService
    private let localization: PluginLocalization
    private var serviceChangeCancellable: AnyCancellable?
    private var isExpanded = false

    init(engineURL: URL?, localization: PluginLocalization) {
        self.service = ProviderQuotaService(
            providerEngineURL: engineURL,
            requiresExplicitProviderEngine: true
        )
        self.localization = localization
        self.metadata = Self.makeMetadata(localization: localization)
        serviceChangeCancellable = service.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.onStateChange?()
            }
        }
    }

    private static func makeMetadata(localization: PluginLocalization) -> PluginMetadata {
        PluginMetadata(
            id: "quota-monitor",
            title: localization.string("metadata.title", defaultValue: "额度监控"),
            iconName: "waveform.path.ecg.rectangle",
            iconTint: Color(nsColor: .systemBlue),
            order: 30,
            defaultDescription: localization.string(
                "metadata.description",
                defaultValue: "读取 Codex、Claude、Grok 等 Provider 的额度与重置时间；菜单栏界面由 TraceFence 保持不变。"
            )
        )
    }

    func refreshLocalization() {
        metadata = Self.makeMetadata(localization: localization)
        onStateChange?()
    }

    var primaryPanelState: PluginPanelState {
        let readable = service.snapshots.filter(\.quotaReadSucceeded)
        let subtitle: String
        if service.isRefreshing {
            subtitle = localization.string("panel.refreshing", defaultValue: "正在读取 Provider 额度…")
        } else if let summary = service.menuBarSummary {
            subtitle = summary
        } else if readable.isEmpty {
            subtitle = localization.string("panel.waiting", defaultValue: "等待首次额度读取")
        } else {
            subtitle = localization.format(
                "panel.providersFormat",
                defaultValue: "%lld 个 Provider 已更新",
                Int64(readable.count)
            )
        }

        let detail = isExpanded ? PluginPanelDetail(controls: [
            PluginPanelControl(
                id: ControlID.refresh,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: service.isRefreshing
                    ? localization.string("action.refreshing", defaultValue: "刷新中…")
                    : localization.string("action.refresh", defaultValue: "刷新额度"),
                actionIconSystemName: "arrow.clockwise",
                isEnabled: !service.isRefreshing && service.refreshCooldownRemaining() <= 0
            )
        ]) : nil

        return PluginPanelState(
            subtitle: subtitle,
            isOn: service.isRefreshing,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: detail,
            errorMessage: nil
        )
    }

    func activate(context: PluginRuntimeContext) {}

    func deactivate(reason: PluginDeactivationReason) {
        service.stop()
    }

    func refresh() {
        service.refresh()
    }

    func handleAction(_ action: PluginPanelAction) {
        switch action {
        case let .setDisclosureExpanded(value):
            isExpanded = value
            onStateChange?()
        case let .invokeAction(controlID) where controlID == ControlID.refresh:
            service.refresh(force: true)
        case .invokeAction, .setSwitch, .setSelection, .setNavigationSelection,
             .clearNavigationSelection, .setDate, .setSlider:
            break
        }
    }

    var quotaSnapshotPayload: Data? {
        try? JSONEncoder().encode(service.snapshots)
    }

    var quotaMonitoringIsRefreshing: Bool { service.isRefreshing }
    var quotaMonitoringLastRefreshDate: Date? { service.lastRefreshDate }
    var quotaMonitoringLastRefreshRequestedDate: Date? { service.lastRefreshRequestedDate }

    func startQuotaMonitoring() {
        service.start()
    }

    func stopQuotaMonitoring() {
        service.stop()
    }

    func refreshQuotaMonitoring(force: Bool) {
        service.refresh(force: force)
    }

    func quotaMonitoringRefreshCooldownRemaining() -> TimeInterval {
        service.refreshCooldownRemaining()
    }
}
