import Foundation
import WhereAmIPCore

/// Every user-facing string the app can show, as a stable key.
///
/// The point of this enum is that the maintainer can retune wording for a release
/// by editing `Resources/en.lproj/Localizable.strings` alone — no Swift, no
/// recompile of intent, and no test breakage, because the tests assert against
/// `L10n.string(.someKey)` rather than against literals.
///
/// The same mechanism carries translations: `de.lproj` sits beside `en.lproj` and macOS
/// picks between them on its own — nothing in this file or at any call site knows which
/// language it is serving. Adding a locale is a folder plus one entry in
/// `L10nTests.shippedLocales`, which then holds it to the same completeness and
/// placeholder-parity bar as English.
///
/// Keys are hierarchical and lowercase dot-separated, grouped by the surface they
/// appear on (`menu.` dropdown rows, `settings.` submenu items, `dns.` the DNS row
/// and its detail submenu, `notification.` banner titles/bodies, `welcome.` the
/// welcome window, `help.` the help window). A raw-string API was deliberately NOT
/// chosen: `CaseIterable`
/// over a typed key is what makes the completeness test mechanical — a key added
/// here but forgotten in the .strings file fails the suite, and a typo at a call
/// site fails the compiler.
///
/// Placeholders are `%@`/`%d` and are filled via `String(format:)`, so the ORDER and
/// COUNT of placeholders in a value is part of its contract: changing wording is
/// free, dropping a `%@` is not.
///
/// Deliberately NOT here: anything the `whereamip` CLI prints (`StateRenderer`,
/// which feeds `status`/`watch` only), JSON field names, and log messages. The CLI's
/// output is a stable API other scripts parse — it is not "text to fine-tune".
public enum L10nKey: String, CaseIterable {

    // MARK: - menu: the dropdown's own rows

    case menuHeader = "menu.header"
    case menuUpdateRestart = "menu.update.restart"
    case menuUpdateAvailable = "menu.update.available"
    case menuUpdateAvailableDownload = "menu.update.available.download"
    case menuOffline = "menu.offline"
    case menuOfflineHijack = "menu.offline.hijack"
    case menuOfflineLastSeen = "menu.offline.lastSeen"
    case menuLeakIPv6 = "menu.leak.ipv6"
    case menuLeakDNS = "menu.leak.dns"
    case menuLeakDNSWithOperator = "menu.leak.dns.withOperator"
    case menuLeakDNSSuspected = "menu.leak.dns.suspected"
    case menuSince = "menu.since"
    case menuChecked = "menu.checked"
    case menuRouteVPN = "menu.route.vpn"
    case menuRouteVPNUnnamed = "menu.route.vpn.unnamed"
    case menuRouteLink = "menu.route.link"
    case menuPrivateRelay = "menu.privateRelay"
    case menuPrivateRelayVia = "menu.privateRelay.via"
    case menuOrgUnknown = "menu.org.unknown"
    case menuCopyExitBoth = "menu.copyExitBoth"
    case menuCopyExitBothUnavailable = "menu.copyExitBoth.unavailable"
    case menuCopyDiagnostics = "menu.copyDiagnostics"
    case menuRefresh = "menu.refresh"
    case menuHelp = "menu.help"
    case menuSettings = "menu.settings"
    case menuRestart = "menu.restart"
    case menuQuit = "menu.quit"

    // MARK: - settings: the Settings submenu, shared with the welcome window's checkboxes

    case settingsStyle = "settings.style"
    case settingsStyleEmoji = "settings.style.emoji"
    case settingsStyleCode = "settings.style.code"
    case settingsStyleImage = "settings.style.image"
    case settingsLanguage = "settings.language"
    case settingsLanguageSystem = "settings.language.system"
    case settingsLanguageEnglish = "settings.language.english"
    case settingsLanguageGerman = "settings.language.german"
    case settingsNotifications = "settings.notifications"
    case settingsLaunchAtLogin = "settings.launchAtLogin"
    case settingsApplicationsLink = "settings.applicationsLink"
    case settingsUpdates = "settings.updates"
    case settingsDNSProbe = "settings.dnsProbe"
    case settingsWelcome = "settings.welcome"
    case settingsWhatsNew = "settings.whatsNew"

    // MARK: - dns: the DNS summary row and its detail submenu

    case dnsRow = "dns.row"
    case dnsRowInterface = "dns.row.interface"
    case dnsRowDoH = "dns.row.doh"
    case dnsRowDoT = "dns.row.dot"
    case dnsRowPlaintext = "dns.row.plaintext"
    case dnsRowMore = "dns.row.more"
    case dnsSectionConfigured = "dns.section.configured"
    case dnsSectionEgress = "dns.section.egress"
    case dnsResolverInterfaces = "dns.resolver.interfaces"
    case dnsDisabled = "dns.disabled"
    case dnsForwarder = "dns.forwarder"
    case dnsCopyConfigured = "dns.copy.configured"
    case dnsCopyAnswering = "dns.copy.answering"

    // MARK: - help: the help window's chrome only. Its BODY is bundled Markdown
    // (Resources/help/help.md, see HelpContent) — prose, not a label, exactly like
    // the welcome window's copy.

    case helpWindowTitle = "help.window.title"

    // MARK: - notification: banner titles and bodies

    case notificationCountryChangedTitle = "notification.countryChanged.title"
    case notificationCountryChangedBody = "notification.countryChanged.body"
    case notificationCountryChangedBodyVPN = "notification.countryChanged.body.vpn"
    case notificationIPChangedTitle = "notification.ipChanged.title"
    case notificationOfflineTitle = "notification.offline.title"
    case notificationOfflineBody = "notification.offline.body"
    case notificationOfflineBodyHijack = "notification.offline.body.hijack"
    case notificationOnlineTitle = "notification.online.title"
    case notificationLeakTitle = "notification.leak.title"
    case notificationLeakBody = "notification.leak.body"
    case notificationRelayOnTitle = "notification.relay.on.title"
    case notificationRelayOnBody = "notification.relay.on.body"
    case notificationRelayOffTitle = "notification.relay.off.title"
    case notificationRelayOffBody = "notification.relay.off.body"
    case notificationIPv6Title = "notification.ipv6.title"
    case notificationIPv6Body = "notification.ipv6.body"
    case notificationDNSTitle = "notification.dns.title"
    case notificationDNSBody = "notification.dns.body"
    case notificationDNSBodyEgress = "notification.dns.body.egress"
    case notificationFlagUnknown = "notification.flag.unknown"
    case notificationOrgUnknown = "notification.org.unknown"

    // MARK: - welcome: the first-run / what's-new window
    //
    // Only its chrome lives here. The window's BODY copy is bundled Markdown
    // (Resources/welcome/*.md, see WelcomeContent) because it is per-milestone
    // prose, not a label.

    case welcomeWindowTitle = "welcome.window.title"
    // ONE heading for both variants. There used to be two — a "Welcome to
    // WhereAmIP v%@" and a "WhereAmIP v%@ — what's new" — because the heading
    // was also carrying the category. The category now has its own badge (the
    // two keys below), so both variants say the same thing and a second key
    // would only be two strings free to drift apart. Which VERSION fills the
    // %@ still differs and is the caller's decision, not the string's: the
    // pitch is titled with the running version, the highlights with the
    // milestone that earned the re-show (see WelcomeContent.copy(variant:)).
    case welcomeHeading = "welcome.heading"
    // The category pill above the heading. Stored in title case and uppercased
    // by the view (BadgePill), the same split SwiftUI's `.textCase(.uppercase)`
    // makes: the strings file stays readable and translatable, and the
    // uppercasing stays locale-aware.
    case welcomeBadgeIntro = "welcome.badge.intro"
    case welcomeBadgeWhatsNew = "welcome.badge.whatsNew"
    /// First-run pitch only — see `WelcomeContent.showsNotchHint(variant:)`.
    case welcomeHint = "welcome.hint"
    /// Section header for the toggles. Stored title case, uppercased by the view
    /// (WelcomeLayout.sectionHeader), the same split the badges make.
    case welcomeSetupHeader = "welcome.setup.header"
    /// Its caption. Used to be a parenthetical stuck onto the header itself; it is
    /// now a caption line under it, so the header can be a header.
    case welcomeSetupCaption = "welcome.setup.caption"
    case welcomeNotifyCaption = "welcome.notify.caption"
    case welcomeNotifyHint = "welcome.notify.hint"
    case welcomePrivacy = "welcome.privacy"
    case welcomeDone = "welcome.done"
}

/// Reads `L10nKey` values out of the bundled strings table.
///
/// `Bundle.localizedString(forKey:value:table:)` with a nil value returns the KEY
/// when the table (or the whole bundle) is missing — deliberately kept as the
/// last-resort fallback: a visible `menu.refresh` in the UI is an obvious,
/// self-describing bug report, where a crash or a blank row is neither.
public enum L10n {
    /// The stored language setting — `AppLanguage.system` or a supported code. One knob,
    /// read by both consumers below, so the strings table and the bundled Markdown can never
    /// disagree about which language the app is currently speaking.
    ///
    /// A closure rather than a direct `Settings()` read at each call site so tests can pin a
    /// language deterministically (the alternative — depending on the HOST Mac's language —
    /// is exactly the fragility this indirection removes).
    public static var languageSetting: () -> String = { Settings().language }

    /// The language list the Markdown loader should walk, derived from the same setting.
    public static func effectiveLanguages() -> [String] {
        AppLanguage.effectiveLanguages(override: languageSetting())
    }

    /// The literal value for `key`, with no formatting applied.
    public static func string(_ key: L10nKey) -> String {
        stringsBundle().localizedString(forKey: key.rawValue, value: nil, table: nil)
    }

    /// Which bundle answers a lookup.
    ///
    /// With NO override this is the located bundle itself, exactly as before this setting
    /// existed — Foundation matches the user's language list against the available `.lproj`s
    /// far better than a hand-rolled walk would, and the system path must not regress.
    ///
    /// With an override it is that language's `.lproj` as its own bundle. Of the two
    /// mechanisms available for a NESTED SwiftPM resource bundle, this is the one that
    /// works end to end: `url(forResource:withExtension:subdirectory:localization:)` does
    /// resolve the right file, but hands back a URL that would have to be parsed by hand,
    /// while `Bundle(path: …/de.lproj)` keeps the whole `localizedString` contract —
    /// including "return the key when the value is missing", which is the visible-bug
    /// fallback the rest of this file relies on. (SwiftPM leaves the .strings files as
    /// plain text in the bundle, which is what makes the sub-bundle load work.)
    static func stringsBundle() -> Bundle {
        guard let code = AppLanguage.overrideCode(languageSetting()) else { return uiResourceBundle }
        return lproj(code) ?? uiResourceBundle
    }

    /// Resolved `.lproj` sub-bundles, cached: a single menu build performs dozens of
    /// lookups, and `Bundle(path:)` touches the filesystem. The lock costs nothing at this
    /// call rate and keeps the cache honest if a lookup ever happens off the main thread.
    private static let cacheLock = NSLock()
    private static var lprojCache: [String: Bundle] = [:]
    private static func lproj(_ code: String) -> Bundle? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = lprojCache[code] { return cached }
        guard let path = uiResourceBundle.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        lprojCache[code] = bundle
        return bundle
    }

    /// The value for `key` with its `%@`/`%d` placeholders filled, in order.
    public static func string(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }
}
