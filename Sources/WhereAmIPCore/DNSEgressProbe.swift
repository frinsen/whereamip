import Foundation
import dnssd

/// Egress-level DNS leak probe. A TXT query for o-o.myaddr.l.google.com answers with the IP
/// of the resolver that performed the lookup (the dnsleaktest.com mechanism). Sent through
/// mDNSResponder (dnssd), so it observes what real apps' lookups experience — including DoH
/// profiles and scoped/split DNS. NOTE: unlike HTTPIPFetcher this does NOT use
/// withHardDeadline — a DNSServiceRef is a C resource that Swift task cancellation can't
/// release; the timeout lives on the callback queue where the ref can be deallocated safely.
public struct DNSEgressProbe: Sendable {
    let deadline: Double
    static let beacon = "o-o.myaddr.l.google.com"
    public init(deadlineSeconds: Double = 4) { deadline = deadlineSeconds }

    public func fetch() async -> (ip: String, isIPv6: Bool)? {
        let strings = await Self.queryTXT(name: Self.beacon, timeout: deadline)
        let parsed = Self.parseAnswer(txtStrings: strings)
        Log.dns.debug("DNSEgressProbe: txt=\(strings, privacy: .public) parsed=\(parsed?.ip ?? "nil", privacy: .public)")
        return parsed
    }

    /// PURE. Prefer a bare IP (the resolver's egress); fall back to an EDNS Client Subnet
    /// echo ("edns0-client-subnet 1.2.3.0/24") — truncated but still attributable by prefix.
    static func parseAnswer(txtStrings: [String]) -> (ip: String, isIPv6: Bool)? {
        for s in txtStrings {
            if RelayRanges.ipv4ToUInt32(s) != nil { return (s, false) }
            if StackPinnedIP.isValidIPv6(s) { return (s, true) }
        }
        for s in txtStrings where s.hasPrefix("edns0-client-subnet ") {
            let p = String(s.dropFirst("edns0-client-subnet ".count))
            if p.contains("/"), p.contains(".") || p.contains(":") { return (p, p.contains(":")) }
        }
        return nil
    }

    /// PURE. TXT rdata is a sequence of length-prefixed character-strings.
    static func parseTXTRData(_ data: Data) -> [String] {
        var out: [String] = []
        var i = data.startIndex
        while i < data.endIndex {
            let len = Int(data[i]); i = data.index(after: i)
            guard let end = data.index(i, offsetBy: len, limitedBy: data.endIndex) else { break }
            if let s = String(data: data[i..<end], encoding: .utf8) { out.append(s) }
            i = end
        }
        return out
    }

    /// IMPURE dnssd bridge. Accumulates TXT strings until the callback reports no MoreComing,
    /// then resumes; a queue-scheduled timeout resumes with whatever arrived (usually []).
    /// The DNSServiceRef is always deallocated on the same queue — never leaked, never raced.
    static func queryTXT(name: String, timeout: Double) async -> [String] {
        // Confined to the single serial `queue` for its entire lifetime (assignment, mutation,
        // and deallocation all happen there) — safe despite not being provably Sendable.
        final class Box: @unchecked Sendable {
            var strings: [String] = []
            var cont: CheckedContinuation<[String], Never>?
            var sdRef: DNSServiceRef?
            func finish() {
                if let ref = sdRef { DNSServiceRefDeallocate(ref); sdRef = nil }
                cont?.resume(returning: strings); cont = nil
            }
        }
        let queue = DispatchQueue(label: "whereamip.dnsprobe")
        let box = Box()
        return await withCheckedContinuation { cont in
            queue.async {
                box.cont = cont
                let callback: DNSServiceQueryRecordReply = { _, flags, _, err, _, _, _, rdlen, rdata, _, ctx in
                    guard let ctx else { return }
                    let box = Unmanaged<Box>.fromOpaque(ctx).takeUnretainedValue()
                    if err == kDNSServiceErr_NoError, let rdata, rdlen > 0 {
                        box.strings += DNSEgressProbe.parseTXTRData(Data(bytes: rdata, count: Int(rdlen)))
                    }
                    if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0 { box.finish() }
                }
                var ref: DNSServiceRef?
                let err = DNSServiceQueryRecord(&ref, 0, 0, name,
                                               UInt16(kDNSServiceType_TXT), UInt16(kDNSServiceClass_IN),
                                               callback, Unmanaged.passUnretained(box).toOpaque())
                guard err == kDNSServiceErr_NoError, let ref else { box.finish(); return }
                box.sdRef = ref
                DNSServiceSetDispatchQueue(ref, queue)
                queue.asyncAfter(deadline: .now() + timeout) { box.finish() }
            }
        }
    }
}
