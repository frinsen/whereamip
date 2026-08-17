import Foundation

public enum StateRenderer {
    // `appVersion` is injected at render time rather than modeled on ExitState
    // itself: ExitState represents network/exit state, not the running
    // binary's identity, so it stays out of the Codable struct. Passing nil
    // (the default) reproduces the exact prior output — additive-only change.
    public static func json(_ state: ExitState, appVersion: String? = nil) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try! enc.encode(state)
        guard let appVersion else {
            return String(data: data, encoding: .utf8)!
        }
        var obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj["appVersion"] = appVersion
        let outData = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(data: outData, encoding: .utf8)!
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
            var r: String
            if let kind = state.route.linkKind {
                r = "route: \(kind) (\(iface))"
            } else {
                r = "route: \(iface)"
            }
            if let vpn = state.route.vpnName { r += " (\(vpn))" }
            lines.append(r)
        }
        if let first = state.dns.resolvers.first {
            var d = "dns: \(first.address)"
            if let iface = first.interface { d += " (\(iface))" }
            let uniqueCount = state.dns.uniqueAddressCount
            if uniqueCount > 1 { d += " +\(uniqueCount - 1)" }
            if state.dns.encryption == .doh { d += " · DoH" }
            if state.dns.encryption == .dot { d += " · DoT" }
            lines.append(d)
        }
        // Indented continuation of the dns line: where those queries actually came out. Kept to
        // IPs plus operator — the dropdown's submenu carries location/transport, a status line
        // that wraps in a terminal stops being glanceable. `--json` has the full records.
        if !state.dns.egressResolvers.isEmpty {
            let egress = state.dns.egressResolvers.map { r in
                r.operatorName.map { "\(r.ip) (\($0))" } ?? r.ip
            }
            lines.append("   egress: \(egress.joined(separator: ", "))")
        }
        // Leak surfacing matches the dropdown's warning-row spirit (MenuBuilder): visible even
        // when the resolvers list itself is empty, so it never depends on the line above.
        if state.dns.leak == .confirmed {
            if let org = state.dns.egressOrg, !org.isEmpty {
                lines.append("⚠️ DNS leak: queries answered via \(org) (\(state.dns.egressIP ?? "?"))")
            } else {
                lines.append("⚠️ DNS leak: queries answered via \(state.dns.egressIP ?? "?")")
            }
        } else if state.dns.leak == .suspected {
            lines.append("DNS leak suspected — resolver exits outside the tunnel")
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
        } else if let exit = state.exit, let exit6 = state.exit6 {
            // The leak line above supersedes this pair when a leak is confirmed. Otherwise,
            // show the split pair whenever both stacks were measured (v6 is a first-class fact).
            lines.append(exit.splitLine(label: "IPv4"))
            lines.append(exit6.splitLine(label: "IPv6"))
        }
        // Footer, not headline: exit info stays first for glanceability.
        lines.append("whereamip v\(whereamipVersion)")
        return lines.joined(separator: "\n")
    }
}
