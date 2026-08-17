import XCTest
@testable import WhereAmIPCore

final class ApplicationsLinkTests: XCTestCase {
    var tmp: URL!
    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApplicationsLinkTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    var linkPath: String { tmp.appendingPathComponent("WhereAmIP.app").path }
    var cellarBundlePath: String {
        tmp.appendingPathComponent("Cellar/whereamip/0.3.2/libexec/WhereAmIP.app").path
    }
    var expectedOptPath: String {
        tmp.appendingPathComponent("opt/whereamip/libexec/WhereAmIP.app").path
    }

    // MARK: - targetPath

    func testTargetPathCellarDerivesOptPath() {
        XCTAssertEqual(ApplicationsLink.targetPath(fromBundlePath: cellarBundlePath), expectedOptPath)
    }
    func testTargetPathNonCellarReturnsSelf() {
        let devBuild = "/tmp/dist/WhereAmIP.app"
        XCTAssertEqual(ApplicationsLink.targetPath(fromBundlePath: devBuild), devBuild)
    }
    func testTargetPathEmptyReturnsNil() {
        XCTAssertNil(ApplicationsLink.targetPath(fromBundlePath: ""))
    }

    // MARK: - appPath(fromExecutablePath:) — CLI's own resolution

    func testAppPathResolvesThroughSymlinkChainFromBinDir() throws {
        // Mimic the real Homebrew layout:
        //   <prefix>/bin/whereamip -> ../Cellar/whereamip/<v>/bin/whereamip -> ../libexec/cli/whereamip
        let fm = FileManager.default
        let cliDir = tmp.appendingPathComponent("Cellar/whereamip/0.3.2/libexec/cli")
        try fm.createDirectory(at: cliDir, withIntermediateDirectories: true)
        let realExe = cliDir.appendingPathComponent("whereamip")
        try Data().write(to: realExe)

        let cellarBinDir = tmp.appendingPathComponent("Cellar/whereamip/0.3.2/bin")
        try fm.createDirectory(at: cellarBinDir, withIntermediateDirectories: true)
        let cellarBinLink = cellarBinDir.appendingPathComponent("whereamip")
        try fm.createSymbolicLink(atPath: cellarBinLink.path, withDestinationPath: "../libexec/cli/whereamip")

        let prefixBinDir = tmp.appendingPathComponent("bin")
        try fm.createDirectory(at: prefixBinDir, withIntermediateDirectories: true)
        let prefixBinLink = prefixBinDir.appendingPathComponent("whereamip")
        try fm.createSymbolicLink(atPath: prefixBinLink.path,
                                   withDestinationPath: "../Cellar/whereamip/0.3.2/bin/whereamip")

        XCTAssertEqual(ApplicationsLink.appPath(fromExecutablePath: prefixBinLink.path), expectedOptPath)
        // Also resolvable when invoked directly from the Cellar libexec/cli path (no symlink hop).
        XCTAssertEqual(ApplicationsLink.appPath(fromExecutablePath: realExe.path), expectedOptPath)
    }
    func testAppPathNonCellarReturnsNil() {
        XCTAssertNil(ApplicationsLink.appPath(fromExecutablePath: "/usr/local/bin/whereamip"))
    }
    func testAppPathEmptyReturnsNil() {
        XCTAssertNil(ApplicationsLink.appPath(fromExecutablePath: ""))
    }

    // MARK: - isLinked / setLinked

    func testInitiallyNotLinked() {
        XCTAssertFalse(ApplicationsLink.isLinked(linkPath: linkPath))
    }
    func testSetLinkedTrueCreatesSymlinkToTarget() throws {
        try ApplicationsLink.setLinked(true, bundlePath: cellarBundlePath, linkPath: linkPath)
        XCTAssertTrue(ApplicationsLink.isLinked(linkPath: linkPath))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linkPath), expectedOptPath)
    }
    func testSetLinkedTrueIsIdempotent() throws {
        try ApplicationsLink.setLinked(true, bundlePath: cellarBundlePath, linkPath: linkPath)
        try ApplicationsLink.setLinked(true, bundlePath: cellarBundlePath, linkPath: linkPath)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linkPath), expectedOptPath)
    }
    func testSetLinkedTrueRepointsStaleSymlink() throws {
        // Create a symlink to some other (stale) target first.
        try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: "/nowhere/stale.app")
        try ApplicationsLink.setLinked(true, bundlePath: cellarBundlePath, linkPath: linkPath)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linkPath), expectedOptPath)
    }
    func testSetLinkedFalseRemovesSymlink() throws {
        try ApplicationsLink.setLinked(true, bundlePath: cellarBundlePath, linkPath: linkPath)
        try ApplicationsLink.setLinked(false, bundlePath: cellarBundlePath, linkPath: linkPath)
        XCTAssertFalse(ApplicationsLink.isLinked(linkPath: linkPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkPath))
    }
    func testSetLinkedFalseWhenNothingThereIsANoOp() throws {
        XCTAssertNoThrow(try ApplicationsLink.setLinked(false, bundlePath: cellarBundlePath, linkPath: linkPath))
    }
    func testSetLinkedRefusesToTouchRealDirectory() throws {
        try FileManager.default.createDirectory(atPath: linkPath, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ApplicationsLink.setLinked(false, bundlePath: cellarBundlePath, linkPath: linkPath)) {
            XCTAssertEqual($0 as? ApplicationsLinkError, .pathIsNotSymlink(linkPath))
        }
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkPath, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        XCTAssertThrowsError(try ApplicationsLink.setLinked(true, bundlePath: cellarBundlePath, linkPath: linkPath)) {
            XCTAssertEqual($0 as? ApplicationsLinkError, .pathIsNotSymlink(linkPath))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkPath, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }
    func testIsLinkedTrueForRealDirectory() throws {
        try FileManager.default.createDirectory(atPath: linkPath, withIntermediateDirectories: true)
        XCTAssertTrue(ApplicationsLink.isLinked(linkPath: linkPath))
    }
    func testSetLinkedTrueThrowsWhenTargetUndeterminable() {
        XCTAssertThrowsError(try ApplicationsLink.setLinked(true, bundlePath: "", linkPath: linkPath)) {
            XCTAssertEqual($0 as? ApplicationsLinkError, .cannotDetermineTarget)
        }
    }
}
