import SystemConfiguration

public enum SCServiceNamer {
    /// Display name of the network service whose live State entry owns `interface`, or nil.
    ///
    /// Field-verified 2026-08-17: NE (NetworkExtension) app VPN tunnels — Tailscale, Cloudflare
    /// WARP, Windscribe, PureVPN's app-based tunnel — register their InterfaceName ONLY under
    /// the service's IPv6 or DNS State keys, never under IPv4 (empirically verified on this
    /// machine: Tailscale's utun16 appears solely under the .../DNS State key). The original
    /// IPv4-only key pattern therefore silently failed to name any NE tunnel — widened to also
    /// scan IPv6 and DNS State entries. Uses three separate CopyKeyList calls, concatenated,
    /// rather than a single regex-alternation pattern: simpler to reason about and doesn't
    /// depend on SCDynamicStore's exact regex dialect supporting `(a|b|c)`.
    public static func serviceName(forInterface interface: String) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "whereamip" as CFString, nil, nil) else { return nil }
        var candidates: [(key: String, dict: [String: Any])] = []
        for suffix in ["IPv4", "IPv6", "DNS"] {
            guard let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/\(suffix)" as CFString) as? [String] else { continue }
            for key in keys {
                if let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] {
                    candidates.append((key, dict))
                }
            }
        }
        guard let serviceID = matchingServiceID(candidates: candidates, interface: interface) else { return nil }
        // key: State:/Network/Service/<UUID>/{IPv4,IPv6,DNS} → Setup:/Network/Service/<UUID>
        let setupKey = "Setup:/Network/Service/\(serviceID)"
        guard let setup = SCDynamicStoreCopyValue(store, setupKey as CFString) as? [String: Any],
              let name = setup["UserDefinedName"] as? String else { return nil }
        return name
    }

    /// PURE, tested: scan candidate (key, dict) pairs — in caller-supplied order — for the
    /// first whose InterfaceName equals `interface`, and return that service's UUID (parsed
    /// out of its State: key). Dedupe by service UUID: a service may now legitimately appear
    /// more than once in `candidates` (e.g. matching both its IPv6 and DNS keys), but the scan
    /// stops at the first hit, so it's only ever reported once — "first match wins" per the
    /// field verification above.
    static func matchingServiceID(candidates: [(key: String, dict: [String: Any])], interface: String) -> String? {
        for (key, dict) in candidates {
            guard dict["InterfaceName"] as? String == interface else { continue }
            let parts = key.split(separator: "/")
            guard parts.count >= 4 else { continue }
            return String(parts[3])
        }
        return nil
    }
}
