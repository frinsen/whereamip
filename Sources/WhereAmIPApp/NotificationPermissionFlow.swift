import AppKit
import UserNotifications
import WhereAmIPCore

/// Shared "turn notifications on" flow used by both the menu's "Notify on
/// changes" toggle (AppDelegate) and the welcome window's checkbox
/// (WelcomeWindowController), so the two surfaces can't drift out of sync.
/// The status→action *decision* (`NotificationPermission.action(for:)`)
/// lives in WhereAmIPCore, pure and unit-tested; this wraps it with the
/// actual `UNUserNotificationCenter`/`NSWorkspace` calls, which need a real
/// system notification center and so aren't unit-tested here — covered by
/// manual smoke instead.
enum NotificationPermissionFlow {
    /// Reads current authorization status, then does whatever
    /// `NotificationPermission.action(for:)` says: requests the system
    /// prompt when undetermined, or short-circuits when previously denied
    /// (see `NotificationPermissionAction.openSystemSettings`'s doc) or
    /// already authorized. Always calls back on the main queue.
    ///
    /// - `enabled`: whether the caller should set `settings.notificationsEnabled = true`.
    /// - `needsSystemSettings`: true when the OS previously denied
    ///   permission, so no system prompt was shown — the caller decides how
    ///   to surface that (an inline hint button in the welcome window;
    ///   opening System Settings directly from the menu, which has no
    ///   inline-label surface to show a hint in).
    static func requestEnable(completion: @escaping (_ enabled: Bool, _ needsSystemSettings: Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { notifSettings in
            DispatchQueue.main.async {
                switch NotificationPermission.action(for: notifSettings.authorizationStatus) {
                case .request:
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
                        DispatchQueue.main.async { completion(granted, false) }
                    }
                case .openSystemSettings:
                    completion(false, true)
                case .enableDirectly:
                    completion(true, false)
                }
            }
        }
    }

    static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
    static func openSystemSettings() {
        NSWorkspace.shared.open(systemSettingsURL)
    }
}
