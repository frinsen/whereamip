import os

// Public (not just internal to this module) so WhereAmIPApp can log through
// the same subsystem/categories — e.g. AppDelegate's relaunch() failure path
// — rather than standing up a second, disconnected Logger. `whereamip debug`
// streams the whole subsystem regardless of which module emitted an entry,
// so this doesn't change what's visible, only who's allowed to write to it.
public enum Log {
    static let subsystem = "io.github.frinsen.whereamip"
    public static let monitor = Logger(subsystem: subsystem, category: "monitor")
    public static let geo     = Logger(subsystem: subsystem, category: "geo")
    public static let route   = Logger(subsystem: subsystem, category: "route")
    public static let reducer = Logger(subsystem: subsystem, category: "reducer")
    public static let relay   = Logger(subsystem: subsystem, category: "relay")
    public static let update  = Logger(subsystem: subsystem, category: "update")
}
