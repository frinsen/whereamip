import Foundation

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handlers: [String: (status: Int, body: Data)] = [:]  // key: URL absoluteString prefix
    nonisolated(unsafe) static var requestLog: [URL] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.requestLog.append(url)
        if let entry = Self.handlers.first(where: { url.absoluteString.hasPrefix($0.key) })?.value {
            let resp = HTTPURLResponse(url: url, statusCode: entry.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: entry.body)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }
    override func stopLoading() {}
    static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }
    static func reset() { handlers = [:]; requestLog = [] }
}

func fixture(_ name: String) -> Data {
    try! Data(contentsOf: Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!)
}
