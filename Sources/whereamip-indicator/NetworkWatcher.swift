import CLinuxSupport
import Foundation
import Glibc
import WhereAmIPCore

/// The Linux stand-in for `NWPathMonitor`: netlink route events (links, addresses, routes,
/// both families), reduced to "the network path actually changed".
///
/// Netlink is far chattier than NWPathMonitor — IPv6 router advertisements refresh address
/// lifetimes every few minutes, a DHCP renewal re-announces the same lease — and every
/// `pathChanged()` ends in a full refresh (geo lookups, a DNS round). So events only arm a
/// short settle timer, and when it fires a cheap local fingerprint (default-route
/// interfaces and the set of on-link prefixes, all syscalls, no network) decides whether
/// anything changed that a refresh could see.
final class NetworkWatcher {
    private let onChange: () -> Void
    private var fingerprint: String
    private var settlePending = false

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.fingerprint = Self.currentFingerprint()
    }

    func start() {
        let fd = whereamip_netlink_route_socket()
        guard fd >= 0 else {
            Log.monitor.error("netlink: socket unavailable — relying on the periodic refresh")
            return
        }
        let thread = Thread { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let n = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
                if n < 0 {
                    if errno == EINTR || errno == ENOBUFS { continue }   // ENOBUFS: events dropped — still a change
                    break
                }
                MainThread.async { self?.eventArrived() }
            }
            close(fd)
        }
        thread.name = "whereamip.netlink"
        thread.start()
    }

    /// Main loop. Coalesces a burst of events into one look, a second after the last.
    private func eventArrived() {
        guard !settlePending else { return }
        settlePending = true
        MainThread.after(milliseconds: 1000) { [weak self] in
            guard let self else { return }
            self.settlePending = false
            let now = Self.currentFingerprint()
            guard now != self.fingerprint else { return }
            Log.monitor.debug("netlink: path changed")
            self.fingerprint = now
            self.onChange()
        }
    }

    static func currentFingerprint() -> String {
        let v4 = RouteInspector.defaultRouteInterface()
        let v6 = RouteInspector.defaultRouteInterface6()
        let prefixes = RouteInspector.localPrefixes().map { "\($0.address)/\($0.prefixLength)" }.sorted()
        return [v4?.interface ?? "-", v4?.localAddress ?? "-", v6?.interface ?? "-"].joined(separator: "|")
            + "|" + prefixes.joined(separator: ",")
    }
}

/// One panel icon per user. A second launch (a double click in the applications menu, an
/// autostart entry plus a manual start) leaves quietly instead of adding a second flag.
///
/// The lock is an flock on a file in the runtime directory: the kernel drops it the moment
/// the holder exits, however it exits, so a crash can never leave a stale lock behind. The
/// descriptor is close-on-exec, which matters for Restart — the waiter it spawns must not
/// inherit the lock and so block the new instance it is about to start.
enum InstanceLock {
    private static var descriptor: Int32 = -1

    static func acquire(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        let directory = environment["XDG_RUNTIME_DIR"].flatMap { $0.hasPrefix("/") ? $0 : nil }
            ?? NSTemporaryDirectory()
        let path = "\(directory)/whereamip-indicator-\(getuid()).lock"
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return true }          // cannot lock at all: run rather than vanish
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        descriptor = fd
        return true
    }
}
