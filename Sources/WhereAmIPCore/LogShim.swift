#if !canImport(os)
import Foundation

// Linux stand-in for `os.Logger`, shaped so `Log.swift` and every call site compile
// unchanged: `Log.geo.debug("fetch \(name, privacy: .public): failure")` reads the same
// on both platforms.
//
// The privacy promise does not change with the platform. macOS keeps debug entries in
// the in-memory ring buffer and nothing persists them; journald on most distributions
// DOES persist, so this shim never writes to it. Entries go to standard error, and only
// while something has switched the sink on: `whereamip debug` (which streams them live,
// exactly like `log stream` on macOS) or `WHEREAMIP_DEBUG=1` in the environment of the
// process being debugged. Otherwise a log call evaluates nothing at all — the message is
// an autoclosure, so not even the string is built.

/// How an interpolated value may appear in a log line. Mirrors `OSLogPrivacy`'s spelling
/// so call sites need no `#if`. Every call site in this codebase says `.public`; the other
/// cases exist so the API means the same thing it means on macOS.
public enum LogPrivacy: Sendable {
    case `public`, `private`, auto
}

public struct LogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral {
    let text: String

    public init(stringLiteral value: String) { text = value }
    public init(stringInterpolation: Interpolation) { text = stringInterpolation.text }

    public struct Interpolation: StringInterpolationProtocol {
        var text = ""
        public init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity + 16 * interpolationCount)
        }
        public mutating func appendLiteral(_ literal: String) { text += literal }

        /// `.public` prints the value. Anything else redacts it the way os_log does by
        /// default: numbers and booleans are not personal data, strings may be.
        public mutating func appendInterpolation<T>(_ value: @autoclosure () -> T,
                                                    privacy: LogPrivacy = .auto) {
            let v = value()
            switch privacy {
            case .public:
                text += String(describing: v)
            case .private, .auto:
                if v is any BinaryInteger || v is any BinaryFloatingPoint || v is Bool {
                    text += String(describing: v)
                } else {
                    text += "<private>"
                }
            }
        }
    }
}

/// Where Linux log entries go, and whether they go anywhere at all.
public enum LogSink {
    private static let lock = NSLock()
    private static var enabledOverride: Bool?
    private static let enabledByEnvironment =
        ProcessInfo.processInfo.environment["WHEREAMIP_DEBUG"].map { !$0.isEmpty && $0 != "0" } ?? false

    /// Off unless `WHEREAMIP_DEBUG` is set, or a caller (the `debug` subcommand) turns it on.
    public static var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return enabledOverride ?? enabledByEnvironment }
        set { lock.lock(); enabledOverride = newValue; lock.unlock() }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(level: String, category: String, _ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(stamp.string(from: Date())) \(level) [\(category)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

public struct Logger: Sendable {
    let subsystem: String
    let category: String

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    public func debug(_ message: @autoclosure () -> LogMessage) { emit("debug", message) }
    public func info(_ message: @autoclosure () -> LogMessage) { emit("info", message) }
    public func notice(_ message: @autoclosure () -> LogMessage) { emit("notice", message) }
    public func error(_ message: @autoclosure () -> LogMessage) { emit("error", message) }
    public func fault(_ message: @autoclosure () -> LogMessage) { emit("fault", message) }

    private func emit(_ level: String, _ message: () -> LogMessage) {
        guard LogSink.isEnabled else { return }
        LogSink.write(level: level, category: category, message().text)
    }
}
#endif
