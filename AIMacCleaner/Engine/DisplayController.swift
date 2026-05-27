import SwiftUI
import AppKit

enum IslandMode {
    case compact
    case hover
    case expanded
    case detail
}

@MainActor
class DisplayController: ObservableObject {
    @Published var mode: IslandMode = .compact
    @Published var isVisible: Bool = false
    @Published var position: IslandPosition = .topCenter

    static let shared = DisplayController()

    weak var islandViewModel: IslandViewModel?
    weak var localizer: Localizer?

    private var islandWindow: NSWindow?
    private var isDragging = false
    private var mouseTrackingArea: NSTrackingArea?

    private let minWidth: CGFloat = 200
    private let minHeight: CGFloat = 48
    private var displayTimer: Timer?

    func setup(islandViewModel: IslandViewModel, localizer: Localizer) {
        self.islandViewModel = islandViewModel
        self.localizer = localizer
    }

    func createIslandWindow() -> NSWindow {
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
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        panel.contentView = NSHostingView(
            rootView: IslandView()
                .environmentObject(islandViewModel ?? IslandViewModel())
                .environmentObject(localizer ?? Localizer())
        )

        islandWindow = panel
        return panel
    }

    func showIsland() {
        guard let window = islandWindow else { return }

        if !window.isVisible {
            positionWindow(window)
            window.orderFrontRegardless()
            window.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }

        isVisible = true

        if mode == .detail {
            window.makeKey()
        }
    }

    func hideIsland(animated: Bool = true) {
        guard let window = islandWindow, window.isVisible else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
            }
        } else {
            window.orderOut(nil)
        }

        isVisible = false
    }

    func updateIslandFrame(level: IslandDisplayLevel, animated: Bool = true) {
        guard let window = islandWindow else { return }

        let width = level.islandWidth
        let height = level.islandHeight

        positionWindow(window, width: width, height: height, animated: animated)

        switch level {
        case .compact: mode = .compact
        case .hover: mode = .hover
        case .expanded: mode = .expanded
        case .detail: mode = .detail
        }
    }

    func positionWindow(_ window: NSWindow, width: CGFloat = 200, height: CGFloat = 48, animated: Bool = true) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame

        let originX: CGFloat
        let originY: CGFloat

        switch position {
        case .topCenter:
            originX = frame.midX - width / 2
            originY = frame.maxY - height - 8
        case .topRight:
            originX = frame.maxX - width - 16
            originY = frame.maxY - height - 8
        case .center:
            originX = frame.midX - width / 2
            originY = frame.midY - height / 2
        }

        let newFrame = NSRect(x: originX, y: originY, width: width, height: height)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }

    func moveToPosition(_ newPosition: IslandPosition) {
        position = newPosition
        if let window = islandWindow, window.isVisible {
            positionWindow(window, width: window.frame.width, height: window.frame.height)
        }
    }

    func handleMouseEnter() {
        guard let vm = islandViewModel, vm.displayLevel >= .compact else { return }
        if vm.displayLevel < .hover {
            vm.show(level: .hover)
        }
    }

    func handleMouseExit() {
        guard let vm = islandViewModel, !vm.isPinned else { return }
        if vm.displayLevel == .hover {
            vm.dismiss()
        }
    }

    func handleEscape() {
        guard let vm = islandViewModel else { return }
        if vm.showPermissionSheet || vm.showQuestionSheet || vm.showPlanApprovalSheet {
            vm.dismissSheets()
        } else if vm.displayLevel > .hover {
            vm.dismiss()
        }
    }

    func windowFrame(for level: IslandDisplayLevel) -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.visibleFrame
        let width = level.islandWidth
        let height = level.islandHeight

        let originX: CGFloat
        let originY: CGFloat

        switch position {
        case .topCenter:
            originX = frame.midX - width / 2
            originY = frame.maxY - height - 8
        case .topRight:
            originX = frame.maxX - width - 16
            originY = frame.maxY - height - 8
        case .center:
            originX = frame.midX - width / 2
            originY = frame.midY - height / 2
        }

        return NSRect(x: originX, y: originY, width: width, height: height)
    }
}
