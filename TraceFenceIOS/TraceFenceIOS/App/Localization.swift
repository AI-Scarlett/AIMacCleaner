import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case maltese = "mt"

    static let storageKey = "TraceFenceIOS.language"

    var id: String { rawValue }

    static var current: AppLanguage {
        fromStoredValue(UserDefaults.standard.string(forKey: storageKey))
    }

    static func fromStoredValue(_ rawValue: String?) -> AppLanguage {
        switch rawValue {
        case "zhHans": return .simplifiedChinese
        case "zhHant": return .traditionalChinese
        default: return rawValue.flatMap(AppLanguage.init(rawValue:)) ?? .english
        }
    }

    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") || preferred.hasPrefix("zh-mo") {
            return .traditionalChinese
        }
        if preferred.hasPrefix("zh") { return .simplifiedChinese }
        if preferred.hasPrefix("ja") { return .japanese }
        if preferred.hasPrefix("ko") { return .korean }
        if preferred.hasPrefix("mt") { return .maltese }
        return .english
    }

    var locale: Locale? {
        guard self != .system else { return nil }
        return Locale(identifier: resolved.rawValue)
    }

    var nativeName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .maltese: return "Malti"
        }
    }

    func title(in displayLanguage: AppLanguage) -> String {
        guard self == .system else { return nativeName }
        return displayLanguage.text(
            zh: "跟随系统",
            en: "Follow System",
            zhHant: "跟隨系統",
            ja: "システムに従う",
            ko: "시스템 설정 사용",
            mt: "Segwi s-Sistema"
        )
    }

    func text(
        zh: String,
        en: String,
        zhHant: String? = nil,
        ja: String? = nil,
        ko: String? = nil,
        mt: String? = nil
    ) -> String {
        switch resolved {
        case .simplifiedChinese:
            return zh
        case .traditionalChinese:
            return zhHant ?? localizedOrEnglish(zh, english: en)
        case .japanese:
            return ja ?? localizedOrEnglish(zh, english: en)
        case .korean:
            return ko ?? localizedOrEnglish(zh, english: en)
        case .maltese:
            return mt ?? localizedOrEnglish(zh, english: en)
        case .english, .system:
            return en
        }
    }

    func localized(_ key: String) -> String {
        if resolved == .simplifiedChinese { return key }
        if let translated = translation(for: key, language: resolved) {
            return translated
        }
        if let english = translation(for: key, language: .english) {
            return english
        }
        return localizedDynamicCopy(key)
    }

    func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale ?? .autoupdatingCurrent, arguments: arguments)
    }

    private func localizedOrEnglish(_ key: String, english: String) -> String {
        let translated = localized(key)
        return translated == key ? english : translated
    }

    private func translation(for key: String, language: AppLanguage) -> String? {
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        let missingValue = "__TRACEFENCE_MISSING_LOCALIZATION__"
        let translated = bundle.localizedString(forKey: key, value: missingValue, table: nil)
        return translated == missingValue ? nil : translated
    }

    private func localizedDynamicCopy(_ key: String) -> String {
        let stoppedSuffix = " TraceFence 已停止该任务。"
        if key.hasSuffix(stoppedSuffix) {
            let reason = String(key.dropLast(stoppedSuffix.count))
            return localized(reason) + text(
                zh: stoppedSuffix,
                en: " TraceFence stopped the task.",
                zhHant: " TraceFence 已停止該任務。",
                ja: " TraceFence はタスクを停止しました。",
                ko: " TraceFence가 작업을 중지했습니다.",
                mt: " TraceFence waqqaf il-kompitu."
            )
        }

        let unconfirmedStopSuffix = " TraceFence 未能确认后台任务已停止，请在 Mac 检查 Claude Code。"
        if key.hasSuffix(unconfirmedStopSuffix) {
            let reason = String(key.dropLast(unconfirmedStopSuffix.count))
            return localized(reason) + text(
                zh: unconfirmedStopSuffix,
                en: " TraceFence could not confirm that the background task stopped. Check Claude Code on the Mac.",
                zhHant: " TraceFence 無法確認背景任務已停止，請在 Mac 上檢查 Claude Code。",
                ja: " TraceFence はバックグラウンドタスクの停止を確認できませんでした。Mac の Claude Code を確認してください。",
                ko: " TraceFence가 백그라운드 작업 중지를 확인하지 못했습니다. Mac에서 Claude Code를 확인하세요.",
                mt: " TraceFence ma setax jikkonferma li l-kompitu fl-isfond waqaf. Iċċekkja Claude Code fuq il-Mac."
            )
        }

        let runningSuffix = " 正在运行"
        if key.hasSuffix(runningSuffix) {
            let name = String(key.dropLast(runningSuffix.count))
            return text(
                zh: "\(name) 正在运行",
                en: "\(name) is running",
                zhHant: "\(name) 正在執行",
                ja: "\(name) は実行中です",
                ko: "\(name) 실행 중",
                mt: "\(name) qed jaħdem"
            )
        }

        let controlledSuffix = " · 可控会话"
        if key.hasSuffix(controlledSuffix) {
            let name = String(key.dropLast(controlledSuffix.count))
            return text(
                zh: "\(name) · 可控会话",
                en: "\(name) · Controlled Session",
                zhHant: "\(name) · 可控工作階段",
                ja: "\(name) · 制御可能なセッション",
                ko: "\(name) · 제어 가능한 세션",
                mt: "\(name) · Sessjoni Kontrollabbli"
            )
        }

        let launchPrefix = "TraceFence 会启动 "
        let launchSuffix = "，创建一个真正可暂停、恢复、发送指令的受控会话。"
        if key.hasPrefix(launchPrefix), key.hasSuffix(launchSuffix) {
            let target = key.dropFirst(launchPrefix.count).dropLast(launchSuffix.count)
            return text(
                zh: key,
                en: "TraceFence will start \(target) and create a controlled session that can truly pause, resume, and receive instructions.",
                zhHant: "TraceFence 將啟動 \(target)，並建立可真正暫停、繼續及接收指令的受控工作階段。",
                ja: "TraceFence は \(target) を起動し、実際に一時停止、再開、指示送信ができる制御セッションを作成します。",
                ko: "TraceFence가 \(target)을 시작하고 실제로 일시 정지, 재개, 지시 전송이 가능한 제어 세션을 만듭니다.",
                mt: "TraceFence se jibda \(target) u joħloq sessjoni kontrollabbli li tista' titwaqqaf, titkompla u tirċievi struzzjonijiet."
            )
        }

        return key
    }
}

extension String {
    var tfLocalized: String {
        AppLanguage.current.localized(self)
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLanguage.current
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}
