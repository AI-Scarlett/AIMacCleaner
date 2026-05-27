import Foundation
import AVFoundation

enum SoundEvent: String, CaseIterable {
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case toolStart = "tool_start"
    case toolEnd = "tool_end"
    case permissionRequest = "permission_request"
    case question = "question"
    case planApproval = "plan_approval"
    case taskComplete = "task_complete"
    case error = "error"
    case interrupt = "interrupt"
    case notification = "notification"
    case subagentStart = "subagent_start"
    case subagentEnd = "subagent_end"
    case shellExecution = "shell_execution"
    case rateLimit = "rate_limit"

    var filePrefix: String { rawValue }
}

struct SoundProfile: Codable {
    var enabled: Bool = true
    var volume: Float = 0.7
    var muteWhenDnD: Bool = true
    var eventSounds: [String: String] = [:]

    static let `default` = SoundProfile(
        eventSounds: [
            "session_start": "pop",
            "session_end": "whoosh",
            "tool_start": "tick",
            "tool_end": "tock",
            "permission_request": "ping",
            "question": "ping",
            "plan_approval": "chime",
            "task_complete": "success",
            "error": "error",
            "interrupt": "pause",
            "notification": "bell",
            "subagent_start": "swoosh",
            "subagent_end": "swoosh",
        ]
    )
}

actor SoundEngine {
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private var profile: SoundProfile = .default
    private let profilePath = NSHomeDirectory() + "/.aimaccleaner_sound_profile.json"

    init() {
        Task { await loadProfile() }
        Task { await preloadSounds() }
    }

    func play(for event: AgentHookEvent) {
        guard profile.enabled else { return }

        if profile.muteWhenDnD, isDoNotDisturb() { return }

        let eventKey = soundKey(for: event)
        guard let soundName = profile.eventSounds[eventKey] else { return }

        playSound(named: soundName)
    }

    func playSound(named name: String) {
        guard let player = audioPlayers[name] else { return }
        player.volume = profile.volume
        player.currentTime = 0
        player.play()
    }

    func updateProfile(_ newProfile: SoundProfile) {
        profile = newProfile
        saveProfile()
    }

    func getProfile() -> SoundProfile {
        profile
    }

    private func soundKey(for event: AgentHookEvent) -> String {
        switch event {
        case .sessionStart: return "session_start"
        case .sessionEnd: return "session_end"
        case .processing: return "tool_start"
        case .toolUse(_, _, _, _, let status): return status == "running" ? "tool_start" : "tool_end"
        case .permissionRequest: return "permission_request"
        case .askQuestion: return "question"
        case .planApproval: return "plan_approval"
        case .taskComplete: return "task_complete"
        case .agentError: return "error"
        case .interrupt: return "interrupt"
        case .notification: return "notification"
        case .subagentStart: return "subagent_start"
        case .subagentStop: return "subagent_end"
        case .shellExecutionStart: return "shell_execution"
        case .rateLimitUpdate: return "rate_limit"
        default: return ""
        }
    }

    private func preloadSounds() {
        let soundNames = ["pop", "whoosh", "tick", "tock", "ping", "chime", "success", "error", "pause", "bell", "swoosh"]

        for name in soundNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "aiff")
                ?? Bundle.main.url(forResource: name, withExtension: "wav")
                ?? Bundle.main.url(forResource: name, withExtension: "mp3") {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    audioPlayers[name] = player
                }
            } else {
                let generator = generateSyntheticSound(named: name)
                generator?.prepareToPlay()
                if let g = generator {
                    audioPlayers[name] = g
                }
            }
        }
    }

    private func generateSyntheticSound(named name: String) -> AVAudioPlayer? {
        let sampleRate: Double = 44100
        let duration: Double

        switch name {
        case "pop": duration = 0.05
        case "whoosh": duration = 0.15
        case "tick": duration = 0.03
        case "tock": duration = 0.06
        case "ping": duration = 0.1
        case "chime": duration = 0.2
        case "success": duration = 0.25
        case "error": duration = 0.15
        case "pause": duration = 0.08
        case "bell": duration = 0.3
        case "swoosh": duration = 0.12
        default: duration = 0.05
        }

        let frameCount = Int(duration * sampleRate)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        let data = buffer.floatChannelData?[0]

        guard let ptr = data else { return nil }

        let total = Double(frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / total
            let envelope: Double
            switch name {
            case "swoosh":
                envelope = 1.0
            default:
                envelope = exp(-t * 8)
            }

            let freq: Double
            switch name {
            case "pop": freq = 400 + 800 * exp(-t * 30)
            case "whoosh": freq = 800 + 400 * t
            case "tick": freq = 2000 * exp(-t * 20)
            case "tock": freq = 1500 * exp(-t * 15)
            case "ping": freq = 880 + 440 * sin(t * .pi * 4)
            case "chime": freq = 1200 * exp(-t * 3) + 1600 * (1 - exp(-t * 3))
            case "success": freq = 523 + 262 * sin(t * .pi * 3)
            case "error": freq = 200 + 100 * sin(t * .pi * 8)
            case "pause": freq = 600 * exp(-t * 10)
            case "bell": freq = 1047 * exp(-t * 2) + 784 * exp(-t * 1.5) + 659 * (1 - exp(-t * 4))
            case "swoosh": freq = 200 + 2000 * t
            default: freq = 440
            }

            let volume: Float = Float(envelope * 0.3)
            let val = volume * sinf(Float(2.0 * .pi * freq * t))

            let idx = Int(i)
            ptr[idx] = val
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).wav")
        try? FileManager.default.removeItem(at: tempURL)

        guard let file = try? AVAudioFile(forWriting: tempURL, settings: format.settings) else {
            return nil
        }

        try? file.write(from: buffer)

        return try? AVAudioPlayer(contentsOf: tempURL)
    }

    private func isDoNotDisturb() -> Bool {
        let defaults = UserDefaults(suiteName: "com.apple.notificationcenterui")
        return defaults?.integer(forKey: "dndStart") != 0
    }

    private func loadProfile() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: profilePath)),
              let decoded = try? JSONDecoder().decode(SoundProfile.self, from: data) else { return }
        profile = decoded
    }

    private func saveProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: URL(fileURLWithPath: profilePath))
    }
}
