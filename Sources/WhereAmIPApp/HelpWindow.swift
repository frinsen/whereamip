import AppKit
import WhereAmIPCore
import WhereAmIPUI

/// Help window: opened from the dropdown's "WhereAmIP Help" row (⌘?). The app is
/// LSUIElement/`.accessory`, so it has no real menu bar and therefore no Help menu —
/// that row is this app's substitute for one, and this window is what it opens.
///
/// Same chrome conventions as WelcomeWindowController (plain AppKit, programmatic
/// NSStackView layout, close-only titlebar, never released when closed) and the same
/// bundled-Markdown path (`HelpContent` → `WelcomeContent.rendered`). It deliberately
/// does NOT reuse WelcomeWindowController itself: that window's layout is a tuned
/// arrangement of fixed-size reserved slots around live setup toggles, and a document
/// of this length has the opposite requirement — it scrolls, it resizes, and it has
/// no controls at all. Sharing the class would have meant destabilising that layout
/// to serve a window with none of its constraints.
///
/// The two windows are independent objects with independent controllers, so opening
/// one never touches the other, and Settings ▸ Show Welcome Window behaves exactly as
/// it did before this window existed.
/// A document view whose origin is top-left. Without this, an NSScrollView lays its
/// document out from the BOTTOM, so a document shorter than the window sits at the
/// bottom edge and a longer one opens scrolled to its end — both wrong for text.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class HelpWindowController: NSWindowController, NSWindowDelegate {
    // Wide enough for the shortcut lines not to wrap mid-chord, tall enough to show
    // a couple of sections at once; resizable because it's a document, not a dialog.
    private static let contentWidth: CGFloat = 480
    private static let contentHeight: CGFloat = 560
    private static let margin: CGFloat = 24
    /// Kept so `windowDidResize` can re-wrap the body: an NSTextField only wraps at
    /// its `preferredMaxLayoutWidth`, which does not follow its constraints on its
    /// own, so a resized window would otherwise keep the width it was born with.
    private var body: NSTextField!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: Self.contentHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = L10n.string(.helpWindowTitle)
        // Matches the dropdown row that opened it; no version in the title (the
        // dropdown header already shows it, and help copy is not per-release).
        window.minSize = NSSize(width: 380, height: 320)
        // Callers may re-show this window; closing it must not deallocate the
        // controller out from under them (same rule as the welcome window).
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        window.delegate = self
        window.center()
    }

    /// Re-wrap on resize — see `body`'s doc for why this isn't automatic.
    func windowDidResize(_ notification: Notification) {
        guard let width = window?.contentView?.bounds.width else { return }
        body.preferredMaxLayoutWidth = max(200, width - 2 * Self.margin)
        body.invalidateIntrinsicContentSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func buildContent() {
        guard let window else { return }

        // Left-aligned, unlike the welcome window's centered pitch: this is a
        // multi-section document with bullet lists, and centered prose at this
        // length is unreadable.
        let bodyFont = NSFont.systemFont(ofSize: 12)
        body = NSTextField(wrappingLabelWithString: "")
        body.font = bodyFont
        body.attributedStringValue = WelcomeContent.rendered(HelpContent.markdown(), font: bodyFont,
                                                             alignment: .left)
        body.preferredMaxLayoutWidth = Self.contentWidth - 2 * Self.margin
        body.translatesAutoresizingMaskIntoConstraints = false

        // A document that outgrows its window scrolls rather than being clipped —
        // the one structural difference from the welcome window, whose content is
        // sized to always fit.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // The label is pinned to the clip view's width so it wraps to whatever the
        // window is currently sized to, and grows downwards only.
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(body)
        scrollView.documentView = documentView

        let contentView = NSView()
        contentView.addSubview(scrollView)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            body.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: Self.margin),
            body.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -Self.margin),
            body.topAnchor.constraint(equalTo: documentView.topAnchor, constant: Self.margin),
            body.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -Self.margin),
        ])
    }

    func show() {
        // Accessory apps aren't brought frontmost automatically when a window opens —
        // without this the window can appear behind whatever the user was reading.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
