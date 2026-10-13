public enum Event: Equatable, Sendable {
    case countryChanged(from: String?, to: String?, vpnName: String?)
    case ipChanged(country: String?, fromOrg: String?, toOrg: String?)
    case connectivityLost(hijackSuspected: Bool)
    case connectivityRestored(country: String?, city: String?, org: String?)
    case vpnRouteChanged(vpnName: String?, interface: String?)
    case privateRelayToggled(active: Bool)
    case leakSuspected(org: String?)
    case ipv6Leak(country: String?, org: String?)
    case dnsLeakConfirmed(egressIP: String?, resolver: String?)
}

public enum Reducer {
    public static func events(old: ExitState, new: ExitState) -> [Event] {
        var out: [Event] = []
        if old.connectivity != .offline, new.connectivity == .offline {
            out.append(.connectivityLost(hijackSuspected: new.route.hijackRoutePresent))
        }
        if old.connectivity == .offline, new.connectivity == .online {
            out.append(.connectivityRestored(country: new.exit?.countryCode, city: new.exit?.city, org: new.exit?.org))
        }
        if old.connectivity == .online, new.connectivity == .online,
           let o = old.exit, let n = new.exit {
            if o.countryCode != n.countryCode {
                out.append(.countryChanged(from: o.countryCode, to: n.countryCode, vpnName: new.route.vpnName))
            } else if o.ip != n.ip {
                out.append(.ipChanged(country: n.countryCode, fromOrg: o.org, toOrg: n.org))
            }
        }
        if old.route.defaultInterface != new.route.defaultInterface || old.route.vpnName != new.route.vpnName {
            out.append(.vpnRouteChanged(vpnName: new.route.vpnName, interface: new.route.defaultInterface))
        }
        let wasActive = { (relay: PrivateRelay) in if case .active = relay { true } else { false } }
        if wasActive(old.privateRelay) != wasActive(new.privateRelay) {
            out.append(.privateRelayToggled(active: wasActive(new.privateRelay)))
        }
        if !old.route.isVPN, new.route.isVPN,
           let oip = old.exit?.ip, let nip = new.exit?.ip, oip == nip {
            out.append(.leakSuspected(org: new.exit?.org))
        }
        // Only fire on the false->true transition — the row disappearing from the menu is
        // enough signal for true->false, and true->true would just be repeat noise.
        if !old.ipv6Leak, new.ipv6Leak {
            out.append(.ipv6Leak(country: new.exit6?.countryCode, org: new.exit6?.org))
        }
        // Only the transition INTO .confirmed notifies — .suspected is dropdown-only by design
        // (confirmation-before-accusation), and confirmed→confirmed would be repeat noise.
        if old.dns.leak != .confirmed, new.dns.leak == .confirmed {
            out.append(.dnsLeakConfirmed(egressIP: new.dns.egressIP, resolver: new.dns.resolvers.first?.address))
        }
        return out
    }
}

/// Holds a "back online" event until the exit is known.
///
/// Connectivity flips back to online as soon as the reachability probe succeeds, which is
/// usually a beat before the exit lookup answers. Notifying at that instant produced
/// "Back online: ❓" — true but useless, and it read like an error. The gate swallows a
/// restore that arrives without an exit country and re-emits it with the real exit on the
/// first later state that has one. Going offline again in between drops the pending restore,
/// so a flapping link yields one honest notification, not a stale one.
public struct RestoreGate: Sendable {
    public private(set) var pending = false
    public init() {}

    public mutating func filter(_ events: [Event], new: ExitState) -> [Event] {
        var out: [Event] = []
        for event in events {
            switch event {
            case .connectivityRestored(let country, _, _) where country == nil:
                pending = true
                continue
            case .connectivityRestored:
                pending = false
            case .connectivityLost:
                pending = false
            default:
                break
            }
            out.append(event)
        }
        if pending, new.connectivity == .online, let iso = new.exit?.countryCode {
            pending = false
            out.append(.connectivityRestored(country: iso, city: new.exit?.city, org: new.exit?.org))
        }
        return out
    }
}
