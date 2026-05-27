import SwiftUI
import AppKit

class IslandWindowController {
    private var window: NSWindow?
    private var localEventMonitor: Any?
    private var displayController: DisplayController
    private var islandViewModel: IslandViewModel
    private var localizer: Localizer

    init(displayController: DisplayController, islandViewModel: IslandViewModel, localizer: Localizer) {
        self.displayController = displayController
        self.islandViewModel = islandViewModel
        self.localizer = localizer
    }

    func createWindow() -> NSWindow {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let hostingView = IslandHostingView(
            rootView: IslandView()
                .environmentObject(islandViewModel)
                .environmentObject(localizer)
        )
        hostingView.displayController = displayController
        hostingView.islandViewModel = islandViewModel

        panel.contentView = hostingView

        setupMouseTracking(for: hostingView)
        setupKeyboardMonitor()

        window = panel
        return panel
    }

    private func setupMouseTracking(for view: NSView) {
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(
            rect: view.bounds,
            options: options,
            owner: view,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
    }

    private func setupKeyboardMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 {
                Task { @MainActor in
                    self.displayController.handleEscape()
                }
                return nil
            }
            return event
        }
    }

    func cleanup() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }

    var currentWindow: NSWindow? { window }
}

class IslandHostingView: NSHostingView<AnyView> {
    weak var displayController: DisplayController?
    weak var islandViewModel: IslandViewModel?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    init<Content: View>(rootView: Content) {
        super.init(rootView: AnyView(rootView))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        displayController?.handleMouseEnter()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        displayController?.handleMouseExit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
}
