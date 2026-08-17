import UserNotifications

/// What should happen next when the user opts to turn notifications on,
/// given the *current* system authorization status. Split out as a pure
/// decision so it's unit-testable without a real notification center — the
/// actual `UNUserNotificationCenter`/`NSWorkspace` calls live in the app
/// target (WhereAmIPApp's `NotificationPermissionFlow`), which both the menu's
/// "Show Notifications" toggle and the welcome window's checkbox go through,
/// so the two surfaces can't drift out of sync.
public enum NotificationPermissionAction: Equatable {
    /// Never asked before — show the system permission prompt.
    case request
    /// Previously denied at the OS level. Calling `requestAuthorization`
    /// again resolves silently with no UI — from the user's point of view
    /// the toggle would just look dead. Send them to System Settings instead.
    case openSystemSettings
    /// Already authorized (or provisional) — just flip the setting, no
    /// system UI needed.
    case enableDirectly
}

public enum NotificationPermission {
    public static func action(for status: UNAuthorizationStatus) -> NotificationPermissionAction {
        switch status {
        case .notDetermined: return .request
        case .denied: return .openSystemSettings
        // .authorized, .provisional, .ephemeral, and any future case macOS
        // adds: all mean "we're allowed to notify already", so just enable.
        default: return .enableDirectly
        }
    }
}
