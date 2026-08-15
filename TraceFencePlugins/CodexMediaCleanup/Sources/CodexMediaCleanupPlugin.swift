import AppKit
import Foundation
import MacToolsPluginKit
import SwiftUI

public final class CodexMediaCleanupPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        CodexMediaCleanupPluginProvider(context: context)
    }
}

@MainActor
private struct CodexMediaCleanupPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        let localization = PluginLocalization(bundle: context.resourceBundle)
        let supportDirectory = context.supportDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TraceFence/Plugins/codex-media-cleanup", isDirectory: true)
        let controller = CodexMediaCleanupController(
            supportDirectory: supportDirectory,
            localization: localization
        )
        return [CodexMediaCleanupPlugin(controller: controller, localization: localization)]
    }
}

@MainActor
final class CodexMediaCleanupPlugin: MacToolsPlugin, PluginPrimaryPanel, PluginSettingsPresenting {
    enum ControlID {
        static let scan = "codex-media-cleanup-scan"
        static let repair = "codex-media-cleanup-repair"
        static let cancel = "codex-media-cleanup-cancel"
        static let openDetails = "codex-media-cleanup-details"
    }

    let metadata: PluginMetadata
    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?
    var requestSettingsPresentation: (() -> Void)?

    private let controller: CodexMediaCleanupController
    private let localization: PluginLocalization
    private var isExpanded = false

    init(controller: CodexMediaCleanupController, localization: PluginLocalization) {
        self.controller = controller
        self.localization = localization
        self.metadata = PluginMetadata(
            id: "codex-media-cleanup",
            title: localization.string("metadata.title", defaultValue: "Codex 媒体整理"),
            iconName: "photo.stack",
            iconTint: Color(nsColor: .systemPurple),
            order: 92,
            defaultDescription: localization.string(
                "metadata.description",
                defaultValue: "清理重复媒体文件，降低磁盘空间占用；修复会话记录中的无效 image_url，避免历史对话出现图片地址格式错误"
            )
        )
        controller.onStateChange = { [weak self] in self?.onStateChange?() }
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: subtitle,
            isOn: controller.snapshot.isBusy,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: isExpanded ? panelDetail : nil,
            errorMessage: controller.snapshot.errorMessage
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    var settingsPage: PluginSettingsPage? {
        let controller = controller
        let localization = localization
        return .workspace(description: metadata.defaultDescription, scrolling: .host) { _ in
            CodexMediaCleanupDetailView(controller: controller, localization: localization)
        }
    }

    func activate(context: PluginRuntimeContext) {}

    func deactivate(reason: PluginDeactivationReason) {
        controller.cancelCurrentOperation()
    }

    func refresh() {}

    func handleAction(_ action: PluginPanelAction) {
        switch action {
        case let .setDisclosureExpanded(value):
            isExpanded = value
            onStateChange?()
        case let .invokeAction(controlID):
            switch controlID {
            case ControlID.scan: controller.scan()
            case ControlID.repair: requestSettingsPresentation?()
            case ControlID.cancel: controller.cancelCurrentOperation()
            case ControlID.openDetails: requestSettingsPresentation?()
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

    private var subtitle: String {
        let snapshot = controller.snapshot
        switch snapshot.phase {
        case .idle: return localization.string("panel.idle", defaultValue: "等待只读扫描")
        case .scanning: return localization.string("panel.scanning", defaultValue: "正在扫描会话…")
        case .waitingForCodex: return localization.string("panel.waiting", defaultValue: "等待 Codex 完全退出")
        case .cleaning: return localization.string("panel.cleaning", defaultValue: "正在备份并清理重复媒体…")
        case .repairing: return localization.string("panel.repairing", defaultValue: "正在备份并修复会话…")
        case .cleaningAndRepairing:
            return localization.string("panel.cleaningAndRepairing", defaultValue: "正在清理并修复…")
        case .completed:
            return localization.string("panel.completed", defaultValue: "处理完成，等待重启验证")
        case .scanned:
            guard let report = snapshot.scanReport else {
                return localization.string("panel.scanned", defaultValue: "扫描完成")
            }
            if report.needsWork {
                return localization.format(
                    "panel.needsRepairFormat",
                    defaultValue: "%lld 个会话需要处理 · 约 %@",
                    Int64(report.affectedFiles),
                    Self.bytes(report.estimatedReclaimableBytes)
                )
            }
            return localization.string("panel.clean", defaultValue: "未发现需要处理的重复媒体")
        }
    }

    private var panelDetail: PluginPanelDetail {
        let snapshot = controller.snapshot
        var controls = [action(
            id: ControlID.scan,
            title: snapshot.phase == .scanning
                ? localization.string("action.scanning", defaultValue: "扫描中…")
                : localization.string("action.scan", defaultValue: "扫描"),
            icon: "magnifyingglass",
            enabled: controller.canScan
        )]
        controls.append(action(
            id: ControlID.repair,
            title: localization.string("action.openRepair", defaultValue: "打开详情选择清理或修复"),
            icon: "arrow.up.right.square",
            enabled: controller.canCleanupAndRepair,
            divider: true
        ))
        if snapshot.isBusy {
            controls.append(action(
                id: ControlID.cancel,
                title: localization.string("action.stop", defaultValue: "停止"),
                icon: "xmark.circle",
                enabled: true,
                divider: true
            ))
        }
        controls.append(action(
            id: ControlID.openDetails,
            title: localization.string("action.openDetails", defaultValue: "打开详情"),
            icon: "arrow.up.right.square",
            enabled: true,
            divider: true,
            behavior: .dismissBeforeHandling
        ))
        return PluginPanelDetail(controls: controls)
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

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
