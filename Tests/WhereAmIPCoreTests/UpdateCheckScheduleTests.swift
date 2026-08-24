import XCTest
@testable import WhereAmIPCore

/// The opportunistic update check: may a full refresh spend a GitHub request right now?
///
/// Pure decision, injected clock — which is what makes it testable at all, since the thing
/// that acts on it (AppDelegate) has no test target. The daily timer stays as the backstop;
/// this only shortens the window between a release appearing and the row showing up.
final class UpdateCheckScheduleTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var interval: TimeInterval { UpdateCheckSchedule.opportunisticInterval }

    func testSixHoursIsTheThrottle() {
        XCTAssertEqual(interval, 6 * 60 * 60)
    }

    func testAFirstEverRefreshMayCheck() {
        XCTAssertTrue(UpdateCheckSchedule.shouldAttempt(lastAttempt: nil, now: now, enabled: true))
    }

    func testARecentAttemptBlocksTheCheck() {
        for minutesAgo in [0.0, 1.0, 60.0, 359.0] {
            let last = now.addingTimeInterval(-minutesAgo * 60)
            XCTAssertFalse(UpdateCheckSchedule.shouldAttempt(lastAttempt: last, now: now, enabled: true),
                           "\(minutesAgo) minutes ago should still be throttled")
        }
    }

    func testAStaleAttemptAllowsTheCheck() {
        for hoursAgo in [6.0, 7.0, 25.0] {
            let last = now.addingTimeInterval(-hoursAgo * 3600)
            XCTAssertTrue(UpdateCheckSchedule.shouldAttempt(lastAttempt: last, now: now, enabled: true),
                          "\(hoursAgo)h should be stale enough")
        }
    }

    func testTheBoundaryIsInclusive() {
        XCTAssertTrue(UpdateCheckSchedule.shouldAttempt(lastAttempt: now.addingTimeInterval(-interval),
                                                        now: now, enabled: true))
        XCTAssertFalse(UpdateCheckSchedule.shouldAttempt(lastAttempt: now.addingTimeInterval(-interval + 1),
                                                         now: now, enabled: true))
    }

    /// The setting is absolute — the README promises no request is ever made when it is off,
    /// and an opportunistic path is exactly where that promise would erode by accident.
    func testDisabledNeverChecksHoweverStaleTheClockIs() {
        XCTAssertFalse(UpdateCheckSchedule.shouldAttempt(lastAttempt: nil, now: now, enabled: false))
        XCTAssertFalse(UpdateCheckSchedule.shouldAttempt(lastAttempt: now.addingTimeInterval(-99 * 3600),
                                                         now: now, enabled: false))
    }

    /// A timestamp in the future means the clock moved backwards (travel, NTP correction, a
    /// wake from a long sleep). Waiting six hours from a future instant could suppress the
    /// check for far longer than the throttle intends, so a nonsensical interval counts as
    /// stale — one extra request is the cheaper mistake.
    func testAFutureTimestampCountsAsStaleRatherThanBlockingForHours() {
        XCTAssertTrue(UpdateCheckSchedule.shouldAttempt(lastAttempt: now.addingTimeInterval(3600),
                                                        now: now, enabled: true))
    }
}
