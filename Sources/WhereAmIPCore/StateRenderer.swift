import Foundation

public enum StateRenderer {
    public static func json(_ state: ExitState) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return String(data: try! enc.encode(state), encoding: .utf8)!
    }
    public static func human(_ state: ExitState) -> String {
        var lines: [String] = []
        switch state.connectivity {
        case .offline: lines.append("✕ offline")
        case .checking: lines.append("… checking")
        case .online:
            let flag = state.exit?.countryCode.flatMap { Flags.emoji(countryCode: $0) } ?? "?"
            let place = [state.exit?.city, state.exit?.countryCode].compactMap { $0 }.joined(separator: ", ")
            lines.append("\(flag) \(state.exit?.ip ?? "unknown IP")  \(place)")
            if let org = state.exit?.org { lines.append("   \(org)") }
        }
        if let iface = state.route.defaultInterface {
            var r = "route: \(iface)"
            if let vpn = state.route.vpnName { r += " (\(vpn))" }
            lines.append(r)
        }
        if state.route.hijackRoutePresent { lines.append("⚠ hijack routes (0/1 + 128/1) present") }
        if case .active(let ip, let country) = state.privateRelay {
            lines.append("Private Relay: ON — relay egress \(ip ?? "?")\(country.map { " (\($0))" } ?? "")")
        }
        // Confirmed leak line supersedes the plain split pair below; a leak already implies
        // the two stacks differ, so showing both would be redundant.
        if state.ipv6Leak {
            let org = state.exit6?.org ?? "your ISP"
            let cc = state.exit6?.countryCode ?? "?"
            lines.append("⚠️ IPv6 leak: v6 exits via \(org) (\(cc))")
        } else if let exit = state.exit, let exit6 = state.exit6, exit6.countryCode != exit.countryCode {
            lines.append(exit.splitLine(label: "IPv4"))
            lines.append(exit6.splitLine(label: "IPv6"))
        }
        return lines.joined(separator: "\n")
    }
}
