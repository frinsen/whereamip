import os

enum Log {
    static let subsystem = "io.github.frinsen.whereamip"
    static let monitor = Logger(subsystem: subsystem, category: "monitor")
    static let geo     = Logger(subsystem: subsystem, category: "geo")
    static let route   = Logger(subsystem: subsystem, category: "route")
    static let reducer = Logger(subsystem: subsystem, category: "reducer")
    static let relay   = Logger(subsystem: subsystem, category: "relay")
    static let update  = Logger(subsystem: subsystem, category: "update")
    static let dns     = Logger(subsystem: subsystem, category: "dns")
}
