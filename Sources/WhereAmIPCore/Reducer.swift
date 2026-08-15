public enum Event: Equatable, Sendable {
    case countryChanged(from: String?, to: String?, vpnName: String?)
    case ipChanged(country: String?, fromOrg: String?, toOrg: String?)
    case connectivityLost(hijackSuspected: Bool)
    case connectivityRestored(country: String?, city: String?, org: String?)
    case vpnRouteChanged(vpnName: String?, interface: String?)
    case privateRelayToggled(active: Bool)
    case leakSuspected(org: String?)
    case ipv6Leak(country: String?, org: String?)
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
        return out
    }
}
