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
final class HelpWindowController: NSWindowController {
    // Wide enough for the shortcut lines not to wrap mid-chord, tall enough to show
    // a couple of sections at once; resizable because it's a document, not a dialog.
    private static let contentWidth: CGFloat = 480
    private static let contentHeight: CGFloat = 560
    private static let margin: CGFloat = 24
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
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func buildContent() {
        guard let window else { return }

        // A document that outgrows its window scrolls rather than being clipped — the one
        // structural difference from the welcome window, whose content is sized to fit.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // NSTextView, not the NSTextField this used to be, for one reason: the closing
        // GitHub pointer is a real link, and a text field will not act on a `.link`
        // attribute no matter how correctly the attributed string carries it. A text view
        // opens it, shows the pointing-hand cursor over it, and lets the reader select and
        // copy any of this text — all for free.
        //
        // Left-aligned, unlike the welcome window's centered pitch: this is a multi-section
        // document with bullet lists, and centered prose at that length is unreadable.
        let bodyFont = NSFont.systemFont(ofSize: 12)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0,
                                                width: Self.contentWidth, height: Self.contentHeight))
        textView.isEditable = false
        textView.isSelectable = true          // required for links to be clickable at all
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: Self.margin, height: Self.margin)
        // Classic autoresizing text-view-in-scroll-view setup rather than Auto Layout: with
        // `widthTracksTextView` the container re-wraps itself on every window resize, which
        // is exactly what the old text field needed a windowDidResize hook to fake.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: Self.contentWidth,
                                                       height: CGFloat.greatestFiniteMagnitude)
        // Link appearance is already carried by the attributed string (WelcomeContent
        // .rendered); this makes the text view agree rather than override it with its own
        // default blue, and adds the underline on hover the platform expects.
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.textStorage?.setAttributedString(
            WelcomeContent.rendered(HelpContent.markdown(), font: bodyFont, alignment: .left))
        scrollView.documentView = textView

        let contentView = NSView()
        contentView.addSubview(scrollView)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
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

/// The presentation contract `AppDelegate.present(_:make:)` needs from both auxiliary
/// windows: something that can report whether it is still on screen, and can bring itself
/// to the front. `window` comes free from NSWindowController; `show()` each controller
/// already implements (activate + makeKeyAndOrderFront, which accessory apps need).
protocol AuxiliaryWindowController: AnyObject {
    var window: NSWindow? { get }
    func show()
}

extension WelcomeWindowController: AuxiliaryWindowController {}
extension HelpWindowController: AuxiliaryWindowController {}
