#if os(Linux)
import Foundation

/// Running process names from procfs — the Linux side of `ProcessScanner`. Used only as
/// naming evidence for tunnels nothing else can name, exactly as on macOS.
///
/// The two limits the macOS scanner documents translate as follows, and a VPNNamer tell
/// must respect them on both platforms:
///
///   - Visibility is BETTER here: `/proc/<pid>/comm` is world-readable, so root daemons
///     (`openvpn`, `tailscaled`, `warp-svc`) are visible to an unprivileged user — unless
///     /proc is mounted with `hidepid`, in which case only the user's own processes are.
///     A tell may therefore not REQUIRE a root daemon to be seen; the macOS rule (match
///     what an unprivileged scanner reliably sees) still holds.
///   - Names are truncated, like `proc_name`: the kernel keeps 15 bytes of the command name
///     (TASK_COMM_LEN). Match by prefix, never against a full executable name.
public enum ProcessScanner {
    public static func runningProcessNames() -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else { return [] }
        var names: Set<String> = []
        for pid in entries where !pid.isEmpty && pid.allSatisfy(\.isASCIIDigit) {
            // A process can exit between the listing and the read; that is a skip, not an error.
            guard let comm = LinuxSystem.read("/proc/\(pid)/comm", limit: 64) else { continue }
            let name = comm.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names.insert(name) }
        }
        return names
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
#endif
