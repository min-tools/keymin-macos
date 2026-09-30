import Foundation

// MARK: - Model

/// One process entry inside `[ ... ]`: a named app or the `*` wildcard, bound to a command or
/// unbound with `~` so the keypress reaches the app.
struct SkhdProcessMapping: Identifiable, Hashable {
    var id = UUID()
    var process: String?
    var command: String?

    var isWildcard: Bool { process == nil }
    var isUnbound: Bool { command == nil }

    // contentEquals(other): Equality that ignores the row identity used by the editor.
    func contentEquals(_ other: SkhdProcessMapping) -> Bool {
        process == other.process && command == other.command
    }
}

/// What a hotkey does when it matches.
enum SkhdAction: Hashable {
    case command(String)
    case processMap([SkhdProcessMapping])
    case activateMode(String)

    // contentEquals(other): Compare actions by content; per-app lists must match entry for entry.
    func contentEquals(_ other: SkhdAction) -> Bool {
        switch (self, other) {
        case (.command(let a), .command(let b)): return a == b
        case (.activateMode(let a), .activateMode(let b)): return a == b
        case (.processMap(let a), .processMap(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.contentEquals($1) }
        default: return false
        }
    }
}

/// One binding line, kept close to the file so unchanged bindings are written back verbatim.
struct SkhdHotkey: Identifiable, Hashable {
    var id = UUID()
    /// Comment lines written directly above the binding, without the `#`.
    var comment: [String] = []
    /// Mode names before `<`. Empty means the default mode.
    var modes: [String] = []
    var modifiers: [SkhdModifier] = []
    var key: SkhdKey
    /// `->` after the key: the keypress is also delivered to the app.
    var passthrough = false
    var action: SkhdAction
    /// The exact statement text from the file, used while the binding is unchanged.
    var sourceText: String?

    // contentEquals(other): Whether the binding and its comment match, ignoring identity and source
    // text.
    func contentEquals(_ other: SkhdHotkey) -> Bool {
        comment == other.comment && modes == other.modes && modifiers == other.modifiers
            && key == other.key && passthrough == other.passthrough && action.contentEquals(other.action)
    }

    // statementEquals(other): Whether the statement itself matches, ignoring the comment, so
    // callers know when the verbatim source text can still be reused.
    func statementEquals(_ other: SkhdHotkey) -> Bool {
        modes == other.modes && modifiers == other.modifiers && key == other.key
            && passthrough == other.passthrough && action.contentEquals(other.action)
    }

    var shortcutSymbols: String { SkhdShortcutText.symbols(modifiers: modifiers, key: key) }

    // commentText(line): Drop the single space that separates `#` from the comment text, nothing
    // more, so text round-trips exactly while the user is still typing it.
    private static func commentText(_ line: String) -> String {
        line.hasPrefix(" ") ? String(line.dropFirst()) : line
    }

    /// The first comment line without a leading shortcut prefix such as `⌥⇧A — `.
    var title: String {
        guard let first = comment.first else { return "" }
        let line = Self.commentText(first)
        // A shortcut prefix such as `⌥⇧A — ` is not part of the title.
        if let split = SkhdShortcutText.splitTitle(line.trimmingCharacters(in: .whitespaces)) {
            // Keep the typed text after the prefix verbatim, trailing spaces included. The title
            // starts right after the prefix and its three-character separator; searching for the
            // title text instead could match inside the prefix, such as the F in `⌥⇧F — Firefox`.
            let text = line.drop(while: \.isWhitespace)
            let skip = split.prefix.count + SkhdShortcutText.separatorLength
            // Slice the original line when the recognized prefix fits it.
            if let start = text.index(text.startIndex, offsetBy: skip, limitedBy: text.endIndex) {
                return String(text[start...])
            }
            return split.title
        }
        return line
    }

    /// Whether the first comment line starts with the shortcut written in symbols.
    var titleHasShortcutPrefix: Bool {
        guard let first = comment.first?.trimmingCharacters(in: .whitespaces) else { return false }
        return SkhdShortcutText.splitTitle(first) != nil
    }

    /// Comment lines after the title line, as stored.
    var notes: [String] { Array(comment.dropFirst()) }

    /// The note lines as the user typed them, joined for a text field.
    var noteText: String { notes.map(Self.commentText).joined(separator: "\n") }

    // setKey(newKey): Change the key and keep skhd's fn flag right. macOS sends arrow, navigation,
    // and function key presses with fn. skhd adds that flag itself only when such a key is written
    // by name, so a key code for one needs an explicit fn to fire, and a name makes it redundant.
    // Leaving such a code for an ordinary key drops the fn it needed, which would otherwise stop
    // the new key from firing.
    mutating func setKey(_ newKey: SkhdKey) {
        let oldKey = key
        key = newKey
        // By name: skhd supplies fn, so an explicit one is dropped.
        if newKey.hasImplicitFn {
            modifiers.removeAll { $0 == .fn }
        } else if newKey.needsExplicitFn {
            // By code: the binding needs fn spelled out.
            // Preserve an existing fn rather than adding a duplicate modifier.
            if !modifiers.contains(.fn) { modifiers = SkhdModifier.canonical(modifiers + [.fn]) }
        } else if oldKey.needsExplicitFn {
            // From such a code to an ordinary key: the fn belonged to the old key.
            modifiers.removeAll { $0 == .fn }
        }
    }

    // setTitle(title, keepPrefix): Rewrite the first comment line, keeping a shortcut prefix when
    // the file used one. An empty title removes the line, unless notes follow and need the line to
    // stay notes.
    mutating func setTitle(_ title: String, keepPrefix: Bool) {
        var updated = comment
        // Without a title the line goes away, or is blanked when notes still need a first line.
        if title.isEmpty {
            // With no following notes, remove the title line entirely.
            if updated.count <= 1 { updated = [] } else {
                // Keep an empty title slot so the first note does not become a title.
                updated[0] = ""
            }
        } else {
            // Replace or add the first line; the prefix is rebuilt from the current shortcut.
            let line = keepPrefix ? " \(shortcutSymbols) — \(title)" : " \(title)"
            // Add the missing title slot.
            if updated.isEmpty { updated = [line] } else {
                // Updating the title must leave all note lines intact.
                updated[0] = line
            }
        }
        comment = updated
    }

    // setNotes(notes): Replace the comment lines after the title. Each note gets the same space
    // after `#` as the title line.
    mutating func setNotes(_ notes: [String]) {
        let title = comment.first
        let lines = notes.map { " " + $0 }
        // Without notes only a non-empty title line survives.
        if lines.isEmpty {
            comment = (title?.isEmpty == false) ? [title!] : []
        } else {
            // A missing title becomes an empty line so the notes keep their position.
            comment = [title ?? ""] + lines
        }
    }

    /// A short description of the action for list rows.
    var actionSummary: String {
        switch action {
        case .command(let command): return command.trimmingCharacters(in: .whitespacesAndNewlines)
        case .activateMode(let mode): return "; " + mode
        case .processMap(let mappings):
            let named = mappings.filter { !$0.isWildcard }.compactMap(\.process)
            return named.joined(separator: ", ")
        }
    }
}

/// `:: name @ : command`
struct SkhdModeDeclaration: Identifiable, Hashable {
    var id = UUID()
    var comment: [String] = []
    var name: String
    var capture = false
    var command: String?
    var sourceText: String?

    // contentEquals(other): Whether the declaration and its comment match, ignoring identity and
    // source text.
    func contentEquals(_ other: SkhdModeDeclaration) -> Bool {
        comment == other.comment && name == other.name && capture == other.capture && command == other.command
    }
}

/// `.load "file"`
struct SkhdLoadDirective: Identifiable, Hashable {
    var id = UUID()
    var comment: [String] = []
    var path: String
    var sourceText: String?
}

/// `.blacklist [ "app" ... ]`
struct SkhdBlacklist: Identifiable, Hashable {
    var id = UUID()
    var comment: [String] = []
    var processes: [String]
    var sourceText: String?
}

/// Text skhd would reject. It is kept verbatim so nothing is lost when the file is saved.
struct SkhdRawText: Identifiable, Hashable {
    var id = UUID()
    var comment: [String] = []
    var text: String
    var error: String
    var line: Int
}

/// Comment lines that are not attached to a statement.
struct SkhdCommentBlock: Identifiable, Hashable {
    var id = UUID()
    var lines: [String]
}

/// A run of empty lines between items.
struct SkhdBlankLines: Identifiable, Hashable {
    var id = UUID()
    var count: Int
}
