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

    // MARK: - the command we hand people, per install channel

    /// Field bug: a tester ran `brew upgrade whereamip` and was told 0.4.2 was already
    /// installed, hours after 0.5 shipped. WhereAmIP lives in a third-party TAP — a git
    /// clone that `brew upgrade` does not reliably pull — so without an explicit
    /// `brew update` first, the upgrade can silently no-op on a stale clone.
    ///
    /// The command is per-channel now, but this anti-regression point is unchanged: the
    /// Homebrew command must never shrink back to the bare upgrade.
    func testHomebrewUpgradeCommandRefreshesTheTapFirst() {
        let command = UpdateChecker.upgradeCommand(for: .homebrew)
        XCTAssertTrue(command?.hasPrefix("brew update &&") ?? false,
                      "must not regress to the bare upgrade: \(command ?? "nil")")
        XCTAssertEqual(command, "brew update && brew upgrade whereamip")
    }

    /// Exactly the command the port submission documents (macports/SUBMISSION.md §6.4) —
    /// the one the Portfile's `post-patch` block used to rewrite the Homebrew string into,
    /// and which this function replaces. Same shape and same reason as `brew update &&`:
    /// `port upgrade` against a ports tree that has not been synced sees no new version.
    func testMacPortsUpgradeCommandSelfUpdatesFirst() {
        let command = UpdateChecker.upgradeCommand(for: .macports)
        XCTAssertTrue(command?.hasPrefix("sudo port selfupdate &&") ?? false,
                      "must not regress to the bare upgrade: \(command ?? "nil")")
        XCTAssertEqual(command, "sudo port selfupdate && sudo port upgrade whereamip")
    }

    /// A zip install has no package manager to drive, so there is no command to hand
    /// anyone — nil is what makes the dropdown row open the releases page instead of
    /// putting a command that would not work on the clipboard.
    func testDirectInstallHasNoUpgradeCommand() {
        XCTAssertNil(UpdateChecker.upgradeCommand(for: .direct))
    }

    func testEveryChannelIsAnsweredWithoutCrashing() {
        for channel in InstallChannel.allCases {
            let command = UpdateChecker.upgradeCommand(for: channel)
            if let command { XCTAssertFalse(command.isEmpty, "\(channel) has an empty command") }
        }
    }

    func testReleasesURLIsTheLatestReleasePage() {
        XCTAssertEqual(UpdateChecker.releasesURL, "https://github.com/frinsen/whereamip/releases/latest")
        XCTAssertNotNil(URL(string: UpdateChecker.releasesURL))
    }
}
