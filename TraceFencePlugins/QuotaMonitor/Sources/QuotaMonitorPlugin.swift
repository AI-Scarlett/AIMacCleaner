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
        return [QuotaMonitorPlugin(
            engineURL: engineURL,
            localization: localization,
            touchBarExporter: TouchBarQuotaSnapshotExporter()
        )]
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
    private let touchBarExporter: TouchBarQuotaSnapshotExporter
    private var serviceChangeCancellable: AnyCancellable?
    private var isExpanded = false
    private var isActive = false

    fileprivate init(
        engineURL: URL?,
        localization: PluginLocalization,
        touchBarExporter: TouchBarQuotaSnapshotExporter
    ) {
        self.service = ProviderQuotaService(
            providerEngineURL: engineURL,
            requiresExplicitProviderEngine: true
        )
        self.localization = localization
        self.touchBarExporter = touchBarExporter
        self.metadata = Self.makeMetadata(localization: localization)
        serviceChangeCancellable = service.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.exportTouchBarSnapshot()
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

    func activate(context: PluginRuntimeContext) {
        isActive = true
        exportTouchBarSnapshot()
    }

    func deactivate(reason: PluginDeactivationReason) {
        isActive = false
        service.stop()
        touchBarExporter.removeSnapshot()
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

    private func exportTouchBarSnapshot() {
        guard isActive else { return }
        touchBarExporter.writeSnapshot(
            snapshots: service.snapshots,
            isRefreshing: service.isRefreshing,
            lastRefreshDate: service.lastRefreshDate
        )
    }
}

/// Exposes only display-safe quota data for a local BetterTouchTool widget.
/// The file deliberately excludes account labels, plans, credits, credential
/// sources, diagnostic strings, tokens, cookies and provider identifiers.
private struct TouchBarQuotaSnapshotExporter {
    private static let directoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TraceFence/TouchBar", isDirectory: true)
    private static let snapshotURL = directoryURL.appendingPathComponent("quota-status.json", isDirectory: false)

    private struct Snapshot: Encodable {
        let schemaVersion = 1
        let updatedAt: Date
        let isRefreshing: Bool
        let lastRefreshAt: Date?
        let providers: [Provider]
    }

    private struct Provider: Encodable {
        let name: String
        let freshness: String
        let windows: [Window]
    }

    private struct Window: Encodable {
        let kind: String
        let remainingPercent: Int
        let resetsAt: Date?
    }

    func writeSnapshot(
        snapshots: [ProviderQuotaSnapshot],
        isRefreshing: Bool,
        lastRefreshDate: Date?
    ) {
        let providers = snapshots.compactMap { snapshot -> Provider? in
            guard !snapshot.isSetupNotice else { return nil }
            let windows = snapshot.windows.map { window in
                Window(
                    kind: window.kind.rawValue,
                    remainingPercent: Int(window.remainingPercent.rounded()),
                    resetsAt: window.resetsAt
                )
            }
            guard !windows.isEmpty else { return nil }
            return Provider(
                name: sanitizedProviderName(snapshot.providerName),
                freshness: snapshot.freshness.rawValue,
                windows: windows
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let payload = Snapshot(
            updatedAt: Date(),
            isRefreshing: isRefreshing,
            lastRefreshAt: lastRefreshDate,
            providers: providers
        )
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: Self.directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.directoryURL.path)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(payload).write(to: Self.snapshotURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.snapshotURL.path)
        } catch {
            // The BTT surface is strictly optional; quota monitoring continues
            // normally if a local display export cannot be written.
        }
    }

    func removeSnapshot() {
        try? FileManager.default.removeItem(at: Self.snapshotURL)
    }

    private func sanitizedProviderName(_ value: String) -> String {
        let normalized = value.lowercased()
        if normalized.contains("codex") { return "Codex" }
        if normalized.contains("claude") { return "Claude" }
        if normalized.contains("grok") { return "Grok" }
        if normalized.contains("cursor") { return "Cursor" }
        if normalized.contains("gemini") { return "Gemini" }
        if normalized.contains("deepseek") { return "DeepSeek" }
        if normalized.contains("antigravity") { return "Antigravity" }
        return "Provider"
    }
}
