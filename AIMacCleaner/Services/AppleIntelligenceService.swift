import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleIntelligenceResult {
    let content: String
    let modelName: String
}

enum AppleIntelligenceServiceError: LocalizedError {
    case unavailable(String)
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .unsupportedOS:
            return "Apple Intelligence requires macOS 26 or later."
        }
    }
}

enum AppleIntelligenceService {
    static var displayName: String { "Apple Intelligence" }

    static func availabilitySummary() -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Apple Intelligence is available on this Mac."
            case .unavailable(.deviceNotEligible):
                return "This Mac is not eligible for Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence is not enabled in System Settings."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still preparing its on-device model."
            @unknown default:
                return "Apple Intelligence is not available right now."
            }
        }
        #endif
        return "Apple Intelligence requires macOS 26 or later."
    }

    static func generate(instructions: String, prompt: String, maximumResponseTokens: Int = 4096) async throws -> AppleIntelligenceResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                let session = LanguageModelSession(instructions: instructions)
                let options = GenerationOptions(temperature: 0.1, maximumResponseTokens: maximumResponseTokens)
                let response = try await session.respond(to: prompt, options: options)
                return AppleIntelligenceResult(content: response.content, modelName: displayName)
            case .unavailable(.deviceNotEligible):
                throw AppleIntelligenceServiceError.unavailable("This Mac is not eligible for Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                throw AppleIntelligenceServiceError.unavailable("Apple Intelligence is not enabled in System Settings.")
            case .unavailable(.modelNotReady):
                throw AppleIntelligenceServiceError.unavailable("Apple Intelligence is still preparing its on-device model.")
            @unknown default:
                throw AppleIntelligenceServiceError.unavailable("Apple Intelligence is not available right now.")
            }
        }
        #endif
        throw AppleIntelligenceServiceError.unsupportedOS
    }
}
