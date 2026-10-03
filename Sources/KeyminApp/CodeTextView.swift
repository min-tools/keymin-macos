import AppKit
import SwiftUI

/// A monospaced multi-line text editor for shell commands and the configuration source.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var isEditable = true
    /// Not read by the view: the height comes from the SwiftUI frame the caller applies.
    var minHeight: CGFloat = 60
    var fontSize: CGFloat = 12.5
    /// Colors skhd syntax; only the Source page shows a whole configuration.
    var highlightsSkhd = false
    /// Adds a line-number gutter, also only for the Source page.
    var showsLineNumbers = false
    /// Reports first-responder changes so the host can draw its own focus ring.
    var onFocusChange: ((Bool) -> Void)?

    // makeCoordinator(): Give the coordinator the text binding so edits flow back to SwiftUI.
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    // makeNSView(context): Build the container with its scroll view, text view, and optional
    // gutter, then apply the initial text and settings.
    func makeNSView(context: Context) -> CodeEditorContainer {
        let container = CodeEditorContainer(showsGutter: showsLineNumbers)
        let scrollView = container.scrollView
        let textView = Self.makeTextView(in: scrollView)
        textView.delegate = context.coordinator
        // Plain monospaced text with undo; every automatic substitution is off because the content
        // is code, where a smart quote or dash would change its meaning.
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        // The find bar makes the Find command work inside the editor; the insets match the other
        // inputs, and zero fragment padding keeps the gutter numbers level with the text.
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 10, height: 9)
        textView.textContainer?.lineFragmentPadding = 0
        textView.placeholder = placeholder
        textView.onFocusChange = onFocusChange
        textView.highlightsSkhd = highlightsSkhd
        textView.string = text
        textView.applyHighlighting()
        textView.setAccessibilityLabel(placeholder)
        container.gutter?.attach(to: textView)
        return container
    }

    // makeTextView(in scrollView): Build the editor on its own TextKit 1 stack, so the
    // line-number gutter can enumerate line fragments through the layout manager. The text view
    // grows with its text and wraps at the scroll view's width.
    private static func makeTextView(in scrollView: NSScrollView) -> CodeEditorTextView {
        let textView = CodeEditorTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        return textView
    }

    // updateNSView(container, context): Push the current settings into the text view and replace
    // its text only when the model changed elsewhere.
    func updateNSView(_ container: CodeEditorContainer, context: Context) {
        guard let textView = container.scrollView.documentView as? CodeEditorTextView else { return }
        context.coordinator.text = $text
        textView.isEditable = isEditable
        textView.placeholder = placeholder
        textView.onFocusChange = onFocusChange
        textView.highlightsSkhd = highlightsSkhd
        // Resetting the text on every update would fight the user's typing, so only do it when
        // the model differs; keep the caret near its place and redraw the gutter for the new text.
        // Never while an input method is composing (marked text): replacing the text then would
        // put the composed characters in the wrong place. The update that follows the end of the
        // composition applies any difference that remains.
        if textView.string != text, !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            textView.string = text
            // The undo history refers to the old text, so it cannot be replayed on the new one.
            context.coordinator.undoManager.removeAllActions()
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            textView.applyHighlighting()
            textView.needsDisplay = true
            container.gutter?.refresh()
        }
    }

    /// Forwards edits from the text view to the SwiftUI binding.
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        /// This editor's own undo history. Sharing the window's would let ⌘Z replay typing from
        /// another field, or from text the model has since replaced, and corrupt it.
        let undoManager = UndoManager()

        // init(text): Keep the binding that edits are written into.
        init(text: Binding<String>) { self.text = text }

        // undoManager(for view): Give the text view this editor's own undo history.
        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        // textDidChange(notification): Copy the edited text into the binding.
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

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

/// Lays out the optional gutter beside the scroll view using frames, keeping their widths
/// coordinated as SwiftUI resizes the editor.
final class CodeEditorContainer: NSView {
    let scrollView = NSScrollView()
    /// Present only when the editor was created with line numbers.
    let gutter: LineNumberGutterView?

    // init(showsGutter): Build the borderless scroll view and, when asked, the gutter, then place
    // them once.
    init(showsGutter: Bool) {
        gutter = showsGutter ? LineNumberGutterView() : nil
        super.init(frame: .zero)
        // macOS 14 stopped clipping subviews by default; the gutter must not paint its neighbors.
        clipsToBounds = true
        // Transparent, vertical-only scrolling; the host draws the background and border.
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        addSubview(scrollView)
        // The gutter widens with the line count, and the scroll view must move over when it does.
        if let gutter {
            addSubview(gutter)
            gutter.onThicknessChange = { [weak self] _ in self?.placeSubviews() }
        }
        placeSubviews()
    }

    // init(coder): Unsupported; the container is only created in code.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Top-left origin, so the frames below read naturally.
    override var isFlipped: Bool { true }

    /// The editor fills whatever SwiftUI proposes; it has no size of its own.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    // setFrameSize(newSize): Re-place the subviews whenever SwiftUI resizes the container.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeSubviews()
    }

    // placeSubviews(): Put the gutter at the left edge and give the scroll view the rest.
    private func placeSubviews() {
        let thickness = gutter?.thickness ?? 0
        gutter?.frame = NSRect(x: 0, y: 0, width: thickness, height: bounds.height)
        scrollView.frame = NSRect(x: thickness, y: 0, width: max(0, bounds.width - thickness), height: bounds.height)
    }
}

/// A gutter that numbers the lines of the Source editor. Wrapped continuations of a long line
/// get no number, and the empty line after a final newline is numbered like any editor does.
final class LineNumberGutterView: NSView {
    private weak var textView: NSTextView?
    private var observers: [NSObjectProtocol] = []
    /// The current width, sized for the digit count of the last line number.
    private(set) var thickness: CGFloat = 40
    /// Called with the new width so the container can move the scroll view over.
    var onThicknessChange: ((CGFloat) -> Void)?

    /// Top-left origin, like the text view, so fragment rects map straight onto gutter rows.
    override var isFlipped: Bool { true }

    // init(frame frameRect): Create the gutter with drawing clipped to its bounds.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Since macOS 14 the dirty rect can reach beyond the view, so clip every fill to it.
        clipsToBounds = true
    }

    // init(coder): Unsupported; the gutter is only created in code.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // deinit(): Stop observing the text view and clip view.
    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // attach(to textView): Follow the editor's content and clip-view scrolling. Edits re-measure
    // the width; scrolling and text-view growth only redraw.
    func attach(to textView: NSTextView) {
        self.textView = textView
        guard let scrollView = textView.enclosingScrollView else { return }
        scrollView.contentView.postsBoundsChangedNotifications = true
        textView.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        })
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        })
        refresh()
    }

    // refresh(): Resize the gutter when the line count gains or loses a digit, then redraw.
    func refresh() {
        let lines = max(1, (textView?.string.components(separatedBy: "\n").count ?? 1))
        let width = CGFloat(max(2, String(lines).count)) * 8 + 22
        // Only report a real change, so the container does not re-place its subviews on every edit.
        if abs(thickness - width) > 0.5 {
            thickness = width
            onThicknessChange?(width)
        }
        needsDisplay = true
    }

    // draw(dirtyRect): Paint the background and the divider on the right, then number every
    // visible line fragment that starts a line.
    override func draw(_ dirtyRect: NSRect) {
        // Never fill the raw dirty rect: without clipping it covers the views beside the gutter.
        let area = bounds.intersection(dirtyRect)
        guard !area.isEmpty else { return }
        NSColor.textBackgroundColor.setFill()
        area.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: area.minY, width: 1, height: area.height).fill()

        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let clipView = textView.enclosingScrollView?.contentView else { return }
        // Numbers use a slightly smaller monospaced-digit font so they stay quiet beside the code.
        let text = textView.string as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(9, (textView.font?.pointSize ?? 12) - 1.5), weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let inset = textView.textContainerInset
        // The clip view's bounds origin is the scroll offset in the text view's coordinates.
        let scrollOffset = clipView.bounds.minY

        // Only the fragments in the visible part of the text view are enumerated.
        let visible = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Count the lines above the first visible character.
        var lineNumber = 1
        var index = 0
        while index < characterRange.location {
            let newline = text.range(of: "\n", range: NSRange(location: index, length: characterRange.location - index))
            // No further newline before the visible range.
            if newline.location == NSNotFound { break }
            lineNumber += 1
            index = newline.location + 1
        }

        // drawNumber(number, beside): Right-align the number, vertically centered on the fragment,
        // after converting the fragment from text-container to gutter coordinates.
        func drawNumber(_ number: Int, beside fragment: NSRect) {
            let label = String(number) as NSString
            let size = label.size(withAttributes: attributes)
            let top = fragment.minY + inset.height - scrollOffset
            let origin = NSPoint(x: thickness - size.width - 9, y: top + (fragment.height - size.height) / 2)
            label.draw(at: origin, withAttributes: attributes)
        }

        // Number only the fragments that begin a line; wrapped continuations stay blank.
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragment, _, _, fragmentGlyphRange, _ in
            let characterIndex = layoutManager.characterIndexForGlyph(at: fragmentGlyphRange.location)
            let startsLine = characterIndex == 0 || text.character(at: characterIndex - 1) == 0x0A
            guard startsLine else { return }
            drawNumber(lineNumber, beside: fragment)
            lineNumber += 1
        }

        // The line after a trailing newline has no glyphs; the layout manager keeps its rect.
        if NSMaxRange(characterRange) >= text.length, text.length == 0 || text.character(at: text.length - 1) == 0x0A {
            let extra = layoutManager.extraLineFragmentRect
            // TextKit may not have laid out the trailing empty line yet.
            if !extra.isEmpty { drawNumber(lineNumber, beside: extra) }
        }
    }
}

/// Field chrome around a code editor so it matches the other inputs.
struct CodeField: View {
    @Binding var text: String
    var placeholder = ""
    var minHeight: CGFloat = 60
    var maxHeight: CGFloat = 220
    @State private var isFocused = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    var body: some View {
        CodeTextView(text: $text, placeholder: placeholder, minHeight: minHeight, onFocusChange: { isFocused = $0 })
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .background(Theme.inputBackground, in: shape)
            .overlay(shape.stroke(isFocused ? Theme.accent : Theme.inputBorder, lineWidth: isFocused ? 1.5 : 1))
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
