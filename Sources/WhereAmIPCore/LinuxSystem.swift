#if os(Linux)
import Foundation
import Glibc

/// The two ways the Linux port asks the system anything: reading a pseudo-file
/// (procfs, sysfs, resolv.conf) and running a short-lived helper (`resolvectl`,
/// `nmcli`). Both answer nil rather than throwing — every caller treats "could not
/// find out" as an ordinary outcome that fails downward to a generic answer, the same
/// rule the macOS readers follow when SCDynamicStore or libproc come back empty.
enum LinuxSystem {
    /// Whole contents of a small text file. Deliberately a raw read loop, not
    /// `String(contentsOfFile:)`: procfs and sysfs report a size of 0, and a reader that
    /// trusts `stat` hands back an empty string for a file that has content.
    static func read(_ path: String, limit: Int = 1 << 20) -> String? {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var out = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while out.count < limit {
            let n = chunk.withUnsafeMutableBytes { Glibc.read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { break }
            out.append(contentsOf: chunk.prefix(n))
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func exists(_ path: String) -> Bool {
        access(path, F_OK) == 0
    }

    /// The final path component a symlink points at (`.../drivers/ipheth` → `ipheth`).
    static func symlinkTargetName(_ path: String) -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { return nil }
        return target.split(separator: "/").last.map(String.init)
    }

    /// First executable named `name` on PATH, plus the standard system locations — a
    /// desktop session's PATH is not always the login shell's.
    static func which(_ name: String) -> String? {
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in pathDirs + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"] where !dir.isEmpty {
            let candidate = "\(dir)/\(name)"
            if access(candidate, X_OK) == 0 { return candidate }
        }
        return nil
    }

    /// Runs a helper and returns its standard output, or nil when it is missing, exits
    /// non-zero, or overruns `timeout`. The timeout is a hard stop rather than a hint:
    /// these run on every route snapshot, and a wedged NetworkManager must not be able to
    /// stall a refresh.
    static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 2) -> String? {
        guard let executable = which(tool) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Parse-stable output regardless of the user's locale: both resolvectl and nmcli
        // translate their labels.
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        process.environment = environment
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        // Drained on its own thread while the child runs: a child that fills the pipe
        // buffer would otherwise block forever, and a read on this thread could never
        // reach the timeout check below.
        final class Output: @unchecked Sendable { var data = Data() }
        let output = Output()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            output.data = stdout.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = drained.wait(timeout: .now() + 1)
            return nil
        }
        // Bounded too: a grandchild that inherited the pipe can hold it open after the
        // tool itself has exited.
        guard drained.wait(timeout: .now() + timeout) == .success,
              process.terminationStatus == 0 else { return nil }
        return String(decoding: output.data, as: UTF8.self)
    }
}
#endif
