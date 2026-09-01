import os

// Public (not just internal to this module) so WhereAmIPApp can log through
// the same subsystem/categories — e.g. AppDelegate's relaunch() failure path
// — rather than standing up a second, disconnected Logger. `whereamip debug`
// streams the whole subsystem regardless of which module emitted an entry,
// so this doesn't change what's visible, only who's allowed to write to it.
//
// Never localized, deliberately: log lines are read by whoever is debugging — through
// `whereamip debug` or Console.app — and end up quoted in issues. English keeps them
// greppable and comparable across machines. The app's UI speaks the user's language; its
// diagnostics speak the project's (same rule as StateRenderer and DiagnosticsReport).
public enum Log {
    static let subsystem = "io.github.frinsen.whereamip"
    public static let monitor = Logger(subsystem: subsystem, category: "monitor")
    public static let geo     = Logger(subsystem: subsystem, category: "geo")
    public static let route   = Logger(subsystem: subsystem, category: "route")
    public static let reducer = Logger(subsystem: subsystem, category: "reducer")
    public static let relay   = Logger(subsystem: subsystem, category: "relay")
    public static let update  = Logger(subsystem: subsystem, category: "update")
    public static let dns     = Logger(subsystem: subsystem, category: "dns")
    // Launch-time single-instance arbitration (AppDelegate + InstanceArbiter). Its own
    // category because the thing it records is a duplicate LAUNCH — the evidence someone
    // needs when two icons appear, and the one decision that happens before any other
    // category has produced a single line.
    public static let instance = Logger(subsystem: subsystem, category: "instance")
}
