import XCTest
@testable import WhereAmIPCore

actor Counter {
    var geoCalls = 0; var probeCalls = 0; var lookupCalls = 0; var httpIPCalls = 0
    func bumpGeo() { geoCalls += 1 }
    @discardableResult func bumpProbe() -> Int { probeCalls += 1; return probeCalls }
    func bumpLookup() { lookupCalls += 1 }; func bumpHTTP() { httpIPCalls += 1 }
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
    func snapshot() -> RouteInfo { info }
}
struct MockHTTPIP: HTTPIPFetching {
    let counter: Counter
    var ip: String?
    func fetch() async -> String? { await counter.bumpHTTP(); return ip }
}

final class MonitorTests: XCTestCase {
    func makeMonitor(counter: Counter, probeOK: Bool = true, httpIP: String? = nil,
                     onEvents: @escaping @Sendable ([Event]) -> Void = { _ in }) -> Monitor {
        let info = ExitInfo(ip: "1.2.3.4", countryCode: "DE", city: "Frankfurt", org: "Vodafone",
                            provider: "mock", fetchedAt: Date())
        return Monitor(geo: MockGeo(counter: counter, info: info),
                       probe: MockProbe(counter: counter, results: { probeOK }),
                       route: MockRoute(),
                       httpIP: MockHTTPIP(counter: counter, ip: httpIP),
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
