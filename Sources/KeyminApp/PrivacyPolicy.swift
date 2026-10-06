import AppKit

/// The policy window. Escape closes it.
private final class PrivacyPolicyPanel: NSPanel {
    // cancelOperation(sender): Close on Escape.
    override func cancelOperation(_ sender: Any?) { close() }
}

/// One native window surface keeps the policy title bar and document visually connected.
private final class PrivacyPolicyBackgroundView: NSView {
    /// Stands in for the native title bar separator, which is turned off, so the line sits on
    /// the shared surface at the same place.
    private final class HairlineView: NSView {
        // draw(dirtyRect): Fill one device pixel along the top edge. The rect comes from bounds,
        // not dirtyRect, so a partial redraw keeps the whole line.
        override func draw(_ dirtyRect: NSRect) {
            let thickness = 1 / (window?.backingScaleFactor ?? 2)
            NSColor.separatorColor.setFill()
            NSRect(
                x: 0,
                y: bounds.height - thickness,
                width: bounds.width,
                height: thickness
            ).fill()
        }

        // viewDidChangeEffectiveAppearance(): Redraw so the line's color follows light and
        // dark mode.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
    }

    private let hairline = HairlineView()

    // init(frame frameRect): Build the surface in code.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installMaterial()
        installHairline()
    }

    // init?(coder): The same setup when unarchived.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installMaterial()
        installHairline()
    }

    // installMaterial(): Fill the whole surface, title bar included, with the window background
    // material.
    private func installMaterial() {
        let material = NSVisualEffectView()
        material.material = .windowBackground
        material.blendingMode = .withinWindow
        material.state = .active
        material.translatesAutoresizingMaskIntoConstraints = false
        addSubview(material)
        NSLayoutConstraint.activate([
            material.topAnchor.constraint(equalTo: topAnchor),
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // installHairline(): Add the separator across the full width. Its vertical position is
    // pinned later, once the window knows where its title bar ends.
    private func installHairline() {
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)
        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    // pinHairline(to titlebarBottom): Put the separator at the title bar's bottom edge.
    func pinHairline(to titlebarBottom: NSLayoutYAxisAnchor) {
        hairline.topAnchor.constraint(equalTo: titlebarBottom).isActive = true
    }
}

// privacyPolicyContentSize(size, in window): Add the title bar height to a document size. The window
// runs its content under the title bar, so this keeps the visible document at the given size.
private func privacyPolicyContentSize(_ size: NSSize, in window: NSWindow) -> NSSize {
    let titlebarHeight = max(
        0,
        (window.contentView?.bounds.height ?? 0) - window.contentLayoutRect.height
    )
    return NSSize(width: size.width, height: size.height + titlebarHeight)
}

// installPrivacyPolicyContent(in window): Make the title bar transparent with content running
// under it, install the shared surface, and return a container pinned below the title bar for
// the document and the button.
private func installPrivacyPolicyContent(in window: NSWindow) -> NSView {
    // Hide the native title bar chrome and let the content extend under it.
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.styleMask.insert(.fullSizeContentView)

    let surface = PrivacyPolicyBackgroundView(frame: window.contentView?.bounds ?? .zero)
    window.contentView = surface

    // The container starts where the title bar ends, so the document never slides under it.
    let content = NSView(frame: window.contentLayoutRect)
    content.translatesAutoresizingMaskIntoConstraints = false
    surface.addSubview(content)
    // contentLayoutGuide tracks the area below the title bar; it is typed as Any, hence the cast.
    if let guide = window.contentLayoutGuide as? NSLayoutGuide {
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: guide.topAnchor),
            content.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        surface.pinHairline(to: content.topAnchor)
    }
    return content
}

/// Shows the bundled privacy policy in its own panel, rendered from Markdown.
final class PrivacyPolicyController: NSObject, NSTextViewDelegate {
    static let shared = PrivacyPolicyController()
    /// Built on first use and kept across closes.
    private var window: NSPanel?
    private var textView: NSTextView!

    // show(): Open the panel, or bring it forward, with the policy text freshly loaded.
    func show() {
        // Build once; later calls reuse the panel.
        if window == nil { buildWindow() }
        textView.textStorage?.setAttributedString(Self.policyText(
            at: Self.bundledPolicyURL
        ))
        // Center only a hidden panel, so a visible one keeps the place the user put it.
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // Once now and once after the window has laid out, so the text starts at the top.
        resetDocumentGeometry()
        DispatchQueue.main.async { [weak self] in self?.resetDocumentGeometry() }
    }

    // buildWindow(): Create the panel, its scrolling text view, and the OK button.
    private func buildWindow() {
        // A resizable panel that stays up when the app deactivates and survives closing.
        let panel = PrivacyPolicyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = Self.policyTitle
        panel.isReleasedWhenClosed = false
        panel.worksWhenModal = true
        panel.hidesOnDeactivate = false
        // Sizes are given for the document; the helper adds the title bar on top.
        let content = installPrivacyPolicyContent(in: panel)
        panel.setContentSize(privacyPolicyContentSize(
            NSSize(width: 640, height: 580),
            in: panel
        ))
        panel.contentMinSize = privacyPolicyContentSize(
            NSSize(width: 420, height: 320),
            in: panel
        )

        // A borderless, vertical-only scroll view that shows the surface through it.
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        guard let policyTextView = scroll.documentView as? NSTextView else {
            preconditionFailure("NSTextView.scrollableTextView() must contain an NSTextView")
        }
        // Read-only, selectable text that wraps to the scroll view's width and grows downward.
        textView = policyTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        // Links look like links; the delegate decides which ones may open.
        textView.delegate = self
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.setAccessibilityLabel(Self.policyTitle)

        // OK is the default button, so Return closes the panel as well.
        let close = NSButton(
            title: localized("OK"),
            target: self,
            action: #selector(dismiss(_:))
        )
        close.bezelStyle = .rounded
        close.keyEquivalent = "\r"

        // The text fills the container; the button sits in the bottom-right corner below it.
        for view in [scroll, close] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -14),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            close.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24)
        ])
        window = panel
    }

    // resetDocumentGeometry(): Match the document width to the visible clip view and scroll to
    // the top-left edge, so the text never opens scrolled or wider than the window.
    private func resetDocumentGeometry() {
        guard let scroll = textView.enclosingScrollView else { return }
        window?.contentView?.layoutSubtreeIfNeeded()
        let width = max(1, scroll.contentSize.width)
        textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// The menu item's title without its trailing ellipsis, reused for the window and VoiceOver.
    private static var policyTitle: String {
        localized("Privacy Policy…").trimmingCharacters(
            in: CharacterSet(charactersIn: ".…")
        )
    }

    /// The bundled policy file: in the module bundle under SwiftPM, in the app bundle from Xcode.
    private static var bundledPolicyURL: URL? {
#if SWIFT_PACKAGE
        // SwiftPM puts resources in the generated module bundle.
        Bundle.module.url(forResource: "PRIVACY", withExtension: "md")
#else
        // Xcode copies resources directly into the application bundle.
        Bundle.main.url(forResource: "PRIVACY", withExtension: "md")
#endif
    }

    // policyText(at url): Render the Markdown file; nil means the resource is missing.
    // For a missing, unreadable, or empty file, show the error and online policy link.
    static func policyText(at url: URL?) -> NSAttributedString {
        do {
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            let markdown = try String(contentsOf: url, encoding: .utf8)
            guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return attributedPolicy(markdown)
        } catch {
            return attributedPolicy(
                "# \(policyTitle)\n\n\(error.localizedDescription)\n\n[\(policyTitle)](\(AppLinks.privacyPolicy.absoluteString))"
            )
        }
    }

    // attributedPolicy(markdown): Convert the policy's Markdown into styled text. Blocks are
    // separated by blank lines; headings get larger semibold type, soft line breaks join into
    // one paragraph, inline bold, italic, code and links come from Foundation's Markdown
    // parser, and bare URLs are linked afterwards.
    static func attributedPolicy(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        for block in normalized.components(separatedBy: "\n\n") {
            var text = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            // A heading is one to six # characters followed by a space.
            let heading = text.prefix { $0 == "#" }.count
            let isHeading = (1...6).contains(heading) && text.dropFirst(heading).first == " "
            // Drop the markers and the space after them.
            if isHeading { text = String(text.dropFirst(heading + 1)) }
            text = text.replacingOccurrences(of: "\n", with: " ")

            // Type size and spacing per block; headings get extra room above, except the first.
            let size: CGFloat = isHeading ? (heading == 1 ? 24 : heading == 2 ? 18 : 15) : 14
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = isHeading ? 12 : 18
            paragraph.paragraphSpacingBefore = isHeading && result.length > 0 ? 8 : 0
            // Inline Markdown only; plain text if the parser rejects the block.
            let parsed = (try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(text)

            // Each run keeps its own weight, italic, monospace and link.
            for run in parsed.runs {
                let intent = run.inlinePresentationIntent ?? []
                let weight: NSFont.Weight = isHeading || intent.contains(.stronglyEmphasized)
                    ? .semibold : .regular
                var font = intent.contains(.code)
                    ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
                // Italic is a font trait, not a weight, so it needs a separate conversion.
                if intent.contains(.emphasized) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph
                ]
                // Keep the link so clicks reach the delegate.
                if let link = run.link { attributes[.link] = link }
                result.append(NSAttributedString(
                    string: String(parsed[run.range].characters),
                    attributes: attributes
                ))
            }
            // End the block with a newline that carries the paragraph spacing.
            result.append(NSAttributedString(
                string: "\n",
                attributes: [.paragraphStyle: paragraph]
            ))
        }

        // Link bare URLs that the Markdown pass left as plain text.
        let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        )
        let range = NSRange(location: 0, length: result.length)
        for match in detector?.matches(in: result.string, range: range) ?? [] {
            // Leave explicit Markdown links alone.
            if let url = match.url,
               result.attribute(.link, at: match.range.location, effectiveRange: nil) == nil {
                result.addAttribute(.link, value: url, range: match.range)
            }
        }
        return result
    }

    // textView(textView, clickedOnLink link, at charIndex): Open web and mail links and
    // report every click as handled, so the text view never opens other schemes itself.
    func textView(
        _ textView: NSTextView,
        clickedOnLink link: Any,
        at charIndex: Int
    ) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        // The link may be a URL or a string; only these schemes leave the app.
        if let url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    // dismiss(sender): Close the panel from the OK button.
    @objc private func dismiss(_ sender: Any?) { window?.close() }
}
