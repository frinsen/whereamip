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
    // Default-on, unlike notificationsEnabled: `d.bool(forKey:)` returns false
    // for an absent key, which would make "unset" indistinguishable from
    // "explicitly disabled". Check `d.object(forKey:)` first so a fresh
    // install checks for updates by default.
    public var updatesEnabled: Bool {
        get { d.object(forKey: "updatesEnabled") == nil ? true : d.bool(forKey: "updatesEnabled") }
        set { d.set(newValue, forKey: "updatesEnabled") }
    }
    public var dnsProbeEnabled: Bool {
        get { d.object(forKey: "dnsProbeEnabled") == nil ? true : d.bool(forKey: "dnsProbeEnabled") }
        set { d.set(newValue, forKey: "dnsProbeEnabled") }
    }
    // Internal, not surfaced in `set(key:value:)`/the config-command switch below:
    // the milestone (see `welcomeMilestone` in Version.swift) last
    // acknowledged via the welcome window's Done button. Empty = never shown
    // (first run). A plain "shown once" bool isn't enough here — a
    // maintainer needs to be able to re-surface the window on a specific
    // future release without touching every existing installs' "already
    // shown" state, hence storing *which* milestone was last acknowledged
    // rather than just whether any welcome ever happened.
    public var welcomedMilestone: String {
        get { d.string(forKey: "welcomedMilestone") ?? "" }
        set { d.set(newValue, forKey: "welcomedMilestone") }
    }
    public func set(key: String, value: String) throws {
        switch key {
        case "style":
            guard let s = MenuBarStyle(rawValue: value) else { throw SettingsError.invalid("style must be emoji|code|image") }
            menuBarStyle = s
        case "notify":
            guard value == "true" || value == "false" else { throw SettingsError.invalid("notify must be true|false") }
            notificationsEnabled = (value == "true")
        case "updates":
            guard value == "true" || value == "false" else { throw SettingsError.invalid("updates must be true|false") }
            updatesEnabled = (value == "true")
        case "dns":
            guard value == "true" || value == "false" else { throw SettingsError.invalid("dns must be true|false") }
            dnsProbeEnabled = (value == "true")
        // "applications" is deliberately absent here: its truth lives on the
        // filesystem (ApplicationsLink.isLinked), not in UserDefaults, and
        // applying it needs a bundle/executable path this generic setter
        // doesn't have. The CLI's `config set applications` handles it
        // directly via ApplicationsLink instead (see whereamip-cli/Main.swift).
        default: throw SettingsError.invalid("unknown key '\(key)' (valid: style, notify, updates, dns, applications)")
        }
    }
    /// `applicationsLinkPath` is injectable for tests; real callers use the
    /// default `/Applications/WhereAmIP.app`. Unlike the other values
    /// this one isn't read from `d` — it's live filesystem state.
    public func allValues(applicationsLinkPath: String = "/Applications/WhereAmIP.app") -> [(key: String, value: String)] {
        [("notify", String(notificationsEnabled)), ("style", menuBarStyle.rawValue), ("updates", String(updatesEnabled)),
         ("dns", String(dnsProbeEnabled)),
         ("applications", String(ApplicationsLink.isLinked(linkPath: applicationsLinkPath)))]
    }
}

/// Whether the welcome window should be shown automatically at launch, given
/// the previously stored `Settings.welcomedMilestone` (empty = never shown).
/// Extracted as pure logic (no AppKit, no Settings dependency) so it's
/// unit-testable directly against string fixtures.
///
/// True when nothing has been acknowledged yet (first run), or when
/// `welcomeMilestone` (Version.swift) has advanced past what's stored — i.e.
/// a maintainer bumped it in a release worth re-surfacing the window for. A
/// "downgrade" (stored somehow newer than the current constant) never
/// re-triggers it. AppDelegate only stores `welcomedMilestone` when the user
/// clicks Done (not on mere close), so an accidentally dismissed window
/// retries next launch; the Settings-menu manual re-show bypasses this
/// predicate entirely and shows unconditionally.
public func shouldShowWelcome(stored: String) -> Bool {
    stored.isEmpty || SemVer.isNewer(welcomeMilestone, than: stored)
}
