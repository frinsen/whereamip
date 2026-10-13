import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension URLSessionConfiguration {
    /// The configuration every lookup in this package is made with.
    ///
    /// Linux gets `.ephemeral`: swift-corelibs-foundation's `.default` keeps a disk-backed
    /// URL cache (`~/.cache/org.swift.foundation.URLCache/…`) and a cookie jar persisted under
    /// `~/.local/share/<app>/` — geo answers carrying this machine's exit IP, a CDN's cookie —
    /// and the README promises nothing of the kind is ever written. Ephemeral keeps both in
    /// memory. (Foundation still creates those two directories, empty, when it starts up.)
    @usableFromInline static var whereamip: URLSessionConfiguration {
        #if os(Linux)
        return .ephemeral
        #else
        return .default
        #endif
    }
}
