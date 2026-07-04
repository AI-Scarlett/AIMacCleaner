import AppKit
import Combine
import CoreGraphics
import CryptoKit
import Foundation

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
        refreshScreenCaptureAccess()
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            refreshScreenCaptureAccess()
            if !screenCaptureAccessGranted {
                setStatus(.init(level: .warning, code: .capturePermissionNeeded, detail: nil, createdAt: Date()))
                return
            }
            return
        }

        isCapturingScreen = true
        defer { isCapturingScreen = false }

        let imageOptions: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]
        guard let cgImage = CGWindowListCreateImage(.infinite, .optionOnScreenOnly, kCGNullWindowID, imageOptions) else {
            setStatus(.init(level: .error, code: .captureFailed, detail: nil, createdAt: Date()))
            return
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        lastPasteboardChangeCount = pasteboard.changeCount

        if let item = makeImageItem(from: image, sourceTitle: "screen") {
            insert(item)
        }
        setStatus(.init(level: .success, code: .captureCopied, detail: nil, createdAt: Date()))
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

    func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshScreenCaptureAccess() {
        screenCaptureAccessGranted = CGPreflightScreenCaptureAccess()
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

    private static func clampedLimit(_ rawValue: Int) -> Int {
        if rawValue == 0 { return defaultHistoryLimit }
        return min(max(rawValue, minHistoryLimit), maxHistoryLimit)
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
