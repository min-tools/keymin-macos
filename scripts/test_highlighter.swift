import AppKit

/// Syntax coloring checks on representative skhd lines, compiled with the highlighter and the
/// syntax tables it reads.
@main
struct HighlighterTests {
    static var checks = 0

    // check(condition, message): Stop at the first failed check with its message; count the rest.
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }

    // color(storage, at offset): The foreground color at a UTF-16 character offset.
    static func color(_ storage: NSTextStorage, at offset: Int) -> NSColor? {
        storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
    }

    // main(): Check where commands start, then the colors of a highlighted sample.
    static func main() {
        // The command starts at the first colon outside quotes that is not part of "::".
        check(SkhdHighlighter.commandStart(in: "alt + shift - a : open -a Safari") == 16, "Commands start after the keysym")
        check(SkhdHighlighter.commandStart(in: ":: resize @ : echo hi") == 12, "Mode declarations skip the double colon")
        check(SkhdHighlighter.commandStart(in: "    \"App: Name\" : cmd") == 16, "Colons inside quotes are not commands")
        check(SkhdHighlighter.commandStart(in: "cmd - x ; resize") == 16, "Lines without a command keep their full length")
        check(SkhdHighlighter.commandStart(in: "") == 0, "Empty lines are handled")

        // A sample with a comment, a passthrough binding, a per-app list, and a mode declaration.
        let text = """
        # Focus Safari
        alt + shift - a -> : open -a "Safari"
        cmd - d [
            "Google Chrome" : skhd -k "cmd - l"
            * ~
        ]
        :: resize @ : echo on
        """
        let storage = NSTextStorage(string: text)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        SkhdHighlighter.highlight(storage, font: font)
        let nsText = text as NSString
        // offset(of needle, [after start = 0]): Find needle's UTF-16 offset from start.
        func offset(of needle: String, after start: Int = 0) -> Int {
            nsText.range(of: needle, range: NSRange(location: start, length: nsText.length - start)).location
        }

        // Each construct gets its semantic color; shell text after the colon keeps the default.
        check(color(storage, at: offset(of: "# Focus")) == .secondaryLabelColor, "Comment lines are muted")
        check(color(storage, at: offset(of: "alt")) == .controlAccentColor, "Modifiers use the accent color")
        check(color(storage, at: offset(of: "->")) == .systemOrange, "Passthrough arrows are orange")
        let keyOffset = offset(of: "- a") + 2
        let keyFont = storage.attribute(.font, at: keyOffset, effectiveRange: nil) as? NSFont
        check(keyFont?.fontDescriptor.symbolicTraits.contains(.bold) == true, "The key is bold")
        check(color(storage, at: offset(of: "open -a")) == .labelColor, "Command text keeps the default color")
        check(color(storage, at: offset(of: "\"Safari\"")) == .labelColor, "Strings inside commands are not colored")
        check(color(storage, at: offset(of: "\"Google Chrome\"")) == .systemGreen, "App names are green")
        check(color(storage, at: offset(of: "* ~")) == .systemOrange, "Wildcards are orange")
        check(color(storage, at: offset(of: ":: resize")) == .systemPurple, "Mode declarations are purple")
        check(color(storage, at: offset(of: "echo on")) == .labelColor, "Mode commands keep the default color")

        // Highlighting is idempotent and survives edits.
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# new\n")
        SkhdHighlighter.highlight(storage, font: font)
        check(color(storage, at: 0) == .secondaryLabelColor, "Re-highlighting after an edit works")
        print("Keymin highlighter: \(checks) coloring checks passed")
    }
}
