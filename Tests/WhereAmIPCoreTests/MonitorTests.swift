import XCTest
@testable import WhereAmIPCore

actor Counter {
    var geoCalls = 0; var probeCalls = 0; var lookupCalls = 0; var httpIPCalls = 0
    var stack4Calls = 0; var stack6Calls = 0
    func bumpGeo() { geoCalls += 1 }
    @discardableResult func bumpProbe() -> Int { probeCalls += 1; return probeCalls }
    func bumpLookup() { lookupCalls += 1 }; func bumpHTTP() { httpIPCalls += 1 }
    func bumpStack4() { stack4Calls += 1 }; func bumpStack6() { stack6Calls += 1 }
}

struct MockGeo: GeoFetching {
    let counter: Counter
    let info: ExitInfo?
    func fetch() async -> ExitInfo? { await counter.bumpGeo(); return info }
    func lookup(ip: String) async -> ExitInfo? {
        await counter.bumpLookup()
        return ExitInfo(ip: ip, countryCode: "DE", provider: "mock", fetchedAt: Date())
    }
}
struct MockProbe: ProbeRunning {
    let counter: Counter
    let results: @Sendable () -> Bool
    func check() async -> Bool { await counter.bumpProbe(); return results() }
}
struct MockRoute: RouteSnapshotting {
    var info = RouteInfo(defaultInterface: "en0")
    // Fixed return for the scoped-route source-address-match fallback — deterministic and
    // never touches the real network stack, unlike the protocol's default implementation
    // (which defers to RouteInspector.interfaceHolding, a real getifaddrs walk).
    var holding: String? = nil
    func snapshot() -> RouteInfo { info }
    func interfaceHolding(ipv6: String) -> String? { holding }
}
/// A `RouteSnapshotting` whose snapshot can be changed mid-test (e.g. to simulate a VPN
/// coming up between two calls) — plain `MockRoute` is an immutable value type, so tests that
/// need to flip the route after a baseline refresh need this instead.
final class MutableMockRoute: RouteSnapshotting, @unchecked Sendable {
    private let lock = NSLock()
    private var info: RouteInfo
    init(_ info: RouteInfo) { self.info = info }
    func snapshot() -> RouteInfo { lock.lock(); defer { lock.unlock() }; return info }
    func set(_ newInfo: RouteInfo) { lock.lock(); info = newInfo; lock.unlock() }
}
struct MockHTTPIP: HTTPIPFetching {
    let counter: Counter
    var ip: String?
    func fetch() async -> String? { await counter.bumpHTTP(); return ip }
}
/// Defaults to (nil, nil) so any existing test that doesn't care about the stack-pinned
/// measurement behaves exactly as before this feature: `ip4` nil means `runFullRefresh`
/// falls back to `geo.fetch()`, same call count as pre-IPv6-leak-detector code.
struct MockStackIP: StackIPFetching {
    let counter: Counter
    var ip4: String?
    var ip6: String?
    func fetch4() async -> String? { await counter.bumpStack4(); return ip4 }
    func fetch6() async -> String? { await counter.bumpStack6(); return ip6 }
}
/// Distinguishes exit4 vs exit6 lookups by IP, unlike `MockGeo.lookup` which always returns a
/// fixed country — needed to simulate genuinely differing per-stack geo results.
struct StackTestGeo: GeoFetching {
    let counter: Counter
    var chainFallback: ExitInfo?
    var lookups: [String: ExitInfo]
    func fetch() async -> ExitInfo? { await counter.bumpGeo(); return chainFallback }
    func lookup(ip: String) async -> ExitInfo? {
        await counter.bumpLookup()
        return lookups[ip]
    }
}
/// Mutable variant of `MockStackIP` — lets a test flip what fetch4()/fetch6() return between
/// two `fullRefresh()` calls (e.g. a baseline that succeeds, then a tick where the v4-pinned
/// fetch fails), which a plain immutable struct mock can't do.
final class MutableStackIP: StackIPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var ip4: String?
    private var ip6: String?
    init(ip4: String?, ip6: String?) { self.ip4 = ip4; self.ip6 = ip6 }
    func set(ip4: String?, ip6: String?) { lock.lock(); self.ip4 = ip4; self.ip6 = ip6; lock.unlock() }
    // Locking happens in a plain synchronous helper (not directly in the async fetch4/fetch6
    // bodies) so NSLock's lock/unlock — unavailable from async contexts — stay outside any
    // suspension point.
    private func snapshot() -> (ip4: String?, ip6: String?) {
        lock.lock(); defer { lock.unlock() }; return (ip4, ip6)
    }
    func fetch4() async -> String? { snapshot().ip4 }
    func fetch6() async -> String? { snapshot().ip6 }
}
/// Mutable variant of `StackTestGeo` — same rationale as `MutableStackIP`, needed so a test can
/// make both the v4-pinned lookup AND the chain fallback fail on a later refresh while still
/// resolving exit6.
final class MutableStackTestGeo: GeoFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var chainFallback: ExitInfo?
    private var lookups: [String: ExitInfo]
    init(chainFallback: ExitInfo?, lookups: [String: ExitInfo]) {
        self.chainFallback = chainFallback; self.lookups = lookups
    }
    func set(chainFallback: ExitInfo?, lookups: [String: ExitInfo]) {
        lock.lock(); self.chainFallback = chainFallback; self.lookups = lookups; lock.unlock()
    }
    // Same rationale as MutableStackIP.snapshot(): keep NSLock's lock/unlock inside a
    // synchronous helper, never directly in the async fetch()/lookup(ip:) bodies.
    private func snapshotFallback() -> ExitInfo? { lock.lock(); defer { lock.unlock() }; return chainFallback }
    private func snapshotLookup(_ ip: String) -> ExitInfo? { lock.lock(); defer { lock.unlock() }; return lookups[ip] }
    func fetch() async -> ExitInfo? { snapshotFallback() }
    func lookup(ip: String) async -> ExitInfo? { snapshotLookup(ip) }
}

/// Configurable stand-in for `LiveDNSConfigReader` — tests hand it a fixed resolver list and/or
/// encryption verdict without touching the real SCDynamicStore.
final class MockDNSConfig: DNSConfigReading, @unchecked Sendable {
    var resolvers: [DNSResolver]
    var encryption: DNSEncryption
    init(resolvers: [DNSResolver], encryption: DNSEncryption = .unknown) {
        self.resolvers = resolvers; self.encryption = encryption
    }
    func snapshot() -> (resolvers: [DNSResolver], encryption: DNSEncryption) { (resolvers, encryption) }
}

/// Stand-in for `DNSEgressProbe` — hands back a fixed egress tuple (or nil, simulating a failed
/// probe) without touching real DNS/dnssd, and counts invocations so tests can assert the probe
/// was (or was not) actually called.
final class MockDNSProbe: DNSEgressProbing, @unchecked Sendable {
    var result: (ip: String, isIPv6: Bool)?
    var callCount = 0
    init(result: (ip: String, isIPv6: Bool)?) { self.result = result }
    func fetch() async -> (ip: String, isIPv6: Bool)? { callCount += 1; return result }
}

final class MonitorTests: XCTestCase {
    func makeMonitor(counter: Counter, probeOK: Bool = true, httpIP: String? = nil,
                     ip4: String? = nil, ip6: String? = nil,
                     dnsConfig: any DNSConfigReading = MockDNSConfig(resolvers: []),
                     dnsProbe: any DNSEgressProbing = MockDNSProbe(result: nil),
                     dnsProbeEnabled: @escaping @Sendable () -> Bool = { true },
                     onEvents: @escaping @Sendable ([Event]) -> Void = { _ in }) -> Monitor {
        let info = ExitInfo(ip: "1.2.3.4", countryCode: "DE", city: "Frankfurt", org: "Vodafone",
                            provider: "mock", fetchedAt: Date())
        return Monitor(geo: MockGeo(counter: counter, info: info),
                       probe: MockProbe(counter: counter, results: { probeOK }),
                       route: MockRoute(),
                       httpIP: MockHTTPIP(counter: counter, ip: httpIP),
                       stackIP: MockStackIP(counter: counter, ip4: ip4, ip6: ip6),
                       dnsConfig: dnsConfig,
                       dnsProbe: dnsProbe,
                       dnsProbeEnabled: dnsProbeEnabled,
                       relayRanges: RelayRanges(csv: "172.224.224.0/27,DE,,,"),
                       debounceSeconds: 0.05,
                       onChange: { _ in }, onEvents: onEvents)
    }
    func testFullRefreshPopulatesState() async {
        let c = Counter()
        let m = makeMonitor(counter: c)
        await m.fullRefresh()
        let s = await m.currentState()
        XCTAssertEqual(s.connectivity, .online)
        XCTAssertEqual(s.exit?.countryCode, "DE")
        let geo = await c.geoCalls
        XCTAssertEqual(geo, 1)
    }
    func testProbeTickNeverCallsGeo() async {
        let c = Counter()
        let m = makeMonitor(counter: c)
        await m.fullRefresh()
        await m.probeTick()
        await m.probeTick()
        let geo = await c.geoCalls
        XCTAssertEqual(geo, 1)   // only the initial fullRefresh
        let probes = await c.probeCalls
        XCTAssertEqual(probes, 3)
    }
    func testProbeTickUpdatesDNSResolvers() async {
        let c = Counter()
        let dns = MockDNSConfig(resolvers: [DNSResolver(address: "192.168.1.1", isIPv6: false)])
        let m = makeMonitor(counter: c, dnsConfig: dns)
        await m.probeTick()
        let state = await m.currentState()
        XCTAssertEqual(state.dns.resolvers.map(\.address), ["192.168.1.1"])
    }
    func testFullRefreshUpdatesDNSEncryption() async {
        let c = Counter()
        let dns = MockDNSConfig(resolvers: [], encryption: .doh)
        let m = makeMonitor(counter: c, dnsConfig: dns)
        await m.fullRefresh()
        let state = await m.currentState()
        XCTAssertEqual(state.dns.encryption, .doh)
    }
    func testPathChangedDebounces() async throws {
        let c = Counter()
        let m = makeMonitor(counter: c)
        await m.pathChanged(); await m.pathChanged(); await m.pathChanged()
        try await Task.sleep(nanoseconds: 300_000_000)  // > debounce
        let geo = await c.geoCalls
        XCTAssertEqual(geo, 1)   // three rapid calls → one refresh
    }
    func testRelayActiveFillsEgressCountry() async {
        let c = Counter()
        let m = makeMonitor(counter: c, httpIP: "172.224.224.5")
        await m.fullRefresh()
        let s = await m.currentState()
        XCTAssertEqual(s.privateRelay, .active(egressIP: "172.224.224.5", egressCountry: "DE"))
    }
    func testEventsEmitted() async {
        let c = Counter()
        let box = EventBox()
        let m = makeMonitor(counter: c, onEvents: { box.append($0) })
        await m.fullRefresh()
        // checking→online is silent per reducer; no events expected on first refresh
        XCTAssertEqual(box.all().count, 0)
    }
    func testConcurrentFullRefreshSingleFlight() async {
        let c = Counter()
        let m = makeMonitor(counter: c)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { await m.fullRefresh() }
            }
        }
        // 5 concurrent callers must coalesce onto one in-flight refresh, not each
        // snapshot `state` and race their own `apply(new)` against each other.
        let geo = await c.geoCalls
        XCTAssertEqual(geo, 1)
        let s = await m.currentState()
        XCTAssertEqual(s.connectivity, .online)
        XCTAssertEqual(s.exit?.countryCode, "DE")
    }
    func testProbeTickDoesNotClobberConcurrentFullRefresh() async {
        let c = Counter()
        let started = Gate()   // signaled by the probe right before it blocks
        let release = Gate()   // the test opens this to let the blocked probe proceed
        let deInfo = ExitInfo(ip: "1.2.3.4", countryCode: "DE", city: "Frankfurt", org: "Vodafone",
                              provider: "mock", fetchedAt: Date())
        let frInfo = ExitInfo(ip: "5.6.7.8", countryCode: "FR", city: "Paris", org: "Orange",
                              provider: "mock", fetchedAt: Date())
        let box = EventBox()
        let m = Monitor(geo: SequencedGeo(counter: c, index: CallIndex(), responses: [deInfo, frInfo]),
                        probe: SlowSecondProbe(counter: c, started: started, release: release),
                        route: MockRoute(),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: nil, ip6: nil),
                        relayRanges: RelayRanges(csv: "172.224.224.0/27,DE,,,"),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { box.append($0) })

        // Baseline: online with country DE (consumes probe call #1 and geo response #0,
        // neither of which blocks).
        await m.fullRefresh()
        let baseline = await m.currentState()
        XCTAssertEqual(baseline.exit?.countryCode, "DE")

        // probeTick starts, registers itself as the in-flight work, snapshots state (DE),
        // then blocks inside probe.check() (call #2 — the one SlowSecondProbe pauses on).
        // Rendezvous via `started` (a continuation, not a poll loop) guarantees we only
        // proceed once the tick has actually registered itself as in-flight and is paused.
        async let tickResult: Void = m.probeTick()
        await started.wait()

        // fullRefresh starts concurrently. A correct Monitor must defer to the in-flight
        // tick (await it) rather than racing its own state snapshot/apply against it. Give
        // its task a bounded number of scheduling turns to actually reach that check (a
        // pure actor-hop + array read, needing no blocking resource) before we release the
        // tick — otherwise this call could just happen to run after the tick has already
        // finished, which would trivially pass without exercising the interleaving at all.
        async let refreshResult: Void = m.fullRefresh()
        for _ in 0..<50 { await Task.yield() }

        await release.open()   // let the tick's probe.check() proceed

        _ = await tickResult
        _ = await refreshResult

        let s = await m.currentState()
        XCTAssertEqual(s.exit?.countryCode, "FR",
                       "fresh refresh data must survive, not be clobbered by the tick's stale snapshot")
        let events = box.all().flatMap { $0 }
        XCTAssertEqual(events, [.countryChanged(from: "DE", to: "FR", vpnName: nil)],
                       "exactly one forward countryChanged; no spurious reverse event")
    }
    func testTwoConcurrentFullRefreshesDuringInFlightTickCoalesceToOne() async {
        let c = Counter()
        let started = Gate()   // signaled by the probe right before it blocks
        let release = Gate()   // the test opens this to let the blocked probe proceed
        let deInfo = ExitInfo(ip: "1.2.3.4", countryCode: "DE", city: "Frankfurt", org: "Vodafone",
                              provider: "mock", fetchedAt: Date())
        let frInfo = ExitInfo(ip: "5.6.7.8", countryCode: "FR", city: "Paris", org: "Orange",
                              provider: "mock", fetchedAt: Date())
        let box = EventBox()
        let m = Monitor(geo: SequencedGeo(counter: c, index: CallIndex(), responses: [deInfo, frInfo]),
                        probe: SlowSecondProbe(counter: c, started: started, release: release),
                        route: MockRoute(),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: nil, ip6: nil),
                        relayRanges: RelayRanges(csv: "172.224.224.0/27,DE,,,"),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { box.append($0) })

        // Baseline: online with country DE (consumes probe call #1 and geo response #0).
        await m.fullRefresh()
        let baseline = await m.currentState()
        XCTAssertEqual(baseline.exit?.countryCode, "DE")

        // A tick is in flight, blocked mid probe.check() (call #2).
        async let tickResult: Void = m.probeTick()
        await started.wait()

        // Two independent fullRefresh callers arrive while the tick is in flight. Both must
        // coalesce onto a single re-registered run — not each start their own (which would
        // orphan one, double-count geo.fetch, and risk last-write-wins flip-flop events).
        async let refresh1: Void = m.fullRefresh()
        async let refresh2: Void = m.fullRefresh()
        for _ in 0..<50 { await Task.yield() }

        await release.open()   // let the tick's probe.check() proceed

        _ = await tickResult
        _ = await refresh1
        _ = await refresh2

        let s = await m.currentState()
        XCTAssertEqual(s.exit?.countryCode, "FR",
                       "final state must reflect the single coalesced refresh, not a stale snapshot")

        let geo = await c.geoCalls
        XCTAssertEqual(geo, 2, "baseline (1) plus exactly one coalesced re-registration (1) — not two")

        let events = box.all().flatMap { $0 }
        XCTAssertEqual(events, [.countryChanged(from: "DE", to: "FR", vpnName: nil)],
                       "exactly one forward countryChanged; no flip-flop from orphaned duplicate runs")
    }
    func testProbeTickEscalatesOnRouteChangeSoNoStaleLeakEvent() async {
        let c = Counter()
        let box = EventBox()
        let route = MutableMockRoute(RouteInfo(defaultInterface: "en0", isVPN: false))
        let preInfo = ExitInfo(ip: "1.2.3.4", countryCode: "DE", city: "Frankfurt", org: "Vodafone",
                               provider: "mock", fetchedAt: Date())
        let postInfo = ExitInfo(ip: "5.6.7.8", countryCode: "DE", city: "Bucharest", org: "PureVPN",
                                provider: "mock", fetchedAt: Date())
        let m = Monitor(geo: SequencedGeo(counter: c, index: CallIndex(), responses: [preInfo, postInfo]),
                        probe: MockProbe(counter: c, results: { true }),
                        route: route,
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: nil, ip6: nil),
                        relayRanges: RelayRanges(csv: "172.224.224.0/27,DE,,,"),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { box.append($0) })

        // Baseline: pre-VPN, en0, IP 1.2.3.4 (consumes geo response #0).
        await m.fullRefresh()
        let baseline = await m.currentState()
        XCTAssertEqual(baseline.exit?.ip, "1.2.3.4")
        XCTAssertEqual(baseline.route.defaultInterface, "en0")
        XCTAssertFalse(baseline.route.isVPN)

        // VPN takes the default route right before a probe tick lands.
        route.set(RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN"))
        await m.probeTick()

        // The route changed, so the tick must have escalated to a full refresh and fetched
        // fresh geo data (response #1) instead of applying the stale pre-VPN exit alongside
        // the new route.
        let geo = await c.geoCalls
        XCTAssertEqual(geo, 2, "route flip must escalate the tick into a full refresh")

        let s = await m.currentState()
        XCTAssertEqual(s.exit?.ip, "5.6.7.8")
        XCTAssertEqual(s.route.defaultInterface, "utun4")
        XCTAssertTrue(s.route.isVPN)

        let events = box.all().flatMap { $0 }
        XCTAssertFalse(events.contains { if case .leakSuspected = $0 { return true }; return false },
                       "exit info was refreshed through the new route, so no leak was actually observed")
        XCTAssertTrue(events.contains { if case .vpnRouteChanged = $0 { return true }; return false },
                      "the route change itself must still be reported")
        XCTAssertTrue(events.contains { if case .ipChanged = $0 { return true }; return false }
                      || events.contains { if case .countryChanged = $0 { return true }; return false },
                      "the fresh exit change must still be reported")
    }

    // MARK: - DNS egress verdict (Phase B)

    func testResolverSetChangeEscalatesTickToFullRefresh() async {
        let c = Counter()
        let dns = MockDNSConfig(resolvers: [DNSResolver(address: "192.168.1.1", isIPv6: false)])
        let m = makeMonitor(counter: c, dnsConfig: dns)

        // Baseline: state carries resolver A, seeded by a full refresh (consumes geo call #1 and
        // stack4 call #1).
        await m.fullRefresh()
        let baseline = await m.currentState()
        XCTAssertEqual(baseline.dns.resolvers.map(\.address), ["192.168.1.1"])

        // The DNS config mock now reports a different resolver set (resolver B) right before a
        // probe tick lands — simulating the OS switching resolvers between ticks.
        dns.resolvers = [DNSResolver(address: "8.8.8.8", isIPv6: false)]
        await m.probeTick()

        // The resolver set changed, so the tick must have escalated to a full refresh and
        // touched the geo/stack mocks again, mirroring how the route-change escalation test
        // asserts escalation via the geo call count.
        let geo = await c.geoCalls
        XCTAssertEqual(geo, 2, "resolver-set change must escalate the tick into a full refresh")
        let stack4 = await c.stack4Calls
        XCTAssertEqual(stack4, 2, "the escalated run is a genuine full refresh, not a partial tick")

        let s = await m.currentState()
        XCTAssertEqual(s.dns.resolvers.map(\.address), ["8.8.8.8"])
    }

    func testTickNeverChangesVerdict() async {
        let c = Counter()
        let dnsConfig = MockDNSConfig(resolvers: [DNSResolver(address: "1.1.1.1", isIPv6: false)])
        let dnsProbe = MockDNSProbe(result: ("9.9.9.9", false))
        let info = ExitInfo(ip: "1.2.3.4", countryCode: "DE", city: "Frankfurt", org: "Vodafone",
                            provider: "mock", fetchedAt: Date())
        let m = Monitor(geo: MockGeo(counter: c, info: info),
                        probe: MockProbe(counter: c, results: { true }),
                        route: MockRoute(info: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN")),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: nil, ip6: nil),
                        dnsConfig: dnsConfig,
                        dnsProbe: dnsProbe,
                        dnsProbeEnabled: { true },
                        relayRanges: RelayRanges(csv: ""),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { _ in })

        // Seed .confirmed via two full refreshes with a mismatching probe (exit "1.2.3.4" vs.
        // egress "9.9.9.9" over a VPN-owned v4 route): first mismatch is only .suspected, the
        // second consecutive one confirms it.
        await m.fullRefresh()
        let afterFirst = await m.currentState()
        XCTAssertEqual(afterFirst.dns.leak, .suspected)

        await m.fullRefresh()
        let afterSecond = await m.currentState()
        XCTAssertEqual(afterSecond.dns.leak, .confirmed)
        XCTAssertEqual(dnsProbe.callCount, 2)

        // Now run a tick with resolvers unchanged — it must never touch the DNS probe or alter
        // the confirmed verdict; only full refreshes are allowed to judge.
        await m.probeTick()
        let afterTick = await m.currentState()
        XCTAssertEqual(afterTick.dns.leak, .confirmed, "a tick must never change the DNS verdict")
        XCTAssertEqual(dnsProbe.callCount, 2, "probeTick must not invoke the DNS egress probe")
    }

    func testTwoMismatchedFullRefreshesConfirm() async {
        let c = Counter()
        let dnsProbe = MockDNSProbe(result: ("203.0.113.7", false))
        let info = ExitInfo(ip: "1.2.3.4", countryCode: "DE", city: "Frankfurt", org: "Vodafone",
                            provider: "mock", fetchedAt: Date())
        let m = Monitor(geo: MockGeo(counter: c, info: info),
                        probe: MockProbe(counter: c, results: { true }),
                        route: MockRoute(info: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN")),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: nil, ip6: nil),
                        dnsConfig: MockDNSConfig(resolvers: []),
                        dnsProbe: dnsProbe,
                        dnsProbeEnabled: { true },
                        relayRanges: RelayRanges(csv: ""),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { _ in })

        // Route is VPN-owned on v4; geo/stack mocks give a fresh v4 exit ("1.2.3.4") that
        // differs from the probe's reported egress ("203.0.113.7") on every refresh.
        await m.fullRefresh()
        let afterOne = await m.currentState()
        XCTAssertEqual(afterOne.dns.leak, .suspected, "a single mismatch is only suspected")

        await m.fullRefresh()
        let afterTwo = await m.currentState()
        XCTAssertEqual(afterTwo.dns.leak, .confirmed, "a second consecutive mismatch confirms the leak")
    }

    func testDisabledProbeNeverCalledAndVerdictUnknown() async {
        let c = Counter()
        let dnsProbe = MockDNSProbe(result: ("203.0.113.7", false))
        let m = makeMonitor(counter: c, dnsProbe: dnsProbe, dnsProbeEnabled: { false })

        await m.fullRefresh()

        XCTAssertEqual(dnsProbe.callCount, 0, "a disabled probe must never send a DNS query")
        let s = await m.currentState()
        XCTAssertEqual(s.dns.leak, .unknown, "an explicit opt-out clears the verdict rather than preserving an alarm")
        XCTAssertNil(s.dns.egressIP)
    }

    func testGenuineLeakStillDetected() async {
        let c = Counter()
        let box = EventBox()
        let route = MutableMockRoute(RouteInfo(defaultInterface: "en0", isVPN: false))
        let info = ExitInfo(ip: "1.2.3.4", countryCode: "DE", city: "Frankfurt", org: "Vodafone",
                            provider: "mock", fetchedAt: Date())
        // Same IP on both fetches: the tunnel does not actually change the exit — a real leak.
        let m = Monitor(geo: SequencedGeo(counter: c, index: CallIndex(), responses: [info, info]),
                        probe: MockProbe(counter: c, results: { true }),
                        route: route,
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: nil, ip6: nil),
                        relayRanges: RelayRanges(csv: "172.224.224.0/27,DE,,,"),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { box.append($0) })

        await m.fullRefresh()
        route.set(RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN"))
        await m.probeTick()

        let geo = await c.geoCalls
        XCTAssertEqual(geo, 2, "route flip must still escalate to a full refresh")

        let events = box.all().flatMap { $0 }
        XCTAssertTrue(events.contains { if case .leakSuspected = $0 { return true }; return false },
                      "a tunnel that genuinely returns the same exit IP must still be flagged")
    }

    // MARK: - IPv6 leak detection (Phase 1)

    func testIPv6LeakConfirmedWhenStacksDifferAndV4RouteIsVPN() async {
        let c = Counter()
        let box = EventBox()
        let ip4 = "1.2.3.4"; let ip6 = "2001:db8::1"
        let info4 = ExitInfo(ip: ip4, countryCode: "NL", org: "PureVPN", provider: "mock", fetchedAt: Date())
        let info6 = ExitInfo(ip: ip6, countryCode: "DE", org: "Deutsche Telekom", provider: "mock", fetchedAt: Date())
        let m = Monitor(geo: StackTestGeo(counter: c, chainFallback: nil, lookups: [ip4: info4, ip6: info6]),
                        probe: MockProbe(counter: c, results: { true }),
                        route: MockRoute(info: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN",
                                                          v6DefaultInterface: "en0", v6IsVPN: false)),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: ip4, ip6: ip6),
                        relayRanges: RelayRanges(csv: ""),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { box.append($0) })

        await m.fullRefresh()
        let s = await m.currentState()
        XCTAssertTrue(s.ipv6Leak)
        XCTAssertEqual(s.exit?.countryCode, "NL")
        XCTAssertEqual(s.exit6?.countryCode, "DE")

        let events = box.all().flatMap { $0 }
        XCTAssertEqual(events.filter { if case .ipv6Leak = $0 { return true }; return false }.count, 1,
                       "exactly one .ipv6Leak event on the false->true transition")
    }
    func testNoV6RouteMeansNoLeak() async {
        // The "Serbia case": a VPN owns the v4 default route but there simply is no IPv6
        // default route at all (nil, not "present but not a tunnel") -- suspicion can never
        // even arise, regardless of what the v6 stack-pinned measurement returns.
        let c = Counter()
        let box = EventBox()
        let ip4 = "1.2.3.4"; let ip6 = "2001:db8::1"
        let info4 = ExitInfo(ip: ip4, countryCode: "NL", org: "PureVPN", provider: "mock", fetchedAt: Date())
        let info6 = ExitInfo(ip: ip6, countryCode: "DE", org: "Deutsche Telekom", provider: "mock", fetchedAt: Date())
        let m = Monitor(geo: StackTestGeo(counter: c, chainFallback: nil, lookups: [ip4: info4, ip6: info6]),
                        probe: MockProbe(counter: c, results: { true }),
                        route: MockRoute(info: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN",
                                                          v6DefaultInterface: nil, v6IsVPN: false)),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: ip4, ip6: ip6),
                        relayRanges: RelayRanges(csv: ""),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { box.append($0) })

        await m.fullRefresh()
        let s = await m.currentState()
        XCTAssertFalse(s.ipv6Leak)
    }
    func testV6MeasurementFailureNeverConfirmsLeak() async {
        // Suspicion alone (VPN owns v4, a v6 route exists and isn't itself a tunnel) is never
        // enough on its own -- if the v6 stack-pinned measurement fails this refresh, there is
        // no fresh exit6 to compare against, so the leak must stay unconfirmed.
        let c = Counter()
        let box = EventBox()
        let ip4 = "1.2.3.4"
        let info4 = ExitInfo(ip: ip4, countryCode: "NL", org: "PureVPN", provider: "mock", fetchedAt: Date())
        let m = Monitor(geo: StackTestGeo(counter: c, chainFallback: nil, lookups: [ip4: info4]),
                        probe: MockProbe(counter: c, results: { true }),
                        route: MockRoute(info: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN",
                                                          v6DefaultInterface: "en0", v6IsVPN: false)),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: ip4, ip6: nil),
                        relayRanges: RelayRanges(csv: ""),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { box.append($0) })

        await m.fullRefresh()
        let s = await m.currentState()
        XCTAssertFalse(s.ipv6Leak)
        XCTAssertNil(s.exit6)
    }
    func testStacksAgreeMeansNoLeak() async {
        let c = Counter()
        let box = EventBox()
        let ip4 = "1.2.3.4"; let ip6 = "2001:db8::1"
        let info4 = ExitInfo(ip: ip4, countryCode: "NL", org: "PureVPN", provider: "mock", fetchedAt: Date())
        let info6 = ExitInfo(ip: ip6, countryCode: "NL", org: "PureVPN", provider: "mock", fetchedAt: Date())
        let m = Monitor(geo: StackTestGeo(counter: c, chainFallback: nil, lookups: [ip4: info4, ip6: info6]),
                        probe: MockProbe(counter: c, results: { true }),
                        route: MockRoute(info: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN",
                                                          v6DefaultInterface: "en0", v6IsVPN: false)),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: ip4, ip6: ip6),
                        relayRanges: RelayRanges(csv: ""),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { box.append($0) })

        await m.fullRefresh()
        let s = await m.currentState()
        XCTAssertFalse(s.ipv6Leak)
        XCTAssertEqual(s.exit?.ip, ip4)
        XCTAssertEqual(s.exit6?.ip, ip6)
    }
    func testStaleV4BaselineNeverConfirmsLeakWhenBothV4SourcesFail() async {
        // Code review finding: `new.exit` starts as a copy of `state` and is only reassigned
        // when the v4-pinned lookup OR the chain fallback succeeds. If BOTH fail on a given
        // refresh while connectivity is otherwise online, `new.exit` is whatever the LAST
        // successful refresh saw -- stale, not measured this tick. exit6 freshness is
        // guaranteed by construction (it's only ever set from this tick's lookup, or nil), but
        // without a freshness guard on the v4 side, a stale v4 baseline that happens to mismatch
        // a genuinely fresh exit6 would wrongly confirm a leak. Must never happen.
        let ip4 = "1.2.3.4"; let ip6 = "2001:db8::1"
        let info4 = ExitInfo(ip: ip4, countryCode: "NL", org: "PureVPN", provider: "mock", fetchedAt: Date())
        let info6 = ExitInfo(ip: ip6, countryCode: "DE", org: "Deutsche Telekom", provider: "mock", fetchedAt: Date())
        let route = RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN",
                              v6DefaultInterface: "en0", v6IsVPN: false)
        let stackIP = MutableStackIP(ip4: ip4, ip6: ip6)
        let geo = MutableStackTestGeo(chainFallback: info4, lookups: [ip4: info4, ip6: info6])
        let m = Monitor(geo: geo,
                        probe: MockProbe(counter: Counter(), results: { true }),
                        route: MockRoute(info: route),
                        httpIP: MockHTTPIP(counter: Counter(), ip: nil),
                        stackIP: stackIP,
                        relayRanges: RelayRanges(csv: ""),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { _ in })

        // Baseline refresh: v4 resolves fine (NL), seeding state.exit with a real value that
        // is about to become stale.
        await m.fullRefresh()
        let baseline = await m.currentState()
        XCTAssertEqual(baseline.exit?.countryCode, "NL")

        // This tick: BOTH the v4-pinned fetch AND the chain fallback fail. Only v6 resolves
        // fresh (DE) -- a genuine mismatch against the now-stale NL baseline, but that stale
        // baseline must never be allowed to confirm a leak.
        stackIP.set(ip4: nil, ip6: ip6)
        geo.set(chainFallback: nil, lookups: [ip6: info6])
        await m.fullRefresh()

        let s = await m.currentState()
        XCTAssertEqual(s.exit?.countryCode, "NL", "exit falls back to the stale baseline when nothing fresh resolves")
        XCTAssertEqual(s.exit6?.countryCode, "DE")
        XCTAssertFalse(s.ipv6Leak, "a stale v4 baseline must never confirm a leak, even if it happens to mismatch a fresh exit6")
    }

    // MARK: - Scoped-route v6 egress attribution (field-verified PureVPN AR case)

    func testScopedV6RouteAttributedViaSourceAddressMatch() async {
        // Field root cause: PureVPN demotes (doesn't delete) the native v6 default route to an
        // interface-SCOPED route when its tunnel comes up, so defaultRouteInterface6()'s
        // unscoped lookup sees nothing (v6DefaultInterface nil) even though URLSession still
        // leaks over it. When exit6 was freshly measured, Monitor must fall back to finding
        // which local interface holds that exact address (mocked here as "en0", simulating
        // RouteInspector.interfaceHolding finding it via getifaddrs) and treat that as the
        // effective v6 egress — completing the leak rule's conditions.
        let c = Counter()
        let box = EventBox()
        let ip4 = "1.2.3.4"; let ip6 = "2001:9e8:a6e:100:c5af:613e:c5ba:e1e0"
        let info4 = ExitInfo(ip: ip4, countryCode: "AR", org: "PureVPN", provider: "mock", fetchedAt: Date())
        let info6 = ExitInfo(ip: ip6, countryCode: "DE", org: "Deutsche Telekom", provider: "mock", fetchedAt: Date())
        let m = Monitor(geo: StackTestGeo(counter: c, chainFallback: nil, lookups: [ip4: info4, ip6: info6]),
                        probe: MockProbe(counter: c, results: { true }),
                        route: MockRoute(info: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN",
                                                          v6DefaultInterface: nil, v6IsVPN: false),
                                         holding: "en0"),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: ip4, ip6: ip6),
                        relayRanges: RelayRanges(csv: ""),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { box.append($0) })

        await m.fullRefresh()
        let s = await m.currentState()
        XCTAssertTrue(s.ipv6Leak)
        XCTAssertEqual(s.route.v6DefaultInterface, "en0", "effective v6 egress recovered via source-address match")
        XCTAssertFalse(s.route.v6IsVPN)

        let events = box.all().flatMap { $0 }
        XCTAssertEqual(events.filter { if case .ipv6Leak = $0 { return true }; return false }.count, 1)
    }
    func testScopedV6RouteWithNoLocalAttributionStaysUnconfirmed() async {
        // exit6's address matches no local interface at all (e.g. a NAT'd/tunneled v6 exit) --
        // the fallback correctly finds nothing, fields stay nil, and the leak rule stays silent
        // exactly as it would for "no v6 route found" today.
        let c = Counter()
        let ip4 = "1.2.3.4"; let ip6 = "2001:db8::1"
        let info4 = ExitInfo(ip: ip4, countryCode: "AR", org: "PureVPN", provider: "mock", fetchedAt: Date())
        let info6 = ExitInfo(ip: ip6, countryCode: "DE", org: "Deutsche Telekom", provider: "mock", fetchedAt: Date())
        let m = Monitor(geo: StackTestGeo(counter: c, chainFallback: nil, lookups: [ip4: info4, ip6: info6]),
                        probe: MockProbe(counter: c, results: { true }),
                        route: MockRoute(info: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN",
                                                          v6DefaultInterface: nil, v6IsVPN: false),
                                         holding: nil),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: ip4, ip6: ip6),
                        relayRanges: RelayRanges(csv: ""),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { _ in })

        await m.fullRefresh()
        let s = await m.currentState()
        XCTAssertFalse(s.ipv6Leak)
        XCTAssertNil(s.route.v6DefaultInterface)
    }
    func testScopedV6RouteAttributedToTunnelInterfaceStaysUnconfirmed() async {
        // The source-address match lands on a utun (e.g. a dual-tunnel VPN that also tunnels
        // v6, just via a scoped route for some reason) -- v6IsVPN must come out true, and the
        // leak rule's `!v6IsVPN` conjunct correctly keeps it unconfirmed.
        let c = Counter()
        let ip4 = "1.2.3.4"; let ip6 = "2001:db8::1"
        let info4 = ExitInfo(ip: ip4, countryCode: "AR", org: "PureVPN", provider: "mock", fetchedAt: Date())
        let info6 = ExitInfo(ip: ip6, countryCode: "DE", org: "Deutsche Telekom", provider: "mock", fetchedAt: Date())
        let m = Monitor(geo: StackTestGeo(counter: c, chainFallback: nil, lookups: [ip4: info4, ip6: info6]),
                        probe: MockProbe(counter: c, results: { true }),
                        route: MockRoute(info: RouteInfo(defaultInterface: "utun4", isVPN: true, vpnName: "PureVPN",
                                                          v6DefaultInterface: nil, v6IsVPN: false),
                                         holding: "utun9"),
                        httpIP: MockHTTPIP(counter: c, ip: nil),
                        stackIP: MockStackIP(counter: c, ip4: ip4, ip6: ip6),
                        relayRanges: RelayRanges(csv: ""),
                        debounceSeconds: 0.05,
                        onChange: { _ in }, onEvents: { _ in })

        await m.fullRefresh()
        let s = await m.currentState()
        XCTAssertFalse(s.ipv6Leak)
        XCTAssertEqual(s.route.v6DefaultInterface, "utun9")
        XCTAssertTrue(s.route.v6IsVPN)
    }
}

/// Broadcasts a one-time signal to any number of concurrent waiters (unlike a single
/// `CheckedContinuation`, which only supports one).
actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Hands out sequential response indices so a mock can track "which call is this".
actor CallIndex {
    private var n = 0
    func next() -> Int { defer { n += 1 }; return n }
}

/// Returns a different `ExitInfo` on each successive call (by response list order).
struct SequencedGeo: GeoFetching {
    let counter: Counter
    let index: CallIndex
    let responses: [ExitInfo?]
    func fetch() async -> ExitInfo? {
        await counter.bumpGeo()
        let n = await index.next()
        return n < responses.count ? responses[n] : responses.last ?? nil
    }
    func lookup(ip: String) async -> ExitInfo? {
        await counter.bumpLookup()
        return ExitInfo(ip: ip, countryCode: "DE", provider: "mock", fetchedAt: Date())
    }
}

/// Always succeeds, but on exactly its 2nd invocation signals `started` and then blocks on
/// `release` — used to deterministically catch a probeTick mid-`probe.check()` while a
/// concurrent fullRefresh starts, without any poll loop on either side of the rendezvous.
struct SlowSecondProbe: ProbeRunning {
    let counter: Counter
    let started: Gate
    let release: Gate
    func check() async -> Bool {
        let n = await counter.bumpProbe()
        if n == 2 {
            await started.open()
            await release.wait()
        }
        return true
    }
}

final class EventBox: @unchecked Sendable {
    private var events: [[Event]] = []
    private let lock = NSLock()
    func append(_ e: [Event]) { lock.lock(); events.append(e); lock.unlock() }
    func all() -> [[Event]] { lock.lock(); defer { lock.unlock() }; return events }
}
