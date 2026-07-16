import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum CaptureSelectionAction {
    case copy
    case save
    case pin
    case recognizeText
}

struct CaptureSelectionResult {
    let image: NSImage
    let action: CaptureSelectionAction
    let screenRect: NSRect
}

struct CaptureWindowTarget: Identifiable {
    let id: CGWindowID
    let rect: NSRect
    let title: String
    let ownerName: String
    let zIndex: Int
}

struct CaptureScreenSnapshot {
    let displayID: CGDirectDisplayID
    let screenFrame: NSRect
    let scale: CGFloat
    let image: NSImage
    let windowTargets: [CaptureWindowTarget]
}

enum CaptureSessionError: LocalizedError {
    case noDisplays
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .noDisplays:
            return "No available displays"
        case .captureFailed:
            return "Unable to capture the display"
        }
    }
}

@MainActor
enum CaptureSnapshotProvider {
    static func prepareScreens() async throws -> [CaptureScreenSnapshot] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw CaptureSessionError.noDisplays }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let processID = ProcessInfo.processInfo.processIdentifier
        let excludedApplications = content.applications.filter { $0.processID == processID }
        var snapshots: [CaptureScreenSnapshot] = []

        for screen in screens {
            guard let displayID = displayID(for: screen),
                  let display = content.displays.first(where: { $0.displayID == displayID }) else {
                continue
            }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            let scale = max(screen.backingScaleFactor, 1)
            let cgImage = try await captureDisplay(
                display,
                filter: filter,
                screen: screen,
                scale: scale
            )
            let image = NSImage(cgImage: cgImage, size: screen.frame.size)
            let targets = windowTargets(
                from: content.windows,
                displayFrame: display.frame,
                screenSize: screen.frame.size,
                excludingProcessID: processID
            )
            snapshots.append(
                CaptureScreenSnapshot(
                    displayID: displayID,
                    screenFrame: screen.frame,
                    scale: scale,
                    image: image,
                    windowTargets: targets
                )
            )
        }

        guard !snapshots.isEmpty else { throw CaptureSessionError.noDisplays }
        return snapshots
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return screen.deviceDescription[key] as? CGDirectDisplayID
    }

    private static func captureDisplay(
        _ display: SCDisplay,
        filter: SCContentFilter,
        screen: NSScreen,
        scale: CGFloat
    ) async throws -> CGImage {
        if #available(macOS 14.0, *) {
            let configuration = SCStreamConfiguration()
            configuration.width = max(Int(screen.frame.width * scale), 1)
            configuration.height = max(Int(screen.frame.height * scale), 1)
            configuration.showsCursor = false
            configuration.queueDepth = 1
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            return try await withCheckedThrowingContinuation { continuation in
                SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                ) { image, error in
                    if let image {
                        continuation.resume(returning: image)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: CaptureSessionError.captureFailed)
                    }
                }
            }
        }

        let displayBounds = CGDisplayBounds(display.displayID)
        let options: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]
        guard let image = CGWindowListCreateImage(
            displayBounds,
            .optionOnScreenOnly,
            kCGNullWindowID,
            options
        ) else {
            throw CaptureSessionError.captureFailed
        }
        return image
    }

    private static func windowTargets(
        from windows: [SCWindow],
        displayFrame: CGRect,
        screenSize: NSSize,
        excludingProcessID processID: pid_t
    ) -> [CaptureWindowTarget] {
        windows.enumerated().compactMap { index, window in
            guard window.isOnScreen,
                  window.windowLayer == 0,
                  window.owningApplication?.processID != processID,
                  window.frame.width >= 48,
                  window.frame.height >= 36 else {
                return nil
            }

            let clipped = window.frame.intersection(displayFrame)
            guard !clipped.isNull, clipped.width >= 24, clipped.height >= 24 else {
                return nil
            }

            let localRect = NSRect(
                x: clipped.minX - displayFrame.minX,
                y: screenSize.height - (clipped.maxY - displayFrame.minY),
                width: clipped.width,
                height: clipped.height
            ).intersection(NSRect(origin: .zero, size: screenSize))
            guard localRect.width >= 24, localRect.height >= 24 else { return nil }

            return CaptureWindowTarget(
                id: window.windowID,
                rect: localRect,
                title: window.title ?? "",
                ownerName: window.owningApplication?.applicationName ?? "",
                zIndex: index
            )
        }
        .sorted { lhs, rhs in lhs.zIndex < rhs.zIndex }
    }
}

@MainActor
final class CaptureSelectionHistoryStore {
    static let shared = CaptureSelectionHistoryStore()

    private let defaults = UserDefaults.standard
    private let maximumCount = 5

    private init() {}

    func selections(for displayID: CGDirectDisplayID, within bounds: NSRect) -> [NSRect] {
        defaults.stringArray(forKey: key(for: displayID))?
            .map(NSRectFromString)
            .filter {
                $0.width >= 24 &&
                $0.height >= 24 &&
                bounds.intersects($0)
            } ?? []
    }

    func record(_ rect: NSRect, for displayID: CGDirectDisplayID) {
        let integral = rect.integral
        var values = selections(
            for: displayID,
            within: NSRect(x: -100_000, y: -100_000, width: 200_000, height: 200_000)
        )
        values.removeAll { approximatelyEqual($0, integral) }
        values.insert(integral, at: 0)
        defaults.set(
            values.prefix(maximumCount).map(NSStringFromRect),
            forKey: key(for: displayID)
        )
    }

    private func key(for displayID: CGDirectDisplayID) -> String {
        "capture.selectionHistory.\(displayID)"
    }

    private func approximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 1 &&
        abs(lhs.minY - rhs.minY) < 1 &&
        abs(lhs.width - rhs.width) < 1 &&
        abs(lhs.height - rhs.height) < 1
    }
}
