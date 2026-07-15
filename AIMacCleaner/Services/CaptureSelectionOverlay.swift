import AppKit
import CoreGraphics
import CoreImage

@MainActor
final class CaptureSelectionOverlayController {
    private let snapshots: [CaptureScreenSnapshot]
    private let completion: (CaptureSelectionResult?) -> Void
    private let previousFrontmostApplication = NSWorkspace.shared.frontmostApplication
    private var windows: [NSWindow] = []
    private var views: [CaptureSelectionView] = []
    private var activeView: CaptureSelectionView?
    private var didComplete = false
    private lazy var toolbarController = CaptureToolbarController(copy: .current)
    private lazy var infoController = CaptureInfoPanelController(copy: .current)

    init(
        snapshots: [CaptureScreenSnapshot],
        completion: @escaping (CaptureSelectionResult?) -> Void
    ) {
        self.snapshots = snapshots
        self.completion = completion
        configurePanels()
    }

    func begin() {
        let mouseLocation = NSEvent.mouseLocation
        NSApp.activate(ignoringOtherApps: true)

        for snapshot in snapshots {
            let window = CaptureSelectionWindow(
                contentRect: snapshot.screenFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = CaptureSelectionView(
                frame: NSRect(origin: .zero, size: snapshot.screenFrame.size),
                snapshot: snapshot
            )
            view.onActivate = { [weak self, weak view] in
                guard let view else { return }
                self?.activate(view)
            }
            view.onStateChanged = { [weak self, weak view] in
                guard let view else { return }
                self?.updatePanels(for: view)
            }
            view.onRequestAction = { [weak self] action in
                self?.complete(action)
            }
            view.onCancel = { [weak self] in
                self?.finish(nil)
            }
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            views.append(view)

            if snapshot.screenFrame.contains(mouseLocation) {
                view.updateHover(at: window.convertPoint(fromScreen: mouseLocation))
                window.makeKey()
                window.makeFirstResponder(view)
            }
        }
        NSCursor.crosshair.set()
    }

    private func configurePanels() {
        toolbarController.onToolChanged = { [weak self] tool in
            self?.activeView?.setSelectedTool(tool)
            self?.refocusActiveView()
        }
        toolbarController.onColorChanged = { [weak self] color in
            self?.activeView?.setAnnotationColor(color)
            self?.refocusActiveView()
        }
        toolbarController.onUndo = { [weak self] in
            self?.activeView?.undo()
            self?.refocusActiveView()
        }
        toolbarController.onRedo = { [weak self] in
            self?.activeView?.redo()
            self?.refocusActiveView()
        }
        toolbarController.onCopy = { [weak self] in self?.complete(.copy) }
        toolbarController.onSave = { [weak self] in self?.complete(.save) }
        toolbarController.onPin = { [weak self] in self?.complete(.pin) }
        toolbarController.onRecognizeText = { [weak self] in self?.complete(.recognizeText) }
        toolbarController.onCancel = { [weak self] in self?.finish(nil) }

        infoController.onRatioChanged = { [weak self] ratio in
            self?.activeView?.setAspectRatio(ratio)
            self?.refocusActiveView()
        }
        infoController.onPreviousSelection = { [weak self] in
            self?.activeView?.selectHistory(offset: -1)
            self?.refocusActiveView()
        }
        infoController.onNextSelection = { [weak self] in
            self?.activeView?.selectHistory(offset: 1)
            self?.refocusActiveView()
        }
    }

    private func activate(_ view: CaptureSelectionView) {
        activeView = view
        for otherView in views where otherView !== view {
            otherView.setActive(false)
        }
        view.setActive(true)
        refocusActiveView()
        updatePanels(for: view)
    }

    private func updatePanels(for view: CaptureSelectionView) {
        guard view === activeView,
              view.isSelectionLocked,
              let selectionRect = view.selectionRect,
              view.isValidSelection(selectionRect),
              let window = view.window else {
            toolbarController.hide()
            infoController.hide()
            return
        }

        toolbarController.update(
            selectedTool: view.selectedTool,
            color: view.annotationColor,
            canUndo: view.canUndo,
            canRedo: view.canRedo
        )
        infoController.update(
            pixelSize: NSSize(
                width: selectionRect.width * view.snapshot.scale,
                height: selectionRect.height * view.snapshot.scale
            ),
            ratio: view.aspectRatio,
            historyPosition: view.historyPosition,
            historyCount: view.historyCount
        )

        let globalSelection = window.convertToScreen(selectionRect)
        let screenFrame = view.snapshot.screenFrame
        position(
            panel: infoController.panel,
            relativeTo: globalSelection,
            screenFrame: screenFrame,
            preferredAbove: true,
            gap: 10
        )
        position(
            panel: toolbarController.panel,
            relativeTo: globalSelection,
            screenFrame: screenFrame,
            preferredAbove: false,
            gap: 12
        )
        infoController.show()
        toolbarController.show()
    }

    private func position(
        panel: NSPanel,
        relativeTo selection: NSRect,
        screenFrame: NSRect,
        preferredAbove: Bool,
        gap: CGFloat
    ) {
        let size = panel.frame.size
        let margin: CGFloat = 8
        let centeredX = selection.midX - size.width / 2
        let x = min(
            max(centeredX, screenFrame.minX + margin),
            screenFrame.maxX - size.width - margin
        )
        let aboveY = selection.maxY + gap
        let belowY = selection.minY - size.height - gap
        let canUseAbove = aboveY + size.height <= screenFrame.maxY - margin
        let canUseBelow = belowY >= screenFrame.minY + margin
        let y: CGFloat
        if preferredAbove {
            y = canUseAbove ? aboveY : (canUseBelow ? belowY : screenFrame.maxY - size.height - margin)
        } else {
            y = canUseBelow ? belowY : (canUseAbove ? aboveY : screenFrame.minY + margin)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func refocusActiveView() {
        guard let activeView, let window = activeView.window else { return }
        window.makeKey()
        window.makeFirstResponder(activeView)
    }

    private func complete(_ action: CaptureSelectionAction) {
        guard let activeView,
              let selectionRect = activeView.selectionRect,
              let window = activeView.window,
              let image = activeView.renderedSelectionImage() else {
            return
        }
        CaptureSelectionHistoryStore.shared.record(
            selectionRect,
            for: activeView.snapshot.displayID
        )
        let result = CaptureSelectionResult(
            image: image,
            action: action,
            screenRect: window.convertToScreen(selectionRect)
        )
        finish(result)
    }

    private func finish(_ result: CaptureSelectionResult?) {
        guard !didComplete else { return }
        didComplete = true
        NSCursor.arrow.set()
        toolbarController.hide()
        infoController.hide()
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        views.removeAll()

        let traceFencePID = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == traceFencePID,
           let previousFrontmostApplication,
           previousFrontmostApplication.processIdentifier != traceFencePID,
           !previousFrontmostApplication.isTerminated {
            previousFrontmostApplication.activate(options: [.activateIgnoringOtherApps])
        }
        completion(result)
    }
}

private final class CaptureSelectionWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CaptureControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private enum CaptureAspectRatio: Int, CaseIterable {
    case free
    case square
    case fourThree
    case sixteenNine
    case threeTwo

    var value: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .threeTwo: return 3.0 / 2.0
        }
    }

    func title(copy: CaptureSelectionCopy) -> String {
        switch self {
        case .free: return copy.freeRatio
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .sixteenNine: return "16:9"
        case .threeTwo: return "3:2"
        }
    }
}

private enum CaptureAnnotationTool: Int, CaseIterable {
    case selection
    case rectangle
    case arrow
    case pen
    case highlight
    case mosaic
    case text

    var symbolName: String {
        switch self {
        case .selection: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .highlight: return "highlighter"
        case .mosaic: return "square.grid.3x3.fill"
        case .text: return "textformat"
        }
    }

    func title(copy: CaptureSelectionCopy) -> String {
        switch self {
        case .selection: return copy.selectTool
        case .rectangle: return copy.rectangleTool
        case .arrow: return copy.arrowTool
        case .pen: return copy.penTool
        case .highlight: return copy.highlightTool
        case .mosaic: return copy.mosaicTool
        case .text: return copy.textTool
        }
    }
}

private struct CaptureAnnotation {
    let tool: CaptureAnnotationTool
    var points: [NSPoint]
    let color: NSColor
    let lineWidth: CGFloat
    var text: String?
}

@MainActor
private final class CaptureToolbarController: NSObject {
    let panel: NSPanel
    var onToolChanged: ((CaptureAnnotationTool) -> Void)?
    var onColorChanged: ((NSColor) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onPin: (() -> Void)?
    var onRecognizeText: (() -> Void)?
    var onCancel: (() -> Void)?

    private let copy: CaptureSelectionCopy
    private var toolButtons: [CaptureAnnotationTool: NSButton] = [:]
    private let colorWell = NSColorWell()
    private let undoButton: NSButton
    private let redoButton: NSButton

    init(copy: CaptureSelectionCopy) {
        self.copy = copy
        undoButton = Self.makeButton(symbol: "arrow.uturn.backward", toolTip: copy.undo)
        redoButton = Self.makeButton(symbol: "arrow.uturn.forward", toolTip: copy.redo)
        panel = CaptureControlPanel(
            contentRect: NSRect(x: 0, y: 0, width: 604, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    private func configurePanel() {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let background = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        background.autoresizingMask = [.width, .height]
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 9
        background.layer?.masksToBounds = true
        panel.contentView = background

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)

        for tool in CaptureAnnotationTool.allCases {
            let button = Self.makeButton(
                symbol: tool.symbolName,
                toolTip: tool.title(copy: copy)
            )
            button.tag = tool.rawValue
            button.target = self
            button.action = #selector(selectTool(_:))
            button.setButtonType(.toggle)
            toolButtons[tool] = button
            stack.addArrangedSubview(button)
        }

        colorWell.color = .systemRed
        colorWell.isBordered = false
        colorWell.toolTip = copy.color
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(colorWell)

        stack.addArrangedSubview(Self.makeSeparator())
        undoButton.target = self
        undoButton.action = #selector(undo)
        redoButton.target = self
        redoButton.action = #selector(redo)
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(redoButton)
        stack.addArrangedSubview(Self.makeSeparator())

        let recognizeTextButton = Self.makeButton(symbol: "text.viewfinder", toolTip: copy.recognizeText)
        recognizeTextButton.target = self
        recognizeTextButton.action = #selector(recognizeText)
        stack.addArrangedSubview(recognizeTextButton)

        let pin = Self.makeButton(symbol: "pin", toolTip: copy.pin)
        pin.target = self
        pin.action = #selector(pinImage)
        stack.addArrangedSubview(pin)

        let save = Self.makeButton(symbol: "square.and.arrow.down", toolTip: copy.save)
        save.target = self
        save.action = #selector(saveImage)
        stack.addArrangedSubview(save)

        let copyButton = Self.makeButton(symbol: "doc.on.doc.fill", toolTip: copy.copy)
        copyButton.target = self
        copyButton.action = #selector(copyImage)
        copyButton.contentTintColor = .systemBlue
        stack.addArrangedSubview(copyButton)

        let cancel = Self.makeButton(symbol: "xmark", toolTip: copy.cancel)
        cancel.target = self
        cancel.action = #selector(cancelCapture)
        stack.addArrangedSubview(cancel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -7),
            colorWell.widthAnchor.constraint(equalToConstant: 30),
            colorWell.heightAnchor.constraint(equalToConstant: 30)
        ])
        toolButtons[.selection]?.state = .on
    }

    func update(
        selectedTool: CaptureAnnotationTool,
        color: NSColor,
        canUndo: Bool,
        canRedo: Bool
    ) {
        for (tool, button) in toolButtons {
            button.state = tool == selectedTool ? .on : .off
            button.contentTintColor = tool == selectedTool ? .systemBlue : .white
        }
        colorWell.color = color
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    @objc private func selectTool(_ sender: NSButton) {
        guard let tool = CaptureAnnotationTool(rawValue: sender.tag) else { return }
        onToolChanged?(tool)
    }

    @objc private func colorChanged(_ sender: NSColorWell) { onColorChanged?(sender.color) }
    @objc private func undo() { onUndo?() }
    @objc private func redo() { onRedo?() }
    @objc private func copyImage() { onCopy?() }
    @objc private func saveImage() { onSave?() }
    @objc private func pinImage() { onPin?() }
    @objc private func recognizeText() { onRecognizeText?() }
    @objc private func cancelCapture() { onCancel?() }

    fileprivate static func makeButton(symbol: String, toolTip: String) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .recessed
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.toolTip = toolTip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32)
        ])
        return button
    }

    private static func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 22)
        ])
        return separator
    }
}

@MainActor
private final class CaptureInfoPanelController: NSObject {
    let panel: NSPanel
    var onRatioChanged: ((CaptureAspectRatio) -> Void)?
    var onPreviousSelection: (() -> Void)?
    var onNextSelection: (() -> Void)?

    private let copy: CaptureSelectionCopy
    private let sizeLabel = NSTextField(labelWithString: "0 x 0")
    private let historyLabel = NSTextField(labelWithString: "")
    private let ratioPopup = NSPopUpButton()
    private let previousButton: NSButton
    private let nextButton: NSButton

    init(copy: CaptureSelectionCopy) {
        self.copy = copy
        previousButton = CaptureToolbarController.makeButton(
            symbol: "chevron.left",
            toolTip: copy.previousSelection
        )
        nextButton = CaptureToolbarController.makeButton(
            symbol: "chevron.right",
            toolTip: copy.nextSelection
        )
        panel = CaptureControlPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 42),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    private func configurePanel() {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let background = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        background.autoresizingMask = [.width, .height]
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        panel.contentView = background

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        sizeLabel.textColor = .white
        sizeLabel.alignment = .center
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false

        ratioPopup.addItems(withTitles: CaptureAspectRatio.allCases.map { $0.title(copy: copy) })
        ratioPopup.target = self
        ratioPopup.action = #selector(ratioChanged(_:))
        ratioPopup.controlSize = .small
        ratioPopup.toolTip = copy.selectionRatio
        ratioPopup.translatesAutoresizingMaskIntoConstraints = false

        historyLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        historyLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        historyLabel.alignment = .center
        historyLabel.translatesAutoresizingMaskIntoConstraints = false

        previousButton.target = self
        previousButton.action = #selector(previousSelection)
        nextButton.target = self
        nextButton.action = #selector(nextSelection)

        let stack = NSStackView(views: [sizeLabel, ratioPopup, previousButton, historyLabel, nextButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            sizeLabel.widthAnchor.constraint(equalToConstant: 90),
            ratioPopup.widthAnchor.constraint(equalToConstant: 82),
            historyLabel.widthAnchor.constraint(equalToConstant: 28)
        ])
    }

    func update(
        pixelSize: NSSize,
        ratio: CaptureAspectRatio,
        historyPosition: Int?,
        historyCount: Int
    ) {
        sizeLabel.stringValue = "\(Int(pixelSize.width.rounded())) x \(Int(pixelSize.height.rounded()))"
        ratioPopup.selectItem(at: ratio.rawValue)
        if let historyPosition, historyCount > 0 {
            historyLabel.stringValue = "\(historyPosition + 1)/\(historyCount)"
        } else {
            historyLabel.stringValue = "-/\(historyCount)"
        }
        previousButton.isEnabled = historyCount > 0
        nextButton.isEnabled = historyCount > 0
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    @objc private func ratioChanged(_ sender: NSPopUpButton) {
        guard let ratio = CaptureAspectRatio(rawValue: sender.indexOfSelectedItem) else { return }
        onRatioChanged?(ratio)
    }

    @objc private func previousSelection() { onPreviousSelection?() }
    @objc private func nextSelection() { onNextSelection?() }
}

private final class CaptureSelectionView: NSView, NSTextFieldDelegate {
    let snapshot: CaptureScreenSnapshot
    var onActivate: (() -> Void)?
    var onStateChanged: (() -> Void)?
    var onRequestAction: ((CaptureSelectionAction) -> Void)?
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
        case pendingWindow(target: CaptureWindowTarget, anchor: NSPoint)
        case drawing(anchor: NSPoint)
        case moving(anchor: NSPoint, initialRect: NSRect)
        case resizing(handle: ResizeHandle, initialRect: NSRect)
        case annotating
    }

    private let minimumSelectionSize: CGFloat = 24
    private let handleVisualSize: CGFloat = 9
    private let handleHitPadding: CGFloat = 7
    private var interaction: Interaction?
    private var hoverTarget: CaptureWindowTarget?
    private var draftAnnotation: CaptureAnnotation?
    private var annotations: [CaptureAnnotation] = []
    private var redoAnnotations: [CaptureAnnotation] = []
    private var trackingAreaReference: NSTrackingArea?
    private var pixelatedImage: NSImage?
    private var textField: NSTextField?
    private var textOrigin: NSPoint?
    private var isActive = false
    private(set) var isSelectionLocked = false
    private(set) var selectedTool: CaptureAnnotationTool = .selection
    private(set) var annotationColor = NSColor.systemRed
    private(set) var aspectRatio: CaptureAspectRatio = .free
    private var historyIndex: Int?
    private lazy var history: [NSRect] = CaptureSelectionHistoryStore.shared.selections(
        for: snapshot.displayID,
        within: bounds
    )

    private(set) var selectionRect: NSRect? {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            onStateChanged?()
        }
    }

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoAnnotations.isEmpty }
    var historyPosition: Int? { historyIndex }
    var historyCount: Int { history.count }

    override var acceptsFirstResponder: Bool { true }

    init(frame frameRect: NSRect, snapshot: CaptureScreenSnapshot) {
        self.snapshot = snapshot
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func draw(_ dirtyRect: NSRect) {
        snapshot.image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        NSColor.black.withAlphaComponent(0.42).setFill()
        bounds.fill()

        guard let visibleSelection = selectionRect ?? hoverTarget?.rect,
              visibleSelection.width > 0,
              visibleSelection.height > 0 else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: visibleSelection).addClip()
        snapshot.image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        if selectionRect != nil {
            drawAnnotations()
        }

        let borderColor = selectionRect == nil ? NSColor.white : NSColor.systemBlue
        borderColor.setStroke()
        let border = NSBezierPath(rect: visibleSelection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = selectionRect == nil ? 1.5 : 2
        border.stroke()

        if let selectionRect, isSelectionLocked {
            drawResizeHandles(for: selectionRect)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard let selectionRect, isSelectionLocked else { return }
        if selectedTool == .selection {
            addCursorRect(selectionRect, cursor: .openHand)
            for (handle, rect) in handleRects(for: selectionRect) {
                addCursorRect(
                    rect.insetBy(dx: -handleHitPadding, dy: -handleHitPadding),
                    cursor: cursor(for: handle)
                )
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard selectionRect == nil, interaction == nil else { return }
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard selectionRect == nil else { return }
        hoverTarget = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = clampedPoint(convert(event.locationInWindow, from: nil))

        if let selectionRect, isSelectionLocked {
            onActivate?()
            if selectedTool == .selection {
                if let handle = resizeHandle(at: point, selectionRect: selectionRect) {
                    interaction = .resizing(handle: handle, initialRect: selectionRect)
                    return
                }
                if selectionRect.contains(point) {
                    if event.clickCount >= 2 {
                        onRequestAction?(.copy)
                    } else {
                        interaction = .moving(anchor: point, initialRect: selectionRect)
                        NSCursor.closedHand.set()
                    }
                    return
                }
                beginManualSelection(at: point)
                return
            }

            guard selectionRect.contains(point) else { return }
            if selectedTool == .text {
                beginTextEntry(at: point)
                return
            }
            draftAnnotation = CaptureAnnotation(
                tool: selectedTool,
                points: [point],
                color: annotationColor,
                lineWidth: lineWidth(for: selectedTool),
                text: nil
            )
            interaction = .annotating
            needsDisplay = true
            return
        }

        if let hoverTarget {
            interaction = .pendingWindow(target: hoverTarget, anchor: point)
        } else {
            beginManualSelection(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let interaction else { return }
        let point = clampedPoint(convert(event.locationInWindow, from: nil))

        switch interaction {
        case .pendingWindow(_, let anchor):
            if hypot(point.x - anchor.x, point.y - anchor.y) >= 4 {
                hoverTarget = nil
                isSelectionLocked = false
                selectionRect = constrainedDrawingRect(from: anchor, to: point)
                self.interaction = .drawing(anchor: anchor)
            }
        case .drawing(let anchor):
            selectionRect = constrainedDrawingRect(from: anchor, to: point)
        case .moving(let anchor, let initialRect):
            selectionRect = constrainedMovedRect(
                initialRect.offsetBy(dx: point.x - anchor.x, dy: point.y - anchor.y)
            )
        case .resizing(let handle, let initialRect):
            selectionRect = resizedRect(initialRect, handle: handle, to: point)
        case .annotating:
            guard var draftAnnotation else { return }
            let clipped = pointInsideSelection(point)
            draftAnnotation.points.append(clipped)
            self.draftAnnotation = draftAnnotation
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            interaction = nil
            NSCursor.crosshair.set()
        }
        guard let interaction else { return }

        switch interaction {
        case .pendingWindow(let target, _):
            selectionRect = target.rect.integral
            hoverTarget = nil
            isSelectionLocked = true
            historyIndex = nil
            onActivate?()
        case .drawing:
            if let selectionRect, isValidSelection(selectionRect) {
                self.selectionRect = selectionRect.integral
                isSelectionLocked = true
                historyIndex = nil
                onActivate?()
            } else {
                selectionRect = nil
                isSelectionLocked = false
            }
        case .moving, .resizing:
            if let selectionRect {
                self.selectionRect = selectionRect.integral
                isSelectionLocked = true
            }
        case .annotating:
            commitDraftAnnotation()
        }
        onStateChanged?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command), (event.keyCode == 123 || event.keyCode == 124) {
            selectHistory(offset: event.keyCode == 123 ? -1 : 1)
            return
        }
        if modifiers.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": onRequestAction?(.copy); return
            case "s": onRequestAction?(.save); return
            case "z":
                modifiers.contains(.shift) ? redo() : undo()
                return
            default: break
            }
        }

        switch event.keyCode {
        case 53:
            if textField != nil {
                cancelTextEntry()
            } else {
                onCancel?()
            }
        case 36, 76:
            if isSelectionLocked { onRequestAction?(.copy) }
        case 48:
            cycleAspectRatio(backward: modifiers.contains(.shift))
        case 7:
            toggleAspectOrientation()
        case 51, 117:
            clearSelection()
        case 123, 124, 125, 126:
            moveSelection(
                keyCode: event.keyCode,
                step: modifiers.contains(.shift) ? 10 : 1
            )
        default:
            super.keyDown(with: event)
        }
    }

    func setActive(_ active: Bool) {
        isActive = active
        needsDisplay = true
    }

    func updateHover(at point: NSPoint) {
        guard selectionRect == nil, interaction == nil else { return }
        hoverTarget = snapshot.windowTargets.first(where: { $0.rect.contains(point) })
        needsDisplay = true
    }

    func setSelectedTool(_ tool: CaptureAnnotationTool) {
        commitTextEntryIfNeeded()
        selectedTool = tool
        window?.invalidateCursorRects(for: self)
        onStateChanged?()
    }

    func setAnnotationColor(_ color: NSColor) {
        annotationColor = color.usingColorSpace(.deviceRGB) ?? color
        onStateChanged?()
    }

    func setAspectRatio(_ ratio: CaptureAspectRatio) {
        aspectRatio = ratio
        if let selectionRect, let value = ratio.value {
            var adjusted = selectionRect
            adjusted.size.height = adjusted.width / value
            if adjusted.maxY > bounds.maxY {
                adjusted.size.height = bounds.maxY - adjusted.minY
                adjusted.size.width = adjusted.height * value
            }
            self.selectionRect = constrainedMovedRect(adjusted).integral
        }
        onStateChanged?()
    }

    func undo() {
        commitTextEntryIfNeeded()
        guard let annotation = annotations.popLast() else { return }
        redoAnnotations.append(annotation)
        needsDisplay = true
        onStateChanged?()
    }

    func redo() {
        guard let annotation = redoAnnotations.popLast() else { return }
        annotations.append(annotation)
        needsDisplay = true
        onStateChanged?()
    }

    func selectHistory(offset: Int) {
        guard !history.isEmpty else { return }
        let current = historyIndex ?? (offset < 0 ? 0 : history.count - 1)
        let next = (current + offset + history.count) % history.count
        historyIndex = next
        selectionRect = history[next].intersection(bounds).integral
        isSelectionLocked = true
        selectedTool = .selection
        onActivate?()
    }

    func isValidSelection(_ rect: NSRect) -> Bool {
        rect.width >= minimumSelectionSize && rect.height >= minimumSelectionSize
    }

    func renderedSelectionImage() -> NSImage? {
        commitTextEntryIfNeeded()
        guard let selectionRect,
              isValidSelection(selectionRect),
              let croppedSnapshot = croppedSnapshotImage(for: selectionRect) else {
            return nil
        }
        let scale = snapshot.scale
        let pixelWidth = max(Int((selectionRect.width * scale).rounded()), 1)
        let pixelHeight = max(Int((selectionRect.height * scale).rounded()), 1)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }
        bitmap.size = selectionRect.size

        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = context
        context.cgContext.saveGState()
        context.cgContext.scaleBy(x: scale, y: scale)
        croppedSnapshot.draw(
            in: NSRect(origin: .zero, size: selectionRect.size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.cgContext.translateBy(x: -selectionRect.minX, y: -selectionRect.minY)
        drawAnnotations(includeDraft: false)
        context.cgContext.restoreGState()
        context.flushGraphics()
        NSGraphicsContext.current = previousContext

        let image = NSImage(size: selectionRect.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func croppedSnapshotImage(for selectionRect: NSRect) -> NSImage? {
        var proposedRect = NSRect(origin: .zero, size: snapshot.image.size)
        guard let source = snapshot.image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }
        let scaleX = CGFloat(source.width) / max(bounds.width, 1)
        let scaleY = CGFloat(source.height) / max(bounds.height, 1)
        var pixelRect = CGRect(
            x: selectionRect.minX * scaleX,
            y: (bounds.height - selectionRect.maxY) * scaleY,
            width: selectionRect.width * scaleX,
            height: selectionRect.height * scaleY
        ).integral
        pixelRect = pixelRect.intersection(
            CGRect(x: 0, y: 0, width: source.width, height: source.height)
        )
        guard pixelRect.width >= 1,
              pixelRect.height >= 1,
              let cropped = source.cropping(to: pixelRect) else {
            return nil
        }
        return NSImage(cgImage: cropped, size: selectionRect.size)
    }

    private func beginManualSelection(at point: NSPoint) {
        commitTextEntryIfNeeded()
        annotations.removeAll()
        redoAnnotations.removeAll()
        hoverTarget = nil
        historyIndex = nil
        isSelectionLocked = false
        selectionRect = NSRect(origin: point, size: .zero)
        interaction = .drawing(anchor: point)
        selectedTool = .selection
        onActivate?()
    }

    private func clearSelection() {
        commitTextEntryIfNeeded()
        annotations.removeAll()
        redoAnnotations.removeAll()
        selectionRect = nil
        hoverTarget = nil
        isSelectionLocked = false
        historyIndex = nil
        selectedTool = .selection
        onStateChanged?()
    }

    private func constrainedDrawingRect(from start: NSPoint, to end: NSPoint) -> NSRect {
        guard let ratio = aspectRatio.value else {
            return standardizedRect(from: start, to: end)
        }
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        var width = abs(deltaX)
        var height = abs(deltaY)
        if height < 1 || width / max(height, 1) > ratio {
            height = width / ratio
        } else {
            width = height * ratio
        }
        let candidate = NSRect(
            x: deltaX >= 0 ? start.x : start.x - width,
            y: deltaY >= 0 ? start.y : start.y - height,
            width: width,
            height: height
        )
        let clipped = candidate.intersection(bounds)
        if clipped.width < candidate.width || clipped.height < candidate.height {
            let maxWidth = min(candidate.width, bounds.width)
            let maxHeight = min(candidate.height, bounds.height)
            let fittedWidth = min(maxWidth, maxHeight * ratio)
            let fittedHeight = fittedWidth / ratio
            return NSRect(
                x: min(max(candidate.minX, bounds.minX), bounds.maxX - fittedWidth),
                y: min(max(candidate.minY, bounds.minY), bounds.maxY - fittedHeight),
                width: fittedWidth,
                height: fittedHeight
            )
        }
        return candidate
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

    private func pointInsideSelection(_ point: NSPoint) -> NSPoint {
        guard let selectionRect else { return point }
        return NSPoint(
            x: min(max(point.x, selectionRect.minX), selectionRect.maxX),
            y: min(max(point.y, selectionRect.minY), selectionRect.maxY)
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
        case .northWest: minX = point.x; maxY = point.y
        case .north: maxY = point.y
        case .northEast: maxX = point.x; maxY = point.y
        case .east: maxX = point.x
        case .southEast: maxX = point.x; minY = point.y
        case .south: minY = point.y
        case .southWest: minX = point.x; minY = point.y
        case .west: minX = point.x
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
        var result = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if let ratio = aspectRatio.value {
            let anchoredRight = [.northWest, .southWest, .west].contains(handle)
            let anchoredTop = [.southEast, .south, .southWest].contains(handle)
            let width = result.width
            let height = width / ratio
            result.origin.y = anchoredTop ? result.maxY - height : result.minY
            result.size.height = height
            if result.maxY > bounds.maxY || result.minY < bounds.minY {
                let fittedHeight = min(result.height, bounds.height)
                let fittedWidth = fittedHeight * ratio
                result.origin.x = anchoredRight ? result.maxX - fittedWidth : result.minX
                result.size = NSSize(width: fittedWidth, height: fittedHeight)
                result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - fittedHeight)
            }
        }
        return result.intersection(bounds)
    }

    private func moveSelection(keyCode: UInt16, step: CGFloat) {
        guard let selectionRect, isSelectionLocked else { return }
        let offset: NSPoint
        switch keyCode {
        case 123: offset = NSPoint(x: -step, y: 0)
        case 124: offset = NSPoint(x: step, y: 0)
        case 125: offset = NSPoint(x: 0, y: -step)
        case 126: offset = NSPoint(x: 0, y: step)
        default: return
        }
        self.selectionRect = constrainedMovedRect(
            selectionRect.offsetBy(dx: offset.x, dy: offset.y)
        ).integral
    }

    private func cycleAspectRatio(backward: Bool) {
        let all = CaptureAspectRatio.allCases
        let delta = backward ? -1 : 1
        let next = (aspectRatio.rawValue + delta + all.count) % all.count
        setAspectRatio(all[next])
    }

    private func toggleAspectOrientation() {
        guard let selectionRect, aspectRatio.value != nil else { return }
        var toggled = selectionRect
        toggled.size = NSSize(width: selectionRect.height, height: selectionRect.width)
        self.selectionRect = constrainedMovedRect(toggled.intersection(bounds)).integral
    }

    private func resizeHandle(at point: NSPoint, selectionRect: NSRect) -> ResizeHandle? {
        handleRects(for: selectionRect).first {
            $0.1.insetBy(dx: -handleHitPadding, dy: -handleHitPadding).contains(point)
        }?.0
    }

    private func handleRects(for rect: NSRect) -> [(ResizeHandle, NSRect)] {
        let half = handleVisualSize / 2
        func make(_ x: CGFloat, _ y: CGFloat) -> NSRect {
            NSRect(x: x - half, y: y - half, width: handleVisualSize, height: handleVisualSize)
        }
        return [
            (.northWest, make(rect.minX, rect.maxY)),
            (.north, make(rect.midX, rect.maxY)),
            (.northEast, make(rect.maxX, rect.maxY)),
            (.east, make(rect.maxX, rect.midY)),
            (.southEast, make(rect.maxX, rect.minY)),
            (.south, make(rect.midX, rect.minY)),
            (.southWest, make(rect.minX, rect.minY)),
            (.west, make(rect.minX, rect.midY))
        ]
    }

    private func cursor(for handle: ResizeHandle) -> NSCursor {
        switch handle {
        case .north, .south: return .resizeUpDown
        case .east, .west: return .resizeLeftRight
        case .northWest, .northEast, .southEast, .southWest: return .crosshair
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

    private func lineWidth(for tool: CaptureAnnotationTool) -> CGFloat {
        switch tool {
        case .highlight: return 18
        case .mosaic: return 22
        case .pen: return 4
        default: return 3
        }
    }

    private func commitDraftAnnotation() {
        guard let draftAnnotation, draftAnnotation.points.count >= 2 else {
            self.draftAnnotation = nil
            return
        }
        annotations.append(draftAnnotation)
        redoAnnotations.removeAll()
        self.draftAnnotation = nil
        needsDisplay = true
        onStateChanged?()
    }

    private func beginTextEntry(at point: NSPoint) {
        commitTextEntryIfNeeded()
        guard let selectionRect else { return }
        let field = NSTextField()
        field.placeholderString = CaptureSelectionCopy.current.enterText
        field.font = .systemFont(ofSize: 18, weight: .semibold)
        field.textColor = annotationColor
        field.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(commitTextField)
        let width = min(max(selectionRect.maxX - point.x, 120), 280)
        field.frame = NSRect(
            x: point.x,
            y: min(point.y, selectionRect.maxY - 32),
            width: width,
            height: 30
        )
        addSubview(field)
        textField = field
        textOrigin = point
        window?.makeFirstResponder(field)
    }

    @objc private func commitTextField() {
        commitTextEntryIfNeeded()
        window?.makeFirstResponder(self)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEntryIfNeeded()
    }

    private func commitTextEntryIfNeeded() {
        guard let field = textField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, let origin = textOrigin {
            annotations.append(
                CaptureAnnotation(
                    tool: .text,
                    points: [origin],
                    color: annotationColor,
                    lineWidth: 0,
                    text: value
                )
            )
            redoAnnotations.removeAll()
        }
        field.removeFromSuperview()
        textField = nil
        textOrigin = nil
        needsDisplay = true
        onStateChanged?()
    }

    private func cancelTextEntry() {
        textField?.removeFromSuperview()
        textField = nil
        textOrigin = nil
        window?.makeFirstResponder(self)
    }

    private func drawAnnotations(includeDraft: Bool = true) {
        guard let selectionRect else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()
        for annotation in annotations {
            draw(annotation)
        }
        if includeDraft, let draftAnnotation {
            draw(draftAnnotation)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ annotation: CaptureAnnotation) {
        guard let first = annotation.points.first else { return }
        switch annotation.tool {
        case .selection:
            break
        case .rectangle:
            guard let last = annotation.points.last else { return }
            annotation.color.setStroke()
            let path = NSBezierPath(rect: standardizedRect(from: first, to: last))
            path.lineWidth = annotation.lineWidth
            path.stroke()
        case .arrow:
            guard let last = annotation.points.last else { return }
            drawArrow(from: first, to: last, color: annotation.color, width: annotation.lineWidth)
        case .pen:
            drawStroke(annotation.points, color: annotation.color, width: annotation.lineWidth)
        case .highlight:
            drawStroke(
                annotation.points,
                color: annotation.color.withAlphaComponent(0.34),
                width: annotation.lineWidth
            )
        case .mosaic:
            drawMosaic(points: annotation.points, width: annotation.lineWidth)
        case .text:
            guard let text = annotation.text else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: annotation.color,
                .strokeColor: NSColor.black.withAlphaComponent(0.42),
                .strokeWidth: -1.5
            ]
            text.draw(at: first, withAttributes: attributes)
        }
    }

    private func drawStroke(_ points: [NSPoint], color: NSColor, width: CGFloat) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: first)
        for point in points.dropFirst() { path.line(to: point) }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private func drawArrow(from start: NSPoint, to end: NSPoint, color: NSColor, width: CGFloat) {
        drawStroke([start, end], color: color, width: width)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 13
        let spread: CGFloat = .pi / 7
        let pointA = NSPoint(
            x: end.x - headLength * cos(angle - spread),
            y: end.y - headLength * sin(angle - spread)
        )
        let pointB = NSPoint(
            x: end.x - headLength * cos(angle + spread),
            y: end.y - headLength * sin(angle + spread)
        )
        let head = NSBezierPath()
        head.move(to: pointA)
        head.line(to: end)
        head.line(to: pointB)
        head.lineWidth = width
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        color.setStroke()
        head.stroke()
    }

    private func drawMosaic(points: [NSPoint], width: CGFloat) {
        guard !points.isEmpty else { return }
        let image = pixelatedSnapshot()
        for point in points {
            let clipRect = NSRect(
                x: point.x - width / 2,
                y: point.y - width / 2,
                width: width,
                height: width
            )
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: clipRect).addClip()
            image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func pixelatedSnapshot() -> NSImage {
        if let pixelatedImage { return pixelatedImage }
        var sourceRect = NSRect(origin: .zero, size: snapshot.image.size)
        guard let cgImage = snapshot.image.cgImage(forProposedRect: &sourceRect, context: nil, hints: nil) else {
            return snapshot.image
        }
        let input = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIPixellate")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(12 * snapshot.scale, forKey: kCIInputScaleKey)
        let context = CIContext(options: [.cacheIntermediates: true])
        guard let output = filter?.outputImage,
              let result = context.createCGImage(output, from: input.extent) else {
            return snapshot.image
        }
        let image = NSImage(cgImage: result, size: bounds.size)
        pixelatedImage = image
        return image
    }
}

private struct CaptureSelectionCopy {
    let cancel: String
    let copy: String
    let save: String
    let pin: String
    let recognizeText: String
    let undo: String
    let redo: String
    let color: String
    let freeRatio: String
    let selectionRatio: String
    let previousSelection: String
    let nextSelection: String
    let selectTool: String
    let rectangleTool: String
    let arrowTool: String
    let penTool: String
    let highlightTool: String
    let mosaicTool: String
    let textTool: String
    let enterText: String

    static var current: CaptureSelectionCopy {
        switch UserDefaults.standard.string(forKey: "appLanguage") {
        case "zh-Hans", "zhHans":
            return CaptureSelectionCopy(
                cancel: "取消", copy: "复制并完成", save: "保存", pin: "钉在屏幕", recognizeText: "识别文字",
                undo: "撤销", redo: "重做", color: "标注颜色", freeRatio: "自由",
                selectionRatio: "选区比例", previousSelection: "上一个历史选区",
                nextSelection: "下一个历史选区", selectTool: "选择或移动",
                rectangleTool: "矩形", arrowTool: "箭头", penTool: "画笔",
                highlightTool: "高亮", mosaicTool: "马赛克", textTool: "文字",
                enterText: "输入文字"
            )
        case "zh-Hant", "zhHant":
            return CaptureSelectionCopy(
                cancel: "取消", copy: "複製並完成", save: "儲存", pin: "釘在螢幕", recognizeText: "辨識文字",
                undo: "復原", redo: "重做", color: "標註顏色", freeRatio: "自由",
                selectionRatio: "選區比例", previousSelection: "上一個歷史選區",
                nextSelection: "下一個歷史選區", selectTool: "選擇或移動",
                rectangleTool: "矩形", arrowTool: "箭頭", penTool: "畫筆",
                highlightTool: "醒目提示", mosaicTool: "馬賽克", textTool: "文字",
                enterText: "輸入文字"
            )
        case "ja":
            return CaptureSelectionCopy(
                cancel: "キャンセル", copy: "コピーして完了", save: "保存", pin: "画面に固定", recognizeText: "テキスト認識",
                undo: "元に戻す", redo: "やり直す", color: "注釈の色", freeRatio: "自由",
                selectionRatio: "選択範囲の比率", previousSelection: "前の選択範囲",
                nextSelection: "次の選択範囲", selectTool: "選択または移動",
                rectangleTool: "長方形", arrowTool: "矢印", penTool: "ペン",
                highlightTool: "ハイライト", mosaicTool: "モザイク", textTool: "テキスト",
                enterText: "テキストを入力"
            )
        case "ko":
            return CaptureSelectionCopy(
                cancel: "취소", copy: "복사 후 완료", save: "저장", pin: "화면에 고정", recognizeText: "텍스트 인식",
                undo: "실행 취소", redo: "다시 실행", color: "주석 색상", freeRatio: "자유",
                selectionRatio: "선택 비율", previousSelection: "이전 선택 영역",
                nextSelection: "다음 선택 영역", selectTool: "선택 또는 이동",
                rectangleTool: "사각형", arrowTool: "화살표", penTool: "펜",
                highlightTool: "강조", mosaicTool: "모자이크", textTool: "텍스트",
                enterText: "텍스트 입력"
            )
        case "mt":
            return CaptureSelectionCopy(
                cancel: "Ikkanċella", copy: "Ikkopja u lesti", save: "Issejvja", pin: "Waħħal fuq l-iskrin", recognizeText: "Agħraf it-test",
                undo: "Annulla", redo: "Erġa' agħmel", color: "Kulur", freeRatio: "Ħieles",
                selectionRatio: "Proporzjon", previousSelection: "Għażla preċedenti",
                nextSelection: "Għażla li jmiss", selectTool: "Agħżel jew mexxi",
                rectangleTool: "Rettangolu", arrowTool: "Vleġġa", penTool: "Pinna",
                highlightTool: "Enfasi", mosaicTool: "Mużajk", textTool: "Test",
                enterText: "Daħħal test"
            )
        default:
            return CaptureSelectionCopy(
                cancel: "Cancel", copy: "Copy and Finish", save: "Save", pin: "Pin on Screen", recognizeText: "Recognize Text",
                undo: "Undo", redo: "Redo", color: "Annotation Color", freeRatio: "Free",
                selectionRatio: "Selection Ratio", previousSelection: "Previous Selection",
                nextSelection: "Next Selection", selectTool: "Select or Move",
                rectangleTool: "Rectangle", arrowTool: "Arrow", penTool: "Pen",
                highlightTool: "Highlight", mosaicTool: "Mosaic", textTool: "Text",
                enterText: "Enter text"
            )
        }
    }
}
