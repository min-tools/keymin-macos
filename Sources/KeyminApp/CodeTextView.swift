import AppKit
import SwiftUI

/// The text view itself: draws the placeholder, reports focus changes, and re-highlights after
/// every edit.
final class CodeEditorTextView: NSTextView {
    /// Drawn in the text area while the text is empty.
    var placeholder = "" {
        didSet { needsDisplay = true }
    }
    var onFocusChange: ((Bool) -> Void)?
    var highlightsSkhd = false

    // applyHighlighting(): Recolor the whole text and keep new typing in the default color.
    // Does nothing unless skhd highlighting is on.
    func applyHighlighting() {
        guard highlightsSkhd, let storage = textStorage, let font else { return }
        SkhdHighlighter.highlight(storage, font: font)
        typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
    }

    // preferredTextAccessoryPlacement(): Hide the caret accessory, the input-source and Caps Lock
    // badge macOS shows beside the cursor, which looks out of place in a small code field.
    override func preferredTextAccessoryPlacement() -> NSTextCursorAccessoryPlacement { .invisible }

    // becomeFirstResponder(): Report focus gained once AppKit accepts the change.
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        // Notify the host only if this view actually took focus.
        if accepted { report(true) }
        return accepted
    }

    // resignFirstResponder(): Report focus lost once AppKit accepts the change.
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        // A refused resignation leaves the host's focus ring in place.
        if resigned { report(false) }
        return resigned
    }

    // report(focused): Deliver the focus change on the next run-loop turn, so the host's SwiftUI
    // state update happens outside the responder change.
    private func report(_ focused: Bool) {
        guard let onFocusChange else { return }
        DispatchQueue.main.async { onFocusChange(focused) }
    }

    // didChangeText(): Re-highlight after every edit and redraw so the placeholder comes and goes.
    override func didChangeText() {
        super.didChangeText()
        applyHighlighting()
        needsDisplay = true
    }

    // draw(dirtyRect): Draw the text, then the placeholder inside the text insets while the text
    // is empty.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty, let font else { return }
        let origin = textContainerOrigin
        // Start where the text would start and mirror the horizontal inset on the right.
        NSAttributedString(string: placeholder, attributes: [
            .font: font,
            .foregroundColor: Theme.inputPlaceholderNSColor
        ]).draw(in: NSRect(
            x: origin.x,
            y: origin.y,
            width: max(0, bounds.width - origin.x * 2),
            height: bounds.height - origin.y
        ))
    }
}
