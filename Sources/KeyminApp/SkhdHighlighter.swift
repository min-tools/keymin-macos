import AppKit

/// Colors skhd syntax in the Source editor. Every color is a semantic AppKit color, so the
/// text follows Light and Dark appearances and the user's accent without any re-highlighting.
/// Lines are colored one at a time, so continuation lines of a multi-line command are treated like
/// statement heads.
enum SkhdHighlighter {
    /// Modifier keywords as whole words.
    private static let modifierPattern = try! NSRegularExpression(
        pattern: "\\b(?:" + SkhdModifier.allCases.map(\.rawValue).joined(separator: "|") + ")\\b"
    )
    /// A quoted app name on one line.
    private static let stringPattern = try! NSRegularExpression(pattern: "\"[^\"\\n]*\"")
    /// `::` and the mode name at the start of a line.
    private static let declarationPattern = try! NSRegularExpression(pattern: "^\\s*::\\s*[A-Za-z_]+[0-9]*")
    /// `.load` or `.blacklist` at the start of a line.
    private static let optionPattern = try! NSRegularExpression(pattern: "^\\s*\\.(?:load|blacklist)\\b")
    /// `;` and the mode name it activates.
    private static let activatePattern = try! NSRegularExpression(pattern: ";\\s*[A-Za-z_]+[0-9]*")
    /// The key after `- `: a key code or a word.
    private static let keyPattern = try! NSRegularExpression(pattern: "(?<=-\\s)(?:0x[0-9A-Fa-f]+|[A-Za-z0-9_]+)")
    /// The passthrough arrow, the unbound tilde, and the wildcard star.
    private static let markerPattern = try! NSRegularExpression(pattern: "->|~|\\*")
    /// Structural characters, plus a dash that is not part of `->`.
    private static let punctuationPattern = try! NSRegularExpression(pattern: "[<\\[\\],+@]|(?<!-)-(?!>)")

    // highlight(storage, font): Reapply the font and syntax colors after an edit.
    // This scans the whole text; later passes override earlier overlapping colors.
    static func highlight(_ storage: NSTextStorage, font: NSFont) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let bold = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: full)
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = text.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Comment lines are dimmed as a whole.
            if trimmed.hasPrefix("#") {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
                return
            }
            // Everything after the command colon is shell text and keeps the default color.
            let head = NSRange(location: lineRange.location, length: commandStart(in: line))
            color(stringPattern, in: head, text: text, storage: storage, color: .systemGreen)
            color(modifierPattern, in: head, text: text, storage: storage, color: .controlAccentColor)
            color(declarationPattern, in: head, text: text, storage: storage, color: .systemPurple)
            color(optionPattern, in: head, text: text, storage: storage, color: .systemPurple)
            color(activatePattern, in: head, text: text, storage: storage, color: .systemPurple)
            color(punctuationPattern, in: head, text: text, storage: storage, color: .tertiaryLabelColor)
            color(markerPattern, in: head, text: text, storage: storage, color: .systemOrange)
            // The key is set in bold rather than colored.
            for match in keyPattern.matches(in: text as String, range: head) {
                storage.addAttribute(.font, value: bold, range: match.range)
            }
        }
        storage.endEditing()
    }

    // color(pattern, in range, text, storage, color): Color each regex match
    // within the range.
    private static func color(
        _ pattern: NSRegularExpression,
        in range: NSRange,
        text: NSString,
        storage: NSTextStorage,
        color: NSColor
    ) {
        for match in pattern.matches(in: text as String, range: range) {
            storage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }

    // commandStart(in line): The UTF-16 offset of a command colon, or the line length
    // when there is none. `::` declares a mode and quoted app names may contain colons, so both are
    // skipped.
    static func commandStart(in line: String) -> Int {
        let characters = Array(line.utf16)
        var inString = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            // A quote toggles string state; strings have no escapes.
            if character == 0x22 { // "
                inString.toggle()
            } else if !inString, character == 0x3A { // :
                // Skip `::` so declaration punctuation cannot start shell-command coloring.
                if index + 1 < characters.count, characters[index + 1] == 0x3A {
                    index += 2
                    continue
                }
                return index
            }
            index += 1
        }
        return characters.count
    }
}
