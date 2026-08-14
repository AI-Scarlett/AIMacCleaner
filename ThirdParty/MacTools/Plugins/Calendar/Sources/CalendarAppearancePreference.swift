import AppKit

enum CalendarAppearancePreference: String {
    case system
    case dark
    case light

    private static let userDefaultsKey = "app.appearancePreference"

    @MainActor
    func apply(to view: NSView?) {
        view?.appearance = nsAppearance
    }

    @MainActor
    func apply(to window: NSWindow?) {
        window?.appearance = nsAppearance
    }

    @MainActor
    func apply(to popover: NSPopover) {
        apply(to: popover.contentViewController?.view)
        apply(to: popover.contentViewController?.view.window)
    }

    @MainActor
    private var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .light:
            return NSAppearance(named: .aqua)
        }
    }

    static func stored(in userDefaults: UserDefaults = .standard) -> CalendarAppearancePreference {
        guard
            let rawValue = userDefaults.string(forKey: userDefaultsKey),
            let preference = CalendarAppearancePreference(rawValue: rawValue)
        else {
            return .system
        }

        return preference
    }
}
