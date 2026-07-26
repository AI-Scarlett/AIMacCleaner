import Foundation
import Combine
import CoreAudio
import CoreMediaIO

@MainActor
final class SensorMonitor: ObservableObject {
    @Published var events: [SensorEvent] = []
    @Published var isMonitoring = false
    @Published var cameraActive = false
    @Published var microphoneActive = false
    @Published var cameraProcess: String?
    @Published var microphoneProcess: String?

    private var timer: Timer?
    private var isChecking = false
    private let maxEvents = 500

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshSensors()
            }
        }
        Task { await refreshSensors() }
    }

    func stop() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        cameraActive = false
        microphoneActive = false
        cameraProcess = nil
        microphoneProcess = nil
    }

    func clearEvents() {
        events.removeAll()
    }

    private func refreshSensors() async {
        guard isMonitoring, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let state = await Task.detached(priority: .utility) {
            SensorState(
                cameraActive: Self.cameraIsActive(),
                microphoneActive: Self.microphoneIsActive()
            )
        }.value
        guard isMonitoring else { return }

        if state.cameraActive && !cameraActive {
            appendEvent(type: .camera, processName: "macOS camera client")
        }
        if state.microphoneActive && !microphoneActive {
            appendEvent(type: .microphone, processName: "macOS microphone client")
        }

        cameraActive = state.cameraActive
        microphoneActive = state.microphoneActive
        cameraProcess = state.cameraActive ? "macOS camera client" : nil
        microphoneProcess = state.microphoneActive ? "macOS microphone client" : nil
    }

    private func appendEvent(type: SensorEvent.SensorType, processName: String) {
        events.append(SensorEvent(
            timestamp: Date(),
            sensorType: type,
            processName: processName,
            pid: 0,
            bundleId: nil
        ))
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
    }

    nonisolated private static func cameraIsActive() -> Bool {
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize >= UInt32(MemoryLayout<CMIODeviceID>.size) else {
            return false
        }

        var devices = [CMIODeviceID](
            repeating: 0,
            count: Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        )
        var dataUsed = dataSize
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            dataSize,
            &dataUsed,
            &devices
        ) == noErr else {
            return false
        }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var running: UInt32 = 0
            let runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningUsed = runningSize
            if CMIOObjectGetPropertyData(
                device,
                &runningAddress,
                0,
                nil,
                runningSize,
                &runningUsed,
                &running
            ) == noErr, running != 0 {
                return true
            }
        }
        return false
    }

    nonisolated private static func microphoneIsActive() -> Bool {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize >= UInt32(MemoryLayout<AudioDeviceID>.size) else {
            return false
        }

        var devices = [AudioDeviceID](
            repeating: 0,
            count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize,
            &devices
        ) == noErr else {
            return false
        }

        for device in devices {
            var inputStreamsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputStreamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(
                device,
                &inputStreamsAddress,
                0,
                nil,
                &inputStreamsSize
            ) == noErr, inputStreamsSize > 0 else {
                continue
            }

            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(
                device,
                &runningAddress,
                0,
                nil,
                &runningSize,
                &running
            ) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}

private struct SensorState: Sendable {
    let cameraActive: Bool
    let microphoneActive: Bool
}
