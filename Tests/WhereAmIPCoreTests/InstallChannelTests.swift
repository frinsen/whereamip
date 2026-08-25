import XCTest
@testable import WhereAmIPCore

/// Path shapes here are the REAL ones the three distribution channels produce,
/// not invented ones: the Homebrew formula installs into `<prefix>/Cellar/whereamip/<version>/`
/// and links `<prefix>/opt/whereamip`, the MacPorts Portfile destroots the app into
/// `${applications_dir}` (`/Applications/MacPorts`) and the CLI into
/// `${prefix}/libexec/${name}` (`/opt/local/libexec/whereamip`), and the release zip
/// lands wherever the user dragged it.
final class InstallChannelTests: XCTestCase {

    // MARK: - Homebrew

    func testCellarAppleSiliconIsHomebrew() {
        XCTAssertEqual(InstallChannel.detect(path: "/opt/homebrew/Cellar/whereamip/0.5.5/libexec/WhereAmIP.app"),
                       .homebrew)
    }

    func testCellarIntelPrefixIsHomebrew() {
        XCTAssertEqual(InstallChannel.detect(path: "/usr/local/Cellar/whereamip/0.5.5/libexec/WhereAmIP.app"),
                       .homebrew)
    }

    func testCellarCLIPathIsHomebrew() {
        XCTAssertEqual(InstallChannel.detect(path: "/opt/homebrew/Cellar/whereamip/0.5.5/libexec/cli/whereamip"),
                       .homebrew)
    }

    /// The stable `opt` path is what `/Applications/WhereAmIP.app` is symlinked at
    /// (ApplicationsLink.targetPath) and what the app reports as its bundle path when
    /// launched through that symlink — it is a Homebrew install even though no `Cellar`
    /// component is left in it.
    func testOptPathIsHomebrew() {
        XCTAssertEqual(InstallChannel.detect(path: "/opt/homebrew/opt/whereamip/libexec/WhereAmIP.app"),
                       .homebrew)
        XCTAssertEqual(InstallChannel.detect(path: "/usr/local/opt/whereamip/libexec/WhereAmIP.app"),
                       .homebrew)
    }

    func testCellarOfAnotherFormulaIsNotHomebrew() {
        XCTAssertEqual(InstallChannel.detect(path: "/opt/homebrew/Cellar/some-other-formula/1.0/WhereAmIP.app"),
                       .direct)
    }

    // MARK: - MacPorts

    func testApplicationsMacPortsIsMacPorts() {
        XCTAssertEqual(InstallChannel.detect(path: "/Applications/MacPorts/WhereAmIP.app"), .macports)
    }

    func testLibexecUnderThePortPrefixIsMacPorts() {
        XCTAssertEqual(InstallChannel.detect(path: "/opt/local/libexec/whereamip/whereamip"), .macports)
    }

    /// `prefix` is not fixed — MacPorts can be installed anywhere, and the guide's own
    /// example alternative is `/opt/mports`. Nothing may hardcode `/opt/local`.
    func testNonDefaultPortPrefixIsStillMacPorts() {
        XCTAssertEqual(InstallChannel.detect(path: "/opt/mports/libexec/whereamip/whereamip"), .macports)
        XCTAssertEqual(InstallChannel.detect(path: "/Users/someone/mports/libexec/whereamip/whereamip"), .macports)
    }

    /// `applications_dir` is configurable too; the MacPorts folder name is what identifies it.
    func testNonDefaultApplicationsDirIsStillMacPorts() {
        XCTAssertEqual(InstallChannel.detect(path: "/Users/someone/Applications/MacPorts/WhereAmIP.app"),
                       .macports)
    }

    /// Homebrew also has a `libexec`, holding `WhereAmIP.app` and `cli/` — it must not be
    /// mistaken for the port layout, whose `libexec` holds a `whereamip` DIRECTORY.
    func testHomebrewLibexecIsNotMistakenForMacPorts() {
        XCTAssertEqual(InstallChannel.detect(path: "/opt/homebrew/Cellar/whereamip/0.5.5/libexec/WhereAmIP.app"),
                       .homebrew)
        XCTAssertEqual(InstallChannel.detect(path: "/opt/homebrew/opt/whereamip/libexec/cli/whereamip"),
                       .homebrew)
    }

    // MARK: - direct

    func testPlainApplicationsIsDirect() {
        XCTAssertEqual(InstallChannel.detect(path: "/Applications/WhereAmIP.app"), .direct)
    }

    func testDistBuildIsDirect() {
        XCTAssertEqual(InstallChannel.detect(path: "/Users/someone/code/whereamip/dist/WhereAmIP.app"), .direct)
    }

    func testDownloadsAndTempAreDirect() {
        XCTAssertEqual(InstallChannel.detect(path: "/Users/someone/Downloads/WhereAmIP.app"), .direct)
        XCTAssertEqual(InstallChannel.detect(path: "/private/tmp/WhereAmIP.app"), .direct)
    }

    func testEmptyAndNonsensePathsAreDirect() {
        XCTAssertEqual(InstallChannel.detect(path: ""), .direct)
        XCTAssertEqual(InstallChannel.detect(path: "/"), .direct)
        XCTAssertEqual(InstallChannel.detect(path: "WhereAmIP.app"), .direct)
    }
}
