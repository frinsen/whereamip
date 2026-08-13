import Foundation

public enum SettingsError: Error, Equatable { case invalid(String) }

public final class Settings: @unchecked Sendable {
    public static let suiteName = "io.github.frinsen.whereamip"
    private let d: UserDefaults
    // `UserDefaults(suiteName:)` returns nil when the suite name equals the process's own
    // main bundle identifier (macOS logs "does not make sense and will not work" and hands
    // back nil rather than a real suite) — exactly the case for the packaged WhereAmIP.app,
    // whose CFBundleIdentifier is this same string. Force-unwrapping crashed the app on
    // launch; falling back to `.standard` degrades gracefully to the same per-app defaults
    // domain the OS would have used anyway. The CLI executable has a distinct bundle
    // identifier (`...whereamip.cli`), so it keeps using the real named suite unaffected.
    public init(defaults: UserDefaults = UserDefaults(suiteName: Settings.suiteName) ?? .standard) { d = defaults }

    public var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: d.string(forKey: "menuBarStyle") ?? "") ?? .emoji }
        set { d.set(newValue.rawValue, forKey: "menuBarStyle") }
    }
    public var notificationsEnabled: Bool {
        get { d.bool(forKey: "notificationsEnabled") }
        set { d.set(newValue, forKey: "notificationsEnabled") }
    }
    public func set(key: String, value: String) throws {
        switch key {
        case "style":
            guard let s = MenuBarStyle(rawValue: value) else { throw SettingsError.invalid("style must be emoji|code|image") }
            menuBarStyle = s
        case "notify":
            guard value == "true" || value == "false" else { throw SettingsError.invalid("notify must be true|false") }
            notificationsEnabled = (value == "true")
        default: throw SettingsError.invalid("unknown key '\(key)' (valid: style, notify)")
        }
    }
    public func allValues() -> [(key: String, value: String)] {
        [("notify", String(notificationsEnabled)), ("style", menuBarStyle.rawValue)]
    }
}
