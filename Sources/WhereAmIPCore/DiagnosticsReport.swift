import Foundation

/// The paste-ready snapshot behind the dropdown's "Copy Diagnostics" row and
/// `whereamip diagnostics` — one implementation, two frontends, same precedent as
/// `ExitInfo.splitLine` and `EgressResolver.displayLine`.
///
/// It lives in Core (not in the UI layer) precisely because the CLI must be able to
/// print it: the project's founding rule is that everything the menu bar can do,
/// the CLI can do too. Pure and fully injectable — state, version, "checked"
/// stamp, and the date formatter all come in as arguments, so every permutation is
/// unit-testable and nothing here reads the clock, the defaults, or the network.
///
/// Deliberately NOT routed through `L10n`: like `StateRenderer`, this is CLI output
/// and a clipboard payload someone pastes into a bug report — a stable artifact,
/// not copy to be retuned per release. It also shows only what the UI already
/// shows; no new measurement is taken to produce it.
public enum DiagnosticsReport {
    /// Same locale-aware dateStyle/timeStyle pairing the dropdown's "Since"/"Checked"
    /// rows use (see `MenuBuilder.timeFormatter`) — a report pasted by a German user
    /// should read the way their menu did. Tests inject their own fixed formatter.
    public static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .medium; return f
    }()

    /// Width of the label column. Continuation lines are indented by exactly this
    /// much, so a multi-resolver DNS block reads as one section rather than as
    /// several truncated ones.
    private static let labelWidth = 8

    public static func text(for state: ExitState,
                            version: String = whereamipVersion,
                            checked: Date? = nil,
                            dnsProbeEnabled: Bool = true,
                            formatter: DateFormatter = timeFormatter) -> String {
        var lines: [String] = []
        lines.append(header(version: version, checked: checked, formatter: formatter))
        // Warnings sit directly under the header, before any of the facts — same
        // reasoning as the dropdown putting its warning row above the IP row: this
        // text exists to be pasted into a bug report, and the reason for the report
        // must not be somewhere in the middle of it.
        // Each warning is labelled in full rather than continuing the one above it:
        // they are independent facts (an offline machine with hijack routes is two
        // separate findings), and a reader skimming a pasted report greps "Warning".
        lines += warnings(state).flatMap { rows(label: "Warning", [$0]) }
        lines += rows(label: "Exit", exitValues(state, formatter: formatter))
        lines += rows(label: "IPv6", [state.exit6.map { detailLine(for: $0) } ?? "not detected"])
        lines += rows(label: "Route", [routeValue(state.route)])
        if case .active(let ip, let country) = state.privateRelay {
            lines += rows(label: "Relay",
                          ["ON — Safari exits via \(ip ?? "?")\(country.map { " (\($0))" } ?? "")"])
        }
        lines += rows(label: "Since", [formatter.string(from: state.since)])
        lines += rows(label: "DNS", dnsValues(state.dns))
        lines += rows(label: "Egress", egressValues(state.dns, dnsProbeEnabled: dnsProbeEnabled))
        return lines.joined(separator: "\n")
    }

    // MARK: - header

    private static func header(version: String, checked: Date?, formatter: DateFormatter) -> String {
        guard let checked else { return "WhereAmIP \(version)" }
        return "WhereAmIP \(version) — checked \(formatter.string(from: checked))"
    }

    // MARK: - warnings

    /// Every condition the UI badges, warns, or greys out — in a settled order
    /// (connectivity first, then route, then the two leak kinds), so two reports of
    /// the same situation are diffable against each other.
    private static func warnings(_ state: ExitState) -> [String] {
        var out: [String] = []
        if state.connectivity == .offline { out.append("Offline — no internet connection") }
        if state.route.hijackRoutePresent {
            out.append("OpenVPN hijack routes (0/1 + 128/1) present — tunnel likely dead")
        }
        if state.ipv6Leak {
            out.append("IPv6 leak — v6 exits via \(state.exit6?.org ?? "your ISP") (\(state.exit6?.countryCode ?? "?"))")
        }
        switch state.dns.leak {
        case .confirmed:
            let address = state.dns.egressIP ?? "?"
            if let org = state.dns.egressOrg, !org.isEmpty {
                out.append("DNS leak — queries answered via \(org) (\(address))")
            } else {
                out.append("DNS leak — queries answered via \(address)")
            }
        case .suspected:
            out.append("DNS leak suspected — resolver exits outside the tunnel")
        case .none, .unknown:
            break
        }
        return out
    }

    // MARK: - sections

    private static func exitValues(_ state: ExitState, formatter: DateFormatter) -> [String] {
        guard let exit = state.exit else { return ["unknown"] }
        var line = detailLine(for: exit)
        // Offline: the exit is still the last one we saw, not the current one — say
        // when it was seen rather than presenting stale data as live.
        if state.connectivity == .offline {
            line += " (last seen \(formatter.string(from: exit.fetchedAt)))"
        }
        return [line]
    }

    /// "104.28.225.96 · Berlin, DE · Cloudflare, Inc.", dropping whatever is missing.
    private static func detailLine(for exit: ExitInfo) -> String {
        let place = [exit.city, exit.countryCode].compactMap { $0 }.joined(separator: ", ")
        return ([exit.ip, place.isEmpty ? nil : place, exit.org].compactMap { $0 }).joined(separator: " · ")
    }

    private static func routeValue(_ route: RouteInfo) -> String {
        guard let iface = route.defaultInterface else { return "no default route" }
        if route.isVPN { return "\(route.vpnName ?? "unknown VPN") (\(iface)) owns default route" }
        if let kind = route.linkKind { return "\(kind) (\(iface))" }
        return iface
    }

    /// Configured resolvers, deduped by address (`DNSConfigReader` emits the same
    /// address once globally and once per service) and then grouped by the interface
    /// set they were scoped to — the same two rules the dropdown's submenu applies,
    /// just packed denser because a pasted report has no width limit to respect.
    private static func dnsValues(_ dns: DNSInfo) -> [String] {
        guard !dns.resolvers.isEmpty else { return ["unknown"] }
        var groups: [(interfaces: String, addresses: [String])] = []
        var seen = Set<String>()
        for resolver in dns.resolvers where seen.insert(resolver.address).inserted {
            let interfaces = dns.resolvers.filter { $0.address == resolver.address }
                                          .compactMap(\.interface).joined(separator: ", ")
            if let index = groups.firstIndex(where: { $0.interfaces == interfaces }) {
                groups[index].addresses.append(resolver.address)
            } else {
                groups.append((interfaces, [resolver.address]))
            }
        }
        var values = groups.map { group in
            group.addresses.joined(separator: ", ")
                + (group.interfaces.isEmpty ? "" : " (\(group.interfaces))")
        }
        // Attached to the first line, exactly where the dropdown's DNS summary row
        // carries it: encryption is a property of the configuration as a whole.
        switch dns.encryption {
        case .doh: values[0] += " · DoH"
        case .dot: values[0] += " · DoT"
        case .plaintext: values[0] += " · plaintext"
        case .unknown: break
        }
        return values
    }

    private static func egressValues(_ dns: DNSInfo, dnsProbeEnabled: Bool) -> [String] {
        guard dnsProbeEnabled else { return ["DNS check disabled"] }
        var values: [String] = []
        if !dns.egressResolvers.isEmpty {
            values = dns.egressResolvers.map(reportLine)
        } else if let egressIP = dns.egressIP {
            // Enumeration found nothing and the beacon fallback answered instead.
            values = [reportLine(EgressResolver(ip: egressIP, operatorName: dns.egressOrg))]
        }
        if let provider = DNSForwarderHint.provider(configured: dns.resolvers, egress: dns.egressResolvers) {
            values.append("Router forwards to \(provider) — encryption of that hop is set on the router")
        }
        return values.isEmpty ? ["not measured"] : values
    }

    /// `EgressResolver.displayLine` with " — " swapped for the " · " this report uses
    /// between an address and its attribution — an em dash already separates the
    /// forwarder hint's clause below, and one separator per meaning keeps the block
    /// scannable.
    private static func reportLine(_ resolver: EgressResolver) -> String {
        var line = resolver.ip
        if let operatorName = resolver.operatorName, !operatorName.isEmpty { line += " · \(operatorName)" }
        if let short = resolver.shortLocation { line += " (\(short))" }
        if let transport = resolver.transport, !transport.isEmpty { line += " · \(transport)" }
        return line
    }

    // MARK: - layout

    /// One labelled row per value: the label owns the first line, every further
    /// value continues the same section indented to the label column.
    private static func rows(label: String, _ values: [String]) -> [String] {
        values.enumerated().map { index, value in
            (index == 0 ? label : "").padding(toLength: labelWidth, withPad: " ", startingAt: 0) + value
        }
    }
}
