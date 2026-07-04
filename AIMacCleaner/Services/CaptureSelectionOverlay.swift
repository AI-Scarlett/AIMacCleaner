import AppKit
import CoreGraphics

@MainActor
final class CaptureSelectionOverlayController {
    private let completion: (CGRect?) -> Void
    private var windows: [NSWindow] = []
    private var didComplete = false

    init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
    }

    func begin() {
        for screen in NSScreen.screens {
            let window = CaptureSelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false

            let view = CaptureSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onComplete = { [weak self, weak window] localRect in
                guard let window else {
                    self?.finish(nil)
                    return
                }
                self?.finish(window.convertToScreen(localRect))
            }
            view.onCancel = { [weak self] in
                self?.finish(nil)
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            windows.append(window)
        }
        NSCursor.crosshair.set()
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
        completion(rect)
    }
}

private final class CaptureSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class CaptureSelectionView: NSView {
    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()

        guard let selectionRect else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        selectionRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
        path.lineWidth = 2
        path.stroke()

        NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
        let inner = NSBezierPath(roundedRect: selectionRect.insetBy(dx: 2, dy: 2), xRadius: 2, yRadius: 2)
        inner.lineWidth = 1
        inner.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width >= 6, rect.height >= 6 else {
            onCancel?()
            return
        }
        onComplete?(rect)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }
}
