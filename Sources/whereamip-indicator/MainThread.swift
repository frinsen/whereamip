import CGtk
import Foundation

/// A closure that crosses into C as a `gpointer`.
final class CallbackBox {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
}

/// GTK's thread is the only one that may touch a widget, and it is not the Swift main
/// actor: `gtk_main()` never drains the main dispatch queue, so `@MainActor` work and
/// `DispatchQueue.main` would simply never run. Everything that comes back from Swift
/// concurrency (the Monitor's callbacks, the end of an `await`) hops onto the GLib main
/// loop through here instead.
enum MainThread {
    /// Runs `work` on the GTK main loop, once. Safe to call from any thread.
    static func async(_ work: @escaping () -> Void) {
        let box = Unmanaged.passRetained(CallbackBox(work)).toOpaque()
        g_idle_add({ data in
            guard let data else { return 0 }
            Unmanaged<CallbackBox>.fromOpaque(data).takeRetainedValue().run()
            return 0                                    // G_SOURCE_REMOVE
        }, box)
    }

    /// Runs `work` on the main loop every `seconds`, for the life of the process.
    static func every(seconds: UInt32, _ work: @escaping () -> Void) {
        let box = Unmanaged.passRetained(CallbackBox(work)).toOpaque()
        g_timeout_add_seconds(seconds, { data in
            guard let data else { return 0 }
            Unmanaged<CallbackBox>.fromOpaque(data).takeUnretainedValue().run()
            return 1                                    // G_SOURCE_CONTINUE
        }, box)
    }

    /// Runs `work` on the main loop once, after `milliseconds`.
    static func after(milliseconds: UInt32, _ work: @escaping () -> Void) {
        let box = Unmanaged.passRetained(CallbackBox(work)).toOpaque()
        g_timeout_add(milliseconds, { data in
            guard let data else { return 0 }
            Unmanaged<CallbackBox>.fromOpaque(data).takeRetainedValue().run()
            return 0
        }, box)
    }
}

/// `g_signal_connect` for a Swift closure. The closure is released with the handler, when
/// GTK destroys the widget — so a rebuilt menu frees its old rows' closures with it.
@discardableResult
func connect(_ instance: UnsafeMutableRawPointer, _ signal: String, _ run: @escaping () -> Void) -> gulong {
    let box = Unmanaged.passRetained(CallbackBox(run)).toOpaque()
    let handler: @convention(c) (gpointer?, gpointer?) -> Void = { _, data in
        guard let data else { return }
        Unmanaged<CallbackBox>.fromOpaque(data).takeUnretainedValue().run()
    }
    let release: @convention(c) (gpointer?, UnsafeMutablePointer<GClosure>?) -> Void = { data, _ in
        guard let data else { return }
        Unmanaged<CallbackBox>.fromOpaque(data).release()
    }
    return wai_connect(instance, signal, unsafeBitCast(handler, to: GCallback.self), box, release)
}
