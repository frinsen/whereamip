import UserNotifications
import XCTest
@testable import WhereAmIPCore

final class NotificationPermissionTests: XCTestCase {
    func testNotDeterminedRequests() {
        XCTAssertEqual(NotificationPermission.action(for: .notDetermined), .request)
    }
    func testDeniedOpensSystemSettings() {
        XCTAssertEqual(NotificationPermission.action(for: .denied), .openSystemSettings)
    }
    func testAuthorizedEnablesDirectly() {
        XCTAssertEqual(NotificationPermission.action(for: .authorized), .enableDirectly)
    }
    func testProvisionalEnablesDirectly() {
        // .ephemeral (App Clips only) is `@available(macOS, unavailable)`, so
        // it can't be referenced in a macOS test target at all — the `default`
        // branch in NotificationPermission.action(for:) covers it anyway.
        XCTAssertEqual(NotificationPermission.action(for: .provisional), .enableDirectly)
    }
}
