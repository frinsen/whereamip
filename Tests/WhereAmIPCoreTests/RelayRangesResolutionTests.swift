import XCTest
@testable import WhereAmIPCore

/// Regression coverage for the distribution seam where a brew-installed CLI
/// (bin/whereamip, a symlink into libexec/cli/) could fail to locate
/// whereamip_WhereAmIPCore.bundle next to it and silently fall back to an
/// empty RelayRanges — making Private Relay detection confidently wrong
/// instead of merely unknown.
///
/// This test proves the bundled CSV resolves and parses to a non-empty,
/// correctly-decoded range set in the normal dev/test execution context.
/// The symlink-resolution path itself (bin/whereamip -> libexec/cli/whereamip,
/// with whereamip_WhereAmIPCore.bundle alongside the real binary in
/// libexec/cli/) was additionally verified by replicating that exact layout
/// in a temp directory and running the symlinked binary directly — see the
/// final-fix report for that run's output. It isn't practical to exercise
/// that path from inside `swift test`, since bundle resolution keys off
/// Bundle.main / the real host executable location, not the test runner.
final class RelayRangesResolutionTests: XCTestCase {
    func testBundledRangesAreNonEmptyAndParsed() {
        let ranges = RelayRanges.bundled()
        XCTAssertFalse(ranges.v4.isEmpty,
                        "RelayRanges.bundled() returned zero ranges — resource bundle not found or CSV failed to parse")
        // Known first entry of Sources/WhereAmIPCore/Resources/relay-ranges.csv
        XCTAssertTrue(ranges.containsIPv4("104.28.100.10"))
    }
}
