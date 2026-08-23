import XCTest
@testable import WhereAmIPCore

/// The paste-into-a-bug-report text, which both the dropdown's "Copy Diagnostics"
/// row and `whereamip diagnostics` render from this one pure function.
///
/// Assertions here ARE literal, unlike the UI tests: this text is CLI output and
/// clipboard payload — a stable, parseable-by-eye artifact, not tunable copy — so
/// the same rule that pins `StateRenderer`'s output applies. Every test injects a
/// fixed formatter so nothing depends on the machine's locale or time zone.
final class DiagnosticsReportTests: XCTestCase {
    let checked = Date(timeIntervalSince1970: 1_700_000_500)
    let since = Date(timeIntervalSince1970: 1_700_000_000)

    /// Locale- and zone-independent, so the expected strings below are the same on
    /// every machine — the whole reason `text(for:)` takes a formatter at all.
    let fixed: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func report(_ state: ExitState, checked: Date? = nil, dnsProbeEnabled: Bool = true) -> String {
        DiagnosticsReport.text(for: state, version: "9.9.9", checked: checked,
                               dnsProbeEnabled: dnsProbeEnabled, formatter: fixed)
    }
    func lines(_ state: ExitState, checked: Date? = nil, dnsProbeEnabled: Bool = true) -> [String] {
        report(state, checked: checked, dnsProbeEnabled: dnsProbeEnabled).components(separatedBy: "\n")
    }

    /// The full picture: VPN route, dual stack, split DNS, enumerated egress.
    func fullState() -> ExitState {
        var state = ExitState(
            connectivity: .online,
            exit: ExitInfo(ip: "104.28.225.96", countryCode: "DE", city: "Berlin",
                           org: "Cloudflare, Inc.", provider: "ipwho.is", fetchedAt: since),
            exit6: ExitInfo(ip: "2a09:bac5:27cd:2a0::43:80", countryCode: "DE", city: "Berlin",
                            provider: "ipwho.is", fetchedAt: since),
            route: RouteInfo(defaultInterface: "utun17", isVPN: true, vpnName: "Cloudflare WARP"),
            since: since)
        state.dns.resolvers = [DNSResolver(address: "127.0.2.2", isIPv6: false, interface: "utun17"),
                               DNSResolver(address: "127.0.2.3", isIPv6: false, interface: "utun17"),
                               DNSResolver(address: "192.168.178.1", isIPv6: false, interface: "en0"),
                               DNSResolver(address: "fd6b:908e:1000::5abc", isIPv6: true, interface: "en0")]
        state.dns.egressResolvers = [
            EgressResolver(ip: "162.158.245.7", operatorName: "Cloudflare, Inc.",
                           location: "Berlin, State of Berlin, DE", transport: "UDP"),
            EgressResolver(ip: "2400:cb00:67:1024::a29e:f507", operatorName: "Cloudflare", transport: "UDP"),
        ]
        state.dns.egressIP = "162.158.245.7"
        state.dns.leak = .none
        return state
    }

    // MARK: - the shape

    func testFullStateRendersEveryLabelledSection() {
        XCTAssertEqual(report(fullState(), checked: checked), """
        WhereAmIP 9.9.9 — checked 2023-11-14 22:21:40
        Exit    104.28.225.96 · Berlin, DE · Cloudflare, Inc.
        IPv6    2a09:bac5:27cd:2a0::43:80 · Berlin, DE
        Route   Cloudflare WARP (utun17) owns default route
        Since   2023-11-14 22:13:20
        DNS     127.0.2.2, 127.0.2.3 (utun17)
                192.168.178.1, fd6b:908e:1000::5abc (en0)
        Egress  162.158.245.7 · Cloudflare, Inc. (Berlin, DE) · UDP
                2400:cb00:67:1024::a29e:f507 · Cloudflare · UDP
        """)
    }

    func testHeaderDropsTheCheckedStampWhenNothingHasBeenCheckedYet() {
        XCTAssertEqual(lines(fullState()).first, "WhereAmIP 9.9.9")
    }

    func testEveryContinuationLineIsIndentedToTheLabelColumn() {
        // Paste-readability is the whole point: a wrapped-looking second line that
        // starts in column 0 reads as a new section.
        for line in lines(fullState(), checked: checked).dropFirst() {
            XCTAssertTrue(line.count > 8, "suspiciously short body line: \(line)")
            XCTAssertEqual(Array(line)[7], " ", "value does not start in the same column: \(line)")
        }
    }

    // MARK: - warnings (the reason anyone pastes this at all)

    func testConfirmedIPv6LeakIsAWarningLine() {
        var state = fullState()
        state.ipv6Leak = true
        state.exit6 = ExitInfo(ip: "2003:e1:1234::1", countryCode: "DE", org: "Deutsche Telekom AG",
                               provider: "ipwho.is", fetchedAt: since)
        XCTAssertTrue(lines(state).contains("Warning IPv6 leak — v6 exits via Deutsche Telekom AG (DE)"),
                      report(state))
    }

    func testIPv6LeakWithNoMeasuredV6ExitStillWarns() {
        var state = fullState()
        state.ipv6Leak = true
        state.exit6 = nil
        XCTAssertTrue(lines(state).contains("Warning IPv6 leak — v6 exits via your ISP (?)"), report(state))
    }

    func testConfirmedDNSLeakNamesTheOperatorWhenKnown() {
        var state = fullState()
        state.dns.leak = .confirmed
        state.dns.egressIP = "8.8.8.8"
        state.dns.egressOrg = "Google LLC"
        XCTAssertTrue(lines(state).contains("Warning DNS leak — queries answered via Google LLC (8.8.8.8)"),
                      report(state))
    }

    func testConfirmedDNSLeakFallsBackToTheEgressAddressAlone() {
        var state = fullState()
        state.dns.leak = .confirmed
        state.dns.egressIP = "8.8.8.8"
        XCTAssertTrue(lines(state).contains("Warning DNS leak — queries answered via 8.8.8.8"), report(state))
    }

    func testSuspectedDNSLeakIsQuieterButStillPresent() {
        var state = fullState()
        state.dns.leak = .suspected
        XCTAssertTrue(lines(state).contains(
            "Warning DNS leak suspected — resolver exits outside the tunnel"), report(state))
    }

    // MARK: - parity with the dropdown: an alarm here only where the app alarms

    func testHijackRoutesWarnOnlyWhenTheMachineIsActuallyOffline() {
        // The dropdown shows its hijack row exclusively inside the offline branch,
        // where it EXPLAINS an already-established offline state. Standing alone it
        // would be a claim ("tunnel likely dead") contradicted by the working
        // connection described three lines below it.
        var offline = fullState()
        offline.connectivity = .offline
        offline.route.hijackRoutePresent = true
        XCTAssertTrue(lines(offline).contains(
            "Warning OpenVPN hijack routes (0/1 + 128/1) present — tunnel likely dead"), report(offline))

        var online = fullState()
        online.route.hijackRoutePresent = true
        XCTAssertFalse(report(online).contains("Warning"), report(online))
    }

    func testHijackPairIsKeptAsANeutralFactOnTheRouteLineWhileOnline() {
        // Not lost, just demoted: leftover 0/1 + 128/1 routes are a real recurring
        // failure mode and belong in a bug report — as a fact, with no health claim.
        var state = fullState()
        state.route.hijackRoutePresent = true
        XCTAssertTrue(lines(state).contains(
            "Route   Cloudflare WARP (utun17) owns default route · hijack pair (0/1 + 128/1) present"),
                      report(state))
        XCTAssertFalse(report(state).contains("likely dead"))
    }

    func testNoHijackFactWhenTheRoutesAreAbsent() {
        XCTAssertFalse(report(fullState()).contains("hijack"))
    }

    func testOfflineHijackIsAWarningAndNotAlsoARouteFact() {
        // One condition, stated once, in the register that fits the situation.
        var state = fullState()
        state.connectivity = .offline
        state.route.hijackRoutePresent = true
        let out = lines(state)
        XCTAssertTrue(out.contains { $0.hasPrefix("Warning OpenVPN hijack") }, report(state))
        XCTAssertFalse(out.contains { $0.hasPrefix("Route") && $0.contains("hijack pair") }, report(state))
    }

    func testStaleLeakVerdictsAreNeverAssertedWhileOffline() {
        // Monitor.runFullRefresh recomputes ipv6Leak and dns.leak ONLY while online
        // and otherwise carries the previous values forward (deliberate — see the
        // comment there). Reporting them offline would assert a leak last measured
        // before the connection dropped, and one the dropdown is not showing either.
        var state = fullState()
        state.connectivity = .offline
        state.ipv6Leak = true
        state.exit6 = ExitInfo(ip: "2003:e1:1234::1", countryCode: "DE", org: "Deutsche Telekom AG",
                               provider: "ipwho.is", fetchedAt: since)
        state.dns.leak = .confirmed
        state.dns.egressIP = "8.8.8.8"
        let text = report(state)
        XCTAssertFalse(text.contains("IPv6 leak"), text)
        XCTAssertFalse(text.contains("DNS leak"), text)
        XCTAssertTrue(lines(state).contains("Warning Offline — no internet connection"), text)
    }

    func testCheckingCountsAsOnlineForWarningVisibility() {
        // The dropdown branches on offline only, so a first-ever refresh still in
        // flight renders the online layout — the report must agree.
        var state = fullState()
        state.connectivity = .checking
        state.ipv6Leak = true
        XCTAssertTrue(lines(state).contains { $0.hasPrefix("Warning IPv6 leak") }, report(state))
    }

    func testOfflineIsAWarningLineAndTheExitIsMarkedAsLastSeen() {
        var state = fullState()
        state.connectivity = .offline
        let out = lines(state)
        XCTAssertTrue(out.contains("Warning Offline — no internet connection"), report(state))
        XCTAssertTrue(out.contains(
            "Exit    104.28.225.96 · Berlin, DE · Cloudflare, Inc. (last seen 2023-11-14 22:13:20)"),
                      report(state))
    }

    func testOfflineWarningsComeDirectlyAfterTheHeaderInASettledOrder() {
        var state = fullState()
        state.connectivity = .offline
        state.route.hijackRoutePresent = true
        // Both leak fields are stale here by construction (see the test above) and
        // must not join the list, however set they are.
        state.ipv6Leak = true
        state.dns.leak = .confirmed
        let out = lines(state, checked: checked)
        XCTAssertEqual(out.filter { $0.hasPrefix("Warning") },
                       ["Warning Offline — no internet connection",
                        "Warning OpenVPN hijack routes (0/1 + 128/1) present — tunnel likely dead"],
                       report(state))
        XCTAssertEqual(Array(out[1...2]).map { String($0.prefix(15)) },
                       ["Warning Offline", "Warning OpenVPN"], report(state))
    }

    func testOnlineWarningsComeDirectlyAfterTheHeaderInASettledOrder() {
        var state = fullState()
        state.ipv6Leak = true
        state.dns.leak = .confirmed
        state.dns.egressIP = "8.8.8.8"
        let out = lines(state, checked: checked)
        XCTAssertEqual(Array(out[1...2]).map { String($0.prefix(15)) },
                       ["Warning IPv6 le", "Warning DNS lea"], report(state))
    }

    func testAHealthyStateCarriesNoWarningLinesAtAll() {
        XCTAssertFalse(report(fullState(), checked: checked).contains("Warning"))
    }

    // MARK: - degraded states, none of which may crash or lie

    func testEmptyStateStillRendersAReport() {
        let out = lines(ExitState(since: since))
        XCTAssertEqual(out.first, "WhereAmIP 9.9.9")
        XCTAssertTrue(out.contains("Exit    unknown"), out.joined(separator: "\n"))
        XCTAssertTrue(out.contains("Route   no default route"), out.joined(separator: "\n"))
        XCTAssertTrue(out.contains("DNS     unknown"), out.joined(separator: "\n"))
        XCTAssertTrue(out.contains("Since   2023-11-14 22:13:20"), out.joined(separator: "\n"))
    }

    func testMissingCityAndOrgJustShrinkTheExitLine() {
        var state = fullState()
        state.exit = ExitInfo(ip: "203.0.113.7", countryCode: "DE", provider: "ipwho.is", fetchedAt: since)
        XCTAssertTrue(lines(state).contains("Exit    203.0.113.7 · DE"), report(state))
    }

    func testExitWithNoGeoAtAllIsJustTheAddress() {
        var state = fullState()
        state.exit = ExitInfo(ip: "203.0.113.7", provider: "ipwho.is", fetchedAt: since)
        XCTAssertTrue(lines(state).contains("Exit    203.0.113.7"), report(state))
    }

    func testNoIPv6ExitSaysSoRatherThanGoingSilent() {
        var state = fullState()
        state.exit6 = nil
        XCTAssertTrue(lines(state).contains("IPv6    not detected"), report(state))
    }

    func testPlainLinkRouteShowsItsKind() {
        var state = fullState()
        state.route = RouteInfo(defaultInterface: "en0", isVPN: false, linkKind: "Wi-Fi", linkName: "Wi-Fi")
        XCTAssertTrue(lines(state).contains("Route   Wi-Fi (en0)"), report(state))
    }

    func testRouteWithoutAKnownKindIsJustTheInterface() {
        var state = fullState()
        state.route = RouteInfo(defaultInterface: "en0", isVPN: false)
        XCTAssertTrue(lines(state).contains("Route   en0"), report(state))
    }

    func testUnnamedVPNStillReadsAsAVPNRoute() {
        var state = fullState()
        state.route = RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: nil)
        XCTAssertTrue(lines(state).contains("Route   unknown VPN (utun4) owns default route"), report(state))
    }

    // MARK: - DNS block

    func testConfiguredResolversAreDedupedAndGroupedByInterface() {
        var state = fullState()
        // DNSConfigReader emits the same address globally AND per service — one row.
        state.dns.resolvers = [DNSResolver(address: "192.168.178.1", isIPv6: false),
                               DNSResolver(address: "192.168.178.1", isIPv6: false, interface: "en0"),
                               DNSResolver(address: "10.2.0.1", isIPv6: false, interface: "utun4")]
        let out = lines(state)
        XCTAssertTrue(out.contains("DNS     192.168.178.1 (en0)"), report(state))
        XCTAssertTrue(out.contains("        10.2.0.1 (utun4)"), report(state))
        XCTAssertEqual(out.filter { $0.contains("192.168.178.1") }.count, 1, report(state))
    }

    func testGloballyScopedResolversCarryNoInterfaceSuffix() {
        var state = fullState()
        state.dns.resolvers = [DNSResolver(address: "9.9.9.9", isIPv6: false)]
        XCTAssertTrue(lines(state).contains("DNS     9.9.9.9"), report(state))
    }

    func testEncryptionIsNamedOnTheDNSLineExactlyAsTheDropdownDoes() {
        var state = fullState()
        state.dns.encryption = .doh
        XCTAssertTrue(lines(state).contains("DNS     127.0.2.2, 127.0.2.3 (utun17) · DoH"), report(state))
    }

    func testDisabledProbeSaysSoInsteadOfImplyingNothingAnswered() {
        var state = fullState()
        let out = lines(state, dnsProbeEnabled: false)
        XCTAssertTrue(out.contains("Egress  DNS check disabled"), report(state, dnsProbeEnabled: false))
        XCTAssertFalse(out.contains { $0.contains("162.158.245.7") },
                       "an opted-out user is never shown a stale measurement")
        state.dns.encryption = .doh   // the configured half is local fact and stays visible
        XCTAssertTrue(lines(state, dnsProbeEnabled: false).contains { $0.hasPrefix("DNS     127.0.2.2") })
    }

    func testNothingMeasuredYetIsStatedRatherThanOmitted() {
        var state = fullState()
        state.dns.egressResolvers = []
        state.dns.egressIP = nil
        XCTAssertTrue(lines(state).contains("Egress  not measured"), report(state))
    }

    func testBeaconFallbackEgressIsShownWhenEnumerationFoundNothing() {
        var state = fullState()
        state.dns.egressResolvers = []
        state.dns.egressIP = "203.0.113.7"
        state.dns.egressOrg = "Cloudflare, Inc."
        XCTAssertTrue(lines(state).contains("Egress  203.0.113.7 · Cloudflare, Inc."), report(state))
    }

    func testRouterForwardingAttributionIsCarriedOverFromTheSubmenu() {
        var state = fullState()
        state.dns.resolvers = [DNSResolver(address: "192.168.178.1", isIPv6: false)]
        state.dns.egressResolvers = [EgressResolver(ip: "9.9.9.9", operatorName: "Quad9")]
        XCTAssertTrue(lines(state).contains(
            "        Router forwards to Quad9 — encryption of that hop is set on the router"), report(state))
    }

    // MARK: - private relay

    func testActivePrivateRelayIsReported() {
        var state = fullState()
        state.privateRelay = .active(egressIP: "172.224.224.5", egressCountry: "DE")
        XCTAssertTrue(lines(state).contains("Relay   ON — Safari exits via 172.224.224.5 (DE)"), report(state))
    }

    func testInactivePrivateRelayAddsNoLine() {
        var state = fullState()
        state.privateRelay = .inactive
        XCTAssertFalse(report(state).contains("Relay"))
    }

    // MARK: - contract

    func testReportNeverEndsWithABlankLineOrLeavesADanglingLabel() {
        for state in [fullState(), ExitState(), ExitState(connectivity: .offline)] {
            let text = DiagnosticsReport.text(for: state, version: "9.9.9", formatter: fixed)
            XCTAssertFalse(text.hasSuffix("\n"))
            for line in text.components(separatedBy: "\n") {
                XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty, "blank line in: \(text)")
                XCTAssertEqual(line, String(line.reversed().drop { $0 == " " }.reversed()),
                               "trailing whitespace in: \(line)")
            }
        }
    }

    func testDefaultVersionIsTheRunningBuild() {
        XCTAssertTrue(DiagnosticsReport.text(for: ExitState()).hasPrefix("WhereAmIP \(whereamipVersion)"))
    }
}
