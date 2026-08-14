import Foundation

public struct ProbeGate: Equatable, Sendable {
    private var connectivity: Connectivity = .checking
    private var consecutiveFailures = 0
    public init() {}
    public mutating func record(success: Bool) -> Connectivity {
        if success {
            consecutiveFailures = 0
            connectivity = .online
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= 2 { connectivity = .offline }
            // 1 failure: keep previous value (.online stays online; .checking stays checking)
        }
        return connectivity
    }
}

public struct ConnectivityProbe: Sendable {
    let session: URLSession
    let deadline: Double
    static let url = URL(string: "https://www.gstatic.com/generate_204")!
    public init(session: URLSession = URLSession(configuration: .default), deadlineSeconds: Double = 4) {
        self.session = session; self.deadline = deadlineSeconds
    }
    public func check() async -> Bool {
        let ok = (try? await withHardDeadline(seconds: deadline) { [session] in
            var req = URLRequest(url: Self.url)
            req.httpMethod = "HEAD"
            let (_, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 204 else { throw BadResponse() }
            return true
        }) ?? false
        Log.route.debug("probe: \(ok ? "success" : "failure", privacy: .public)")
        return ok
    }
}
