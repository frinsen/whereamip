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

    // MARK: - the command we hand people

    /// Field bug: a tester ran `brew upgrade whereamip` and was told 0.4.2 was already
    /// installed, hours after 0.5 shipped. WhereAmIP lives in a third-party TAP — a git
    /// clone that `brew upgrade` does not reliably pull — so without an explicit
    /// `brew update` first, the upgrade can silently no-op on a stale clone.
    func testUpgradeCommandRefreshesTheTapFirst() {
        XCTAssertTrue(UpdateChecker.upgradeCommand.hasPrefix("brew update &&"),
                      "must not regress to the bare upgrade: \(UpdateChecker.upgradeCommand)")
        XCTAssertEqual(UpdateChecker.upgradeCommand, "brew update && brew upgrade whereamip")
    }
}
