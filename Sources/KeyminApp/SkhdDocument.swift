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

/// Everything a configuration file contains, in file order.
enum SkhdItem: Identifiable, Hashable {
    case blank(SkhdBlankLines)
    case comment(SkhdCommentBlock)
    case hotkey(SkhdHotkey)
    case mode(SkhdModeDeclaration)
    case load(SkhdLoadDirective)
    case blacklist(SkhdBlacklist)
    case raw(SkhdRawText)

    var id: UUID {
        switch self {
        case .blank(let value): return value.id
        case .comment(let value): return value.id
        case .hotkey(let value): return value.id
        case .mode(let value): return value.id
        case .load(let value): return value.id
        case .blacklist(let value): return value.id
        case .raw(let value): return value.id
        }
    }

    var hotkey: SkhdHotkey? {
        // Expose only bindings; configuration directives have separate editors.
        if case .hotkey(let value) = self { return value }
        return nil
    }
}

/// A problem skhd would report, or a weaker warning the editor noticed.
struct SkhdDiagnostic: Identifiable, Hashable {
    enum Severity: Hashable { case error, warning }
    var id = UUID()
    var severity: Severity
    var message: String
    var itemID: UUID?
    var line: Int?
    /// A field the user has not filled in yet. It still blocks saving, but the editor shows it
    /// as a hint rather than as an error, because nothing is wrong yet.
    var isIncomplete = false
}

/// The parsed configuration with the helpers the editor needs.
struct SkhdDocument: Hashable {
    var items: [SkhdItem] = []

    /// Hotkeys in file order.
    var hotkeys: [SkhdHotkey] { items.compactMap(\.hotkey) }

    /// Mode declarations in file order.
    var modeDeclarations: [SkhdModeDeclaration] {
        items.compactMap {
            // Keep declarations for the mode editor.
            if case .mode(let value) = $0 { return value } else {
                // Other statements do not declare modes.
                return nil
            }
        }
    }

    /// Names of the declared modes in file order. `default` appears only when the file declares it.
    var declaredModeNames: [String] { modeDeclarations.map(\.name) }

    var blacklists: [SkhdBlacklist] {
        items.compactMap {
            // Keep every blacklist block, including files with several blocks.
            if case .blacklist(let value) = $0 { return value } else {
                // Exclude statements with no blacklist entries.
                return nil
            }
        }
    }

    var loadDirectives: [SkhdLoadDirective] {
        items.compactMap {
            // Keep included-file directives in document order.
            if case .load(let value) = $0 { return value } else {
                // Other statements do not name included files.
                return nil
            }
        }
    }

    var rawItems: [SkhdRawText] {
        items.compactMap {
            // Keep unparsed statements for diagnostics and lossless saving.
            if case .raw(let value) = $0 { return value } else {
                // Successfully parsed items have their own typed representation.
                return nil
            }
        }
    }

    // index(of id): Find the document item's position, or nil after removal.
    func index(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    // update(hotkey): Replace a hotkey and drop its verbatim source when the statement changed.
    mutating func update(_ hotkey: SkhdHotkey) {
        guard let index = index(of: hotkey.id), case .hotkey(let existing) = items[index] else { return }
        var updated = hotkey
        // Comment-only edits can still reuse the exact binding statement.
        if !existing.statementEquals(hotkey) { updated.sourceText = nil }
        items[index] = .hotkey(updated)
    }

    // update(mode): Replace a mode declaration and drop its verbatim source when anything but the
    // comment changed.
    mutating func update(_ mode: SkhdModeDeclaration) {
        guard let index = index(of: mode.id), case .mode(let existing) = items[index] else { return }
        var updated = mode
        // Only a comment edit may keep the original statement text.
        if existing.name != mode.name || existing.capture != mode.capture || existing.command != mode.command {
            updated.sourceText = nil
        }
        items[index] = .mode(updated)
    }

    // remove(id): Remove the item with this id without leaving a doubled or trailing blank line.
    mutating func remove(_ id: UUID) {
        guard let index = index(of: id) else { return }
        items.remove(at: index)
        // Two blank runs now touch, so drop the one that followed the removed item.
        if index < items.count, case .blank = items[index], index > 0, case .blank = items[index - 1] {
            items.remove(at: index)
        } else if index == items.count, index > 0, case .blank = items[index - 1] {
            // The last item went away, so the blank line before it is now trailing.
            items.remove(at: index - 1)
        }
    }

    // append(item): Append an item after one blank line, keeping the file readable.
    mutating func append(_ item: SkhdItem) {
        // Separate it from the previous item unless the file already ends with blank lines.
        if let last = items.last, !isBlank(last) {
            items.append(.blank(SkhdBlankLines(count: 1)))
        }
        items.append(item)
    }

    // insert(item, after id): Insert after this item, separated by one
    // blank line. An unknown id appends instead.
    mutating func insert(_ item: SkhdItem, after id: UUID) {
        guard let index = index(of: id) else {
            append(item)
            return
        }
        items.insert(contentsOf: [.blank(SkhdBlankLines(count: 1)), item], at: index + 1)
    }

    // insertModeDeclaration(mode): Mode declarations must precede their first use, and any binding
    // may be moved into the new mode, so it goes above the first binding: right after the last
    // declaration above that binding or, when there is none, directly above the binding.
    mutating func insertModeDeclaration(_ mode: SkhdModeDeclaration) {
        let firstHotkey = items.firstIndex { $0.hotkey != nil }
        // Only declarations above the first binding count; later ones may follow bindings.
        let lastMode = items[..<(firstHotkey ?? items.count)].lastIndex {
            // A declaration anchors insertion beside the existing modes.
            if case .mode = $0 { return true } else {
                // Skip comments and other statements when locating that anchor.
                return false
            }
        }
        // Keep declarations together.
        if let lastMode {
            items.insert(.mode(mode), at: lastMode + 1)
        } else if let firstHotkey {
            // The first declaration above the bindings gets a blank line after it.
            items.insert(contentsOf: [.mode(mode), .blank(SkhdBlankLines(count: 1))], at: firstHotkey)
        } else {
            // There are no bindings and no declarations, so the end of the file is fine.
            append(.mode(mode))
        }
    }

    // isBlank(item): Whether the item is a run of blank lines.
    private func isBlank(_ item: SkhdItem) -> Bool {
        // Only explicit blank runs can be merged or removed as spacing.
        if case .blank = item { return true }
        return false
    }

    // MARK: Diagnostics

    // diagnostics(): Problems in the current document, errors first. Modes count as declared only
    // from their declaration onward, matching skhd's single pass over the file.
    func diagnostics() -> [SkhdDiagnostic] {
        var result: [SkhdDiagnostic] = []
        // A mode list may always name `default`. `declaredNames` finds duplicate declarations, and
        // `seen` maps a mode, flags, and key to the first hotkey bound to them.
        var declared = Set<String>(["default"])
        var seen: [String: UUID] = [:]
        var declaredNames = Set<String>()
        // skhd creates the default mode only for a binding without a mode list, a mode list that
        // names it, or `:: default`. Before that, `; default` is an undeclared mode to skhd.
        var defaultExists = false

        for item in items {
            switch item {
            case .raw(let raw):
                result.append(SkhdDiagnostic(severity: .error, message: raw.error, itemID: raw.id, line: raw.line))
            case .mode(let mode):
                // The editor accepts any typed name, so validate it the way the tokenizer would.
                if !SkhdTokenizer.isIdentifier(mode.name) {
                    result.append(SkhdDiagnostic(
                        severity: .error,
                        message: localizedFormat("Mode name “%@” must start with a letter, contain only letters and underscores, and may end with digits.", mode.name),
                        itemID: mode.id
                    ))
                } else if !SkhdTokenizer.isModeName(mode.name) {
                    // skhd reads a single letter or a key or modifier word as a key, not a name.
                    result.append(SkhdDiagnostic(
                        severity: .error,
                        message: localizedFormat("“%@” is a key or modifier name in skhd and cannot name a mode.", mode.name),
                        itemID: mode.id
                    ))
                }
                // A regenerated command ending in a backslash would swallow the next line.
                if mode.sourceText == nil, let command = mode.command, SkhdTokenizer.endsWithContinuation(command) {
                    result.append(SkhdDiagnostic(
                        severity: .error,
                        message: localizedFormat("The command for mode “%@” ends with a backslash, which would join the next line to it.", mode.name),
                        itemID: mode.id
                    ))
                }
                // A regenerated command cannot keep a line break inside quotes.
                if mode.sourceText == nil, let command = mode.command, SkhdSerializer.breaksQuotedText(command) {
                    result.append(SkhdDiagnostic(severity: .warning, message: Self.quotedLineBreakMessage, itemID: mode.id))
                }
                // Catches duplicates made in the editor and a second `:: default`, which the
                // parser allows.
                if declaredNames.contains(mode.name) {
                    result.append(SkhdDiagnostic(
                        severity: .error,
                        message: localizedFormat("Mode “%@” is declared more than once.", mode.name),
                        itemID: mode.id
                    ))
                }
                declaredNames.insert(mode.name)
                declared.insert(mode.name)
                // `:: default` creates the default mode when no binding has done so yet.
                if mode.name == "default" { defaultExists = true }
            case .blacklist(let list):
                // The parser rejects an empty list, but the editor can make one, and a name can be
                // blank either way, from the editor or from `""` in the file.
                if list.processes.isEmpty || list.processes.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    result.append(SkhdDiagnostic(
                        severity: .error,
                        message: localized("The blacklist needs at least one app name, and names cannot be empty."),
                        itemID: list.id
                    ))
                }
                // skhd's string token has no escapes, so a quote would end a name early.
                if list.processes.contains(where: { $0.contains("\"") }) {
                    result.append(SkhdDiagnostic(severity: .error, message: localized("App names cannot contain quotation marks."), itemID: list.id))
                }
                // skhd compares names exactly, apart from case, so spaces around a name mean it
                // never matches an app. The editor keeps them while the user types.
                for name in list.processes {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Blank names already have the error above.
                    if !trimmed.isEmpty, trimmed != name {
                        result.append(SkhdDiagnostic(
                            severity: .warning,
                            message: localizedFormat("The blacklisted app name “%@” has spaces before or after it, so skhd never matches it.", trimmed),
                            itemID: list.id
                        ))
                    }
                }
            case .load(let load):
                // A load directive without a path has nothing to load.
                if load.path.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append(SkhdDiagnostic(severity: .error, message: localized("The load directive needs a file path."), itemID: load.id))
                } else if load.path.contains("\"") {
                    // skhd's string token has no escapes, so a quote would end the path early.
                    result.append(SkhdDiagnostic(severity: .error, message: localized("File paths cannot contain quotation marks."), itemID: load.id))
                }
            case .hotkey(let hotkey):
                // skhd reads the mode list before the action, so a binding in the default mode
                // creates that mode in time for its own `; default`.
                if hotkey.modes.isEmpty || hotkey.modes.contains("default") { defaultExists = true }
                result.append(contentsOf: hotkeyDiagnostics(hotkey, declared: declared, defaultExists: defaultExists, seen: &seen))
            case .blank, .comment:
                break
            }
        }
        // Errors before warnings, then by line; diagnostics without a line sort as line 0.
        return result.sorted { lhs, rhs in
            // A warning never precedes an error just because its line is earlier.
            if lhs.severity != rhs.severity { return lhs.severity == .error }
            return (lhs.line ?? 0) < (rhs.line ?? 0)
        }
    }

    /// The warning for a command whose line break falls inside quotes or a here-document.
    private static var quotedLineBreakMessage: String {
        localized("This command has a line break inside quotes or a here-document. skhd cannot preserve it; saving will change the command's text.")
    }

    // hotkeyDiagnostics(hotkey, declared, defaultExists, seen): Problems with one hotkey.
    // `declared` holds the modes declared above it; `defaultExists` says whether skhd has created
    // the default mode by the time it reads this hotkey's action; `seen` records which hotkey first
    // claimed each mode, flag, and key combination.
    private func hotkeyDiagnostics(_ hotkey: SkhdHotkey, declared: Set<String>, defaultExists: Bool, seen: inout [String: UUID]) -> [SkhdDiagnostic] {
        var result: [SkhdDiagnostic] = []
        // skhd rejects a mode that is used before its declaration.
        for mode in hotkey.modes where !declared.contains(mode) {
            result.append(SkhdDiagnostic(
                severity: .error,
                message: localizedFormat("Mode “%@” is used before it is declared with “:: %@”.", mode, mode),
                itemID: hotkey.id
            ))
        }
        switch hotkey.action {
        case .command(let command):
            // A blank command is a binding the user has not finished.
            if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(SkhdDiagnostic(severity: .error, message: localized("The command is empty."), itemID: hotkey.id, isIncomplete: true))
            } else if hotkey.sourceText == nil, SkhdTokenizer.endsWithContinuation(command) {
                // A regenerated command ending in a backslash would swallow the next line.
                result.append(SkhdDiagnostic(
                    severity: .error,
                    message: localized("The command ends with a backslash, which would join the next line to it."),
                    itemID: hotkey.id
                ))
            }
            // A regenerated command cannot keep a line break inside quotes.
            if hotkey.sourceText == nil, SkhdSerializer.breaksQuotedText(command) {
                result.append(SkhdDiagnostic(severity: .warning, message: Self.quotedLineBreakMessage, itemID: hotkey.id))
            }
        case .activateMode(let mode):
            // For `;` skhd only looks the mode up, so `default` must already exist above this line.
            if mode == "default", !defaultExists {
                result.append(SkhdDiagnostic(
                    severity: .error,
                    message: localized("The default mode does not exist yet at this point in the file. Add a binding in the default mode above this one, or declare “:: default” above it."),
                    itemID: hotkey.id
                ))
            } else if !declared.contains(mode) {
                // Any other mode entered with `;` must be declared above.
                result.append(SkhdDiagnostic(
                    severity: .error,
                    message: localizedFormat("Mode “%@” is used before it is declared with “:: %@”.", mode, mode),
                    itemID: hotkey.id
                ))
            }
        case .processMap(let mappings):
            // skhd rejects a list that holds only the `*` entry.
            if !mappings.contains(where: { !$0.isWildcard }) {
                result.append(SkhdDiagnostic(
                    severity: .error,
                    message: localized("Per-app bindings need at least one named app."),
                    itemID: hotkey.id
                ))
            }
            // Check each entry's name and command.
            for mapping in mappings {
                let name = mapping.process?.trimmingCharacters(in: .whitespaces)
                // A blank name is unfinished.
                if let name, name.isEmpty {
                    result.append(SkhdDiagnostic(
                        severity: .error,
                        message: localized("Each per-app entry needs an app name."),
                        itemID: hotkey.id,
                        isIncomplete: true
                    ))
                } else if let name, name.contains("\"") {
                    // skhd's string token has no escapes, so a quote would end the name early.
                    result.append(SkhdDiagnostic(
                        severity: .error,
                        message: localized("App names cannot contain quotation marks."),
                        itemID: hotkey.id
                    ))
                }
                // Name the entry in command messages.
                let subject = mapping.isWildcard ? localized("other apps") : (name?.isEmpty == false ? name! : localized("the new app"))
                // A bound entry with a blank command is unfinished.
                if let command = mapping.command, command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(SkhdDiagnostic(
                        severity: .error,
                        message: localizedFormat("The command for %@ is empty.", subject),
                        itemID: hotkey.id,
                        isIncomplete: true
                    ))
                } else if hotkey.sourceText == nil, let command = mapping.command, SkhdTokenizer.endsWithContinuation(command) {
                    // A regenerated command ending in a backslash would swallow the next line.
                    result.append(SkhdDiagnostic(
                        severity: .error,
                        message: localizedFormat("The command for %@ ends with a backslash, which would join the next line to it.", subject),
                        itemID: hotkey.id
                    ))
                }
            }
            // Regenerated per-app commands cannot keep a line break inside quotes either.
            if hotkey.sourceText == nil, mappings.contains(where: { $0.command.map(SkhdSerializer.breaksQuotedText) ?? false }) {
                result.append(SkhdDiagnostic(severity: .warning, message: Self.quotedLineBreakMessage, itemID: hotkey.id))
            }
            // skhd keeps only the last wildcard command, so earlier ones are silently lost.
            if mappings.count > 1, mappings.filter(\.isWildcard).count > 1 {
                result.append(SkhdDiagnostic(
                    severity: .warning,
                    message: localized("Only the last “other apps” entry takes effect."),
                    itemID: hotkey.id
                ))
            }
        }
        // The editor can hold any character, but skhd only takes an ASCII letter or digit as a key.
        if case .character(let character) = hotkey.key, !(character.isASCII && (character.isLetter || character.isNumber)) {
            result.append(SkhdDiagnostic(severity: .error, message: localized("Single-character keys must be a letter or digit."), itemID: hotkey.id))
        }
        let liveInDefaultMode = hotkey.modes.isEmpty || hotkey.modes.contains("default")
        // Warn about typing ordinary characters only when the binding is live by default.
        if hotkey.modifiers.isEmpty, liveInDefaultMode, case .character = hotkey.key {
            result.append(SkhdDiagnostic(
                severity: .warning,
                message: localized("This key has no modifier, so typing it anywhere triggers the binding."),
                itemID: hotkey.id
            ))
        }
        // Duplicates are checked per mode with keywords expanded to generic flags, because a
        // generic modifier also matches the side-specific keys and `hyper` and `meh` stand for flag
        // sets. Navigation keys carry the `fn` flag skhd adds for them.
        var flags = Set(hotkey.modifiers.flatMap(\.expanded))
        // Named navigation keys add fn even when it is absent from the text.
        if hotkey.key.hasImplicitFn { flags.insert(.fn) }
        let flagText = flags.map(\.rawValue).sorted().joined(separator: "+")
        let modes = hotkey.modes.isEmpty ? ["default"] : hotkey.modes
        for mode in modes {
            let identity = "\(mode)|\(flagText)|\(hotkey.key.identity)"
            // Another hotkey already owns this combination in this mode.
            if let other = seen[identity], other != hotkey.id {
                result.append(SkhdDiagnostic(
                    severity: .warning,
                    message: localizedFormat("%@ is bound more than once in mode “%@”.", hotkey.shortcutSymbols, mode),
                    itemID: hotkey.id
                ))
            } else {
                // The first binding claims the slot; later ones get the warning.
                seen[identity] = hotkey.id
            }
        }
        return result
    }
}

// MARK: - Tokenizer

/// A token in skhd's configuration language. The rules mirror skhd's `tokenize.c`.
struct SkhdToken {
    /// Compound tokens carry their text without the introducer: `activate` holds the mode name
    /// after `;`, `command` the text after `:` up to an unescaped line end, `option` the word after
    /// `.`, and `string` the text between the quotes. `keyHex` keeps its `0x` prefix.
    enum Kind {
        case identifier, activate, command, modifier, literal, keyHex, key
        case decl, comma, insert, plus, dash, arrow, capture, unbound, wildcard, string, option
        case beginList, endList, unknown, endOfStream
    }

    var kind: Kind
    var text: String
    var line: Int
    var column: Int
    var endLine: Int
}

/// Splits configuration text into tokens, mirroring skhd's `tokenize.c`. Comments are skipped here;
/// the parser reads them back from the raw lines.
struct SkhdTokenizer {
    private let characters: [Character]
    private var index = 0
    private(set) var line = 1
    private(set) var column = 1
    private var lineStarts: [Int]

    // init(text): Index the start of every line so the parser can restart the tokenizer after an
    // error.
    init(_ text: String) {
        characters = Array(text)
        var starts = [0]
        for (offset, character) in characters.enumerated() where Self.isLineBreak(character) {
            starts.append(offset + 1)
        }
        lineStarts = starts
    }

    // isSpace(character): Whether skhd skips the character between tokens. Its tokenizer uses C
    // isspace(), which accepts only space, tab, line feed, vertical tab, form feed, and carriage
    // return. Swift reads "\r\n" as one character, so that pair counts too. A no-break space, an
    // ideographic space, or a byte order mark is not skipped and becomes an unknown token.
    static func isSpace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20].contains($0.value) }
    }

    /// The characters isSpace(_:) accepts, as a set for trimming lines.
    static let spaces = CharacterSet(charactersIn: " \t\n\u{0B}\u{0C}\r")

    // isLineBreak(character): Whether the character ends a line: a line feed, or "\r\n", which
    // Swift reads as one character.
    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r\n"
    }

    // isIdentifier(text): Whether the whole text is a mode or option identifier: an ASCII letter,
    // then letters or underscores, then optional digits, with nothing after them. skhd starts a
    // word only on a letter, so a leading underscore is rejected.
    static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.first, first.isASCII, first.isLetter else { return false }
        var sawDigit = false
        for character in text {
            // Letters may not follow the digit run.
            if character.isASCII, character.isLetter || character == "_" {
                // Reject a return to the letter part after digits have begun.
                if sawDigit { return false }
            } else if character.isASCII, character.isNumber {
                // Digits may only end the identifier.
                sawDigit = true
            } else {
                // Anything else, including non-ASCII letters, is rejected.
                return false
            }
        }
        return true
    }

    // isModeName(text): Whether skhd reads the text as a mode name: a valid identifier that is
    // not a single letter, a modifier, or a key name, which its tokenizer reads as keys instead.
    static func isModeName(_ text: String) -> Bool {
        isIdentifier(text) && identifierKind(text) == .identifier
    }

    // endsWithContinuation(command): Whether the command ends with an unescaped backslash, the last
    // of an odd run. skhd reads that as a line continuation, so the next statement in the file
    // would become part of the command. An even run ends in an escaped backslash, which is text.
    static func endsWithContinuation(_ command: String) -> Bool {
        command.trimmingCharacters(in: .whitespacesAndNewlines).reversed().prefix { $0 == "\\" }.count % 2 == 1
    }

    // reset(toLine target): Resume at this 1-based line after a parse error. A
    // line past the last one moves to the end of the text, so the next token is `endOfStream` and
    // a failed last line without a final newline is never parsed again.
    mutating func reset(toLine target: Int) {
        // Past the last line: stop at the end, on the position advance() would have reached.
        if target > lineStarts.count {
            index = characters.count
            line = lineStarts.count
            column = characters.count - (lineStarts.last ?? 0) + 1
            return
        }
        // Otherwise start the requested line; anything before line 1 means line 1.
        let lineIndex = max(0, target - 1)
        index = lineStarts[lineIndex]
        line = lineIndex + 1
        column = 1
    }

    private var current: Character? { index < characters.count ? characters[index] : nil }

    // peekCharacter([offset = 1]): The character this many positions ahead, or nil past the end.
    private func peekCharacter(_ offset: Int = 1) -> Character? {
        index + offset < characters.count ? characters[index + offset] : nil
    }

    // advance(): Consume one character, counting lines and columns the way skhd does.
    private mutating func advance() {
        guard index < characters.count else { return }
        // Start the next line; the increment below makes it column 1.
        if Self.isLineBreak(characters[index]) {
            line += 1
            column = 0
        }
        column += 1
        index += 1
    }

    // eatWhitespace(): Skip the characters C isspace() accepts, and nothing else, as skhd does.
    private mutating func eatWhitespace() {
        while let character = current, Self.isSpace(character) { advance() }
    }

    // eatComment(): Skip to the end of the line; the line break itself is left for eatWhitespace().
    private mutating func eatComment() {
        while let character = current, !Self.isLineBreak(character) { advance() }
    }

    // eatCommand(): Consume command text to the end of the line. A backslash escapes the next
    // character, so an escaped line break continues the command on the next line. Before "\r\n",
    // which Swift reads as one character, the backslash escapes only the carriage return, as in
    // skhd, so the line feed still ends the command.
    private mutating func eatCommand() {
        while let character = current, !Self.isLineBreak(character) {
            // A backslash takes the next character with it.
            if character == "\\" {
                advance()
                // An escaped carriage return leaves its line feed to end the command.
                if current == "\r\n" { break }
            }
            advance()
        }
    }

    // eatHex(): Consume hex digits the way skhd does: ASCII digits and uppercase A to F only, so a
    // lowercase digit ends the key code early. The parser reports that case.
    private mutating func eatHex() {
        while let character = current, character.isASCII, character.isNumber || ("A"..."F").contains(character) {
            advance()
        }
    }

    // eatString(): Consume up to the closing quote. There are no escapes, exactly as in skhd.
    private mutating func eatString() {
        while let character = current, character != "\"" { advance() }
    }

    // eatOption(): Consume the option name up to the next character C isspace() accepts.
    private mutating func eatOption() {
        while let character = current, !Self.isSpace(character) { advance() }
    }

    // isIdentifierCharacter(character): Whether the character can appear in the letter part of an
    // identifier.
    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character == "_")
    }

    // eatIdentifier(): Consume letters and underscores, then any trailing digits.
    private mutating func eatIdentifier() {
        while let character = current, Self.isIdentifierCharacter(character) { advance() }
        while let character = current, character.isASCII, character.isNumber { advance() }
    }

    // text(from start): Return the characters consumed since this array index.
    private func text(from start: Int) -> String {
        String(characters[start..<index])
    }

    // identifierKind(text): Classify a word: a single character is a key, then come modifier and
    // key keywords, and anything else is a plain identifier such as a mode name.
    private static func identifierKind(_ text: String) -> SkhdToken.Kind {
        // Single letters are keys even if they could form identifiers.
        if text.count == 1 { return .key }
        // Modifier keywords must enter the modifier-list parser.
        if SkhdModifier.keywords.contains(text) { return .modifier }
        // Named keys cannot be used as mode identifiers.
        if SkhdLiteralKey.keywords.contains(text) { return .literal }
        return .identifier
    }

    // next(): Return the next token, skipping whitespace and comments, or `endOfStream` at the end.
    mutating func next() -> SkhdToken {
        eatWhitespace()
        let startLine = line
        let startColumn = column
        guard let character = current else {
            return SkhdToken(kind: .endOfStream, text: "", line: startLine, column: startColumn, endLine: startLine)
        }
        var start = index
        advance()
        var kind: SkhdToken.Kind
        // Single-character tokens keep their text; compound ones move `start` past the introducer.
        switch character {
        case "+": kind = .plus
        case ",": kind = .comma
        case "<": kind = .insert
        case "@": kind = .capture
        case "~": kind = .unbound
        case "*": kind = .wildcard
        case "[": kind = .beginList
        case "]": kind = .endList
        case ".":
            start = index
            eatOption()
            kind = .option
        case "\"":
            start = index
            eatString()
            let token = SkhdToken(kind: .string, text: text(from: start), line: startLine, column: startColumn, endLine: line)
            advance()
            return token
        case "#":
            eatComment()
            return next()
        case "-":
            // `->` marks passthrough.
            if current == ">" {
                advance()
                kind = .arrow
            } else {
                // A lone dash separates the modifiers from the key.
                kind = .dash
            }
        case ";":
            eatWhitespace()
            start = index
            eatIdentifier()
            kind = .activate
        case ":":
            // `::` starts a mode declaration.
            if current == ":" {
                advance()
                kind = .decl
            } else {
                // A single colon starts a command that runs to the end of the line.
                eatWhitespace()
                start = index
                eatCommand()
                kind = .command
            }
        default:
            // `0x` starts a key code; the prefix stays in the text.
            if character == "0", current == "x" {
                advance()
                eatHex()
                kind = .keyHex
            } else if character.isASCII, character.isNumber {
                // A digit on its own is a key.
                kind = .key
            } else if character.isASCII, character.isLetter {
                // A word starts on a letter, as in skhd, and is a key, a keyword, or an identifier.
                eatIdentifier()
                kind = Self.identifierKind(text(from: start))
            } else {
                // Anything else is left for the parser to report.
                kind = .unknown
            }
        }
        return SkhdToken(kind: kind, text: text(from: start), line: startLine, column: startColumn, endLine: line)
    }
}

// MARK: - Parser

/// Parses a configuration the way skhd does, but keeps going after an error so one bad line does
/// not hide the rest of the file. Comments and blank lines are preserved as items. Use of an
/// undeclared mode is not an error here; `SkhdDocument.diagnostics()` reports it.
struct SkhdParser {
    /// A syntax error at a token. The parser turns it into a raw item.
    struct Failure: Error {
        let token: SkhdToken
        let message: String
    }

    private let lines: [String]
    private var tokenizer: SkhdTokenizer
    private var current: SkhdToken
    private var previous: SkhdToken
    private var declaredModes = Set<String>(["default"])

    // parse(text): Parse the whole text into a document.
    static func parse(_ text: String) -> SkhdDocument {
        var parser = SkhdParser(text)
        return parser.run()
    }

    // init(text): Normalize line endings, split the text into lines for run() and gapItems(), and
    // prime the first token. As in skhd, only a line feed ends a line. Carriage returns right
    // before one, or at the very end of the text, are dropped, as Save drops them, except after a
    // backslash: skhd lets the backslash escape the carriage return, so the line feed still ends
    // the command, and the tokenizer reads the pair the same way. Any other carriage return stays
    // and is read as skhd reads it: as a space between words, or as part of a comment or command.
    private init(_ text: String) {
        let normalized = text.replacingOccurrences(of: "(?<!\\\\)\\r+(?=\\n|\\z)", with: "", options: .regularExpression)
        var split = normalized.components(separatedBy: "\n")
        // The final newline terminates the last line; it is not an extra blank line.
        if split.count > 1, split.last == "" { split.removeLast() }
        lines = split
        tokenizer = SkhdTokenizer(normalized)
        current = tokenizer.next()
        previous = current
    }

    // run(): Parse statements one at a time. Comment and blank lines between statements become
    // items, a comment block directly above a statement is attached to it, and a statement that
    // fails becomes a raw item before parsing resumes on the following line. Statements that share
    // a line are written from their fields, each on its own line, because none of them can keep
    // the whole line as its source; when one of them fails, the line becomes one raw item.
    private mutating func run() -> SkhdDocument {
        var items: [SkhdItem] = []
        var consumedLine = 0
        // The first statement of the latest run of statements on shared lines: its position in
        // `items`, its first line, and its attached comment. Nil after a raw item.
        var group: (index: Int, line: Int, comment: [String])?

        while true {
            let token = current
            let statementLine = token.kind == .endOfStream ? lines.count + 1 : token.line
            // Lines between the last statement and this token hold only comments and blank lines.
            var pending = gapItems(from: consumedLine + 1, to: statementLine - 1)
            // Trailing comments and blank lines are kept as items.
            if token.kind == .endOfStream {
                items.append(contentsOf: pending)
                break
            }
            var attached: [String] = []
            // A comment block directly above the statement supplies its title and notes.
            if case .comment(let block)? = pending.last {
                attached = block.lines
                pending.removeLast()
            }
            items.append(contentsOf: pending)
            // The statement starts on the line where the previous one ended.
            let sharesLine = token.line <= consumedLine && group != nil

            do {
                var item = try statement()
                item.attach(attached)
                // A command or string that runs to the end of the file can step past the last
                // line, so the end is clamped as in the error path below.
                let endLine = min(max(previous.endLine, token.line), lines.count)
                if sharesLine, let group {
                    // Neither statement may write the shared line back, so both are written
                    // from their fields; later statements on the line never get source text.
                    items[group.index].setSource(nil)
                } else {
                    // Keep the statement's exact lines so an unchanged item is written back
                    // verbatim, and start a new group with it.
                    item.setSource(lines[(token.line - 1)...(endLine - 1)].joined(separator: "\n"))
                    group = (items.count, token.line, attached)
                }
                items.append(item)
                consumedLine = endLine
            } catch let failure as Failure {
                // Keep the statement's lines up to the error verbatim and resume on the next line.
                var startLine = token.line
                var comment = attached
                // On a shared line the statements before the failure become part of the raw item,
                // so the line is written back once, exactly as it was.
                if sharesLine, let group {
                    items.removeSubrange(group.index...)
                    startLine = group.line
                    comment = group.comment
                }
                let endLine = max(failure.token.line, previous.endLine, token.line)
                let text = lines[(startLine - 1)...(min(endLine, lines.count) - 1)].joined(separator: "\n")
                items.append(.raw(SkhdRawText(
                    comment: comment,
                    text: text,
                    error: localizedFormat("Line %lld: %@", Int64(failure.token.line), failure.message),
                    line: failure.token.line
                )))
                group = nil
                consumedLine = endLine
                tokenizer.reset(toLine: endLine + 1)
                current = tokenizer.next()
                previous = current
            } catch {
                // Only Failure is thrown; this branch exists for exhaustiveness.
                break
            }
        }
        return SkhdDocument(items: items)
    }

    // gapItems(from start, to end): Convert the intervening lines, given as
    // 1-based line numbers, into items. Any other line would have produced a token, so none occur.
    private func gapItems(from start: Int, to end: Int) -> [SkhdItem] {
        var items: [SkhdItem] = []
        var blankCount = 0
        var commentLines: [String] = []
        // flushBlanks(): Emit the pending blank run as one item.
        func flushBlanks() {
            // Avoid empty spacing items when the gap contains only comments.
            if blankCount > 0 { items.append(.blank(SkhdBlankLines(count: blankCount))) }
            blankCount = 0
        }
        // flushComments(): Emit the pending comment lines as one block.
        func flushComments() {
            // Blank-only gaps do not create empty comment blocks.
            if !commentLines.isEmpty { items.append(.comment(SkhdCommentBlock(lines: commentLines))) }
            commentLines = []
        }
        guard start <= end, start >= 1 else { return items }
        for number in start...min(end, lines.count) {
            // Trim what the tokenizer skips, vertical tabs and form feeds included, so every line
            // skhd reads as blank or as a comment is kept as one.
            let line = lines[number - 1]
            let trimmed = line.trimmingCharacters(in: SkhdTokenizer.spaces)
            // A blank line ends the current comment block.
            if trimmed.isEmpty {
                flushComments()
                blankCount += 1
            } else if trimmed.hasPrefix("#") {
                // A comment line ends the current blank run. Indentation before `#` is dropped.
                flushBlanks()
                commentLines.append(String(trimmed.dropFirst()))
            }
        }
        flushBlanks()
        flushComments()
        return items
    }

    // MARK: Token helpers

    // advance(): Consume the current token; `endOfStream` stays current once reached.
    private mutating func advance() {
        previous = current
        // End-of-stream is stable so repeated lookahead cannot advance past the file.
        if current.kind != .endOfStream { current = tokenizer.next() }
    }

    // check(kind): Whether the current token has this kind.
    private func check(_ kind: SkhdToken.Kind) -> Bool {
        current.kind == kind
    }

    // match(kind): Consume the current token when it has this kind.
    private mutating func match(_ kind: SkhdToken.Kind) -> Bool {
        guard check(kind) else { return false }
        advance()
        return true
    }

    // fail(message, [at token = nil]): Build a failure at token, or at the current token. An
    // unknown token that is an invisible space or format character, such as a no-break space or a
    // byte order mark, gets a message that names its code point, because the editor cannot show it.
    private func fail(_ message: String, at token: SkhdToken? = nil) -> Failure {
        let token = token ?? current
        // Name the invisible character; every other failure keeps the parser's message.
        if token.kind == .unknown, let scalar = token.text.unicodeScalars.first,
           scalar.properties.isWhitespace || scalar.properties.generalCategory == .format {
            let code = String(format: "U+%04X", scalar.value)
            return Failure(token: token, message: localizedFormat("Unexpected invisible character %@. skhd separates words only with plain spaces, tabs, and line breaks.", code))
        }
        return Failure(token: token, message: message)
    }

    // MARK: Statements

    // statement(): Parse one statement by its first token: a hotkey, a `::` mode declaration, or a
    // `.` option.
    private mutating func statement() throws -> SkhdItem {
        switch current.kind {
        case .identifier, .modifier, .literal, .keyHex, .key:
            return .hotkey(try hotkey())
        case .decl:
            advance()
            return .mode(try modeDeclaration())
        case .option:
            return try option()
        default:
            throw fail(localized("Expected a mode declaration, modifier, or key."))
        }
    }

    // hotkey(): Parse `[modes <] [modifiers -] key [->]` followed by a command, a per-app list, or
    // `; mode`. Mode names are not checked against declarations here; diagnostics report that.
    private mutating func hotkey() throws -> SkhdHotkey {
        var modes: [String] = []
        // An identifier at the start can only be a mode list, which `<` must close.
        if check(.identifier) {
            modes = try modeList()
            guard match(.insert) else { throw fail(localized("Expected “<” after the mode list.")) }
        }
        var modifiers: [SkhdModifier] = []
        // Modifiers must be followed by `-` and then the key.
        if check(.modifier) {
            modifiers = try modifierList()
            guard match(.dash) else { throw fail(localized("Expected “-” between the modifiers and the key.")) }
        }
        let key = try keyToken()
        let passthrough = match(.arrow)
        let action: SkhdAction
        // `:` introduces a shell command.
        if match(.command) {
            action = .command(previous.text)
        } else if match(.beginList) {
            // `[` introduces per-app commands.
            action = .processMap(try processList())
        } else if match(.activate) {
            // `;` names the mode to enter; the text is empty when no identifier followed it.
            let mode = previous.text
            guard SkhdTokenizer.isIdentifier(mode) else { throw fail(localized("Expected a mode name after “;”."), at: previous) }
            action = .activateMode(mode)
        } else {
            // Every hotkey needs one of the three actions.
            throw fail(localized("Expected “:” and a command, “[” and per-app commands, or “;” and a mode."))
        }
        return SkhdHotkey(modes: modes, modifiers: modifiers, key: key, passthrough: passthrough, action: action)
    }

    // modeList(): Parse comma-separated mode names.
    private mutating func modeList() throws -> [String] {
        var modes: [String] = []
        repeat {
            guard match(.identifier) else { throw fail(localized("Expected a mode name.")) }
            modes.append(previous.text)
        } while match(.comma)
        return modes
    }

    // modifierList(): Parse modifier keywords joined by `+`.
    private mutating func modifierList() throws -> [SkhdModifier] {
        var modifiers: [SkhdModifier] = []
        repeat {
            guard match(.modifier), let modifier = SkhdModifier(rawValue: previous.text) else {
                throw fail(localized("Expected a modifier such as cmd, alt, shift, ctrl, or fn."))
            }
            modifiers.append(modifier)
        } while match(.plus)
        return modifiers
    }

    // keyToken(): Parse a single-character key, a `0x` key code, or a key keyword.
    private mutating func keyToken() throws -> SkhdKey {
        // A single character; parse() accepts only an ASCII letter or digit.
        if match(.key) {
            guard let key = SkhdKey.parse(previous.text) else { throw fail(localized("Expected a key."), at: previous) }
            return key
        }
        // A key code: `0x` and hex digits.
        if match(.keyHex) {
            let code = previous
            // skhd ends a key code at a lowercase hex digit and then rejects the letter after it.
            if current.line == code.line, current.column == code.column + code.text.count,
               let next = current.text.first, ("a"..."f").contains(next) {
                let digits = String(Array(lines[code.line - 1]).dropFirst(code.column + 1).prefix { $0.isASCII && $0.isHexDigit })
                throw fail(localizedFormat("The key code 0x%@ has lowercase hex digits, which skhd does not read. Write it as 0x%@.", digits, digits.uppercased()), at: code)
            }
            // `0x` on its own has no digits.
            guard previous.text.count > 2, let key = SkhdKey.parse(previous.text) else {
                throw fail(localized("Expected hex digits after “0x”."), at: previous)
            }
            return key
        }
        // Keyword keys are kept as written.
        if match(.literal) {
            return .literal(previous.text)
        }
        throw fail(localized("Expected a key."))
    }

    // processList(): Parse `"app" : command`, `"app" ~`, `* : command`, and `* ~` entries up to
    // `]`. At least one named app is required, as in skhd.
    private mutating func processList() throws -> [SkhdProcessMapping] {
        var mappings: [SkhdProcessMapping] = []
        while true {
            // A named app is bound to a command or unbound with `~`.
            if match(.string) {
                let process = previous.text
                // Bound to a command.
                if match(.command) {
                    mappings.append(SkhdProcessMapping(process: process, command: previous.text))
                } else if match(.unbound) {
                    // `~` lets the keypress reach this app.
                    mappings.append(SkhdProcessMapping(process: process, command: nil))
                } else {
                    // The name must be followed by one or the other.
                    throw fail(localized("Expected “:” and a command or “~” after the app name."))
                }
            } else if match(.wildcard) {
                // `*` covers every app not named in the list, bound to a command or unbound.
                if match(.command) {
                    mappings.append(SkhdProcessMapping(process: nil, command: previous.text))
                } else if match(.unbound) {
                    // Unbound for the other apps.
                    mappings.append(SkhdProcessMapping(process: nil, command: nil))
                } else {
                    // `*` must be bound or unbound too.
                    throw fail(localized("Expected “:” and a command or “~” after “*”."))
                }
            } else if match(.endList) {
                // The list is complete; skhd rejects one that holds only `*` entries.
                guard mappings.contains(where: { !$0.isWildcard }) else {
                    throw fail(localized("Per-app bindings need at least one named app."), at: previous)
                }
                return mappings
            } else {
                // Anything else is a syntax error.
                throw fail(localized("Expected an app name in quotes, “*”, or “]”."))
            }
        }
    }

    // modeDeclaration(): Parse `name [@] [: command]` after `::`. A repeated name fails here except
    // `default`, which skhd lets a file declare after hotkeys used it implicitly; diagnostics flag
    // a second `:: default`.
    private mutating func modeDeclaration() throws -> SkhdModeDeclaration {
        guard match(.identifier) else { throw fail(localized("Expected a mode name after “::”.")) }
        let name = previous.text
        let capture = match(.capture)
        var command: String?
        // The on-enter command is optional; a declaration can only name the mode.
        if match(.command) { command = previous.text }
        // skhd reports a duplicate declaration.
        if declaredModes.contains(name), name != "default" {
            throw fail(localizedFormat("Mode “%@” is declared more than once.", name), at: previous)
        }
        declaredModes.insert(name)
        return SkhdModeDeclaration(name: name, capture: capture, command: command)
    }

    // option(): Parse `.blacklist [ "app" ... ]` or `.load "file"`, the only options skhd knows.
    private mutating func option() throws -> SkhdItem {
        let option = current
        advance()
        switch option.text {
        case "blacklist":
            guard match(.beginList) else { throw fail(localized("Expected “[” and a list of app names after .blacklist."), at: option) }
            var processes: [String] = []
            while true {
                // Collect the quoted app names.
                if match(.string) {
                    processes.append(previous.text)
                } else if match(.endList) {
                    // The list is complete; skhd rejects an empty one.
                    guard !processes.isEmpty else { throw fail(localized("The blacklist needs at least one app name."), at: previous) }
                    return .blacklist(SkhdBlacklist(processes: processes))
                } else {
                    // Anything else is a syntax error.
                    throw fail(localized("Expected an app name in quotes or “]”."))
                }
            }
        case "load":
            guard match(.string) else { throw fail(localized("Expected a file path in quotes after .load."), at: option) }
            return .load(SkhdLoadDirective(path: previous.text))
        default:
            throw fail(localizedFormat("Unknown option “.%@”.", option.text), at: option)
        }
    }
}

private extension SkhdItem {
    // attach(comment): Store the comment lines parsed above the statement; blank and comment items
    // have none.
    mutating func attach(_ comment: [String]) {
        switch self {
        case .hotkey(var value): value.comment = comment; self = .hotkey(value)
        case .mode(var value): value.comment = comment; self = .mode(value)
        case .load(var value): value.comment = comment; self = .load(value)
        case .blacklist(var value): value.comment = comment; self = .blacklist(value)
        case .raw(var value): value.comment = comment; self = .raw(value)
        case .blank, .comment: break
        }
    }

    // setSource(text): Keep the statement's exact lines, or nil to write it from its fields; raw
    // items already hold their text.
    mutating func setSource(_ text: String?) {
        switch self {
        case .hotkey(var value): value.sourceText = text; self = .hotkey(value)
        case .mode(var value): value.sourceText = text; self = .mode(value)
        case .load(var value): value.sourceText = text; self = .load(value)
        case .blacklist(var value): value.sourceText = text; self = .blacklist(value)
        case .blank, .comment, .raw: break
        }
    }
}

// MARK: - Serializer

/// Writes a document back in skhd syntax. Unchanged statements keep their original text.
enum SkhdSerializer {
    // serialize(document): Write the items in order, restoring `#` on comment lines, and end the
    // file with exactly one newline.
    static func serialize(_ document: SkhdDocument) -> String {
        var lines: [String] = []
        for item in document.items {
            switch item {
            case .blank(let blank):
                lines.append(contentsOf: Array(repeating: "", count: blank.count))
            case .comment(let block):
                lines.append(contentsOf: block.lines.map { "#" + $0 })
            case .hotkey(let hotkey):
                lines.append(contentsOf: hotkey.comment.map { "#" + $0 })
                lines.append(hotkey.sourceText ?? hotkeyText(hotkey))
            case .mode(let mode):
                lines.append(contentsOf: mode.comment.map { "#" + $0 })
                lines.append(mode.sourceText ?? modeText(mode))
            case .load(let load):
                lines.append(contentsOf: load.comment.map { "#" + $0 })
                lines.append(load.sourceText ?? ".load \"\(load.path)\"")
            case .blacklist(let list):
                lines.append(contentsOf: list.comment.map { "#" + $0 })
                lines.append(list.sourceText ?? blacklistText(list))
            case .raw(let raw):
                lines.append(contentsOf: raw.comment.map { "#" + $0 })
                lines.append(raw.text)
            }
        }
        // Collapse trailing blank lines and end with one newline.
        var text = lines.joined(separator: "\n")
        while text.hasSuffix("\n\n") { text.removeLast() }
        // Supply a line terminator even for a newly created empty document.
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    // keysymText(hotkey): Join modes, modifiers, the key, and the passthrough arrow into the
    // statement head, such as `alt + shift - a`.
    static func keysymText(_ hotkey: SkhdHotkey) -> String {
        var head = ""
        // An empty mode list uses skhd's implicit default mode.
        if !hotkey.modes.isEmpty { head += hotkey.modes.joined(separator: ", ") + " < " }
        // Bare keys omit both the modifier list and its separating dash.
        if !hotkey.modifiers.isEmpty { head += hotkey.modifiers.map(\.rawValue).joined(separator: " + ") + " - " }
        head += hotkey.key.source
        // Preserve delivery to the foreground app when passthrough is selected.
        if hotkey.passthrough { head += " ->" }
        return head
    }

    // hotkeyText(hotkey): Write a whole binding. Per-app lists take one entry per line, with the
    // names padded so the commands line up.
    static func hotkeyText(_ hotkey: SkhdHotkey) -> String {
        let head = keysymText(hotkey)
        switch hotkey.action {
        case .command(let command):
            return head + " : " + commandText(command)
        case .activateMode(let mode):
            return head + " ; " + mode
        case .processMap(let mappings):
            let names = mappings.map { $0.process.map { "\"\($0)\"" } ?? "*" }
            let width = names.map(\.count).max() ?? 0
            var lines = [head + " ["]
            for (mapping, name) in zip(mappings, names) {
                let padded = name.padding(toLength: width, withPad: " ", startingAt: 0)
                // Bound entries get their command.
                if let command = mapping.command {
                    lines.append("    \(padded) : \(commandText(command))")
                } else {
                    // Unbound entries end with `~`.
                    lines.append("    \(padded) ~")
                }
            }
            lines.append("]")
            return lines.joined(separator: "\n")
        }
    }

    // modeText(mode): Write `:: name`, then `@` when the mode captures keys, then any command.
    static func modeText(_ mode: SkhdModeDeclaration) -> String {
        var text = ":: " + mode.name
        // Capture modes suppress otherwise unbound keypresses.
        if mode.capture { text += " @" }
        // A blank command is left out: skhd would read the next line as the command after `:`.
        if let command = mode.command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += " : " + commandText(command)
        }
        return text
    }

    // blacklistText(list): Write `.blacklist [`, one quoted app per line, and `]` on its own line.
    // `\u{2E}` is the dot.
    static func blacklistText(_ list: SkhdBlacklist) -> String {
        (["\u{2E}blacklist ["] + list.processes.map { "    \"\($0)\"" } + ["]"]).joined(separator: "\n")
    }

    // commandText(command): Write a command as one logical statement. Surrounding spaces and line
    // breaks are trimmed first, so a Return at the end of the field cannot leave a backslash that
    // joins the next statement. skhd hands an escaped line break to the shell as a continuation,
    // so each inner line break the user typed becomes ` ; \` plus the break, and the lines run as
    // separate commands, as the shell runs the typed lines. Where a `;` would be wrong, a line
    // only continues with ` \`: after an unescaped `;`, `&`, or `|` (which covers `&&` and `||`),
    // before a line that starts with one, and after a word the next line completes, such as
    // `then`, `do`, or `{` (see continuesCompound(_:)). A line ending in an unescaped backslash
    // already continues and is kept as typed. Blank lines are dropped so no empty command
    // appears; one right after a continued line ends that line's command, as in the shell, so
    // the continuing backslash goes with it. The output is a fixed point: writing it again
    // changes nothing.
    static func commandText(_ command: String) -> String {
        let trimmed = command.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        for line in trimmed.components(separatedBy: "\n") {
            // A blank line is dropped.
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // It ends the command of a line that continued into it, so that backslash goes.
                if let last = lines.last, trailingBackslashes(last) % 2 == 1 { lines[lines.count - 1].removeLast() }
                continue
            }
            lines.append(line)
        }
        // A single line needs no separators.
        guard lines.count > 1 else { return trimmed }
        var result = ""
        for index in lines.indices.dropLast() {
            // Trailing spaces would sit between a backslash and the line break and stop it from
            // escaping the break, so they go.
            var text = lines[index]
            while text.last == " " || text.last == "\t" { text.removeLast() }
            // A backslash that escapes the first of them makes that space part of the command, so
            // the line keeps them all.
            if text.count < lines[index].count, trailingBackslashes(text) % 2 == 1 { text = lines[index] }
            // Operators at the end of this line or the start of the next one join the two.
            let endsWithOperator = text.last.map { ";&|".contains($0) } == true && trailingBackslashes(String(text.dropLast())) % 2 == 0
            let nextStartsWithOperator = lines[index + 1].first { $0 != " " && $0 != "\t" }.map { ";&|".contains($0) } == true
            if trailingBackslashes(text) % 2 == 1 {
                // An odd run of backslashes ends in an unescaped one: the line already continues.
                result += text + "\n"
            } else if endsWithOperator || nextStartsWithOperator || continuesCompound(text) {
                // The command goes on in the next line; a separator here would break it.
                result += text + " \\\n"
            } else {
                // Any other line ends its command.
                result += text + " ; \\\n"
            }
        }
        return result + lines[lines.count - 1]
    }

    /// Shell keywords that a command must follow, so a line ending in one cannot end a command.
    private static let commandOpeners: Set<String> = ["if", "then", "do", "else", "elif", "while", "until", "!", "{", "("]

    // continuesCompound(line): Whether the line stops where the shell needs more of the same
    // command, so a `;` after it would be a syntax error: an open `$(`, a keyword such as `then`,
    // `do`, `else`, or `{` where a command starts, `in` after for, select, or case and a name, or
    // a `{` that opens a function's body. A keyword used as a plain word, as in `echo what to do`,
    // does not count.
    private static func continuesCompound(_ line: String) -> Bool {
        // An open command substitution goes on in the next line.
        if line.hasSuffix("$(") { return true }
        // Split into words at spaces and tabs; `;`, `&`, and `|` are words of their own.
        var words: [String] = []
        var word = ""
        // endWord(): Add the current word, when there is one, and start the next.
        func endWord() {
            words += word.isEmpty ? [] : [word]
            word = ""
        }
        for character in line {
            // Spaces only end the current word.
            if character == " " || character == "\t" {
                endWord()
            } else if ";&|".contains(character) {
                // An operator ends the current word and stands alone.
                endWord()
                words.append(String(character))
            } else {
                // Anything else belongs to the current word.
                word.append(character)
            }
        }
        endWord()
        guard let last = words.last else { return false }
        let index = words.count - 1
        // startsCommand(position): Whether the shell reads the word there as the start of a
        // command, the only place it sees keywords: first, after an operator, or after a keyword.
        func startsCommand(_ position: Int) -> Bool {
            position == 0 || [";", "&", "|"].contains(words[position - 1]) || commandOpeners.contains(words[position - 1])
        }
        // `in` is a keyword only as the third word of for, select, or case.
        if last == "in" {
            return index >= 2 && ["for", "select", "case"].contains(words[index - 2]) && startsCommand(index - 2)
        }
        // `{` after `name()` or `function name` opens the function's body.
        if last == "{", index > 0, words[index - 1].hasSuffix("()") || (index == 2 && words[0] == "function") {
            return true
        }
        return commandOpeners.contains(last) && startsCommand(index)
    }

    // breaksQuotedText(command): Whether commandText(_:) would put a separator inside text the
    // shell reads as quoted: a line break inside single or double quotes, or a here-document
    // spread over lines. skhd cannot keep such a line break, so the written text changes there.
    static func breaksQuotedText(_ command: String) -> Bool {
        let characters = Array(command.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        // A single line has no line break to change.
        guard characters.contains("\n") else { return false }
        var quote: Character?
        var escaped = false
        var inComment = false
        for (index, character) in characters.enumerated() {
            let before: Character = index > 0 ? characters[index - 1] : " "
            if inComment {
                // A comment runs to the end of its line; quotes inside it do not count.
                if character == "\n" { inComment = false }
            } else if escaped {
                // The escaped character, a line break included, is taken as it is.
                escaped = false
            } else if quote == "'" {
                // Single quotes have no escapes; the next single quote closes them.
                if character == "'" { quote = nil } else if character == "\n" {
                    // A newline before closure would change the quoted value on save.
                    return true
                }
            } else if character == "\\" {
                // Outside single quotes a backslash escapes the next character.
                escaped = true
            } else if quote == "\"" {
                // The earlier escape branch leaves only unescaped closing quotes here.
                if character == "\"" { quote = nil } else if character == "\n" {
                    // A newline inside the quotes cannot survive command serialization.
                    return true
                }
            } else if character == "'" || character == "\"" {
                // A quote opens.
                quote = character
            } else if character == "#", before.isWhitespace || ";&|(".contains(before) {
                // A `#` that starts a word starts a comment.
                inComment = true
            } else if character == "<", before == "<", index < 2 || characters[index - 2] != "<",
                      index + 1 >= characters.count || characters[index + 1] != "<" {
                // `<<`, but not `<<<`, starts a here-document, whose body is on the next lines.
                return true
            }
        }
        return false
    }

    // trailingBackslashes(text): The number of backslashes at the end of the text.
    private static func trailingBackslashes(_ text: String) -> Int {
        text.reversed().prefix { $0 == "\\" }.count
    }
}
