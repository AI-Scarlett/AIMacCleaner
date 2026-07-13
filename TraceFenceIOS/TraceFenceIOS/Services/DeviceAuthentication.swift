import Foundation
import LocalAuthentication

enum DeviceAuthenticationMethod: Equatable {
    case faceID
    case touchID
    case devicePasscode

    var icon: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .devicePasscode: return "lock.fill"
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .devicePasscode:
            return language.text(
                zh: "设备密码",
                en: "Device Passcode",
                zhHant: "裝置密碼",
                ja: "デバイスのパスコード",
                ko: "기기 암호",
                mt: "Kodiċi tal-Apparat"
            )
        }
    }
}

enum DeviceAuthenticationError: LocalizedError {
    case unavailable
    case cancelled
    case failed

    var errorDescription: String? {
        let language = AppLanguage.current
        switch self {
        case .unavailable:
            return language.text(
                zh: "此设备未启用 Face ID、Touch ID 或设备密码。请先在系统设置中启用设备密码。",
                en: "Face ID, Touch ID, and the device passcode are unavailable. Enable a device passcode in Settings first.",
                zhHant: "此裝置未啟用 Face ID、Touch ID 或裝置密碼。請先在系統設定中啟用裝置密碼。",
                ja: "Face ID、Touch ID、デバイスのパスコードを利用できません。先に設定でパスコードを有効にしてください。",
                ko: "Face ID, Touch ID 및 기기 암호를 사용할 수 없습니다. 먼저 설정에서 기기 암호를 활성화하세요.",
                mt: "Face ID, Touch ID u l-kodiċi tal-apparat mhumiex disponibbli. Attiva kodiċi fl-Issettjar."
            )
        case .cancelled:
            return language.text(zh: "身份验证已取消。", en: "Authentication was cancelled.", zhHant: "身分驗證已取消。", ja: "認証がキャンセルされました。", ko: "인증이 취소되었습니다.", mt: "L-awtentikazzjoni ġiet ikkanċellata.")
        case .failed:
            return language.text(zh: "身份验证失败，请重试。", en: "Authentication failed. Try again.", zhHant: "身分驗證失敗，請再試一次。", ja: "認証に失敗しました。もう一度お試しください。", ko: "인증에 실패했습니다. 다시 시도하세요.", mt: "L-awtentikazzjoni falliet. Erġa' pprova.")
        }
    }
}

enum DeviceAuthentication {
    static func availableMethod() -> DeviceAuthenticationMethod {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            default: break
            }
        }
        return .devicePasscode
    }

    static func authorize(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = AppLanguage.current.text(zh: "取消", en: "Cancel", zhHant: "取消", ja: "キャンセル", ko: "취소", mt: "Ikkanċella")
        context.localizedFallbackTitle = AppLanguage.current.text(zh: "使用设备密码", en: "Use Passcode", zhHant: "使用裝置密碼", ja: "パスコードを使用", ko: "기기 암호 사용", mt: "Uża l-Kodiċi")

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw DeviceAuthenticationError.unavailable
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            guard success else { throw DeviceAuthenticationError.failed }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                throw DeviceAuthenticationError.cancelled
            case .passcodeNotSet, .biometryNotAvailable:
                throw DeviceAuthenticationError.unavailable
            default:
                throw DeviceAuthenticationError.failed
            }
        }
    }
}

@MainActor
final class AppSecurityController: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var method = DeviceAuthentication.availableMethod()

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TraceFenceUITestUnlocked") {
            isUnlocked = true
        }
#endif
    }

    func unlock() async {
        guard !isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        method = DeviceAuthentication.availableMethod()
        defer { isAuthenticating = false }

        let language = AppLanguage.current
        do {
            try await DeviceAuthentication.authorize(
                reason: language.text(
                    zh: "验证身份后查看和控制 Mac 上的 Agent 会话。",
                    en: "Authenticate to view and control agent sessions on your Mac.",
                    zhHant: "驗證身分後查看及控制 Mac 上的 Agent 工作階段。",
                    ja: "認証して Mac 上の Agent セッションを表示・操作します。",
                    ko: "인증 후 Mac의 Agent 세션을 확인하고 제어합니다.",
                    mt: "Awtentika biex tara u tikkontrolla s-sessjonijiet tal-Agent fuq il-Mac."
                )
            )
            isUnlocked = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func authorizeSensitiveAction(reason: String) async -> Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TraceFenceUITestUnlocked") {
            errorMessage = nil
            return true
        }
#endif
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        errorMessage = nil
        method = DeviceAuthentication.availableMethod()
        defer { isAuthenticating = false }

        do {
            try await DeviceAuthentication.authorize(reason: reason)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func lock() {
        isUnlocked = false
        errorMessage = nil
    }
}
