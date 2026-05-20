import Foundation
import Combine
import CoreGraphics

class SensorMonitor: ObservableObject {
    @Published var events: [SensorEvent] = []
    @Published var isMonitoring: Bool = false
    @Published var cameraActive: Bool = false
    @Published var microphoneActive: Bool = false
    @Published var cameraProcess: String?
    @Published var microphoneProcess: String?

    private var timer: Timer?
    private var knownCameraApps: Set<Int32> = []
    private var knownMicApps: Set<Int32> = []
    private let maxEvents = 500

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.checkSensors()
            }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.checkSensors()
        }
    }

    func stop() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        cameraActive = false
        microphoneActive = false
        cameraProcess = nil
        microphoneProcess = nil
        knownCameraApps.removeAll()
        knownMicApps.removeAll()
    }

    func clearEvents() {
        events.removeAll()
    }

    private func checkSensors() {
        let cameraApps = getCameraUsingApps()
        let micApps = getMicrophoneUsingApps()

        let newCamera = cameraApps.filter { !knownCameraApps.contains($0.pid) }
        let newMic = micApps.filter { !knownMicApps.contains($0.pid) }

        var newEvents: [SensorEvent] = []
        for app in newCamera {
            let event = SensorEvent(
                timestamp: Date(),
                sensorType: .camera,
                processName: app.name,
                pid: app.pid,
                bundleId: app.bundleId
            )
            newEvents.append(event)
        }

        for app in newMic {
            let event = SensorEvent(
                timestamp: Date(),
                sensorType: .microphone,
                processName: app.name,
                pid: app.pid,
                bundleId: app.bundleId
            )
            newEvents.append(event)
        }

        knownCameraApps = Set(cameraApps.map(\.pid))
        knownMicApps = Set(micApps.map(\.pid))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cameraActive = !cameraApps.isEmpty
            self.microphoneActive = !micApps.isEmpty
            self.cameraProcess = cameraApps.first?.name
            self.microphoneProcess = micApps.first?.name
            if !newEvents.isEmpty {
                self.events.append(contentsOf: newEvents)
                if self.events.count > self.maxEvents {
                    self.events = Array(self.events.suffix(self.maxEvents))
                }
            }
        }
    }

    private struct AppInfo {
        let pid: Int32
        let name: String
        let bundleId: String?
    }

    private func getCameraUsingApps() -> [AppInfo] {
        var result: [AppInfo] = []
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let cameraIndicators = ["FaceTime", "Zoom", "Microsoft Teams", "Google Meet", "Webex", "Skype", "OBS", "Discord", "Slack", "腾讯会议", "钉钉", "飞书"]

        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let name = window[kCGWindowOwnerName as String] as? String else { continue }

            if cameraIndicators.contains(where: { name.contains($0) }) {
                let bundleId = getBundleId(for: pid)
                result.append(AppInfo(pid: pid, name: name, bundleId: bundleId))
            }
        }

        let lsofResult = runProcess("/usr/sbin/lsof", arguments: ["/dev/video0"])
        if !lsofResult.isEmpty {
            for line in lsofResult.components(separatedBy: "\n").dropFirst() {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2, let pid = Int32(parts[1]) {
                    let name = String(parts[0])
                    if !result.contains(where: { $0.pid == pid }) {
                        result.append(AppInfo(pid: pid, name: name, bundleId: getBundleId(for: pid)))
                    }
                }
            }
        }

        return result
    }

    private func getMicrophoneUsingApps() -> [AppInfo] {
        var result: [AppInfo] = []
        let micIndicators = ["FaceTime", "Zoom", "Microsoft Teams", "Google Meet", "Webex", "Skype", "Discord", "Slack", "腾讯会议", "钉钉", "飞书", "OBS", "GarageBand", "Logic Pro", "VoiceMemos", "语音备忘录"]

        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let name = window[kCGWindowOwnerName as String] as? String else { continue }
            if micIndicators.contains(where: { name.contains($0) }) {
                let bundleId = getBundleId(for: pid)
                result.append(AppInfo(pid: pid, name: name, bundleId: bundleId))
            }
        }

        let lsofResult = runProcess("/usr/sbin/lsof", arguments: ["-c", "coreaudio"])
        if !lsofResult.isEmpty {
            for line in lsofResult.components(separatedBy: "\n").dropFirst() {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2, let pid = Int32(parts[1]) {
                    let name = String(parts[0])
                    if !result.contains(where: { $0.pid == pid }) {
                        result.append(AppInfo(pid: pid, name: name, bundleId: getBundleId(for: pid)))
                    }
                }
            }
        }

        return result
    }

    private func getBundleId(for pid: Int32) -> String? {
        let result = runProcess("/usr/bin/ps", arguments: ["-o", "bundleidentifier=", "-p", "\(pid)"])
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func runProcess(_ path: String, arguments: [String]) -> String {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
