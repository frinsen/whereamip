import WhereAmIPCore

public enum NotificationText {
    static func flag(_ iso: String?) -> String {
        iso.flatMap { Flags.emoji(countryCode: $0) } ?? L10n.string(.notificationFlagUnknown)
    }
    public static func text(for event: Event) -> (title: String, body: String)? {
        switch event {
        case .countryChanged(let from, let to, let vpnName):
            return (L10n.string(.notificationCountryChangedTitle, flag(from), flag(to)),
                    vpnName.map { L10n.string(.notificationCountryChangedBodyVPN, $0) }
                        ?? L10n.string(.notificationCountryChangedBody))
        case .ipChanged(let country, let fromOrg, let toOrg):
            return (L10n.string(.notificationIPChangedTitle, flag(country)),
                    [fromOrg, toOrg].compactMap { $0 }.joined(separator: " → "))
        case .connectivityLost(let hijack):
            return (L10n.string(.notificationOfflineTitle),
                    hijack ? L10n.string(.notificationOfflineBodyHijack)
                           : L10n.string(.notificationOfflineBody))
        case .connectivityRestored(let country, let city, let org):
            return (L10n.string(.notificationOnlineTitle, flag(country), city ?? ""),
                    org ?? "")
        case .leakSuspected(let org):
            return (L10n.string(.notificationLeakTitle),
                    L10n.string(.notificationLeakBody, org ?? L10n.string(.notificationOrgUnknown)))
        case .privateRelayToggled(let active):
            return (L10n.string(active ? .notificationRelayOnTitle : .notificationRelayOffTitle),
                    L10n.string(active ? .notificationRelayOnBody : .notificationRelayOffBody))
        case .vpnRouteChanged:
            return nil   // route changes alone are visible in the flag; don't notify
        case .ipv6Leak(_, let org):
            return (L10n.string(.notificationIPv6Title),
                    L10n.string(.notificationIPv6Body, org ?? L10n.string(.notificationOrgUnknown)))
        case .dnsLeakConfirmed(let egressIP, _):
            return (L10n.string(.notificationDNSTitle),
                    L10n.string(.notificationDNSBody)
                    + (egressIP.map { L10n.string(.notificationDNSBodyEgress, $0) } ?? ""))
        }
    }
}
