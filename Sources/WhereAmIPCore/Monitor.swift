import Foundation

public protocol GeoFetching: Sendable {
    func fetch() async -> ExitInfo?
    func lookup(ip: String) async -> ExitInfo?
}
public protocol ProbeRunning: Sendable { func check() async -> Bool }
public protocol RouteSnapshotting: Sendable { func snapshot() -> RouteInfo }
public protocol HTTPIPFetching: Sendable { func fetch() async -> String? }

extension GeoProviderChain: GeoFetching {
    public func fetch() async -> ExitInfo? { await fetch(now: Date()) }
    public func lookup(ip: String) async -> ExitInfo? { await lookup(ip: ip, now: Date()) }
}
extension ConnectivityProbe: ProbeRunning {}
extension HTTPIPFetcher: HTTPIPFetching {}

public actor Monitor {
    let geo: any GeoFetching
    let probe: any ProbeRunning
    let route: any RouteSnapshotting
    let httpIP: any HTTPIPFetching
    let relayRanges: RelayRanges
    let debounce: Double
    let onChange: @Sendable (ExitState) -> Void
    let onEvents: @Sendable ([Event]) -> Void

    public private(set) var state: ExitState
    var gate = ProbeGate()
    var debounceTask: Task<Void, Never>?

    /// Kind of work a tracked in-flight task is doing. Both `fullRefresh` and `probeTick`
    /// register their work under the single `inFlight` slot below, so ANY state-mutating
    /// work (not just fullRefresh) is serialized — otherwise a probeTick that snapshots
    /// `state` before suspending on `probe.check()` can resume after a concurrent
    /// fullRefresh has already applied fresh data, and clobber it with its stale snapshot
    /// (lost-update race, incl. spurious reverse events).
    private enum RefreshKind { case tick, full }
    var inFlight: Task<Void, Never>?
    private var inFlightKind: RefreshKind?
    /// Bumped every time a new task claims the `inFlight` slot. An owner only clears the
    /// slot if this still matches the generation it registered under — otherwise a newer
    /// caller has already claimed it (e.g. `fullRefresh` starting its own run right after
    /// awaiting an in-flight tick), and clearing would erase someone else's live task.
    private var inFlightGeneration = 0

    public init(geo: any GeoFetching, probe: any ProbeRunning, route: any RouteSnapshotting,
                httpIP: any HTTPIPFetching, relayRanges: RelayRanges,
                debounceSeconds: Double = 1.5,
                onChange: @escaping @Sendable (ExitState) -> Void,
                onEvents: @escaping @Sendable ([Event]) -> Void) {
        self.geo = geo; self.probe = probe; self.route = route; self.httpIP = httpIP
        self.relayRanges = relayRanges; self.debounce = debounceSeconds
        self.onChange = onChange; self.onEvents = onEvents
        // Seed the initial route synchronously so the first refresh doesn't report a
        // spurious vpnRouteChanged for simply discovering the already-current interface.
        self.state = ExitState(route: route.snapshot())
    }

    public func currentState() -> ExitState { state }

    public func fullRefresh() async {
        // Coalesce onto any in-flight state-mutating work. If it's a full refresh, awaiting
        // it satisfies this call. If it's only a tick, a genuine full refresh is still owed:
        // help clear the now-finished slot ourselves (generation-guarded, since several
        // coalescers and the original owner may all reach this independently) and loop back
        // to re-check — another caller may have *already* registered fresh work while we
        // were awaiting, in which case we must await THAT instead of blindly registering our
        // own. Blindly registering without this re-check is exactly how two concurrent
        // fullRefresh calls could each start their own redundant run and orphan one another.
        //
        // Terminates: each iteration either (a) returns, (b) clears a now-stale completed
        // slot and finds it empty on re-check, exiting the loop, or (c) finds a newer task
        // already registered (inFlightGeneration strictly greater than what we last saw) and
        // awaits that instead — bounded by the actual number of concurrent callers, never an
        // unconditional re-observation of the same finished task (which was the round-2 bug).
        while let task = inFlight {
            let wasFull = (inFlightKind == .full)
            let gen = inFlightGeneration
            await task.value
            if wasFull { return }
            if inFlightGeneration == gen, inFlight != nil {
                inFlight = nil
                inFlightKind = nil
            }
        }
        inFlightGeneration += 1
        let myGeneration = inFlightGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runFullRefresh()
        }
        inFlight = task
        inFlightKind = .full
        await task.value
        // Only clear if nobody newer has already claimed the slot (see inFlightGeneration).
        if inFlightGeneration == myGeneration {
            inFlight = nil
            inFlightKind = nil
        }
    }

    private func runFullRefresh() async {
        var new = state
        new.connectivity = gate.record(success: await probe.check())
        new.route = route.snapshot()
        if new.connectivity != .offline {
            if let info = await geo.fetch() { new.exit = info }
            let httpsIP = new.exit?.ip
            var relay = PrivateRelayDetector.decide(httpsIP: httpsIP, httpIP: await httpIP.fetch(), ranges: relayRanges)
            if case .active(let egressIP, nil) = relay, let ip = egressIP {
                relay = .active(egressIP: ip, egressCountry: await geo.lookup(ip: ip)?.countryCode)
            }
            new.privateRelay = relay
        }
        apply(new)
    }

    public func probeTick() async {
        // ANY in-flight state-mutating work (tick or full refresh) already covers this call's
        // job — await it and return rather than snapshotting `state` ourselves and racing our
        // own `apply(new)` against it.
        if let task = inFlight {
            await task.value
            return
        }
        inFlightGeneration += 1
        let myGeneration = inFlightGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runProbeTick()
        }
        inFlight = task
        inFlightKind = .tick
        await task.value
        if inFlightGeneration == myGeneration {
            inFlight = nil
            inFlightKind = nil
        }
    }

    private func runProbeTick() async {
        let before = state.connectivity
        var new = state
        new.connectivity = gate.record(success: await probe.check())
        new.route = route.snapshot()
        if before == .offline, new.connectivity == .online {
            apply(new)
            // Escalating within the same tracked slot — reclassify it as a full refresh so
            // any coalescer awaiting this task treats it as one (and doesn't then run a
            // redundant extra refresh of its own, which would also widen the window for the
            // N-way registration race this slot's generation-guard exists to prevent).
            inFlightKind = .full
            await runFullRefresh()
            return
        }
        if new.route.defaultInterface != state.route.defaultInterface || new.route.isVPN != state.route.isVPN {
            // The default route just changed (e.g. a VPN took over). Applying this partial
            // tick would pair the new route with `exit`, which is still whatever the last
            // full refresh fetched over the OLD route — the Reducer's leakSuspected rule
            // can't tell that apart from a genuine leak. Never let a route change reach state
            // without exit info fetched fresh through it: escalate to a full refresh instead,
            // same as the offline→online case above.
            inFlightKind = .full
            await runFullRefresh()
            return
        }
        apply(new)
    }

    public func pathChanged() {
        debounceTask?.cancel()
        debounceTask = Task { [debounce] in
            try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.fullRefresh()
        }
    }

    func apply(_ new: ExitState) {
        var next = new
        let old = state
        if old.connectivity != next.connectivity
            || old.exit?.countryCode != next.exit?.countryCode
            || old.route.defaultInterface != next.route.defaultInterface {
            next.since = Date()
        }
        guard next != old else { return }
        state = next
        onChange(next)
        let events = Reducer.events(old: old, new: next)
        if !events.isEmpty { onEvents(events) }
    }
}
