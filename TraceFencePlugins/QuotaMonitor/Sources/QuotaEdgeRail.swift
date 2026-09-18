import AppKit
import Foundation
import MacToolsPluginKit

/// A plugin-owned screen-edge rail. It renders the same quota snapshots as
/// Touch Bar and never fetches providers on its own.
@MainActor
final class QuotaEdgeRailController {
    enum Edge: String, CaseIterable {
        case left
        case right
        case top
    }

    private enum Preference {
        static let visibleKey = "com.tracefence.plugin.quota-monitor.edge-rail.visible"
        static let edgeKey = "com.tracefence.plugin.quota-monitor.edge-rail.edge"
    }

    private let localization: PluginLocalization
    private let window: QuotaEdgeRailWindow
    private var snapshots: [ProviderQuotaSnapshot] = []
    private var isActive = false
    var onSelectProvider: ((String) -> Void)?
    var onCycleMetric: (() -> Void)?
    var onResumeAutomatic: (() -> Void)?
    var onHide: (() -> Void)?
    var onStateChange: (() -> Void)?

    init(localization: PluginLocalization) {
        self.localization = localization
        self.window = QuotaEdgeRailWindow(localization: localization)
        window.onSelectProvider = { [weak self] id in self?.onSelectProvider?(id) }
        window.onCycleMetric = { [weak self] in self?.onCycleMetric?() }
        window.onResumeAutomatic = { [weak self] in self?.onResumeAutomatic?() }
        window.onHide = { [weak self] in
            self?.setVisible(false)
            self?.onHide?()
            self?.onStateChange?()
        }
    }

    var isVisible: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Preference.visibleKey) == nil {
            defaults.set(true, forKey: Preference.visibleKey)
            return true
        }
        return defaults.bool(forKey: Preference.visibleKey)
    }

    var edge: Edge {
        Edge(rawValue: UserDefaults.standard.string(forKey: Preference.edgeKey) ?? "") ?? .right
    }

    func activate(snapshots: [ProviderQuotaSnapshot], state: QuotaDisplay.State) {
        isActive = true
        self.snapshots = snapshots
        refresh(state: state)
    }

    func deactivate() {
        isActive = false
        window.deactivate()
    }

    func receive(snapshots: [ProviderQuotaSnapshot], state: QuotaDisplay.State) {
        self.snapshots = snapshots
        guard isActive else { return }
        refresh(state: state)
    }

    func toggleVisibility(state: QuotaDisplay.State) {
        setVisible(!isVisible)
        refresh(state: state)
    }

    func setEdge(_ edge: Edge, state: QuotaDisplay.State) {
        UserDefaults.standard.set(edge.rawValue, forKey: Preference.edgeKey)
        refresh(state: state)
        onStateChange?()
    }

    private func setVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: Preference.visibleKey)
        if !visible { window.hide() }
    }

    private func refresh(state: QuotaDisplay.State) {
        guard isActive else { return }
        guard isVisible else {
            window.hide()
            return
        }
        window.update(
            items: QuotaDisplay.items(from: snapshots, localization: localization),
            state: state,
            edge: edge,
            localization: localization
        )
    }
}

@MainActor
private final class QuotaEdgeRailWindow: NSPanel {
    var onSelectProvider: ((String) -> Void)?
    var onCycleMetric: (() -> Void)?
    var onResumeAutomatic: (() -> Void)?
    var onHide: (() -> Void)?

    private let railView: QuotaEdgeRailView
    private var collapseWork: DispatchWorkItem?
    private var isExpanded = true
    private var isHovering = false

    init(localization: PluginLocalization) {
        railView = QuotaEdgeRailView(localization: localization)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        contentView = railView
        railView.onSelectProvider = { [weak self] id in self?.onSelectProvider?(id) }
        railView.onCycleMetric = { [weak self] in self?.onCycleMetric?() }
        railView.onResumeAutomatic = { [weak self] in self?.onResumeAutomatic?() }
        railView.onHide = { [weak self] in self?.onHide?() }
        railView.onHoverChanged = { [weak self] hovering in
            self?.isHovering = hovering
            if hovering {
                self?.collapseWork?.cancel()
                self?.collapseWork = nil
                self?.setExpanded(true)
            } else {
                self?.scheduleCollapse()
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func deactivate() {
        collapseWork?.cancel()
        collapseWork = nil
        isHovering = false
        orderOut(nil)
    }

    func hide() {
        collapseWork?.cancel()
        collapseWork = nil
        orderOut(nil)
    }

    func update(
        items: [QuotaDisplay.Item],
        state: QuotaDisplay.State,
        edge: QuotaEdgeRailController.Edge,
        localization: PluginLocalization
    ) {
        railView.edge = edge
        railView.items = items
        railView.state = state
        railView.localization = localization
        railView.collapsed = !isExpanded
        let size = railView.preferredSize
        railView.frame = NSRect(origin: .zero, size: size)
        setContentSize(size)
        position(on: edge, size: size)
        orderFrontRegardless()
        if isHovering {
            collapseWork?.cancel()
            collapseWork = nil
            setExpanded(true)
        } else {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        guard !isHovering else { return }
        guard collapseWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.collapseWork = nil
            self?.setExpanded(false)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        railView.collapsed = !expanded
        let size = railView.preferredSize
        railView.frame = NSRect(origin: .zero, size: size)
        setContentSize(size)
        position(on: railView.edge, size: size)
        railView.needsDisplay = true
    }

    private func position(on edge: QuotaEdgeRailController.Edge, size: NSSize) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin: NSPoint
        switch edge {
        case .right:
            origin = NSPoint(x: visible.maxX - size.width - 8, y: visible.midY - size.height / 2)
        case .left:
            origin = NSPoint(x: visible.minX + 8, y: visible.midY - size.height / 2)
        case .top:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 8)
        }
        setFrameOrigin(origin)
    }
}

@MainActor
private final class QuotaEdgeRailView: NSView {
    var localization: PluginLocalization
    var items: [QuotaDisplay.Item] = []
    var state = QuotaDisplay.State.unavailable()
    var edge: QuotaEdgeRailController.Edge = .right
    var collapsed = false
    var onSelectProvider: ((String) -> Void)?
    var onCycleMetric: (() -> Void)?
    var onResumeAutomatic: (() -> Void)?
    var onHide: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var tracking: NSTrackingArea?

    init(localization: PluginLocalization) {
        self.localization = localization
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
    }

    required init?(coder: NSCoder) { nil }

    var preferredSize: NSSize {
        let count = max(1, items.count)
        if collapsed {
            return edge == .top ? NSSize(width: 28 + CGFloat(count * 18), height: 10) : NSSize(width: 10, height: 28 + CGFloat(count * 18))
        }
        if edge == .top {
            return NSSize(width: 24 + CGFloat(count) * 56, height: 72)
        }
        return NSSize(width: 72, height: 28 + CGFloat(count) * 56)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        tracking = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if collapsed {
            onHoverChanged?(true)
            return
        }
        if hideButtonRect.contains(point) {
            onHide?()
            return
        }
        if modeButtonRect.contains(point) {
            onResumeAutomatic?()
            return
        }
        if let item = item(at: point) {
            if item.id == state.providerID {
                onCycleMetric?()
            } else {
                onSelectProvider?(item.id)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16).fill()

        if collapsed {
            drawCollapsed()
            return
        }

        for (index, item) in items.enumerated() {
            drawRing(item: item, in: ringRect(at: index))
        }
        if items.isEmpty {
            drawCentered(
                localization.string("touchbar.unavailable", defaultValue: "No quota data"),
                in: bounds.insetBy(dx: 8, dy: 8),
                size: 9,
                color: .secondaryLabelColor
            )
        }
        drawAccessory()
    }

    private func drawCollapsed() {
        let values = items.isEmpty ? [state.lowestRemaining ?? 0] : items.map(\.lowestRemaining)
        for (index, remaining) in values.enumerated() {
            QuotaDisplay.meterColor(for: remaining).setFill()
            NSBezierPath(ovalIn: collapsedDotRect(at: index)).fill()
        }
    }

    private func drawRing(item: QuotaDisplay.Item, in rect: NSRect) {
        let selected = item.id == state.providerID
        let metric = selected ? state.currentMetric : item.metrics.first
        let remaining = metric?.remaining ?? item.lowestRemaining
        let inset = rect.insetBy(dx: 10, dy: 8)
        let ring = NSRect(x: inset.midX - 18, y: inset.maxY - 40, width: 36, height: 36)
        NSColor.white.withAlphaComponent(0.12).setStroke()
        let track = NSBezierPath(ovalIn: ring)
        track.lineWidth = 4
        track.stroke()

        let start = CGFloat.pi / 2
        let end = start - (2 * .pi * CGFloat(remaining) / 100)
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: ring.midX, y: ring.midY),
            radius: 16,
            startAngle: start * 180 / .pi,
            endAngle: end * 180 / .pi,
            clockwise: true
        )
        arc.lineWidth = 4
        arc.lineCapStyle = .round
        QuotaDisplay.meterColor(for: remaining).setStroke()
        arc.stroke()

        drawCentered("\(remaining)", in: ring, size: 9, color: .white, weight: .semibold)
        let labelRect = NSRect(x: rect.minX + 4, y: rect.minY + 4, width: rect.width - 8, height: 16)
        drawCentered(item.providerName, in: labelRect, size: 9, color: selected ? .white : NSColor.white.withAlphaComponent(0.7))
        if selected {
            NSColor.white.withAlphaComponent(0.18).setStroke()
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 2), xRadius: 12, yRadius: 12)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    private func drawAccessory() {
        let mode = localization.string(
            state.isAutomatic ? "touchbar.mode.automatic" : "touchbar.mode.manual",
            defaultValue: state.isAutomatic ? "Automatic follow" : "Manual lock"
        )
        drawCentered(mode, in: modeButtonRect, size: 8, color: NSColor.white.withAlphaComponent(0.65))
        drawCentered("×", in: hideButtonRect, size: 11, color: NSColor.white.withAlphaComponent(0.8))
    }

    private func ringRect(at index: Int) -> NSRect {
        if edge == .top {
            return NSRect(x: 12 + CGFloat(index) * 56, y: 12, width: 52, height: 52)
        }
        return NSRect(x: 10, y: bounds.height - 64 - CGFloat(index) * 56, width: 52, height: 52)
    }

    private func collapsedDotRect(at index: Int) -> NSRect {
        if edge == .top {
            return NSRect(x: 8 + CGFloat(index) * 18, y: 2, width: 6, height: 6)
        }
        return NSRect(x: 2, y: bounds.height - 14 - CGFloat(index) * 18, width: 6, height: 6)
    }

    private var hideButtonRect: NSRect {
        NSRect(x: bounds.maxX - 18, y: bounds.maxY - 16, width: 14, height: 12)
    }

    private var modeButtonRect: NSRect {
        NSRect(x: 8, y: 4, width: bounds.width - 16, height: 14)
    }

    private func item(at point: NSPoint) -> QuotaDisplay.Item? {
        for (index, item) in items.enumerated() where ringRect(at: index).contains(point) {
            return item
        }
        return nil
    }

    private func drawCentered(
        _ text: String,
        in rect: NSRect,
        size: CGFloat,
        color: NSColor,
        weight: NSFont.Weight = .medium
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let font = attributes[.font] as! NSFont
        let height = ceil(font.ascender - font.descender)
        let drawRect = NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        (text as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }
}
