import XCTest
import WhereAmIPCore
@testable import WhereAmIPUI

/// The click-strips-the-styling bug, and the guarantee that fixes it.
///
/// Field-reported on 0.5.5: clicking anywhere in the welcome window's body turned the
/// rendered markdown into flat uniform text — bold lead-ins gone, hanging bullet indents
/// collapsed so the bullets ran together. The mechanism reproduces headlessly, which is why
/// this is a real regression test and not a comment: `selectText` is what a click does, and
/// it is enough to trigger the whole field-editor round trip.
final class ReadingLabelTests: XCTestCase {
    let font = NSFont.systemFont(ofSize: 12)

    /// Two bullets with a bold lead-in: exactly the shapes the bug destroyed.
    func styledCopy() -> NSAttributedString {
        WelcomeContent.rendered("- **DNS** is watched\n- second item", font: font, alignment: .center)
    }

    /// True when the string still carries the two things a click used to remove.
    func isStyled(_ string: NSAttributedString) -> Bool {
        var bold = false
        var hangingIndent = false
        string.enumerateAttributes(in: NSRange(location: 0, length: string.length)) { attrs, _, _ in
            if let font = attrs[.font] as? NSFont,
               NSFontManager.shared.traits(of: font).contains(.boldFontMask) { bold = true }
            if let paragraph = attrs[.paragraphStyle] as? NSParagraphStyle,
               paragraph.headIndent > 0 { hangingIndent = true }
        }
        return bold && hangingIndent
    }

    /// Puts `field` in a window and starts an editing session in it, the way a click does.
    func click(_ field: NSTextField) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        field.frame = NSRect(x: 10, y: 10, width: 380, height: 120)
        window.contentView?.addSubview(field)
        field.selectText(nil)
        window.endEditing(for: field)
    }

    func testReadingLabelKeepsItsStylingWhenClicked() {
        let label = ReadingLabel.wrapping(font: font)
        label.attributedStringValue = styledCopy()
        XCTAssertTrue(isStyled(label.attributedStringValue), "precondition: the copy starts styled")

        click(label)

        XCTAssertTrue(isStyled(label.attributedStringValue),
                      "a click flattened the copy: \(label.attributedStringValue)")
    }

    /// The bug itself, pinned so nobody reintroduces it by reaching for the raw factory:
    /// the stock wrapping label really does lose everything, so the fix above is load-bearing
    /// rather than defensive decoration.
    func testTheStockWrappingLabelStillDemonstratesTheBug() {
        let stock = NSTextField(wrappingLabelWithString: "")
        stock.font = font
        stock.attributedStringValue = styledCopy()
        XCTAssertTrue(stock.isSelectable, "wrappingLabelWithString is selectable by default")
        XCTAssertTrue(isStyled(stock.attributedStringValue))

        click(stock)

        XCTAssertFalse(isStyled(stock.attributedStringValue),
                       "if this passes, AppKit changed and ReadingLabel's rationale needs rereading")
    }

    func testReadingLabelIsInertRatherThanMerelyStyle_Preserving() {
        // isSelectable = false is the fix, not allowsEditingTextAttributes = true: both keep
        // the pixels, only one stops offering an interaction that leads nowhere.
        let label = ReadingLabel.wrapping(font: font)
        XCTAssertFalse(label.isSelectable)
        XCTAssertFalse(label.isEditable)
    }

    /// The welcome window's layout is a tuned arrangement of fixed slots, so this fix was
    /// only allowed to change interactivity — never measurement. Same content, same width:
    /// the two labels must size identically, or the window shifts.
    func testTheFixChangesInteractivityAndNotMeasurement() {
        let markdown = WelcomeContent.markdown(milestone: welcomeMilestone, preferredLanguages: ["en"])
        let copy = WelcomeContent.rendered(markdown, font: font, alignment: .center)
        func measure(_ field: NSTextField) -> NSSize {
            field.attributedStringValue = copy
            field.preferredMaxLayoutWidth = 372   // the welcome window's content width
            field.invalidateIntrinsicContentSize()
            return field.intrinsicContentSize
        }
        let stock = NSTextField(wrappingLabelWithString: "")
        stock.font = font
        XCTAssertEqual(measure(ReadingLabel.wrapping(font: font)), measure(stock))
    }

    /// The help window's body is an NSTextView on purpose (its GitHub link must be
    /// clickable, which needs isSelectable = true). NSTextView owns its text storage and
    /// never routes through the window's shared field editor, so the same click cannot
    /// flatten it — asserted here rather than assumed, since "selectable" is the flag that
    /// caused the bug next door.
    func testASelectableTextViewIsImmuneToTheSameClick() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 120))
        textView.isEditable = false
        textView.isSelectable = true
        textView.textStorage?.setAttributedString(styledCopy())

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        window.contentView?.addSubview(textView)
        _ = window.makeFirstResponder(textView)
        textView.selectAll(nil)
        window.endEditing(for: textView)

        XCTAssertTrue(isStyled(textView.attributedString()),
                      "the help body lost styling: \(textView.attributedString())")
    }
}
