import AppKit
import CoreGraphics

@MainActor
final class CaptureSelectionOverlayController {
    private let completion: (CGRect?) -> Void
    private let previousFrontmostApplication = NSWorkspace.shared.frontmostApplication
    private var windows: [NSWindow] = []
    private var didComplete = false

    init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
    }

    func begin() {
        let mouseLocation = NSEvent.mouseLocation

        for screen in NSScreen.screens {
            let window = CaptureSelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false

            let view = CaptureSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onComplete = { [weak self, weak window] localRect in
                guard let window else {
                    self?.finish(nil)
                    return
                }
                self?.finish(Self.captureRect(for: localRect, in: window, screen: screen))
            }
            view.onCancel = { [weak self] in
                self?.finish(nil)
            }
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)

            if screen.frame.contains(mouseLocation) {
                window.makeKey()
                window.makeFirstResponder(view)
            }
        }
        NSCursor.crosshair.set()
    }

    private static func captureRect(for viewRect: NSRect, in window: NSWindow, screen: NSScreen) -> CGRect {
        let appKitRect = window.convertToScreen(viewRect)
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? screen.frame.maxY
            return CGRect(
                x: appKitRect.minX,
                y: desktopTop - appKitRect.maxY,
                width: appKitRect.width,
                height: appKitRect.height
            )
        }

        let displayBounds = CGDisplayBounds(displayID)
        let scaleX = displayBounds.width / max(screen.frame.width, 1)
        let scaleY = displayBounds.height / max(screen.frame.height, 1)
        return CGRect(
            x: displayBounds.minX + (appKitRect.minX - screen.frame.minX) * scaleX,
            y: displayBounds.minY + (screen.frame.maxY - appKitRect.maxY) * scaleY,
            width: appKitRect.width * scaleX,
            height: appKitRect.height * scaleY
        )
    }

    private func finish(_ rect: CGRect?) {
        guard !didComplete else { return }
        didComplete = true
        NSCursor.arrow.set()
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()

        let traceFencePID = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == traceFencePID,
           let previousFrontmostApplication,
           previousFrontmostApplication.processIdentifier != traceFencePID,
           !previousFrontmostApplication.isTerminated {
            previousFrontmostApplication.activate(options: [.activateIgnoringOtherApps])
        }
        completion(rect)
    }
}

private final class CaptureSelectionWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CaptureSelectionView: NSView {
    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private enum ResizeHandle: CaseIterable {
        case northWest
        case north
        case northEast
        case east
        case southEast
        case south
        case southWest
        case west
    }

    private enum Interaction {
        case drawing(anchor: NSPoint)
        case moving(anchor: NSPoint, initialRect: NSRect)
        case resizing(handle: ResizeHandle, initialRect: NSRect)
    }

    private enum ToolbarAction: Equatable {
        case cancel
        case confirm
    }

    private struct ToolbarGeometry {
        let background: NSRect
        let metric: NSRect
        let cancel: NSRect
        let confirm: NSRect
    }

    private let minimumSelectionSize: CGFloat = 24
    private let handleVisualSize: CGFloat = 9
    private let handleHitPadding: CGFloat = 7
    private var interaction: Interaction?
    private var pressedToolbarAction: ToolbarAction?
    private var selectionRect: NSRect? {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.26).setFill()
        bounds.fill()

        guard let selectionRect, selectionRect.width > 0, selectionRect.height > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        selectionRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.98).setStroke()
        let outerPath = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
        outerPath.lineWidth = 2
        outerPath.stroke()

        NSColor.systemBlue.withAlphaComponent(0.98).setStroke()
        let innerRect = selectionRect.insetBy(dx: 2, dy: 2)
        if innerRect.width > 0, innerRect.height > 0 {
            let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 2, yRadius: 2)
            innerPath.lineWidth = 1
            innerPath.stroke()
        }

        guard isValidSelection(selectionRect) else { return }
        drawResizeHandles(for: selectionRect)
        drawToolbar(for: selectionRect)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard let selectionRect, isValidSelection(selectionRect) else { return }

        addCursorRect(selectionRect, cursor: .openHand)
        for (handle, rect) in handleRects(for: selectionRect) {
            addCursorRect(rect.insetBy(dx: -handleHitPadding, dy: -handleHitPadding), cursor: cursor(for: handle))
        }

        let toolbar = toolbarGeometry(for: selectionRect)
        addCursorRect(toolbar.cancel, cursor: .arrow)
        addCursorRect(toolbar.confirm, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if let action = toolbarAction(at: point) {
            pressedToolbarAction = action
            needsDisplay = true
            return
        }

        if let selectionRect, isValidSelection(selectionRect) {
            if let handle = resizeHandle(at: point, selectionRect: selectionRect) {
                interaction = .resizing(handle: handle, initialRect: selectionRect)
                return
            }
            if selectionRect.contains(point) {
                if event.clickCount >= 2 {
                    confirmSelection()
                } else {
                    interaction = .moving(anchor: point, initialRect: selectionRect)
                    NSCursor.closedHand.set()
                }
                return
            }
        }

        let clamped = clampedPoint(point)
        selectionRect = NSRect(origin: clamped, size: .zero)
        interaction = .drawing(anchor: clamped)
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedToolbarAction == nil, let interaction else { return }
        let point = clampedPoint(convert(event.locationInWindow, from: nil))

        switch interaction {
        case .drawing(let anchor):
            selectionRect = standardizedRect(from: anchor, to: point)
        case .moving(let anchor, let initialRect):
            let deltaX = point.x - anchor.x
            let deltaY = point.y - anchor.y
            selectionRect = constrainedMovedRect(initialRect.offsetBy(dx: deltaX, dy: deltaY))
        case .resizing(let handle, let initialRect):
            selectionRect = resizedRect(initialRect, handle: handle, to: point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let pressedToolbarAction {
            let shouldPerform = toolbarAction(at: point) == pressedToolbarAction
            self.pressedToolbarAction = nil
            needsDisplay = true
            if shouldPerform {
                perform(pressedToolbarAction)
            }
            return
        }

        if case .drawing = interaction,
           let selectionRect,
           !isValidSelection(selectionRect) {
            self.selectionRect = nil
        }
        interaction = nil
        NSCursor.crosshair.set()
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel?()
        case 36, 76:
            confirmSelection()
        case 51, 117:
            selectionRect = nil
        case 123, 124, 125, 126:
            moveSelection(keyCode: event.keyCode, step: event.modifierFlags.contains(.shift) ? 10 : 1)
        default:
            super.keyDown(with: event)
        }
    }

    private func confirmSelection() {
        guard let selectionRect, isValidSelection(selectionRect) else { return }
        onComplete?(selectionRect.integral)
    }

    private func perform(_ action: ToolbarAction) {
        switch action {
        case .cancel:
            onCancel?()
        case .confirm:
            confirmSelection()
        }
    }

    private func isValidSelection(_ rect: NSRect) -> Bool {
        rect.width >= minimumSelectionSize && rect.height >= minimumSelectionSize
    }

    private func standardizedRect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).intersection(bounds)
    }

    private func clampedPoint(_ point: NSPoint) -> NSPoint {
        NSPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func constrainedMovedRect(_ rect: NSRect) -> NSRect {
        var constrained = rect
        constrained.origin.x = min(max(constrained.origin.x, bounds.minX), bounds.maxX - constrained.width)
        constrained.origin.y = min(max(constrained.origin.y, bounds.minY), bounds.maxY - constrained.height)
        return constrained
    }

    private func resizedRect(_ rect: NSRect, handle: ResizeHandle, to point: NSPoint) -> NSRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .northWest:
            minX = point.x
            maxY = point.y
        case .north:
            maxY = point.y
        case .northEast:
            maxX = point.x
            maxY = point.y
        case .east:
            maxX = point.x
        case .southEast:
            maxX = point.x
            minY = point.y
        case .south:
            minY = point.y
        case .southWest:
            minX = point.x
            minY = point.y
        case .west:
            minX = point.x
        }

        if maxX - minX < minimumSelectionSize {
            if [.northWest, .southWest, .west].contains(handle) {
                minX = maxX - minimumSelectionSize
            } else {
                maxX = minX + minimumSelectionSize
            }
        }
        if maxY - minY < minimumSelectionSize {
            if [.southEast, .south, .southWest].contains(handle) {
                minY = maxY - minimumSelectionSize
            } else {
                maxY = minY + minimumSelectionSize
            }
        }

        minX = max(minX, bounds.minX)
        minY = max(minY, bounds.minY)
        maxX = min(maxX, bounds.maxX)
        maxY = min(maxY, bounds.maxY)
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func moveSelection(keyCode: UInt16, step: CGFloat) {
        guard let selectionRect, isValidSelection(selectionRect) else { return }
        let offset: NSPoint
        switch keyCode {
        case 123: offset = NSPoint(x: -step, y: 0)
        case 124: offset = NSPoint(x: step, y: 0)
        case 125: offset = NSPoint(x: 0, y: -step)
        case 126: offset = NSPoint(x: 0, y: step)
        default: return
        }
        self.selectionRect = constrainedMovedRect(selectionRect.offsetBy(dx: offset.x, dy: offset.y))
    }

    private func resizeHandle(at point: NSPoint, selectionRect: NSRect) -> ResizeHandle? {
        for (handle, rect) in handleRects(for: selectionRect) {
            if rect.insetBy(dx: -handleHitPadding, dy: -handleHitPadding).contains(point) {
                return handle
            }
        }
        return nil
    }

    private func handleRects(for rect: NSRect) -> [(ResizeHandle, NSRect)] {
        let half = handleVisualSize / 2
        func handleRect(_ x: CGFloat, _ y: CGFloat) -> NSRect {
            NSRect(x: x - half, y: y - half, width: handleVisualSize, height: handleVisualSize)
        }
        return [
            (.northWest, handleRect(rect.minX, rect.maxY)),
            (.north, handleRect(rect.midX, rect.maxY)),
            (.northEast, handleRect(rect.maxX, rect.maxY)),
            (.east, handleRect(rect.maxX, rect.midY)),
            (.southEast, handleRect(rect.maxX, rect.minY)),
            (.south, handleRect(rect.midX, rect.minY)),
            (.southWest, handleRect(rect.minX, rect.minY)),
            (.west, handleRect(rect.minX, rect.midY))
        ]
    }

    private func cursor(for handle: ResizeHandle) -> NSCursor {
        switch handle {
        case .north, .south:
            return .resizeUpDown
        case .east, .west:
            return .resizeLeftRight
        case .northWest, .northEast, .southEast, .southWest:
            return .crosshair
        }
    }

    private func drawResizeHandles(for rect: NSRect) {
        for (_, handleRect) in handleRects(for: rect) {
            NSColor.white.setFill()
            NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func toolbarGeometry(for selectionRect: NSRect) -> ToolbarGeometry {
        let horizontalMargin: CGFloat = 8
        let padding: CGFloat = 6
        let gap: CGFloat = 6
        let toolbarWidth = min(CGFloat(292), bounds.width - horizontalMargin * 2)
        let toolbarHeight: CGFloat = 46
        let proposedX = selectionRect.midX - toolbarWidth / 2
        let x = min(max(proposedX, bounds.minX + horizontalMargin), bounds.maxX - toolbarWidth - horizontalMargin)

        let belowY = selectionRect.minY - toolbarHeight - 10
        let y: CGFloat
        if belowY >= bounds.minY + horizontalMargin {
            y = belowY
        } else {
            y = min(selectionRect.maxY + 10, bounds.maxY - toolbarHeight - horizontalMargin)
        }

        let background = NSRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight)
        let buttonHeight = toolbarHeight - padding * 2
        let confirmWidth: CGFloat = 86
        let cancelWidth: CGFloat = 76
        let confirm = NSRect(
            x: background.maxX - padding - confirmWidth,
            y: background.minY + padding,
            width: confirmWidth,
            height: buttonHeight
        )
        let cancel = NSRect(
            x: confirm.minX - gap - cancelWidth,
            y: background.minY + padding,
            width: cancelWidth,
            height: buttonHeight
        )
        let metric = NSRect(
            x: background.minX + padding,
            y: background.minY + padding,
            width: max(cancel.minX - gap - background.minX - padding, 48),
            height: buttonHeight
        )
        return ToolbarGeometry(background: background, metric: metric, cancel: cancel, confirm: confirm)
    }

    private func toolbarAction(at point: NSPoint) -> ToolbarAction? {
        guard let selectionRect, isValidSelection(selectionRect) else { return nil }
        let toolbar = toolbarGeometry(for: selectionRect)
        if toolbar.cancel.contains(point) { return .cancel }
        if toolbar.confirm.contains(point) { return .confirm }
        return nil
    }

    private func drawToolbar(for selectionRect: NSRect) {
        let toolbar = toolbarGeometry(for: selectionRect)
        let copy = CaptureSelectionCopy.current

        NSColor.black.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: toolbar.background, xRadius: 8, yRadius: 8).fill()

        drawCenteredText(
            "\(Int(selectionRect.width.rounded())) x \(Int(selectionRect.height.rounded()))",
            in: toolbar.metric,
            color: NSColor.white.withAlphaComponent(0.82),
            font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        )

        let cancelColor = pressedToolbarAction == .cancel
            ? NSColor.white.withAlphaComponent(0.25)
            : NSColor.white.withAlphaComponent(0.14)
        cancelColor.setFill()
        NSBezierPath(roundedRect: toolbar.cancel, xRadius: 6, yRadius: 6).fill()
        drawCenteredText(copy.cancel, in: toolbar.cancel, color: .white, font: .systemFont(ofSize: 13, weight: .semibold))

        let confirmColor = pressedToolbarAction == .confirm
            ? NSColor.systemBlue.withAlphaComponent(0.72)
            : NSColor.systemBlue
        confirmColor.setFill()
        NSBezierPath(roundedRect: toolbar.confirm, xRadius: 6, yRadius: 6).fill()
        drawCenteredText(copy.confirm, in: toolbar.confirm, color: .white, font: .systemFont(ofSize: 13, weight: .semibold))
    }

    private func drawCenteredText(_ text: String, in rect: NSRect, color: NSColor, font: NSFont) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        let drawRect = NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        string.draw(in: drawRect, withAttributes: attributes)
    }
}

private struct CaptureSelectionCopy {
    let cancel: String
    let confirm: String

    static var current: CaptureSelectionCopy {
        switch UserDefaults.standard.string(forKey: "appLanguage") {
        case "zh-Hans", "zhHans":
            return CaptureSelectionCopy(cancel: "取消", confirm: "确认")
        case "zh-Hant", "zhHant":
            return CaptureSelectionCopy(cancel: "取消", confirm: "確認")
        case "ja":
            return CaptureSelectionCopy(cancel: "キャンセル", confirm: "確定")
        case "ko":
            return CaptureSelectionCopy(cancel: "취소", confirm: "확인")
        case "mt":
            return CaptureSelectionCopy(cancel: "Ikkanċella", confirm: "Ikkonferma")
        default:
            return CaptureSelectionCopy(cancel: "Cancel", confirm: "Confirm")
        }
    }
}
