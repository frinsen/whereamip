import Darwin

/// Running process names via libproc — kernel API, no AppKit, works from the CLI.
/// Used only as naming evidence (classic VPN daemons are invisible to SCDynamicStore).
///
/// Two limits decide what a caller may match on, both MEASURED on a real machine (1284
/// pids), not assumed:
///
///   - `proc_name` FAILS for processes owned by another user. 282 of those 1284 pids
///     returned no name, and every one of them was root-owned. **Root daemons are
///     invisible to this scanner**, so a check for a privileged daemon's name is dead
///     code that silently never fires — exactly how VPNNamer's original `ovpnagent`
///     tell came to do nothing at all. Match the user-owned GUI processes an app also
///     runs instead. Running as root to see them is not on the table: this ships as an
///     unprivileged menu bar app, and no naming nicety is worth asking for that.
///   - The names are the kernel's SHORT names, and they are truncated — the field
///     sample "OpenVPN Connect Helper (Rendere" is cut mid-word. Never match against a
///     full executable name; use a prefix.
public enum ProcessScanner {
    public static func runningProcessNames() -> Set<String> {
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        count = proc_listallpids(&pids, Int32(pids.count) * Int32(MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        var names: Set<String> = []
        var buf = [CChar](repeating: 0, count: 4 * 1024)
        for pid in pids.prefix(Int(count)) where pid > 0 {
            if proc_name(pid, &buf, UInt32(buf.count)) > 0 { names.insert(String(cString: buf)) }
        }
        return names
    }
}
