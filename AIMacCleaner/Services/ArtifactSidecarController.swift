import AppKit
import ApplicationServices
import QuickLookUI
import SwiftUI
import WebKit

/// A TraceFence-owned companion shelf that follows the foreground agent window.
///
/// The panel deliberately renders previews itself. It never asks Finder (or the
/// agent host) to open a target, which keeps the user in the current task.
@MainActor
final class ArtifactSidecarController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ArtifactSidecarController()

    static let enabledDefaultsKey = "artifactSidecarEnabled"
    private static let collapsedDefaultsKey = "artifactSidecarCollapsed"
    private static let compactSize = NSSize(width: 92, height: 52)
    private static let defaultExpandedSize = NSSize(width: 390, height: 720)

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isCollapsed: Bool
    @Published private(set) var isFollowPaused = false
    @Published private(set) var hasAccessibilityPermission = AXIsProcessTrusted()

    private static let supportedAgentBundleIDs: Set<String> = [
        "com.openai.codex",
        "com.anthropic.claudefordesktop",
        "com.todesktop.230313mzl4w4u92"
    ]

    private let traceFenceBundleID = Bundle.main.bundleIdentifier ?? SandboxPaths.directDistributionBundleID
    private let shelf = ArtifactShelfService.shared
    private var panel: ArtifactSidecarPanel?
    private var pollTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isStarted = false
    private var expandedPanelSize = ArtifactSidecarController.defaultExpandedSize
    private var lastAgentPID: pid_t?
    private var lastAnchorFrame: NSRect?
    private var lastFocusedTaskSignature: String?
    private var isPreviewActive = false
    private var isPreviewPauseApplied = false
    private var cachedFocusedTaskPID: pid_t?
    private var cachedFocusedTaskButton: AXUIElement?
    private var cachedFocusedTaskRow: AXUIElement?
    private var cachedFocusedTaskProjectHint: String?

    private override init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.enabledDefaultsKey) == nil {
            defaults.set(SandboxPaths.isDirectDistribution, forKey: Self.enabledDefaultsKey)
        }
        if defaults.object(forKey: Self.collapsedDefaultsKey) == nil {
            defaults.set(true, forKey: Self.collapsedDefaultsKey)
        }
        isEnabled = SandboxPaths.isDirectDistribution && defaults.bool(forKey: Self.enabledDefaultsKey)
        isCollapsed = defaults.bool(forKey: Self.collapsedDefaultsKey)
        super.init()
    }

    /// Starts foreground-window tracking when the persisted switch is enabled.
    func start() {
        guard SandboxPaths.isDirectDistribution, isEnabled, !isStarted else { return }
        isStarted = true
        shelf.start(for: .sidecar)
        installWorkspaceObservers()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateAttachment() }
        }
        RunLoop.main.add(timer, forMode: .default)
        pollTimer = timer
        updateAttachment(forceShow: true)
    }

    /// Stops tracking and hides the panel without changing the saved switch.
    func stop() {
        isStarted = false
        pollTimer?.invalidate()
        pollTimer = nil
        removeWorkspaceObservers()
        hidePanel()
        clearFocusedTaskCache()
        shelf.stop(for: .sidecar)
    }

    func setEnabled(_ enabled: Bool) {
        let nextValue = SandboxPaths.isDirectDistribution && enabled
        guard isEnabled != nextValue else {
            if nextValue { start() }
            return
        }
        isEnabled = nextValue
        UserDefaults.standard.set(nextValue, forKey: Self.enabledDefaultsKey)
        if nextValue {
            start()
        } else {
            stop()
        }
    }

    func toggleEnabled() {
        setEnabled(!isEnabled)
    }

    /// Makes the sidecar visible at its most recent agent anchor, if available.
    func showNow() {
        guard isEnabled else { return }
        if !isStarted { start() }
        setCollapsed(false)
        updateAttachment(forceShow: true)
    }

    /// The close affordance becomes a compact floating capsule instead of
    /// making the shelf disappear completely.
    func closePanel() {
        setCollapsed(true)
    }

    func expandPanel() {
        setCollapsed(false)
    }

    func setCollapsed(_ collapsed: Bool) {
        guard isCollapsed != collapsed else {
            if isEnabled { updateAttachment(forceShow: true) }
            return
        }
        if collapsed, let panel {
            expandedPanelSize = panel.frame.size
        }
        isCollapsed = collapsed
        UserDefaults.standard.set(collapsed, forKey: Self.collapsedDefaultsKey)
        if let panel {
            configureSize(of: panel)
        }
        updateAttachment(forceShow: true)
    }

    func toggleFollowPaused() {
        setFollowPaused(!isFollowPaused)
    }

    func setFollowPaused(_ paused: Bool) {
        guard isFollowPaused != paused else {
            if paused { shelf.setManualSelectionLocked(true) }
            return
        }
        isFollowPaused = paused
        shelf.setManualSelectionLocked(paused)
        if !paused {
            lastFocusedTaskSignature = nil
            refreshFocusFromLastAgent()
            updateAttachment(forceShow: true)
        }
    }

    func setPreviewActive(_ active: Bool) {
        guard isPreviewActive != active else { return }
        isPreviewActive = active
        applyPreviewPause(active)
        if !active, isStarted {
            clearFocusedTaskCache()
            updateAttachment(forceShow: true)
        }
    }

    private func applyPreviewPause(_ paused: Bool) {
        guard isPreviewPauseApplied != paused else { return }
        isPreviewPauseApplied = paused
        shelf.setAutomaticRefreshPaused(paused, for: .sidecar)
    }

    private func hidePanel() {
        applyPreviewPause(false)
        panel?.orderOut(nil)
    }

    private func refreshFocusFromLastAgent() {
        guard let lastAgentPID,
              let application = NSRunningApplication(processIdentifier: lastAgentPID),
              let bundleID = application.bundleIdentifier,
              Self.supportedAgentBundleIDs.contains(bundleID) else { return }
        if let frame = mainWindowFrame(for: lastAgentPID) {
            lastAnchorFrame = frame
        }
        let focusedTask = focusedTaskInAgent(pid: lastAgentPID)
        shelf.focusTask(
            title: focusedTask?.title,
            projectHint: focusedTask?.projectHint,
            bundleIdentifier: bundleID
        )
        lastFocusedTaskSignature = [
            bundleID,
            focusedTask?.title ?? "",
            focusedTask?.projectHint ?? ""
        ].joined(separator: "|")
    }

    /// Requests the standard macOS Accessibility grant used for exact task-title matching.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closePanel()
        return false
    }

    private func installWorkspaceObservers() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateAttachment() }
            }
        }
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
    }

    private func makePanelIfNeeded() -> ArtifactSidecarPanel {
        if let panel { return panel }

        let initialSize = isCollapsed ? Self.compactSize : Self.defaultExpandedSize
        let panel = ArtifactSidecarPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.title = "TraceFence Task Artifacts"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = ArtifactSidecarRootView(controller: self, shelf: shelf)
        panel.contentView = NSHostingView(rootView: rootView)
        configureSize(of: panel)
        self.panel = panel
        return panel
    }

    private func configureSize(of panel: NSPanel) {
        if isCollapsed {
            panel.contentMinSize = Self.compactSize
            panel.contentMaxSize = Self.compactSize
            panel.setContentSize(Self.compactSize)
        } else {
            panel.contentMinSize = NSSize(width: 330, height: 430)
            panel.contentMaxSize = NSSize(width: 560, height: 1_400)
            let visible = NSScreen.main?.visibleFrame.size ?? expandedPanelSize
            let size = NSSize(
                width: min(max(expandedPanelSize.width, 330), min(560, visible.width)),
                height: min(max(expandedPanelSize.height, 430), min(1_400, visible.height))
            )
            panel.setContentSize(size)
        }
    }

    private func updateAttachment(forceShow: Bool = false) {
        guard isStarted, isEnabled else { return }
        let accessibilityPermission = AXIsProcessTrusted()
        if hasAccessibilityPermission != accessibilityPermission {
            hasAccessibilityPermission = accessibilityPermission
            if accessibilityPermission { lastFocusedTaskSignature = nil }
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontBundleID = frontmost?.bundleIdentifier

        if let frontmost,
           let bundleID = frontBundleID,
           Self.supportedAgentBundleIDs.contains(bundleID) {
            if lastAgentPID != frontmost.processIdentifier {
                clearFocusedTaskCache()
            }
            lastAgentPID = frontmost.processIdentifier

            if !isFollowPaused, !isPreviewActive {
                if let frame = mainWindowFrame(for: frontmost.processIdentifier) {
                    lastAnchorFrame = frame
                }
                let focusedTask = focusedTaskInAgent(pid: frontmost.processIdentifier)
                let focusSignature = [bundleID, focusedTask?.title ?? "", focusedTask?.projectHint ?? ""].joined(separator: "|")
                // Refresh the service's short external-focus lease every poll. This
                // also reapplies a title discovered before the task catalog loaded.
                shelf.focusTask(
                    title: focusedTask?.title,
                    projectHint: focusedTask?.projectHint,
                    bundleIdentifier: bundleID
                )
                if lastFocusedTaskSignature != focusSignature {
                    lastFocusedTaskSignature = focusSignature
                    shelf.refresh(force: true)
                }
            } else if isPreviewActive {
                if panel?.isVisible != true,
                   let frame = mainWindowFrame(for: frontmost.processIdentifier) {
                    lastAnchorFrame = frame
                }
                shelf.retainExternalFocus()
            }
        } else if frontBundleID == traceFenceBundleID {
            // Clicking the non-activating panel normally leaves the agent in front,
            // but controls such as a text field may briefly activate TraceFence.
            // Retain and refresh the previous anchor in that case.
            if isPreviewActive {
                shelf.retainExternalFocus()
            } else if !isFollowPaused,
               let pid = lastAgentPID,
               let running = NSRunningApplication(processIdentifier: pid),
               !running.isTerminated,
               !running.isHidden {
                guard let frame = mainWindowFrame(for: pid) else {
                    hidePanel()
                    return
                }
                lastAnchorFrame = frame
                // Clicking a preview control can make TraceFence the frontmost
                // app. Keep the previously resolved agent task leased while the
                // user is interacting with this panel instead of falling over to
                // a different active task on the shelf refresh timer.
                shelf.retainExternalFocus()
            } else if !isFollowPaused {
                hidePanel()
                return
            }
        } else {
            hidePanel()
            return
        }

        guard let anchorFrame = lastAnchorFrame else {
            hidePanel()
            return
        }

        let panel = makePanelIfNeeded()
        position(panel, beside: anchorFrame)
        if forceShow || !panel.isVisible {
            panel.orderFrontRegardless()
            if isPreviewActive {
                applyPreviewPause(true)
            }
        }
    }

    private struct FocusedAgentTask {
        let title: String
        let projectHint: String?
    }

    /// Reads the selected Codex task from its accessible sidebar without using
    /// partial CSS-class matching. Claude/Cursor safely fall back to agent-level
    /// selection when they do not expose this DOM-backed structure.
    private func focusedTaskInAgent(pid: pid_t) -> FocusedAgentTask? {
        guard hasAccessibilityPermission else { return nil }

        if cachedFocusedTaskPID == pid,
           let button = cachedFocusedTaskButton,
           let row = cachedFocusedTaskRow,
           axStringArray(button, attribute: "AXDOMClassList" as CFString)
                .contains(where: { $0 == "bg-token-list-hover-background" }) {
            var inspected = 0
            if let title = firstStaticText(in: row, inspected: &inspected, limit: 120) {
                return FocusedAgentTask(title: title, projectHint: cachedFocusedTaskProjectHint)
            }
        }
        clearFocusedTaskCache()

        struct PendingNode {
            let element: AXUIElement
            let containingRow: AXUIElement?
            let nearestListDescription: String?
        }

        let root = AXUIElementCreateApplication(pid)
        var queue = [PendingNode(element: root, containingRow: nil, nearestListDescription: nil)]
        var cursor = 0
        var visited: Set<CFHashCode> = []
        var inspected = 0
        let maximumNodes = 2_500

        while cursor < queue.count, inspected < maximumNodes {
            let pending = queue[cursor]
            cursor += 1
            let identity = CFHash(pending.element)
            guard visited.insert(identity).inserted else { continue }
            inspected += 1

            let role = axString(pending.element, attribute: kAXRoleAttribute as CFString)
            // Electron task rows are commonly AXGroup rather than AXRow. Keep
            // the nearest row-like ancestor so the title lookup stays local.
            let row = role == (kAXRowRole as String) || role == (kAXGroupRole as String)
                ? pending.element
                : pending.containingRow
            let listHint: String?
            if role == (kAXListRole as String) {
                listHint = nonemptyAXString(pending.element, attribute: kAXDescriptionAttribute as CFString)
                    ?? pending.nearestListDescription
            } else {
                listHint = pending.nearestListDescription
            }

            if role == (kAXButtonRole as String),
               axStringArray(pending.element, attribute: "AXDOMClassList" as CFString)
                    .contains(where: { $0 == "bg-token-list-hover-background" }),
               let row,
               let title = firstStaticText(in: row, inspected: &inspected, limit: maximumNodes) {
                cachedFocusedTaskPID = pid
                cachedFocusedTaskButton = pending.element
                cachedFocusedTaskRow = row
                cachedFocusedTaskProjectHint = listHint
                return FocusedAgentTask(title: title, projectHint: listHint)
            }

            for child in axChildren(pending.element) {
                queue.append(PendingNode(
                    element: child,
                    containingRow: row,
                    nearestListDescription: listHint
                ))
            }
        }
        return nil
    }

    private func clearFocusedTaskCache() {
        cachedFocusedTaskPID = nil
        cachedFocusedTaskButton = nil
        cachedFocusedTaskRow = nil
        cachedFocusedTaskProjectHint = nil
    }

    private func firstStaticText(in root: AXUIElement, inspected: inout Int, limit: Int) -> String? {
        var queue = [root]
        var cursor = 0
        var visited: Set<CFHashCode> = []
        while cursor < queue.count, inspected < limit {
            let element = queue[cursor]
            cursor += 1
            let identity = CFHash(element)
            guard visited.insert(identity).inserted else { continue }
            inspected += 1
            if axString(element, attribute: kAXRoleAttribute as CFString) == (kAXStaticTextRole as String),
               let value = nonemptyAXString(element, attribute: kAXValueAttribute as CFString) {
                return value
            }
            queue.append(contentsOf: axChildren(element))
        }
        return nil
    }

    private func axValue(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private func axString(_ element: AXUIElement, attribute: CFString) -> String? {
        axValue(element, attribute: attribute) as? String
    }

    private func nonemptyAXString(_ element: AXUIElement, attribute: CFString) -> String? {
        guard let raw = axString(element, attribute: attribute)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    private func axStringArray(_ element: AXUIElement, attribute: CFString) -> [String] {
        axValue(element, attribute: attribute) as? [String] ?? []
    }

    private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        axValue(element, attribute: kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    }

    /// Uses the public window server list, so following works without Accessibility permission.
    private func mainWindowFrame(for pid: pid_t) -> NSRect? {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var candidates: [CGRect] = []
        for info in windowInfo {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 360,
                  rect.height >= 260 else { continue }
            candidates.append(rect)
        }

        guard let quartzFrame = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return nil
        }
        return appKitFrame(fromQuartzFrame: quartzFrame)
    }

    private func appKitFrame(fromQuartzFrame quartzFrame: CGRect) -> NSRect? {
        struct DisplayPair {
            let screen: NSScreen
            let quartzBounds: CGRect
            let intersectionArea: CGFloat
        }

        let pairs: [DisplayPair] = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            let intersection = displayBounds.intersection(quartzFrame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return DisplayPair(screen: screen, quartzBounds: displayBounds, intersectionArea: area)
        }

        guard let pair = pairs.max(by: { $0.intersectionArea < $1.intersectionArea }),
              pair.intersectionArea > 0 else { return nil }
        let localX = quartzFrame.minX - pair.quartzBounds.minX
        let localYFromTop = quartzFrame.minY - pair.quartzBounds.minY
        return NSRect(
            x: pair.screen.frame.minX + localX,
            y: pair.screen.frame.maxY - localYFromTop - quartzFrame.height,
            width: quartzFrame.width,
            height: quartzFrame.height
        )
    }

    private func position(_ panel: NSPanel, beside anchor: NSRect) {
        let screen = NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(anchor).area < rhs.frame.intersection(anchor).area
        } ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let gap: CGFloat = 8
        var size = panel.frame.size
        size.width = min(max(size.width, panel.contentMinSize.width), min(panel.contentMaxSize.width, visible.width))
        size.height = min(max(size.height, panel.contentMinSize.height), min(panel.contentMaxSize.height, visible.height))

        let x: CGFloat
        if anchor.maxX + gap + size.width <= visible.maxX {
            x = anchor.maxX + gap
        } else if anchor.minX - gap - size.width >= visible.minX {
            x = anchor.minX - gap - size.width
        } else {
            // Full-screen/large windows have no outside space; sit on their right edge
            // like an in-app sidebar while remaining a TraceFence-owned panel.
            x = min(max(anchor.maxX - size.width - 12, visible.minX), visible.maxX - size.width)
        }

        let alignedTop = anchor.maxY - size.height
        let y = min(max(alignedTop, visible.minY), visible.maxY - size.height)
        let frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        if panel.frame != frame {
            panel.setFrame(frame, display: panel.isVisible, animate: false)
        }
    }
}

private final class ArtifactSidecarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension NSRect {
    var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }
}

// MARK: - SwiftUI shelf

@MainActor
private struct ArtifactSidecarRootView: View {
    @ObservedObject var controller: ArtifactSidecarController
    @ObservedObject var shelf: ArtifactShelfService

    private static let traceFenceIcon: NSImage =
        NSApplication.shared.applicationIconImage
        ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    @State private var previewStack: [ArtifactSidecarPreviewItem] = []

    private var taskSelection: Binding<String> {
        Binding(
            get: { shelf.selectedTaskID ?? "" },
            set: { value in
                guard !value.isEmpty else { return }
                shelf.selectTask(value)
                controller.setFollowPaused(true)
                previewStack.removeAll()
            }
        )
    }

    private var savedItems: [ArtifactSidecarListItem] {
        shelf.bookmarksForSelectedTask.map(ArtifactSidecarListItem.init)
    }

    private var discoveredArtifactItems: [ArtifactSidecarListItem] {
        shelf.visibleCandidates
            .filter { $0.kind != .url }
            .map(ArtifactSidecarListItem.init)
    }

    private var displayedArtifactCount: Int {
        savedItems.count + discoveredArtifactItems.count
    }

    private var compactCountLabel: String {
        shelf.hiddenCandidateCount > 0 ? "\(displayedArtifactCount)+" : "\(displayedArtifactCount)"
    }

    var body: some View {
        Group {
            if controller.isCollapsed {
                compactShelf
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    if previewStack.isEmpty {
                        shelfContents
                    } else if let preview = previewStack.last {
                        previewContents(preview)
                    }
                }
                .frame(minWidth: 330, minHeight: 430)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onChange(of: shelf.selectedTaskID) { _ in previewStack.removeAll() }
        .onChange(of: controller.isCollapsed) { collapsed in
            if collapsed { previewStack.removeAll() }
        }
        .onChange(of: previewStack.isEmpty) { isEmpty in
            controller.setPreviewActive(!isEmpty)
        }
    }

    private var compactShelf: some View {
        Button {
            controller.expandPanel()
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: Self.traceFenceIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(compactCountLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(width: 88, height: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("展开当前会话最终交付")
        .accessibilityLabel(
            shelf.hiddenCandidateCount > 0
                ? "展开当前会话最终交付，优先显示 \(displayedArtifactCount) 项，另有 \(shelf.hiddenCandidateCount) 项可搜索"
                : "展开当前会话最终交付，共 \(displayedArtifactCount) 项"
        )
        .frame(width: 92, height: 52)
        .background(Color.clear)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("当前会话产物")
                    .font(.system(size: 13, weight: .semibold))
                Text(shelf.selectedTask?.agentDisplayName ?? "Agent")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)

            Toggle("启用", isOn: Binding(
                get: { controller.isEnabled },
                set: { controller.setEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("启用或关闭伴随侧栏")

            headerButton(
                controller.isFollowPaused ? "play.fill" : "pause.fill",
                help: controller.isFollowPaused ? "继续跟随" : "暂停跟随"
            ) {
                controller.toggleFollowPaused()
            }
            headerButton("arrow.clockwise", help: "刷新产物") {
                shelf.refresh(force: true)
            }
            headerButton("chevron.right.circle", help: "缩小为悬浮窗") {
                controller.closePanel()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func headerButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private var shelfContents: some View {
        VStack(spacing: 0) {
            if !controller.hasAccessibilityPermission {
                HStack(spacing: 8) {
                    Image(systemName: "accessibility")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("授权后可准确跟随当前会话")
                            .font(.system(size: 11, weight: .medium))
                        Text("未授权时会回退到最近活跃会话")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("授权") {
                        controller.requestAccessibilityPermission()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
                Divider()
            }
            controls
            Divider()

            if shelf.tasks.isEmpty {
                emptyState(
                    icon: "rectangle.stack.badge.questionmark",
                    title: "还没有可用会话",
                    detail: "切换到 Codex、Claude 或 Cursor 后会自动匹配。"
                )
            } else if savedItems.isEmpty && discoveredArtifactItems.isEmpty {
                if shelf.isLoadingCandidates {
                    emptyState(
                        icon: "arrow.triangle.2.circlepath",
                        title: "正在查找最终交付…",
                        detail: "正在读取当前会话的完整历史。"
                    )
                } else if !shelf.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyState(
                        icon: "magnifyingglass",
                        title: "没有匹配的交付物",
                        detail: "换个关键词，或清空搜索查看最近交付。"
                    )
                } else if shelf.hiddenCandidateCount > 0 {
                    emptyState(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "旧批次与过程文件已收起",
                        detail: "使用搜索可查找另外 \(shelf.hiddenCandidateCount) 项；源码与配置文件不会展示。"
                    )
                } else {
                    emptyState(
                        icon: "doc.badge.plus",
                        title: "最终答复里还没有交付物",
                        detail: "这里只显示最终答复明确交付的文件和文件夹；中间过程与源码会自动过滤。"
                    )
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !savedItems.isEmpty {
                            sectionHeader("已收藏", count: savedItems.count)
                            ForEach(savedItems) { item in
                                artifactRow(item)
                                Divider().padding(.leading, 45)
                            }
                        }
                        if !discoveredArtifactItems.isEmpty {
                            sectionHeader("最终交付", count: discoveredArtifactItems.count)
                            ForEach(discoveredArtifactItems) { item in
                                artifactRow(item)
                                Divider().padding(.leading, 45)
                            }
                            if shelf.hiddenCandidateCount > 0 {
                                HStack(spacing: 6) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                    Text("已优先显示最近交付；搜索可查另外 \(shelf.hiddenCandidateCount) 项旧批次或过程文件")
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("会话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("会话", selection: taskSelection) {
                    if shelf.selectedTaskID == nil {
                        Text("选择会话").tag("")
                    }
                    ForEach(shelf.tasks) { task in
                        Text("\(task.agentDisplayName) · \(task.title)")
                            .lineLimit(1)
                            .tag(task.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索最终交付", text: $shelf.searchText)
                    .textFieldStyle(.plain)
                if !shelf.searchText.isEmpty {
                    Button { shelf.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(12)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 5)
    }

    private func artifactRow(_ item: ArtifactSidecarListItem) -> some View {
        HStack(spacing: 9) {
            Button {
                open(item.previewItem)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 15))
                        .foregroundStyle(item.kind == .url ? .blue : .accentColor)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(item.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let candidate = item.candidate {
                Button {
                    shelf.addBookmark(candidate)
                } label: {
                    Image(systemName: "star")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("收藏")
            } else {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
    }

    private func previewContents(_ preview: ArtifactSidecarPreviewItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    if !previewStack.isEmpty { previewStack.removeLast() }
                } label: {
                    Label(previewStack.count > 1 ? "返回" : "产物列表", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(preview.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if previewStack.count > 1 {
                    Button("返回列表") { previewStack.removeAll() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            Divider()

            switch preview.kind {
            case .url:
                if let url = URL(string: preview.target) {
                    ArtifactSidecarWebPreview(url: url)
                } else {
                    previewError("网址无效")
                }
            case .directory:
                ArtifactSidecarDirectoryView(directoryURL: preview.url) { child in
                    open(child)
                }
            case .html:
                if FileManager.default.fileExists(atPath: preview.url.path) {
                    ArtifactSidecarLocalHTMLPreview(url: preview.url)
                } else {
                    previewError("文件已移动或删除")
                }
            case .file, .image:
                if FileManager.default.fileExists(atPath: preview.url.path) {
                    ArtifactSidecarQuickLookPreview(url: preview.url)
                } else {
                    previewError("文件已移动或删除")
                }
            }
        }
    }

    private func open(_ item: ArtifactSidecarPreviewItem) {
        if previewStack.last?.target != item.target {
            previewStack.append(item)
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 9) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewError(_ message: String) -> some View {
        emptyState(icon: "exclamationmark.triangle", title: "无法预览", detail: message)
    }
}

private struct ArtifactSidecarListItem: Identifiable {
    let id: String
    let kind: ArtifactShelfCandidate.Kind
    let target: String
    let title: String
    let candidate: ArtifactShelfCandidate?

    init(_ bookmark: ArtifactShelfBookmark) {
        id = "bookmark:\(bookmark.id.uuidString)"
        kind = bookmark.kind
        target = bookmark.target
        title = bookmark.title
        candidate = nil
    }

    init(_ candidate: ArtifactShelfCandidate) {
        id = "candidate:\(candidate.target)"
        kind = candidate.kind
        target = candidate.target
        title = candidate.title
        self.candidate = candidate
    }

    var detail: String {
        if kind == .url { return target }
        return (target as NSString).deletingLastPathComponent
    }

    var symbolName: String {
        switch kind {
        case .directory: return "folder.fill"
        case .image: return "photo.fill"
        case .html: return "safari.fill"
        case .url: return "link"
        case .file:
            return URL(fileURLWithPath: target).pathExtension.lowercased() == "pdf"
                ? "doc.richtext.fill" : "doc.fill"
        }
    }

    var previewItem: ArtifactSidecarPreviewItem {
        ArtifactSidecarPreviewItem(kind: kind, target: target, title: title)
    }
}

private struct ArtifactSidecarPreviewItem: Identifiable, Hashable {
    let kind: ArtifactShelfCandidate.Kind
    let target: String
    let title: String

    var id: String { target }
    var url: URL {
        kind == .url ? (URL(string: target) ?? URL(fileURLWithPath: target)) : URL(fileURLWithPath: target)
    }

    static func localFile(_ url: URL, isDirectory: Bool) -> ArtifactSidecarPreviewItem {
        let ext = url.pathExtension.lowercased()
        let kind: ArtifactShelfCandidate.Kind
        if isDirectory {
            kind = .directory
        } else if ["png", "jpg", "jpeg", "gif", "webp", "heic", "avif"].contains(ext) {
            kind = .image
        } else if ["html", "htm"].contains(ext) {
            kind = .html
        } else {
            kind = .file
        }
        return ArtifactSidecarPreviewItem(kind: kind, target: url.path, title: url.lastPathComponent)
    }
}

// MARK: - In-panel previews

private struct ArtifactSidecarQuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        let currentURL = (view.previewItem as? NSURL) as URL?
        guard currentURL != url else { return }
        view.previewItem = url as NSURL
        view.refreshPreviewItem()
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.autostarts = false
        view.previewItem = nil
    }
}

private struct ArtifactSidecarWebPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsMagnification = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard view.url != url else { return }
        view.load(URLRequest(url: url))
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: ()) {
        view.stopLoading()
        view.navigationDelegate = nil
    }
}

private struct ArtifactSidecarLocalHTMLPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsMagnification = true
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard view.url?.standardizedFileURL != url.standardizedFileURL else { return }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: ()) {
        view.stopLoading()
        view.navigationDelegate = nil
    }
}

@MainActor
private struct ArtifactSidecarDirectoryView: View {
    let directoryURL: URL
    let onOpen: (ArtifactSidecarPreviewItem) -> Void

    @State private var entries: [ArtifactSidecarDirectoryEntry] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("读取目录…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.title)
                    Text("目录中没有需要展示的交付文件")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    Button {
                        onOpen(.localFile(entry.url, isDirectory: entry.isDirectory))
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: entry.isDirectory ? "folder.fill" : entry.symbolName)
                                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.url.lastPathComponent)
                                    .lineLimit(1)
                                if let modifiedAt = entry.modifiedAt {
                                    Text(modifiedAt, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .task(id: directoryURL) {
            isLoading = true
            errorMessage = nil
            let result = await Task.detached(priority: .utility) {
                ArtifactSidecarDirectoryEntry.load(from: directoryURL)
            }.value
            switch result {
            case .success(let values): entries = values
            case .failure(let error): errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

private struct ArtifactSidecarDirectoryEntry: Identifiable {
    let url: URL
    let isDirectory: Bool
    let modifiedAt: Date?

    var id: String { url.path }

    var symbolName: String {
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "avif"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        if ["html", "htm"].contains(ext) { return "safari" }
        return "doc"
    }

    static func load(from directoryURL: URL) -> Result<[ArtifactSidecarDirectoryEntry], Error> {
        do {
            let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .isHiddenKey]
            let urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            let values = urls.prefix(1_000).compactMap { url -> ArtifactSidecarDirectoryEntry? in
                let resource = try? url.resourceValues(forKeys: Set(keys))
                let isDirectory = resource?.isDirectory == true
                let ext = url.pathExtension.lowercased()
                let kind: ArtifactShelfCandidate.Kind = isDirectory ? .directory
                    : ["png", "jpg", "jpeg", "gif", "webp", "heic", "avif"].contains(ext) ? .image
                    : ["html", "htm"].contains(ext) ? .html : .file
                let candidate = ArtifactShelfCandidate(
                    kind: kind,
                    target: url.path,
                    title: url.lastPathComponent,
                    discoveredAt: resource?.contentModificationDate ?? .distantPast,
                    exists: true
                )
                guard resource?.isHidden != true,
                      !isSensitiveName(url.lastPathComponent),
                      ArtifactShelfService.isUserFacingArtifact(candidate) else { return nil }
                return ArtifactSidecarDirectoryEntry(
                    url: url,
                    isDirectory: isDirectory,
                    modifiedAt: resource?.contentModificationDate
                )
            }
            return .success(values.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            })
        } catch {
            return .failure(error)
        }
    }

    private static func isSensitiveName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasPrefix(".") { return true }
        return lower == "credentials" || lower == "secrets" || lower == "tokens" ||
            lower.hasPrefix(".env") || lower.hasPrefix("id_rsa") || lower.hasPrefix("id_ed25519") ||
            lower.contains("private_key") || lower.contains("api_key")
    }
}
