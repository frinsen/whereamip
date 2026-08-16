import ArgumentParser
import Foundation
import WhereAmIPCore

@main
struct WhereAmIP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "whereamip",
        abstract: "Where am I(P)? Exit IP, geolocation, VPN route, and Private Relay status.",
        version: whereamipVersion,
        subcommands: [Status.self, Watch.self, Config.self, Debug.self],
        defaultSubcommand: Status.self)
}

func makeMonitor(onChange: @escaping @Sendable (ExitState) -> Void = { _ in },
                 onEvents: @escaping @Sendable ([Event]) -> Void = { _ in }) -> Monitor {
    Monitor(geo: GeoProviderChain(), probe: ConnectivityProbe(),
            route: LiveRoute(), httpIP: HTTPIPFetcher(), stackIP: StackPinnedIP(),
            relayRanges: RelayRanges.bundled(),
            onChange: onChange, onEvents: onEvents)
}
struct LiveRoute: RouteSnapshotting {
    func snapshot() -> RouteInfo { RouteInspector.snapshot(runningBundleIDs: []) }
}

struct Status: AsyncParsableCommand {
    @Flag var json = false
    func run() async throws {
        let m = makeMonitor()
        await m.fullRefresh()
        let state = await m.currentState()
        print(json ? StateRenderer.json(state) : StateRenderer.human(state))
    }
}

struct Watch: AsyncParsableCommand {
    @Flag var json = false
    func run() async throws {
        setbuf(stdout, nil)   // line-latency output: watch is a streaming interface; when
                              // piped/redirected (the documented `watch --json >> file` use
                              // and the e2e suite's gate) block buffering delays lines by minutes.
        let stream = AsyncStream<ExitState> { continuation in
            let m = makeMonitor(onChange: { continuation.yield($0) })
            Task {
                await m.fullRefresh()
                var tick = 0
                while true {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    tick += 1
                    // Every 10th tick (~5 min) do a full geo refresh instead of a
                    // connectivity-only probe, so exit-IP/geo data doesn't go stale
                    // for long-running `watch` sessions (spec §3 backstop).
                    if tick % 10 == 0 {
                        await m.fullRefresh()
                    } else {
                        await m.probeTick()
                    }
                }
            }
        }
        for await state in stream {
            print(json ? StateRenderer.json(state) : StateRenderer.human(state))
        }
    }
}

struct Debug: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Live-stream WhereAmIP's diagnostic log (nothing is written to disk).")
    func run() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--level", "debug",
                              "--predicate", "subsystem == \"io.github.frinsen.whereamip\"",
                              "--style", "compact"]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
    }
}

struct Config: AsyncParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [Get.self, Set.self])
    struct Get: ParsableCommand {
        func run() throws {
            for (k, v) in Settings().allValues() { print("\(k)=\(v)") }
        }
    }
    struct Set: ParsableCommand {
        @Argument var key: String
        @Argument var value: String
        func run() throws { try Settings().set(key: key, value: value) }
    }
}
