import XCTest
@testable import WhereAmIPCore

final class UpdateCheckerTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }

    let endpoint = "https://api.github.com/repos/frinsen/whereamip/releases/latest"

    func checker() -> UpdateChecker {
        UpdateChecker(session: MockURLProtocol.session(), deadlineSeconds: 2)
    }

    func testParsesTagNameStrippingLeadingV() async {
        MockURLProtocol.handlers[endpoint] = (200, #"{"tag_name":"v0.3"}"#.data(using: .utf8)!)
        let v = await checker().latestVersion()
        XCTAssertEqual(v, "0.3")
    }
    func testNotFoundReturnsNil() async {
        MockURLProtocol.handlers[endpoint] = (404, Data())
        let v = await checker().latestVersion()
        XCTAssertNil(v)
    }
    func testGarbageJSONReturnsNil() async {
        MockURLProtocol.handlers[endpoint] = (200, "not json".data(using: .utf8)!)
        let v = await checker().latestVersion()
        XCTAssertNil(v)
    }
}
