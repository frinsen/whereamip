import XCTest
@testable import WhereAmIPCore

final class StackPinnedIPTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }

    func stackIP() -> StackPinnedIP { StackPinnedIP(session: MockURLProtocol.session(), deadlineSeconds: 2) }

    func testFetch4ParsesPlainTextIPv4() async {
        MockURLProtocol.handlers["https://api4.ipify.org"] = (200, "203.0.113.7".data(using: .utf8)!)
        let ip = await stackIP().fetch4()
        XCTAssertEqual(ip, "203.0.113.7")
    }
    func testFetch4TrimsWhitespace() async {
        MockURLProtocol.handlers["https://api4.ipify.org"] = (200, "203.0.113.7\n".data(using: .utf8)!)
        let ip = await stackIP().fetch4()
        XCTAssertEqual(ip, "203.0.113.7")
    }
    func testFetch4RejectsNonIPv4Body() async {
        MockURLProtocol.handlers["https://api4.ipify.org"] = (200, "not-an-ip".data(using: .utf8)!)
        let ip = await stackIP().fetch4()
        XCTAssertNil(ip)
    }
    func testFetch4NilOnHTTPError() async {
        MockURLProtocol.handlers["https://api4.ipify.org"] = (500, Data())
        let ip = await stackIP().fetch4()
        XCTAssertNil(ip)
    }
    func testFetch4NilOnConnectionFailure() async {
        // No handler registered -> MockURLProtocol fails the request. This simulates a
        // v6-only (or v4-broken) network where api4 fails fast -- the expected signal for
        // a v4 leak-detection probe, not an error to surface.
        let ip = await stackIP().fetch4()
        XCTAssertNil(ip)
    }
    func testFetch6ParsesPlainTextIPv6() async {
        MockURLProtocol.handlers["https://api6.ipify.org"] = (200, "2001:db8::1".data(using: .utf8)!)
        let ip = await stackIP().fetch6()
        XCTAssertEqual(ip, "2001:db8::1")
    }
    func testFetch6TrimsWhitespace() async {
        MockURLProtocol.handlers["https://api6.ipify.org"] = (200, "2001:db8::1\n".data(using: .utf8)!)
        let ip = await stackIP().fetch6()
        XCTAssertEqual(ip, "2001:db8::1")
    }
    func testFetch6RejectsNonIPv6Body() async {
        MockURLProtocol.handlers["https://api6.ipify.org"] = (200, "203.0.113.7".data(using: .utf8)!)
        let ip = await stackIP().fetch6()
        XCTAssertNil(ip)   // no ':' -> not a v6 literal
    }
    func testFetch6NilOnHTTPError() async {
        MockURLProtocol.handlers["https://api6.ipify.org"] = (500, Data())
        let ip = await stackIP().fetch6()
        XCTAssertNil(ip)
    }
    func testFetch6NilOnConnectionFailure() async {
        // No handler registered -> connection error. This is the expected signal on a
        // v4-only network (e.g. the field case this feature targets): api6 fails fast,
        // and that failure alone must never be treated as a confirmed leak upstream.
        let ip = await stackIP().fetch6()
        XCTAssertNil(ip)
    }
    func testUsesDistinctHostsForEachFamily() async {
        MockURLProtocol.handlers["https://api4.ipify.org"] = (200, "203.0.113.7".data(using: .utf8)!)
        MockURLProtocol.handlers["https://api6.ipify.org"] = (200, "2001:db8::1".data(using: .utf8)!)
        let s = stackIP()
        _ = await s.fetch4()
        _ = await s.fetch6()
        XCTAssertTrue(MockURLProtocol.requestLog.contains { $0.absoluteString.hasPrefix("https://api4.ipify.org") })
        XCTAssertTrue(MockURLProtocol.requestLog.contains { $0.absoluteString.hasPrefix("https://api6.ipify.org") })
    }
}
