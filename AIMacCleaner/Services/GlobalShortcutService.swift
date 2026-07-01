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
        case showAgentCenter = "show_agent_center"
        case startStopServer = "start_stop_server"
        case toggleMonitoring = "toggle_monitoring"
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

actor GlobalShortcutService {
    private var registeredShortcuts: [GlobalShortcut] = []
    private var eventHandlers: [EventHotKeyRef] = []
    private var actionHandlers: [GlobalShortcut.ShortcutAction: @MainActor () -> Void] = [:]

    private let shortcutsPath = NSHomeDirectory() + "/.tracefence_shortcuts.json"

    static let defaultShortcuts: [GlobalShortcut] = [
        GlobalShortcut(
            id: "show_sessions",
            name: "Show Sessions",
            keyCode: 11,
            modifiers: [.command, .option],
            action: .showSessions
        ),
    ]

    init() {
        Task { await loadShortcuts() }
    }

    func register(action: GlobalShortcut.ShortcutAction, handler: @MainActor @escaping () -> Void) {
        actionHandlers[action] = handler
    }

    func registerAll() {
        unregisterAll()

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
        }
        saveShortcuts()
        registerAll()
    }

    func resetToDefaults() {
        registeredShortcuts = Self.defaultShortcuts
        saveShortcuts()
        registerAll()
    }

    private func registerHotKey(_ shortcut: GlobalShortcut) {
        var hotKeyRef: EventHotKeyRef?

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = OSType(("AGRD" as NSString).utf8String?.pointee ?? 0)

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

            InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard err == noErr else { return err }

                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .agentGuardHotKeyPressed, object: Int(hotKeyID.id))
                }
                return noErr
            }, 1, &eventSpec, nil, nil)
        }
    }

    private func loadShortcuts() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: shortcutsPath)),
           let decoded = try? JSONDecoder().decode([GlobalShortcut].self, from: data) {
            registeredShortcuts = decoded
        } else {
            registeredShortcuts = Self.defaultShortcuts
        }
    }

    private func saveShortcuts() {
        guard let data = try? JSONEncoder().encode(registeredShortcuts) else { return }
        try? data.write(to: URL(fileURLWithPath: shortcutsPath))
    }
}

extension Notification.Name {
    static let agentGuardHotKeyPressed = Notification.Name("agentGuardHotKeyPressed")
}
