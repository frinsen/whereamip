import AppKit

/// Labels for READING copy — prose the user reads, never interacts with.
///
/// `NSTextField(wrappingLabelWithString:)` is selectable by default (unlike
/// `labelWithString:`), and `allowsEditingTextAttributes` defaults to false. Put attributed
/// text in one of those and a single CLICK destroys the styling: the click begins an editing
/// session in the window's shared field editor, the editor is populated from the field's
/// PLAIN string plus its base font, and that flattened text is written back into the field.
/// Bold lead-ins go regular, hanging bullet indents collapse to zero, and the bullets run
/// together as one paragraph. It does not come back.
///
/// Field-measured on 0.5.5 and reproduced in ReadingLabelTests:
///   as shipped                            → after click: bold=false, headIndent=0
///   allowsEditingTextAttributes = true    → styling survives
///   isSelectable = false                  → no field editor at all, styling survives
///
/// The last one is the fix, because it matches what these labels ARE. The welcome window is
/// something you read and dismiss; nothing offers or documents selecting its text, and the
/// app's copy-to-clipboard story is ⌘D, which carries live state rather than marketing copy.
/// Turning attribute editing on instead would preserve the pixels while leaving a caret, a
/// selection highlight and a text-cursor in the middle of a paragraph — interaction affordances
/// for an interaction that does nothing.
///
/// NOT for the help window: its body is an NSTextView, which owns its text storage and never
/// routes through the shared field editor, and it must stay selectable so its GitHub link
/// stays clickable. Different view, different rules — see HelpWindow.
public enum ReadingLabel {
    /// A wrapping label for attributed reading copy. The caller still owns font, alignment,
    /// colour and `preferredMaxLayoutWidth` — this changes interactivity only, so it can be
    /// dropped into a tuned layout without moving anything.
    public static func wrapping(font: NSFont) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = font
        label.isSelectable = false
        label.isEditable = false
        return label
    }
}
