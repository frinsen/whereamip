import Foundation

public protocol GeoFetching: Sendable {
    func fetch() async -> ExitInfo?
    func lookup(ip: String) async -> ExitInfo?
}
public protocol ProbeRunning: Sendable { func check() async -> Bool }
public protocol RouteSnapshotting: Sendable {
    func snapshot() -> RouteInfo
    /// Fallback v6 egress attribution by source-address match (see `RouteInspector
    /// .interfaceHolding(ipv6:)` for the scoped-route rationale). Defaulted below so existing
    /// conformers need no changes; test mocks override it to return a fixed interface name (or
    /// nil) instead of touching the real network stack.
    func interfaceHolding(ipv6: String) -> String?
}
public extension RouteSnapshotting {
    func interfaceHolding(ipv6: String) -> String? { RouteInspector.interfaceHolding(ipv6: ipv6) }
}
public protocol HTTPIPFetching: Sendable { func fetch() async -> String? }
public protocol StackIPFetching: Sendable {
    func fetch4() async -> String?
    func fetch6() async -> String?
}
public protocol DNSConfigReading: Sendable {
    func snapshot() -> (resolvers: [DNSResolver], encryption: DNSEncryption)
}
public protocol DNSEgressProbing: Sendable { func fetch() async -> (ip: String, isIPv6: Bool)? }

extension GeoProviderChain: GeoFetching {
    public func fetch() async -> ExitInfo? { await fetch(now: Date()) }
    public func lookup(ip: String) async -> ExitInfo? { await lookup(ip: ip, now: Date()) }
}
extension ConnectivityProbe: ProbeRunning {}
extension HTTPIPFetcher: HTTPIPFetching {}
extension StackPinnedIP: StackIPFetching {}
extension LiveDNSConfigReader: DNSConfigReading {}
extension DNSEgressProbe: DNSEgressProbing {}

public actor Monitor {
    let geo: any GeoFetching
    let probe: any ProbeRunning
    let route: any RouteSnapshotting
    let httpIP: any HTTPIPFetching
    let stackIP: any StackIPFetching
    let dnsConfig: any DNSConfigReading
    let dnsProbe: any DNSEgressProbing
    let dnsProbeEnabled: @Sendable () -> Bool
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
                httpIP: any HTTPIPFetching, stackIP: any StackIPFetching = StackPinnedIP(),
                dnsConfig: any DNSConfigReading = LiveDNSConfigReader(),
                dnsProbe: any DNSEgressProbing = DNSEgressProbe(),
                dnsProbeEnabled: @escaping @Sendable () -> Bool = { Settings().dnsProbeEnabled },
                relayRanges: RelayRanges,
                debounceSeconds: Double = 1.5,
                onChange: @escaping @Sendable (ExitState) -> Void,
                onEvents: @escaping @Sendable ([Event]) -> Void) {
        self.geo = geo; self.probe = probe; self.route = route; self.httpIP = httpIP; self.stackIP = stackIP
        self.dnsConfig = dnsConfig
        self.dnsProbe = dnsProbe; self.dnsProbeEnabled = dnsProbeEnabled
        self.relayRanges = relayRanges; self.debounce = debounceSeconds
        self.onChange = onChange; self.onEvents = onEvents
        // Seed the initial route synchronously so the first refresh doesn't report a
        // spurious vpnRouteChanged for simply discovering the already-current interface.
        self.state = ExitState(route: route.snapshot())
    }

    public func currentState() -> ExitState { state }

    public func fullRefresh() async {
        Log.monitor.debug("fullRefresh() called")
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
            Log.monitor.debug("fullRefresh() coalescing onto in-flight \(self.inFlightKind == .full ? "full" : "tick", privacy: .public) work")
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
        let dnsCfg = dnsConfig.snapshot()
        new.dns.resolvers = dnsCfg.resolvers
        new.dns.encryption = dnsCfg.encryption
        if new.connectivity != .offline {
            // Stack-pinned dual-stack measurement (IPv6 leak detector, Phase 1): api4/api6
            // force the request over each protocol family independently. Both are under
            // their own hard deadlines, so a v4-only or v6-only network just yields nil for
            // the missing side rather than blocking the refresh.
            let ip4 = await stackIP.fetch4()
            let ip6 = await stackIP.fetch6()
            Log.monitor.debug("runFullRefresh: stack ip4=\(ip4 ?? "nil", privacy: .public) ip6=\(ip6 ?? "nil", privacy: .public)")

            var resolved: [String: ExitInfo] = [:]
            for ip in Set([ip4, ip6].compactMap { $0 }) {
                if let info = await geo.lookup(ip: ip) { resolved[ip] = info }
            }
            // `new.exit` starts as a copy of `state.exit` (possibly stale, from a previous
            // refresh) and is only overwritten below when a fresh v4 source actually succeeds.
            // Track that explicitly — `new.exit != nil` alone can't tell fresh from stale,
            // since a stale value is also non-nil.
            var exitFreshThisTick = false
            if let ip4, let info = resolved[ip4] {
                new.exit = info
                exitFreshThisTick = true
            } else if let info = await geo.fetch() {
                // v4-pinned discovery failed (or its geo lookup did) — fall back to the
                // existing multi-provider chain, same as before this feature existed.
                new.exit = info
                exitFreshThisTick = true
            }
            new.exit6 = ip6.flatMap { resolved[$0] }

            // Scoped-route fallback (field-verified against a live PureVPN AR profile): some
            // VPNs demote the native v6 default route to an interface-SCOPED route instead of
            // deleting it, so `defaultRouteInterface6()`'s unscoped lookup sees nothing even
            // though URLSession (and thus our own stack-pinned v6 measurement) still leaks over
            // it. `new.exit6` is fresh-or-nil by construction, so when it's present but the
            // unscoped route lookup came up empty, ask `route.interfaceHolding(ipv6:)` which
            // local interface actually holds that exact address — native v6 has no NAT, so a
            // direct match recovers the true egress. No match (e.g. a NAT'd/tunneled v6 exit)
            // correctly leaves the fields nil, same as "no v6 route found".
            if new.route.v6DefaultInterface == nil, let e6 = new.exit6,
               let iface = route.interfaceHolding(ipv6: e6.ip) {
                new.route.v6DefaultInterface = iface
                new.route.v6IsVPN = RouteInspector.isTunnelInterface(iface)
                Log.route.debug("runFullRefresh: scoped-route fallback attributed v6 egress to \(iface, privacy: .public)")
            }

            // Two-tier leak rule. `suspicion` alone is never enough to warn — this codebase
            // already had one false-alarm lesson (see the route-change escalation comments in
            // probeTick/runFullRefresh below): a leak is only *confirmed* when both stacks were
            // freshly measured in THIS refresh and genuinely differ, while the v4 default route
            // is owned by a VPN and the v6 default route still exits natively (not itself a
            // tunnel). Anything less — no v6 route at all, a failed v6 measurement, a v4 exit
            // that fell back to a stale baseline because BOTH the v4-pinned fetch and the chain
            // fallback failed this tick, or stacks that agree — must never set ipv6Leak from
            // stale or partial data. `exitFreshThisTick` is the guard for that last case:
            // exit6 is always fresh-or-nil by construction, but `new.exit` alone doesn't carry
            // that guarantee, so it needs an explicit conjunct here.
            let suspicion = new.route.isVPN && new.route.v6DefaultInterface != nil && !new.route.v6IsVPN
            if suspicion, exitFreshThisTick, let e6 = new.exit6, let e4 = new.exit,
               (e6.countryCode != e4.countryCode || e6.org != e4.org) {
                new.ipv6Leak = true
            } else {
                new.ipv6Leak = false
            }
            Log.monitor.debug("runFullRefresh: suspicion=\(suspicion, privacy: .public) exitFresh=\(exitFreshThisTick, privacy: .public) ipv6Leak=\(new.ipv6Leak, privacy: .public)")

            // DNS egress verdict — only full refreshes may judge (ticks update observations only).
            // Consent gate: when the probe is disabled, no DNS query is EVER sent and the verdict is
            // deliberately .unknown, not a preserved alarm (an explicit opt-out clears state; a mere
            // probe FAILURE preserves .confirmed inside decide() — different cases, both intentional).
            if dnsProbeEnabled() {
                let egress = await dnsProbe.fetch()
                new.dns.leak = DNSLeakDetector.decide(egress: egress,
                                                      exit4: exitFreshThisTick ? new.exit : nil,
                                                      exit6: new.exit6,
                                                      route: new.route,
                                                      previous: state.dns.leak)
                new.dns.egressIP = egress?.ip
                new.dns.egressIsIPv6 = egress?.isIPv6 ?? false
                new.dns.measuredAt = egress != nil ? Date() : state.dns.measuredAt
                Log.dns.debug("verdict: egress=\(egress?.ip ?? "nil", privacy: .public) leak=\(new.dns.leak.rawValue, privacy: .public)")
            } else {
                new.dns.leak = .unknown
                new.dns.egressIP = nil
                new.dns.measuredAt = nil
            }

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
        Log.monitor.debug("probeTick() called")
        // ANY in-flight state-mutating work (tick or full refresh) already covers this call's
        // job — await it and return rather than snapshotting `state` ourselves and racing our
        // own `apply(new)` against it.
        if let task = inFlight {
            Log.monitor.debug("probeTick() coalescing onto in-flight \(self.inFlightKind == .full ? "full" : "tick", privacy: .public) work")
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
        let dnsCfg = dnsConfig.snapshot()
        new.dns.resolvers = dnsCfg.resolvers
        new.dns.encryption = dnsCfg.encryption
        if before == .offline, new.connectivity == .online {
            Log.monitor.debug("probeTick escalating to fullRefresh: offline -> online")
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
            Log.monitor.debug("probeTick escalating to fullRefresh: route changed \(self.state.route.defaultInterface ?? "nil", privacy: .public) -> \(new.route.defaultInterface ?? "nil", privacy: .public)")
            inFlightKind = .full
            await runFullRefresh()
            return
        }
        // Third escalation trigger (same pattern as offline→online and route-change above): a
        // changed resolver set means the last egress verdict was measured under a DNS config
        // that no longer exists — never let the two coexist in state. The full refresh re-reads
        // config and re-judges with fresh measurements.
        if new.dns.resolvers != state.dns.resolvers {
            Log.monitor.debug("probeTick escalating to fullRefresh: DNS resolver set changed")
            inFlightKind = .full
            await runFullRefresh()
            return
        }
        apply(new)
    }

    public func pathChanged() {
        Log.monitor.debug("pathChanged() called, debouncing")
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
        Log.monitor.debug("apply: connectivity=\(next.connectivity.rawValue, privacy: .public) exit=\(next.exit?.ip ?? "nil", privacy: .public)/\(next.exit?.countryCode ?? "nil", privacy: .public) route=\(next.route.defaultInterface ?? "nil", privacy: .public)/vpn=\(next.route.vpnName ?? "nil", privacy: .public) dns=\(next.dns.leak.rawValue, privacy: .public)/\(next.dns.resolvers.count, privacy: .public)res")
        onChange(next)
        let events = Reducer.events(old: old, new: next)
        if !events.isEmpty {
            Log.reducer.debug("events: \(String(describing: events), privacy: .public)")
            onEvents(events)
        }
    }
}
