import SystemConfiguration

public enum SCServiceNamer {
    /// Display name of the network service whose live State entry owns `interface`, or nil.
    public static func serviceName(forInterface interface: String) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "whereamip" as CFString, nil, nil) else { return nil }
        guard let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString) as? [String] else { return nil }
        for key in keys {
            guard let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  dict["InterfaceName"] as? String == interface else { continue }
            // key: State:/Network/Service/<UUID>/IPv4 → Setup:/Network/Service/<UUID>
            let parts = key.split(separator: "/")
            guard parts.count >= 4 else { continue }
            let setupKey = "Setup:/Network/Service/\(parts[3])"
            if let setup = SCDynamicStoreCopyValue(store, setupKey as CFString) as? [String: Any],
               let name = setup["UserDefinedName"] as? String { return name }
        }
        return nil
    }
}
