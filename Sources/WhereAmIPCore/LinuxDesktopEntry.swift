#if os(Linux)
import Foundation

/// The Linux equivalents of two macOS integrations, as freedesktop.org desktop entries:
///
///   - `.launcher` — the app's entry in the desktop's applications menu, the Linux
///     counterpart of the `/Applications/WhereAmIP.app` symlink (`ApplicationsLink`), and
///     what the "applications" setting and its menu toggle manage on Linux.
///   - `.autostart` — Launch at Login (`SMAppService` on macOS).
///
/// The safety rule is ApplicationsLink's: only ever create or remove a file WhereAmIP
/// itself wrote. Ours carry `managedMarker`; an entry without it (a user's own, a distro
/// package's) is reported as present and never overwritten or deleted.
public enum LinuxDesktopEntry {
    public enum Kind: Sendable { case launcher, autostart }

    public enum EntryError: Error, Equatable, CustomStringConvertible {
        case notManaged(String)
        case cannotDetermineExecutable

        public var description: String {
            switch self {
            case .notManaged(let path):
                return "\(path) exists and was not created by WhereAmIP — refusing to touch it. "
                    + "Remove it yourself first if you want WhereAmIP to manage it."
            case .cannotDetermineExecutable:
                return "Could not find the whereamip-indicator executable next to this program."
            }
        }
    }

    /// Desktop-file ID — also the notification hint and the installed icon's name, so the
    /// desktop can tie all three together.
    public static let id = "io.github.frinsen.whereamip"
    public static let managedMarker = "X-WhereAmIP-Managed=true"
    /// The tray app's executable name, installed next to the `whereamip` CLI.
    public static let indicatorExecutableName = "whereamip-indicator"

    /// `$XDG_DATA_HOME/applications/<id>.desktop` or `$XDG_CONFIG_HOME/autostart/<id>.desktop`,
    /// with the spec's defaults (`~/.local/share`, `~/.config`) when the variables are unset.
    /// Home is `$HOME` first, as GLib and the desktop read it — Foundation's NSHomeDirectory()
    /// on Linux goes straight to the password database and ignores it.
    public static func path(_ kind: Kind,
                            environment: [String: String] = ProcessInfo.processInfo.environment,
                            home: String? = nil) -> String {
        let home = home ?? environment["HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? NSHomeDirectory()
        func base(_ variable: String, _ fallback: String) -> String {
            if let value = environment[variable], value.hasPrefix("/") { return value }
            return "\(home)/\(fallback)"
        }
        switch kind {
        case .launcher: return "\(base("XDG_DATA_HOME", ".local/share"))/applications/\(id).desktop"
        case .autostart: return "\(base("XDG_CONFIG_HOME", ".config"))/autostart/\(id).desktop"
        }
    }

    /// Present in any form — a file or a symlink, ours or not. What the toggles show.
    public static func isInstalled(at path: String) -> Bool {
        let fm = FileManager.default
        return (try? fm.destinationOfSymbolicLink(atPath: path)) != nil || fm.fileExists(atPath: path)
    }

    public static func isManaged(at path: String) -> Bool {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return text.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == managedMarker }
    }

    /// Writes (on) or removes (off) the entry. Writing over our own entry is how a moved
    /// install re-points it — the same self-healing `ln -sfn` semantics as ApplicationsLink.
    public static func setInstalled(_ on: Bool, kind: Kind, executable: String,
                                    at path: String? = nil) throws {
        let path = path ?? self.path(kind)
        let fm = FileManager.default
        let present = isInstalled(at: path)
        if present, !isManaged(at: path) { throw EntryError.notManaged(path) }
        if on {
            let directory = (path as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
            if present { try fm.removeItem(atPath: path) }
            try contents(kind: kind, executable: executable).write(toFile: path, atomically: true, encoding: .utf8)
        } else if present {
            try fm.removeItem(atPath: path)
        }
    }

    /// PURE, tested.
    public static func contents(kind: Kind, executable: String) -> String {
        var lines = [
            "[Desktop Entry]",
            "Type=Application",
            "Name=WhereAmIP",
            "Comment=Country flag of your internet exit, VPN route and DNS leak checks in the panel",
            "Exec=\(execValue(executable))",
            "Icon=\(id)",
            "Terminal=false",
            "Categories=Network;Monitor;",
            "Keywords=IP;VPN;DNS;leak;flag;exit;",
            "StartupNotify=false",
            "StartupWMClass=\(indicatorExecutableName)",
        ]
        if kind == .autostart { lines.append("X-GNOME-Autostart-enabled=true") }
        lines.append(managedMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    /// PURE, tested. An `Exec=` value for a path: bare when it needs no quoting, otherwise
    /// double-quoted with the spec's escapes — `"` `` ` `` `$` `\` inside the quotes, the
    /// string-level doubling of each backslash on top, and `%` as `%%` (a field code).
    static func execValue(_ path: String) -> String {
        let plain = path.allSatisfy { $0.isLetter || $0.isNumber || "/._-+".contains($0) }
        if plain { return path }
        var quoted = ""
        for ch in path {
            switch ch {
            case "\"", "`", "$": quoted += "\\\\\(ch)"
            case "\\": quoted += "\\\\\\\\"
            case "%": quoted += "%%"
            default: quoted.append(ch)
            }
        }
        return "\"\(quoted)\""
    }

    /// The indicator executable sitting next to `executablePath` (symlinks resolved, so a
    /// `~/.local/bin/whereamip` link finds the real install directory), or nil.
    public static func indicatorExecutable(nextTo executablePath: String) -> String? {
        guard !executablePath.isEmpty else { return nil }
        let resolved = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        let candidate = resolved.deletingLastPathComponent().appendingPathComponent(indicatorExecutableName).path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }
}
#endif
