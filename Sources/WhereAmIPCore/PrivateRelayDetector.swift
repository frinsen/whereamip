import Foundation

private final class RelayRangesBundleToken {}

public struct RelayRanges: Sendable {
    struct V4 { let network: UInt32; let maskBits: Int }
    let v4: [V4]
    public init(csv: String) {
        var out: [V4] = []
        for line in csv.split(separator: "\n") {
            guard let cidr = line.split(separator: ",").first, cidr.contains("."),
                  let slash = cidr.firstIndex(of: "/"),
                  let bits = Int(cidr[cidr.index(after: slash)...]),
                  (0...32).contains(bits),
                  let net = RelayRanges.ipv4ToUInt32(String(cidr[..<slash])) else { continue }
            out.append(V4(network: net, maskBits: bits))
        }
        v4 = out
    }
    public static func bundled() -> RelayRanges {
        let resourceBundle = findResourceBundle()
        guard let url = resourceBundle.url(forResource: "Resources/relay-ranges", withExtension: "csv"),
              let csv = try? String(contentsOf: url, encoding: .utf8) else { return RelayRanges(csv: "") }
        return RelayRanges(csv: csv)
    }

    private static func findResourceBundle() -> Bundle {
        let bundleName = "whereamip_WhereAmIPCore.bundle"
        let token = Bundle(for: RelayRangesBundleToken.self)
        let candidates = [
            Bundle.main.resourceURL,
            token.resourceURL,
            Bundle.main.bundleURL as URL?,
            token.bundleURL as URL?,
            token.bundleURL.deletingLastPathComponent() as URL?,  // For tests: .../debug/
            token.resourceURL?.deletingLastPathComponent().deletingLastPathComponent(),
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ]
        .compactMap { $0 }
        .map { $0.appendingPathComponent(bundleName) }
        for candidate in candidates {
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        // No bundle found — return token to safely fall back to empty CSV, never crash.
        return token
    }
    public func containsIPv4(_ ip: String) -> Bool {
        guard let v = RelayRanges.ipv4ToUInt32(ip) else { return false }
        return v4.contains { range in
            let mask: UInt32 = range.maskBits == 0 ? 0 : ~UInt32(0) << (32 - range.maskBits)
            return (v & mask) == (range.network & mask)
        }
    }
    static func ipv4ToUInt32(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return nil }
        return (UInt32(parts[0]) << 24) | (UInt32(parts[1]) << 16) | (UInt32(parts[2]) << 8) | UInt32(parts[3])
    }
}

public enum PrivateRelayDetector {
    public static func decide(httpsIP: String?, httpIP: String?, ranges: RelayRanges) -> PrivateRelay {
        guard let httpIP else {
            Log.relay.debug("decide: httpIP=nil -> unknown")
            return .unknown
        }
        if ranges.containsIPv4(httpIP), httpIP != httpsIP {
            Log.relay.debug("decide: httpIP=\(httpIP, privacy: .public) httpsIP=\(httpsIP ?? "nil", privacy: .public) -> active")
            return .active(egressIP: httpIP, egressCountry: nil)
        }
        Log.relay.debug("decide: httpIP=\(httpIP, privacy: .public) httpsIP=\(httpsIP ?? "nil", privacy: .public) -> inactive")
        return .inactive
    }
}

public struct HTTPIPFetcher: Sendable {
    let session: URLSession
    let deadline: Double
    static let url = URL(string: "http://api.ipify.org")!
    public init(session: URLSession = URLSession(configuration: .default), deadlineSeconds: Double = 4) {
        self.session = session; self.deadline = deadlineSeconds
    }
    public func fetch() async -> String? {
        let s = try? await withHardDeadline(seconds: deadline) { [session] in
            let (data, resp) = try await session.data(from: Self.url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  RelayRanges.ipv4ToUInt32(s) != nil else { throw BadResponse() }
            return s
        }
        Log.relay.debug("HTTPIPFetcher: httpIP=\(s ?? "nil", privacy: .public)")
        return s
    }
}
