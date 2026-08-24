public let whereamipVersion = "0.5.5"

/// Release-time "flag" for re-showing the first-run welcome window on
/// upgrade. Bump this ONLY in a release whose changes genuinely warrant
/// re-surfacing the window (major changes, notable new features) — leaving
/// it untouched means ordinary upgrades stay silent. Compared against
/// `Settings.welcomedMilestone` via `shouldShowWelcome(stored:)`.
public let welcomeMilestone = "0.5"
