public struct DeadlineExceeded: Error {}

public func withHardDeadline<T: Sendable>(seconds: Double,
                                          _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw DeadlineExceeded()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
