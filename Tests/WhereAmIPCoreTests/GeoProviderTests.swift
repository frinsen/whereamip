import XCTest
@testable import WhereAmIPCore

final class GeoProviderTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }

    func chain() -> GeoProviderChain {
        GeoProviderChain(session: MockURLProtocol.session(), deadlineSeconds: 2)
    }
    func testPrimarySuccess() async {
        MockURLProtocol.handlers["https://ipwho.is/"] = (200, fixture("ipwhois-ok.json"))
        let info = await chain().fetch()
        XCTAssertEqual(info?.ip, "185.107.56.123")
        XCTAssertEqual(info?.countryCode, "NL")
        XCTAssertEqual(info?.org, "M247 Europe SRL")
        XCTAssertEqual(info?.provider, "ipwho.is")
    }
    func testIpwhoisSoftFailureFallsThrough() async {
        MockURLProtocol.handlers["https://ipwho.is/"] = (200, fixture("ipwhois-failed.json"))
        MockURLProtocol.handlers["https://ipapi.co/json/"] = (200, fixture("ipapi-ok.json"))
        let info = await chain().fetch()
        XCTAssertEqual(info?.provider, "ipapi.co")
        XCTAssertEqual(info?.countryCode, "DE")
    }
    func testIPOnlyLastResort() async {
        MockURLProtocol.handlers["https://ipwho.is/"] = (500, Data())
        MockURLProtocol.handlers["https://ipapi.co/json/"] = (429, Data())
        MockURLProtocol.handlers["https://api.ipify.org"] = (200, fixture("ipify-ok.json"))
        let info = await chain().fetch()
        XCTAssertEqual(info?.ip, "46.114.1.2")
        XCTAssertNil(info?.countryCode)
    }
    func testAllDeadReturnsNil() async {
        let info = await chain().fetch()   // no handlers → connection errors
        XCTAssertNil(info)
    }
    func testHardDeadlineFires() async {
        let start = Date()
        do {
            _ = try await withHardDeadline(seconds: 0.2) { () async throws -> Int in
                try await Task.sleep(nanoseconds: 10_000_000_000); return 1
            }
            XCTFail("should have thrown")
        } catch { XCTAssertLessThan(Date().timeIntervalSince(start), 2.0) }
    }
    func testLookupSpecificIP() async {
        MockURLProtocol.handlers["https://ipwho.is/5.6.7.8"] = (200, fixture("ipwhois-ok.json"))
        let info = await chain().lookup(ip: "5.6.7.8")
        XCTAssertEqual(info?.countryCode, "NL")
    }
}
