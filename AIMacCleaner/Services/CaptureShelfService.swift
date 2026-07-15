import AppKit
import AVFoundation
import Combine
import CoreGraphics
import CryptoKit
import Foundation
import UniformTypeIdentifiers
import Vision

struct CaptureShelfItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case text
        case image
        case files
    }

    let id: UUID
    let kind: Kind
    let title: String
    let detail: String
    let previewText: String?
    let filePaths: [String]
    let imagePNGData: Data?
    let createdAt: Date
    let contentHash: String
}

struct CaptureShelfStatus: Identifiable, Equatable {
    enum Level: Equatable {
        case success
        case info
        case warning
        case error
    }

    enum Code: Equatable {
        case captureCopied
        case capturePermissionNeeded
        case captureFailed
        case recordingStarted
        case recordingStopped
        case recordingFailed
        case itemCopied
        case historyCleared
        case historyPaused
    }

    let id = UUID()
    let level: Level
    let code: Code
    let detail: String?
    let createdAt: Date
}

@MainActor
final class CaptureShelfService: ObservableObject {
    static let shared = CaptureShelfService()
    static let minHistoryLimit = 20
    static let maxHistoryLimit = 500
    static let defaultHistoryLimit = 100

    @Published private(set) var items: [CaptureShelfItem] = []
    @Published private(set) var status: CaptureShelfStatus?
    @Published private(set) var isCapturingScreen = false
    @Published private(set) var isRecordingScreen = false
    @Published private(set) var screenCaptureAccessGranted = CGPreflightScreenCaptureAccess()
    @Published private(set) var isClipboardHistoryEnabled: Bool
    @Published private(set) var includeImages: Bool
    @Published private(set) var includeFiles: Bool
    @Published private(set) var historyLimit: Int

    private enum DefaultsKey {
        static let isClipboardHistoryEnabled = "captureShelf.clipboardHistoryEnabled"
        static let includeImages = "captureShelf.includeImages"
        static let includeFiles = "captureShelf.includeFiles"
        static let historyLimit = "captureShelf.historyLimit"
    }

    private let pasteboard = NSPasteboard.general
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pollTimer: Timer?
    private var lastPasteboardChangeCount: Int
    private var saveWorkItem: DispatchWorkItem?
    private var selectionOverlayController: CaptureSelectionOverlayController?
    private var lastSelectionCaptureRequestAt = Date.distantPast
    private var pinnedImageControllers: [UUID: CapturePinnedImageController] = [:]
    private var completionPreviewController: CaptureCompletionPreviewController?
    private var recordingSession: AVCaptureSession?
    private var recordingOutput: AVCaptureMovieFileOutput?
    private var recordingDelegate: ScreenRecordingDelegate?
    private var activeRecordingURL: URL?

    private init() {
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        isClipboardHistoryEnabled = defaults.object(forKey: DefaultsKey.isClipboardHistoryEnabled) as? Bool ?? false
        includeImages = defaults.object(forKey: DefaultsKey.includeImages) as? Bool ?? true
        includeFiles = defaults.object(forKey: DefaultsKey.includeFiles) as? Bool ?? true
        historyLimit = Self.clampedLimit(defaults.integer(forKey: DefaultsKey.historyLimit))
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        loadHistory()
        trimHistory()
    }

    func start() {
        refreshScreenCaptureAccess()
        guard isClipboardHistoryEnabled else {
            stopPolling()
            return
        }
        startPolling()
    }

    func stop() {
        stopPolling()
        saveHistoryNow()
    }

    func setClipboardHistoryEnabled(_ enabled: Bool) {
        guard isClipboardHistoryEnabled != enabled else { return }
        isClipboardHistoryEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.isClipboardHistoryEnabled)
        lastPasteboardChangeCount = pasteboard.changeCount
        if enabled {
            startPolling()
        } else {
            stopPolling()
            setStatus(.init(level: .info, code: .historyPaused, detail: nil, createdAt: Date()))
        }
    }

    func setIncludeImages(_ enabled: Bool) {
        includeImages = enabled
        defaults.set(enabled, forKey: DefaultsKey.includeImages)
    }

    func setIncludeFiles(_ enabled: Bool) {
        includeFiles = enabled
        defaults.set(enabled, forKey: DefaultsKey.includeFiles)
    }

    func setHistoryLimit(_ limit: Int) {
        let clamped = Self.clampedLimit(limit)
        guard historyLimit != clamped else { return }
        historyLimit = clamped
        defaults.set(clamped, forKey: DefaultsKey.historyLimit)
        trimHistory()
        scheduleSave()
    }

    func captureVisibleScreenToClipboard() {
        guard prepareScreenCapture() else { return }
        isCapturingScreen = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshots = try await CaptureSnapshotProvider.prepareScreens()
                let mouseLocation = NSEvent.mouseLocation
                let snapshot = snapshots.first(where: { $0.screenFrame.contains(mouseLocation) })
                    ?? snapshots.first
                guard let snapshot else { throw CaptureSessionError.noDisplays }
                self.processCapturedImage(
                    snapshot.image,
                    sourceTitle: "screen",
                    action: .copy,
                    screenRect: snapshot.screenFrame
                )
            } catch {
                self.setStatus(.init(
                    level: .error,
                    code: .captureFailed,
                    detail: error.localizedDescription,
                    createdAt: Date()
                ))
            }
            self.isCapturingScreen = false
        }
    }

    func captureSelectedRegionToClipboard() {
        guard prepareScreenCapture() else { return }
        presentSelectionOverlay(isUITest: false)
    }

#if DEBUG
    func presentSelectionOverlayForUITest() {
        guard prepareScreenCapture() else { return }
        presentSelectionOverlay(isUITest: true)
    }
#endif

    func toggleScreenRecording() {
        if isRecordingScreen {
            stopScreenRecording()
        } else {
            startScreenRecording()
        }
    }

    func startScreenRecording() {
        guard !isRecordingScreen else { return }
        guard prepareScreenCapture() else { return }
        guard let displayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            setStatus(.init(level: .error, code: .recordingFailed, detail: nil, createdAt: Date()))
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let input = AVCaptureScreenInput(displayID: displayID) else {
            setStatus(.init(level: .error, code: .recordingFailed, detail: nil, createdAt: Date()))
            return
        }
        input.minFrameDuration = CMTime(value: 1, timescale: 30)
        input.capturesCursor = true
        input.capturesMouseClicks = true

        let output = AVCaptureMovieFileOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            setStatus(.init(level: .error, code: .recordingFailed, detail: nil, createdAt: Date()))
            return
        }

        session.addInput(input)
        session.addOutput(output)

        let url = nextRecordingURL()
        let delegate = ScreenRecordingDelegate { [weak self] outputURL, error in
            Task { @MainActor in
                self?.finishScreenRecording(outputURL: outputURL, error: error)
            }
        }

        recordingSession = session
        recordingOutput = output
        recordingDelegate = delegate
        activeRecordingURL = url
        isRecordingScreen = true

        session.startRunning()
        output.startRecording(to: url, recordingDelegate: delegate)
        setStatus(.init(level: .info, code: .recordingStarted, detail: url.lastPathComponent, createdAt: Date()))
    }

    func stopScreenRecording() {
        guard isRecordingScreen else { return }
        if recordingOutput?.isRecording == true {
            recordingOutput?.stopRecording()
        } else if let activeRecordingURL {
            finishScreenRecording(outputURL: activeRecordingURL, error: nil)
        } else {
            finishScreenRecording(outputURL: nil, error: nil)
        }
    }

    private func prepareScreenCapture() -> Bool {
        refreshScreenCaptureAccess()
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            refreshScreenCaptureAccess()
            if !screenCaptureAccessGranted {
                setStatus(.init(level: .warning, code: .capturePermissionNeeded, detail: nil, createdAt: Date()))
                return false
            }
            return false
        }
        return true
    }

    private func presentSelectionOverlay(isUITest: Bool) {
        guard selectionOverlayController == nil, !isCapturingScreen else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSelectionCaptureRequestAt) >= 0.5 else { return }
        lastSelectionCaptureRequestAt = now

        isCapturingScreen = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshots = try await CaptureSnapshotProvider.prepareScreens()
                guard self.selectionOverlayController == nil else {
                    self.isCapturingScreen = false
                    return
                }
                let controller = CaptureSelectionOverlayController(
                    snapshots: snapshots
                ) { [weak self] result in
                    Task { @MainActor in
                        guard let self else { return }
                        self.selectionOverlayController = nil
                        self.lastSelectionCaptureRequestAt = Date()
#if DEBUG
                        if isUITest {
                            print("[TraceFence][CaptureUITest] result=\(String(describing: result?.screenRect.integral)) action=\(String(describing: result?.action))")
                        }
#endif
                        if !isUITest, let result {
                            self.processCapturedImage(
                                result.image,
                                sourceTitle: "selection",
                                action: result.action,
                                screenRect: result.screenRect
                            )
                        }
                        self.isCapturingScreen = false
                    }
                }
                self.selectionOverlayController = controller
                controller.begin()
            } catch {
                self.selectionOverlayController = nil
                self.isCapturingScreen = false
                self.setStatus(.init(
                    level: .error,
                    code: .captureFailed,
                    detail: error.localizedDescription,
                    createdAt: Date()
                ))
            }
        }
    }

    private func processCapturedImage(
        _ image: NSImage,
        sourceTitle: String,
        action: CaptureSelectionAction,
        screenRect: NSRect
    ) {
        switch action {
        case .copy:
            copyCapturedImage(image, sourceTitle: sourceTitle)
            showCompletionPreview(image: image, near: screenRect)
        case .save:
            guard let savedURL = saveCapturedImage(image) else { return }
            if let item = makeImageItem(from: image, sourceTitle: sourceTitle) {
                insert(item)
            }
            setStatus(.init(
                level: .success,
                code: .captureCopied,
                detail: savedURL.lastPathComponent,
                createdAt: Date()
            ))
            showCompletionPreview(image: image, near: screenRect)
        case .pin:
            pinCapturedImage(image, near: screenRect)
            if let item = makeImageItem(from: image, sourceTitle: sourceTitle) {
                insert(item)
            }
            setStatus(.init(
                level: .success,
                code: .captureCopied,
                detail: nil,
                createdAt: Date()
            ))
        case .recognizeText:
            recognizeText(in: image, sourceTitle: sourceTitle, screenRect: screenRect)
        }
    }

    private func recognizeText(
        in image: NSImage,
        sourceTitle: String,
        screenRect: NSRect
    ) {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            setStatus(.init(level: .error, code: .captureFailed, detail: nil, createdAt: Date()))
            return
        }

        Task { [weak self] in
            do {
                let recognizedText = try await Task.detached(priority: .userInitiated) {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try handler.perform([request])
                    let observations = request.results?.sorted { lhs, rhs in
                        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.015 {
                            return lhs.boundingBox.midY > rhs.boundingBox.midY
                        }
                        return lhs.boundingBox.minX < rhs.boundingBox.minX
                    } ?? []
                    return observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }.value

                guard let self else { return }
                if !recognizedText.isEmpty {
                    self.pasteboard.clearContents()
                    self.pasteboard.setString(recognizedText, forType: .string)
                    self.lastPasteboardChangeCount = self.pasteboard.changeCount
                }
                if let item = self.makeImageItem(from: image, sourceTitle: sourceTitle) {
                    self.insert(item)
                }
                self.setStatus(.init(
                    level: recognizedText.isEmpty ? .warning : .success,
                    code: recognizedText.isEmpty ? .captureFailed : .captureCopied,
                    detail: recognizedText.isEmpty ? nil : "OCR",
                    createdAt: Date()
                ))
                if !recognizedText.isEmpty {
                    self.showCompletionPreview(image: image, near: screenRect)
                }
            } catch {
                self?.setStatus(.init(
                    level: .error,
                    code: .captureFailed,
                    detail: error.localizedDescription,
                    createdAt: Date()
                ))
            }
        }
    }

    private func copyCapturedImage(_ image: NSImage, sourceTitle: String) {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        lastPasteboardChangeCount = pasteboard.changeCount

        if let item = makeImageItem(from: image, sourceTitle: sourceTitle) {
            insert(item)
        }
        setStatus(.init(level: .success, code: .captureCopied, detail: nil, createdAt: Date()))
    }

    private func saveCapturedImage(_ image: NSImage) -> URL? {
        guard let data = fullResolutionPNGData(for: image) else {
            setStatus(.init(level: .error, code: .captureFailed, detail: nil, createdAt: Date()))
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "TraceFence-Capture-\(formatter.string(from: Date())).png"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            setStatus(.init(
                level: .error,
                code: .captureFailed,
                detail: error.localizedDescription,
                createdAt: Date()
            ))
            return nil
        }
    }

    private func pinCapturedImage(_ image: NSImage, near screenRect: NSRect) {
        let id = UUID()
        let controller = CapturePinnedImageController(
            image: image,
            screenRect: screenRect
        ) { [weak self] in
            self?.pinnedImageControllers[id] = nil
        }
        pinnedImageControllers[id] = controller
        controller.show()
    }

    private func showCompletionPreview(image: NSImage, near screenRect: NSRect) {
        completionPreviewController?.dismiss()
        let controller = CaptureCompletionPreviewController(image: image, screenRect: screenRect)
        completionPreviewController = controller
        controller.onDismiss = { [weak self, weak controller] in
            guard self?.completionPreviewController === controller else { return }
            self?.completionPreviewController = nil
        }
        controller.show()
    }

    private func finishScreenRecording(outputURL: URL?, error: Error?) {
        recordingOutput = nil
        recordingSession?.stopRunning()
        recordingSession = nil
        recordingDelegate = nil
        activeRecordingURL = nil
        isRecordingScreen = false

        if let error {
            setStatus(.init(level: .error, code: .recordingFailed, detail: error.localizedDescription, createdAt: Date()))
            return
        }
        guard let outputURL else {
            setStatus(.init(level: .error, code: .recordingFailed, detail: nil, createdAt: Date()))
            return
        }
        addFileReferences([outputURL])
        setStatus(.init(level: .success, code: .recordingStopped, detail: outputURL.lastPathComponent, createdAt: Date()))
    }

    func copy(_ item: CaptureShelfItem) {
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            pasteboard.setString(item.previewText ?? item.title, forType: .string)
        case .files:
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            pasteboard.writeObjects(urls)
        case .image:
            if let data = item.imagePNGData, let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        }
        lastPasteboardChangeCount = pasteboard.changeCount
        insert(item)
        setStatus(.init(level: .success, code: .itemCopied, detail: nil, createdAt: Date()))
    }

    func delete(_ item: CaptureShelfItem) {
        items.removeAll { $0.id == item.id }
        scheduleSave()
    }

    func clearHistory() {
        items.removeAll()
        scheduleSave()
        setStatus(.init(level: .info, code: .historyCleared, detail: nil, createdAt: Date()))
    }

    func addFileReferences(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        insert(makeFileItem(urls))
    }

    func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshScreenCaptureAccess() {
        screenCaptureAccessGranted = CGPreflightScreenCaptureAccess()
    }

    private func nextRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "TraceFence-Recording-\(formatter.string(from: Date())).mov"
        return URL(fileURLWithPath: SandboxPaths.shared.screenRecordingsDirectory)
            .appendingPathComponent(fileName)
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboardIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollPasteboardIfNeeded() {
        guard isClipboardHistoryEnabled else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = changeCount

        if let item = makeItem(from: pasteboard) {
            insert(item)
        }
    }

    private func makeItem(from pasteboard: NSPasteboard) -> CaptureShelfItem? {
        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return makeTextItem(text)
        }

        if includeFiles,
           let urlObjects = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
           ) as? [NSURL] {
            let urls = urlObjects.map { $0 as URL }
            if !urls.isEmpty {
                return makeFileItem(urls)
            }
        }

        if includeImages, let image = NSImage(pasteboard: pasteboard) {
            return makeImageItem(from: image, sourceTitle: nil)
        }

        return nil
    }

    private func makeTextItem(_ text: String) -> CaptureShelfItem {
        let cappedText = String(text.prefix(24_000))
        let firstLine = cappedText
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String((firstLine?.isEmpty == false ? firstLine! : cappedText).prefix(90))
        let detail = "\(text.count) chars"
        let hash = contentHash(for: Data(cappedText.utf8), prefix: "text")
        return CaptureShelfItem(
            id: UUID(),
            kind: .text,
            title: title,
            detail: detail,
            previewText: cappedText,
            filePaths: [],
            imagePNGData: nil,
            createdAt: Date(),
            contentHash: hash
        )
    }

    private func makeFileItem(_ urls: [URL]) -> CaptureShelfItem {
        let paths = urls.map(\.path).sorted()
        let firstName = paths.first.map { ($0 as NSString).lastPathComponent } ?? ""
        let title = urls.count == 1 ? firstName : "\(urls.count) files"
        let detail = urls.count == 1 ? (paths.first ?? "") : firstName
        let hash = contentHash(for: Data(paths.joined(separator: "\n").utf8), prefix: "files")
        return CaptureShelfItem(
            id: UUID(),
            kind: .files,
            title: title,
            detail: detail,
            previewText: nil,
            filePaths: paths,
            imagePNGData: nil,
            createdAt: Date(),
            contentHash: hash
        )
    }

    private func makeImageItem(from image: NSImage, sourceTitle: String?) -> CaptureShelfItem? {
        guard let pngData = pngData(for: image) else { return nil }
        let pixelSize = image.pixelSize
        let title = sourceTitle ?? ""
        let detail = "\(Int(pixelSize.width)) x \(Int(pixelSize.height))"
        let hash = contentHash(for: pngData, prefix: "image")
        return CaptureShelfItem(
            id: UUID(),
            kind: .image,
            title: title,
            detail: detail,
            previewText: nil,
            filePaths: [],
            imagePNGData: pngData,
            createdAt: Date(),
            contentHash: hash
        )
    }

    private func insert(_ item: CaptureShelfItem) {
        if let existingIndex = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            items.remove(at: existingIndex)
        }
        let freshItem = CaptureShelfItem(
            id: UUID(),
            kind: item.kind,
            title: item.title,
            detail: item.detail,
            previewText: item.previewText,
            filePaths: item.filePaths,
            imagePNGData: item.imagePNGData,
            createdAt: Date(),
            contentHash: item.contentHash
        )
        items.insert(freshItem, at: 0)
        trimHistory()
        scheduleSave()
    }

    private func trimHistory() {
        if items.count > historyLimit {
            items = Array(items.prefix(historyLimit))
        }
    }

    private func setStatus(_ next: CaptureShelfStatus) {
        status = next
    }

    private func loadHistory() {
        let url = URL(fileURLWithPath: SandboxPaths.shared.captureShelfHistoryPath)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode([CaptureShelfItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.saveHistoryNow()
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func saveHistoryNow() {
        guard let data = try? encoder.encode(items) else { return }
        let url = URL(fileURLWithPath: SandboxPaths.shared.captureShelfHistoryPath)
        try? data.write(to: url, options: .atomic)
    }

    private func contentHash(for data: Data, prefix: String) -> String {
        let digest = SHA256.hash(data: data)
        return "\(prefix):" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func pngData(for image: NSImage) -> Data? {
        let resized = image.resizedToFit(maxPixelDimension: 1400)
        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func fullResolutionPNGData(for image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func clampedLimit(_ rawValue: Int) -> Int {
        if rawValue == 0 { return defaultHistoryLimit }
        return min(max(rawValue, minHistoryLimit), maxHistoryLimit)
    }
}

@MainActor
private final class CapturePinnedImageController: NSObject, NSWindowDelegate {
    private let panel: CapturePinnedImagePanel
    private let onClose: () -> Void
    private var didClose = false

    init(image: NSImage, screenRect: NSRect, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let aspect = max(image.size.width / max(image.size.height, 1), 0.1)
        var width = min(max(image.size.width, 220), 720)
        var height = width / aspect
        if height > 520 {
            height = 520
            width = height * aspect
        }
        panel = CapturePinnedImagePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.onRequestClose = { [weak self] in self?.close() }
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = image.size
        panel.minSize = NSSize(width: 120, height: 80)
        panel.title = CapturePinnedImageLocalization.windowTitle
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.standardWindowButton(.closeButton)?.toolTip = CapturePinnedImageLocalization.closeTitle
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let imageView = CapturePinnedImageView(
            frame: NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        )
        imageView.onRequestClose = { [weak self] in self?.close() }
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        imageView.autoresizingMask = [.width, .height]
        panel.contentView = imageView

        let origin = NSPoint(
            x: screenRect.midX - width / 2,
            y: screenRect.midY - height / 2
        )
        panel.setFrameOrigin(origin)
    }

    func show() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    @objc private func close() {
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !didClose else { return }
        didClose = true
        onClose()
    }
}

@MainActor
private final class CapturePinnedImagePanel: NSPanel {
    var onRequestClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onRequestClose?()
    }
}

@MainActor
private final class CapturePinnedImageView: NSImageView {
    var onRequestClose: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let closeItem = NSMenuItem(
            title: CapturePinnedImageLocalization.closeTitle,
            action: #selector(closePinnedImage),
            keyEquivalent: ""
        )
        closeItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeItem.target = self
        menu.addItem(closeItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func closePinnedImage() {
        onRequestClose?()
    }
}

private enum CapturePinnedImageLocalization {
    static var windowTitle: String {
        localized(
            zh: "钉图",
            en: "Pinned Capture",
            zhHant: "釘圖",
            ja: "固定したキャプチャ",
            ko: "고정된 캡처",
            mt: "Pinned Capture"
        )
    }

    static var closeTitle: String {
        localized(
            zh: "关闭钉图",
            en: "Close Pinned Capture",
            zhHant: "關閉釘圖",
            ja: "固定キャプチャを閉じる",
            ko: "고정된 캡처 닫기",
            mt: "Close Pinned Capture"
        )
    }

    private static func localized(
        zh: String,
        en: String,
        zhHant: String,
        ja: String,
        ko: String,
        mt: String
    ) -> String {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue
        switch AppLanguage(rawValue: raw) ?? .english {
        case .simplifiedChinese: return zh
        case .traditionalChinese: return zhHant
        case .japanese: return ja
        case .korean: return ko
        case .maltese: return mt
        case .english: return en
        }
    }
}

@MainActor
private final class CaptureCompletionPreviewController: NSObject {
    let panel: NSPanel
    var onDismiss: (() -> Void)?
    private var dismissWorkItem: DispatchWorkItem?

    init(image: NSImage, screenRect: NSRect) {
        let maxWidth: CGFloat = 210
        let maxHeight: CGFloat = 150
        let aspect = max(image.size.width / max(image.size.height, 1), 0.1)
        var width = maxWidth
        var height = width / aspect
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }
        width = max(width, 96)
        height = max(height, 72)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageView.layer?.cornerRadius = 7
        imageView.layer?.masksToBounds = true
        panel.contentView = imageView

        let visibleFrame = NSScreen.screens.first(where: { $0.frame.intersects(screenRect) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? screenRect
        let x = min(max(screenRect.maxX - width, visibleFrame.minX + 10), visibleFrame.maxX - width - 10)
        let below = screenRect.minY - height - 12
        let y = below >= visibleFrame.minY + 10
            ? below
            : min(screenRect.maxY + 12, visibleFrame.maxY - height - 10)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func show() {
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel.orderOut(nil)
        onDismiss?()
    }
}

private extension NSImage {
    var pixelSize: CGSize {
        if let rep = representations.max(by: { lhs, rhs in
            lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
        }) {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return CGSize(width: size.width, height: size.height)
    }

    func resizedToFit(maxPixelDimension: CGFloat) -> NSImage {
        let currentSize = pixelSize
        let largestSide = max(currentSize.width, currentSize.height)
        guard largestSide > maxPixelDimension, largestSide > 0 else { return self }

        let scale = maxPixelDimension / largestSide
        let targetSize = NSSize(width: currentSize.width * scale, height: currentSize.height * scale)
        let targetImage = NSImage(size: targetSize)
        targetImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: targetSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        targetImage.unlockFocus()
        return targetImage
    }
}

private final class ScreenRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let completion: (URL?, Error?) -> Void

    init(completion: @escaping (URL?, Error?) -> Void) {
        self.completion = completion
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        completion(outputFileURL, error)
    }
}
