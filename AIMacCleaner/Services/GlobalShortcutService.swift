import Carbon
import AppKit

struct GlobalShortcut: Identifiable, Codable {
    var id: String
    var name: String
    var keyCode: Int
    var modifiers: ModifierFlags
    var action: ShortcutAction

    struct ModifierFlags: OptionSet, Codable {
        let rawValue: Int
        static let command = ModifierFlags(rawValue: 1 << 0)
        static let option = ModifierFlags(rawValue: 1 << 1)
        static let control = ModifierFlags(rawValue: 1 << 2)
        static let shift = ModifierFlags(rawValue: 1 << 3)

        var carbonValue: UInt32 {
            var value: UInt32 = 0
            if contains(.command) { value |= UInt32(cmdKey) }
            if contains(.option) { value |= UInt32(optionKey) }
            if contains(.control) { value |= UInt32(controlKey) }
            if contains(.shift) { value |= UInt32(shiftKey) }
            return value
        }

        var displayString: String {
            var parts: [String] = []
            if contains(.command) { parts.append("⌘") }
            if contains(.option) { parts.append("⌥") }
            if contains(.control) { parts.append("⌃") }
            if contains(.shift) { parts.append("⇧") }
            return parts.joined()
        }
    }

    enum ShortcutAction: String, Codable, CaseIterable {
        case showSessions = "show_sessions"
        case captureSelectedRegion = "capture_selected_region"
        case captureFullScreen = "capture_full_screen"
        case toggleScreenRecording = "toggle_screen_recording"

        func localizedName(_ localizer: Localizer) -> String {
            switch self {
            case .showSessions:
                return localizer.t("打开 TraceFence", en: "Open TraceFence", zhHant: "開啟 TraceFence", ja: "TraceFence を開く", ko: "TraceFence 열기", mt: "Open TraceFence")
            case .captureSelectedRegion:
                return localizer.t("区域截屏", en: "Area Screenshot", zhHant: "區域截圖", ja: "範囲スクリーンショット", ko: "영역 스크린샷", mt: "Area Screenshot")
            case .captureFullScreen:
                return localizer.t("全屏截屏", en: "Full Screen Screenshot", zhHant: "全螢幕截圖", ja: "全画面スクリーンショット", ko: "전체 화면 스크린샷", mt: "Full Screen Screenshot")
            case .toggleScreenRecording:
                return localizer.t("开始/停止录屏", en: "Start/Stop Recording", zhHant: "開始/停止錄屏", ja: "録画の開始/停止", ko: "녹화 시작/중지", mt: "Start/Stop Recording")
            }
        }
    }

    var displayString: String {
        "\(modifiers.displayString)\(keyDisplayName)"
    }

    private var keyDisplayName: String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        case 48: return "Tab"
        case 51: return "Delete"
        case 117: return "Del"
        case 122: return "F1"; case 120: return "F2"
        case 99: return "F3"; case 118: return "F4"
        case 96: return "F5"; case 97: return "F6"
        case 98: return "F7"; case 100: return "F8"
        case 101: return "F9"; case 109: return "F10"
        case 103: return "F11"; case 111: return "F12"
        case 123: return "←"; case 124: return "→"
        case 125: return "↓"; case 126: return "↑"
        default:
            if let str = keyCodeToString(keyCode) {
                return str
            }
            return "Key(\(keyCode))"
        }
    }

    private func keyCodeToString(_ code: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let result = UCKeyTranslate(
            keyboardLayout,
            UInt16(code),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &length,
            &chars
        )

        guard result == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

enum GlobalShortcutValidationIssue: Equatable {
    case tooFewModifiers
    case requiresCommandOrControl
    case unsupportedKey
    case reservedSystemShortcut
    case duplicate
    case unavailable

    func localizedMessage(_ localizer: Localizer) -> String {
        switch self {
        case .tooFewModifiers:
            return localizer.t("自定义快捷键至少需要两个修饰键。", en: "Custom shortcuts require at least two modifier keys.", zhHant: "自訂快捷鍵至少需要兩個修飾鍵。", ja: "カスタムショートカットには修飾キーが2つ以上必要です。", ko: "사용자 지정 단축키에는 보조 키가 2개 이상 필요합니다.", mt: "Custom shortcuts require at least two modifier keys.")
        case .requiresCommandOrControl:
            return localizer.t("快捷键必须包含 Command 或 Control。", en: "The shortcut must include Command or Control.", zhHant: "快捷鍵必須包含 Command 或 Control。", ja: "ショートカットには Command または Control が必要です。", ko: "단축키에는 Command 또는 Control이 포함되어야 합니다.", mt: "The shortcut must include Command or Control.")
        case .unsupportedKey:
            return localizer.t("请选择字母、数字、方向键或 F1–F12。", en: "Choose a letter, number, arrow key, or F1–F12.", zhHant: "請選擇字母、數字、方向鍵或 F1–F12。", ja: "英数字、矢印キー、または F1–F12 を選択してください。", ko: "문자, 숫자, 방향 키 또는 F1–F12를 선택하세요.", mt: "Choose a letter, number, arrow key, or F1–F12.")
        case .reservedSystemShortcut:
            return localizer.t("该组合由 macOS 或辅助功能保留，请选择其他快捷键。", en: "This combination is reserved by macOS or accessibility features. Choose another shortcut.", zhHant: "此組合由 macOS 或輔助功能保留，請選擇其他快捷鍵。", ja: "この組み合わせは macOS またはアクセシビリティ機能で予約されています。", ko: "이 조합은 macOS 또는 손쉬운 사용 기능에 예약되어 있습니다.", mt: "This combination is reserved by macOS or accessibility features. Choose another shortcut.")
        case .duplicate:
            return localizer.t("这个组合已用于另一项 TraceFence 操作。", en: "This combination is already assigned to another TraceFence action.", zhHant: "此組合已用於另一項 TraceFence 操作。", ja: "この組み合わせは別の TraceFence 操作に割り当てられています。", ko: "이 조합은 다른 TraceFence 작업에 이미 할당되어 있습니다.", mt: "This combination is already assigned to another TraceFence action.")
        case .unavailable:
            return localizer.t("该快捷键已被其它应用占用，或系统无法注册。", en: "This shortcut is used by another app or could not be registered by macOS.", zhHant: "此快捷鍵已被其他應用程式佔用，或系統無法註冊。", ja: "このショートカットは他のアプリで使用中か、macOS が登録できません。", ko: "이 단축키는 다른 앱에서 사용 중이거나 macOS가 등록할 수 없습니다.", mt: "This shortcut is used by another app or could not be registered by macOS.")
        }
    }
}

extension GlobalShortcut.ModifierFlags {
    init(eventModifiers: NSEvent.ModifierFlags) {
        var value: GlobalShortcut.ModifierFlags = []
        if eventModifiers.contains(.command) { value.insert(.command) }
        if eventModifiers.contains(.option) { value.insert(.option) }
        if eventModifiers.contains(.control) { value.insert(.control) }
        if eventModifiers.contains(.shift) { value.insert(.shift) }
        self = value
    }

    var hasPrimaryModifier: Bool {
        contains(.command) || contains(.option) || contains(.control)
    }

    var modifierCount: Int {
        [Self.command, .option, .control, .shift].reduce(0) { count, flag in
            count + (contains(flag) ? 1 : 0)
        }
    }
}

actor GlobalShortcutService {
    private var registeredShortcuts: [GlobalShortcut] = []
    private var eventHandlers: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var actionHandlers: [GlobalShortcut.ShortcutAction: @MainActor () -> Void] = [:]
    private var lastHandledAt: [GlobalShortcut.ShortcutAction: Date] = [:]

    static let defaultShortcuts: [GlobalShortcut] = [
        GlobalShortcut(
            id: "show_sessions",
            name: "Show Sessions",
            keyCode: 11,
            modifiers: [.command, .option],
            action: .showSessions
        ),
        GlobalShortcut(
            id: "capture_selected_region",
            name: "Area Screenshot",
            keyCode: 21,
            modifiers: [.command, .option, .control],
            action: .captureSelectedRegion
        ),
        GlobalShortcut(
            id: "capture_full_screen",
            name: "Full Screen Screenshot",
            keyCode: 20,
            modifiers: [.command, .option, .control],
            action: .captureFullScreen
        ),
        GlobalShortcut(
            id: "toggle_screen_recording",
            name: "Start/Stop Recording",
            keyCode: 23,
            modifiers: [.command, .option, .control],
            action: .toggleScreenRecording
        ),
    ]

    static func validationIssue(
        for shortcut: GlobalShortcut,
        among shortcuts: [GlobalShortcut]
    ) -> GlobalShortcutValidationIssue? {
        if shortcuts.contains(where: {
            $0.action != shortcut.action
                && $0.keyCode == shortcut.keyCode
                && $0.modifiers == shortcut.modifiers
        }) {
            return .duplicate
        }

        // Existing defaults remain valid so upgrades do not disable capture
        // shortcuts chosen before the stricter recorder rules were added.
        let isShippedDefault = defaultShortcuts.contains {
            $0.action == shortcut.action
                && $0.keyCode == shortcut.keyCode
                && $0.modifiers == shortcut.modifiers
        }
        if isShippedDefault { return nil }

        guard shortcut.modifiers.modifierCount >= 2 else { return .tooFewModifiers }
        guard shortcut.modifiers.contains(.command) || shortcut.modifiers.contains(.control) else {
            return .requiresCommandOrControl
        }
        guard supportedKeyCodes.contains(shortcut.keyCode) else { return .unsupportedKey }
        guard !isReservedSystemShortcut(shortcut) else { return .reservedSystemShortcut }
        return nil
    }

    /// Probes Carbon registration before replacing a saved shortcut. The
    /// candidate is immediately unregistered; the live actor reload then owns
    /// the real registration. Existing self-registration is handled by the
    /// caller by skipping this probe when the combination did not change.
    static func canRegisterTemporarily(_ shortcut: GlobalShortcut) -> Bool {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x54465052, id: UInt32.random(in: 1...UInt32.max))
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers.carbonValue,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if let reference {
            UnregisterEventHotKey(reference)
        }
        return status == noErr
    }

    init() {
        registeredShortcuts = Self.loadPersistedShortcuts()
    }

    func register(action: GlobalShortcut.ShortcutAction, handler: @MainActor @escaping () -> Void) {
        actionHandlers[action] = handler
    }

    func registerAll() {
        unregisterAll()
        installEventHandlerIfNeeded()

        for shortcut in registeredShortcuts {
            registerHotKey(shortcut)
        }
    }

    func unregisterAll() {
        for handler in eventHandlers {
            UnregisterEventHotKey(handler)
        }
        eventHandlers.removeAll()
    }

    func getShortcuts() -> [GlobalShortcut] {
        registeredShortcuts
    }

    func updateShortcut(_ shortcut: GlobalShortcut) {
        if let idx = registeredShortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            registeredShortcuts[idx] = shortcut
        } else {
            registeredShortcuts.append(shortcut)
        }
        saveShortcuts()
        registerAll()
    }

    func reloadShortcutsAndRegister() {
        registeredShortcuts = Self.loadPersistedShortcuts()
        registerAll()
    }

    func handleHotKeyPressed(id: Int) {
        guard registeredShortcuts.indices.contains(id) else { return }
        let action = registeredShortcuts[id].action
        guard let handler = actionHandlers[action] else { return }
        let now = Date()
        let minimumInterval: TimeInterval = action == .toggleScreenRecording ? 0.8 : 0.45
        if let lastHandled = lastHandledAt[action], now.timeIntervalSince(lastHandled) < minimumInterval {
            return
        }
        lastHandledAt[action] = now
        Task { @MainActor in
            handler()
        }
    }

    func resetToDefaults() {
        registeredShortcuts = Self.defaultShortcuts
        saveShortcuts()
        registerAll()
    }

    private func registerHotKey(_ shortcut: GlobalShortcut) {
        var hotKeyRef: EventHotKeyRef?

        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = Self.hotKeySignature

        let idBase = registeredShortcuts.firstIndex(where: { $0.id == shortcut.id }) ?? 0
        gMyHotKeyID.id = UInt32(idBase)

        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers.carbonValue,
            gMyHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            eventHandlers.append(ref)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard err == noErr else { return err }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .traceFenceHotKeyPressed, object: Int(hotKeyID.id))
            }
            return noErr
        }, 1, &eventSpec, nil, &eventHandlerRef)
    }

    private func saveShortcuts() {
        Self.savePersistedShortcuts(registeredShortcuts)
    }

    static func loadPersistedShortcuts() -> [GlobalShortcut] {
        let url = URL(fileURLWithPath: SandboxPaths.shared.shortcutsPath)
        let saved: [GlobalShortcut]
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([GlobalShortcut].self, from: data) {
            saved = decoded
        } else {
            saved = defaultShortcuts
        }
        let merged = mergedWithDefaults(saved)
        return merged.map { shortcut in
            validationIssue(for: shortcut, among: merged) == nil
                ? shortcut
                : (defaultShortcuts.first { $0.action == shortcut.action } ?? shortcut)
        }
    }

    static func savePersistedShortcuts(_ shortcuts: [GlobalShortcut]) {
        let merged = mergedWithDefaults(shortcuts)
        guard let data = try? JSONEncoder().encode(merged) else { return }
        try? data.write(to: URL(fileURLWithPath: SandboxPaths.shared.shortcutsPath), options: .atomic)
    }

    private static func mergedWithDefaults(_ shortcuts: [GlobalShortcut]) -> [GlobalShortcut] {
        var byAction = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.action, $0) })
        for shortcut in defaultShortcuts where byAction[shortcut.action] == nil {
            byAction[shortcut.action] = shortcut
        }
        return defaultShortcuts.compactMap { byAction[$0.action] }
    }

    private static let hotKeySignature: OSType = 0x54464B59

    private static let supportedKeyCodes: Set<Int> = Set(
        Array(0...50)
            + [96, 97, 98, 99, 100, 101, 103, 109, 111, 117, 120, 122, 123, 124, 125, 126]
    )

    private static func isReservedSystemShortcut(_ shortcut: GlobalShortcut) -> Bool {
        let modifiers = shortcut.modifiers
        if modifiers.contains(.control)
            && modifiers.contains(.option)
            && !modifiers.contains(.command) {
            return true
        }

        let reserved: [(keyCode: Int, modifiers: GlobalShortcut.ModifierFlags)] = [
            (53, [.command, .option]),
            (12, [.command, .control]),
            (12, [.command, .shift]),
            (2, [.command, .option]),
            (3, [.command, .control]),
            (4, [.command, .option]),
            (46, [.command, .option]),
            (13, [.command, .option]),
            (20, [.command, .shift]),
            (21, [.command, .shift]),
            (23, [.command, .shift]),
            (96, [.command, .option])
        ]
        return reserved.contains { item in
            item.keyCode == shortcut.keyCode
                && modifiers.intersection(item.modifiers) == item.modifiers
        }
    }
}

extension Notification.Name {
    static let traceFenceHotKeyPressed = Notification.Name("traceFenceHotKeyPressed")
    static let traceFenceShortcutsChanged = Notification.Name("traceFenceShortcutsChanged")
}

extension Notification.Name {
    @available(*, deprecated, message: "Use traceFenceHotKeyPressed.")
    static let agentGuardHotKeyPressed = Notification.Name("agentGuardHotKeyPressed")
}
