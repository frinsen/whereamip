import Darwin

/// Running process names via libproc — kernel API, no AppKit, works from the CLI.
/// Used only as naming evidence (classic VPN daemons are invisible to SCDynamicStore).
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
