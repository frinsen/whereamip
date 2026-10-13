#if os(Linux)
import Foundation

/// The Linux side of `InterfaceKind`: the same short labels the macOS version derives from
/// SCNetworkInterface, derived here from what the kernel exposes under
/// `/sys/class/net/<iface>`. Still no vendor tables — the one driver named below is the
/// kernel's own iPhone tethering driver, which is the Linux spelling of the "iPhone USB"
/// service macOS reports.
extension InterfaceKind {
    /// IMPURE: interface name -> (kind, displayName) via sysfs. nil when the interface does
    /// not exist (anymore). Linux has no system-wide localized display name for a device, so
    /// the kind doubles as the display name, exactly as macOS falls back when SC has none.
    public static func lookup(bsdName: String) -> (kind: String, displayName: String)? {
        let base = "/sys/class/net/\(bsdName)"
        guard !bsdName.isEmpty, !bsdName.contains("/"), LinuxSystem.exists(base) else { return nil }
        let uevent = LinuxSystem.read("\(base)/uevent") ?? ""
        let kind = linuxKindLabel(
            devType: ueventValue("DEVTYPE", in: uevent),
            arphrdType: LinuxSystem.read("\(base)/type").flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) },
            driver: LinuxSystem.symlinkTargetName("\(base)/device/driver"),
            isWireless: LinuxSystem.exists("\(base)/wireless") || LinuxSystem.exists("\(base)/phy80211"))
        return (kind, kind)
    }

    /// PURE, tested: sysfs facts -> short kind label. Wireless wins over everything (a Wi-Fi
    /// card is ARPHRD_ETHER too), then the device type the driver declares, then the link type.
    static func linuxKindLabel(devType: String?, arphrdType: Int?, driver: String?, isWireless: Bool) -> String {
        if isWireless || devType == "wlan" { return "Wi-Fi" }
        if driver == "ipheth" { return "iPhone USB" }
        switch devType {
        case "bridge": return "Bridge"
        case "wwan": return "WWAN"
        case "bond": return "Bond"
        case "vlan": return "VLAN"
        default: break
        }
        switch arphrdType {
        case 1: return "Ethernet"          // ARPHRD_ETHER
        case 512: return "PPP"             // ARPHRD_PPP
        default: return devType.map { $0.isEmpty ? "Unknown" : $0 } ?? "Unknown"
        }
    }

    /// `KEY=value` lines, as found in a sysfs `uevent` file.
    static func ueventValue(_ key: String, in uevent: String) -> String? {
        for line in uevent.split(separator: "\n") where line.hasPrefix("\(key)=") {
            return String(line.dropFirst(key.count + 1))
        }
        return nil
    }
}
#endif
