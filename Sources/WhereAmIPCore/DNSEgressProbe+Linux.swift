#if os(Linux)
import CLinuxSupport
import Foundation

/// The Linux transport under `DNSEgressProbe` and `DNSEgressEnumerator`: one TXT lookup
/// through glibc's resolver, which reads /etc/resolv.conf — on systemd-resolved machines
/// that is the local stub, so the query takes exactly the path every application's lookup
/// takes (per-link routing, VPN-pushed resolvers, DNS-over-TLS), the role mDNSResponder
/// plays on macOS.
extension DNSEgressProbe {
    /// Same contract as the macOS dnssd bridge: whatever TXT strings arrived, `[]` on any
    /// failure or when `timeout` passes first. The blocking resolver call runs on its own
    /// thread; a timeout resumes the caller and lets that thread finish on its own — it is
    /// bounded too, by the resolver's own per-attempt timeout.
    static func queryTXT(name: String, timeout: Double) async -> [String] {
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<[String], Never>?
            init(_ continuation: CheckedContinuation<[String], Never>) { self.continuation = continuation }
            func resume(_ strings: [String]) {
                lock.lock()
                let pending = continuation
                continuation = nil
                lock.unlock()
                pending?.resume(returning: strings)
            }
        }
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            let attemptSeconds = Int32(max(1, Int(timeout.rounded(.up))))
            DispatchQueue.global().async {
                var answer = [UInt8](repeating: 0, count: 4096)
                let length = Int(whereamip_res_query(name, Int32(txtType), attemptSeconds,
                                                     &answer, Int32(answer.count)))
                // A response larger than the buffer reports its full size; only what fit is real.
                once.resume(length > 0 ? parseTXTResponse(Array(answer.prefix(min(length, answer.count)))) : [])
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.resume([]) }
        }
    }

    static let txtType: UInt16 = 16
    static let classIN: UInt16 = 1

    /// PURE, tested. The TXT strings of every IN/TXT answer record in a raw DNS response
    /// (RFC 1035 §4.1), in answer order. Anything else in the answer section — a CNAME chain
    /// in front of the TXT record, say — is skipped. Malformed or truncated input yields
    /// whatever parsed cleanly before the damage, never a crash: this is network data.
    static func parseTXTResponse(_ message: [UInt8]) -> [String] {
        guard message.count >= 12 else { return [] }
        func u16(_ i: Int) -> UInt16? {
            guard i >= 0, i + 1 < message.count else { return nil }
            return UInt16(message[i]) << 8 | UInt16(message[i + 1])
        }
        guard let questions = u16(4), let answers = u16(6) else { return [] }
        var offset = 12
        for _ in 0..<questions {
            guard let end = skipName(message, from: offset) else { return [] }
            offset = end + 4                              // QTYPE + QCLASS
        }
        var strings: [String] = []
        for _ in 0..<answers {
            guard let end = skipName(message, from: offset),
                  let type = u16(end), let rrClass = u16(end + 2),
                  let rdLength = u16(end + 8) else { break }
            let rdStart = end + 10
            let rdEnd = rdStart + Int(rdLength)
            guard rdEnd <= message.count else { break }
            if type == txtType, rrClass == classIN {
                strings += parseTXTRData(Data(message[rdStart..<rdEnd]))
            }
            offset = rdEnd
        }
        return strings
    }

    /// Index just past a (possibly compressed) domain name starting at `start`, or nil when
    /// the name runs off the end of the message. A compression pointer ends the name in two
    /// bytes, so the walk never follows pointers and cannot loop.
    static func skipName(_ message: [UInt8], from start: Int) -> Int? {
        var i = start
        while i < message.count {
            let length = Int(message[i])
            if length == 0 { return i + 1 }
            if length & 0xC0 == 0xC0 { return i + 2 <= message.count ? i + 2 : nil }
            guard length & 0xC0 == 0 else { return nil }  // reserved label types
            i += 1 + length
        }
        return nil
    }
}
#endif
