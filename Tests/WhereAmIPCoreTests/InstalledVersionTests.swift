import XCTest
@testable import WhereAmIPCore

final class InstalledVersionTests: XCTestCase {

    // MARK: - optAppPath derivation

    func testOptAppPathHappyCellarPathAppleSilicon() {
        let bundle = "/opt/homebrew/Cellar/whereamip/0.3.1/libexec/WhereAmIP.app"
        XCTAssertEqual(InstalledVersion.optAppPath(fromBundlePath: bundle),
                        "/opt/homebrew/opt/whereamip/libexec/WhereAmIP.app")
    }

    func testOptAppPathIntelPrefix() {
        let bundle = "/usr/local/Cellar/whereamip/0.3.1/libexec/WhereAmIP.app"
        XCTAssertEqual(InstalledVersion.optAppPath(fromBundlePath: bundle),
                        "/usr/local/opt/whereamip/libexec/WhereAmIP.app")
    }

    func testOptAppPathNonCellarReturnsNil() {
        XCTAssertNil(InstalledVersion.optAppPath(fromBundlePath: "/tmp/some/dist/WhereAmIP.app"))
        XCTAssertNil(InstalledVersion.optAppPath(fromBundlePath: "/Applications/WhereAmIP.app"))
    }

    func testOptAppPathNestedWeirdness() {
        // "rest" can be arbitrarily nested; make sure everything after <version>/ is preserved verbatim.
        let bundle = "/opt/homebrew/Cellar/whereamip/0.3.1/libexec/deep/nested/WhereAmIP.app"
        XCTAssertEqual(InstalledVersion.optAppPath(fromBundlePath: bundle),
                        "/opt/homebrew/opt/whereamip/libexec/deep/nested/WhereAmIP.app")
    }

    func testOptAppPathWrongFormulaNameReturnsNil() {
        let bundle = "/opt/homebrew/Cellar/some-other-formula/0.3.1/libexec/WhereAmIP.app"
        XCTAssertNil(InstalledVersion.optAppPath(fromBundlePath: bundle))
    }

    // MARK: - onDisk

    func testOnDiskReadsVersionFromOptPlist() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalledVersionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Running bundle path is Cellar-style (mimics the real world: process still
        // running from the old Cellar keg after `brew upgrade` replaced the opt symlink).
        let runningBundlePath = tmp.appendingPathComponent("Cellar/whereamip/0.1/libexec/WhereAmIP.app").path

        // Installed copy lives at the stable opt path.
        let optAppDir = tmp.appendingPathComponent("opt/whereamip/libexec/WhereAmIP.app")
        let contentsDir = optAppDir.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": "9.9"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsDir.appendingPathComponent("Info.plist"))

        let result = InstalledVersion.onDisk(bundlePath: runningBundlePath)
        XCTAssertEqual(result?.version, "9.9")
        XCTAssertEqual(result?.appPath, optAppDir.path)
    }

    func testOnDiskMissingPlistReturnsNil() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalledVersionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runningBundlePath = tmp.appendingPathComponent("Cellar/whereamip/0.1/libexec/WhereAmIP.app").path
        // Deliberately do not create anything at the opt path.
        XCTAssertNil(InstalledVersion.onDisk(bundlePath: runningBundlePath))
    }

    func testOnDiskNonCellarBundlePathReturnsNil() {
        XCTAssertNil(InstalledVersion.onDisk(bundlePath: "/Applications/WhereAmIP.app"))
    }
}
