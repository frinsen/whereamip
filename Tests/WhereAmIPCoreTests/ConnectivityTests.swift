import XCTest
@testable import WhereAmIPCore

final class ConnectivityTests: XCTestCase {
    func testGateHysteresis() {
        var g = ProbeGate()
        XCTAssertEqual(g.record(success: true), .online)
        XCTAssertEqual(g.record(success: false), .online)   // 1 failure: still online
        XCTAssertEqual(g.record(success: false), .offline)  // 2nd consecutive: offline
        XCTAssertEqual(g.record(success: true), .online)    // instant recovery
        XCTAssertEqual(g.record(success: false), .online)   // counter was reset
    }
    func testGateStartsChecking() {
        var g = ProbeGate()
        XCTAssertEqual(g.record(success: false), .checking) // never online yet: stay checking after 1 fail
        XCTAssertEqual(g.record(success: false), .offline)
    }
    func testProbeSuccessOn204() async {
        MockURLProtocol.reset()
        MockURLProtocol.handlers["https://www.gstatic.com/generate_204"] = (204, Data())
        let probe = ConnectivityProbe(session: MockURLProtocol.session(), deadlineSeconds: 2)
        let ok = await probe.check()
        XCTAssertTrue(ok)
    }
    func testProbeFailureOnError() async {
        MockURLProtocol.reset()   // no handler → connection error
        let probe = ConnectivityProbe(session: MockURLProtocol.session(), deadlineSeconds: 2)
        let ok = await probe.check()
        XCTAssertFalse(ok)
    }
}
