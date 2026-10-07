import Foundation

/// Parser, serializer, editing, and diagnostic checks, compiled with the syntax sources and run
/// against scripts/fixtures/sample.skhdrc. The termination fuzz also reads every other file in the
/// fixture's folder. Usage: tests <fixture>
@main
struct SyntaxTests {
    static var checks = 0

    /// Documents parsed on the worker thread in parseInTime(_:seconds:_:).
    final class ParseResults: @unchecked Sendable {
        var documents: [SkhdDocument] = []
    }

    // check(condition, message): Stop at the first failed check with its message; count the rest.
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }

    // parseInTime(texts, seconds, message): Parse the texts on a worker thread and fail with the
    // message when that takes longer than the limit. A parser that loops never returns, so the
    // limit is how these checks see it; the main thread stays free to report the failure.
    static func parseInTime(_ texts: [String], seconds: Double, _ message: String) -> [SkhdDocument] {
        let results = ParseResults()
        let finished = DispatchSemaphore(value: 0)
        let worker = Thread {
            results.documents = texts.map(SkhdParser.parse)
            finished.signal()
        }
        // A deep comment run recurses in the tokenizer, so give the worker a main-thread stack.
        worker.stackSize = 8 << 20
        worker.start()
        check(finished.wait(timeout: .now() + seconds) == .success, message)
        return results.documents
    }

    // command(document, [index = 0]): The command of a hotkey, or nil when it has another action.
    static func command(_ document: SkhdDocument, _ index: Int = 0) -> String? {
        guard index < document.hotkeys.count, case .command(let text) = document.hotkeys[index].action else { return nil }
        return text
    }

    // main(): Run every check against the fixture named on the command line.
    static func main() {
        let arguments = CommandLine.arguments
        precondition(arguments.count == 2, "usage: tests <fixture>")
        let fixture = try! String(contentsOfFile: arguments[1], encoding: .utf8)

        // A file in canonical form is written back byte for byte.
        let document = SkhdParser.parse(fixture)
        check(document.rawItems.isEmpty, "Fixture parsed without errors: \(document.rawItems.map(\.error))")
        check(SkhdSerializer.serialize(document) == fixture, "Unchanged fixture round-trips verbatim")

        // Parsing the output again yields the same structure.
        let reparsed = SkhdParser.parse(SkhdSerializer.serialize(document))
        check(reparsed.hotkeys.count == document.hotkeys.count, "Reparse keeps every hotkey")
        check(zip(reparsed.hotkeys, document.hotkeys).allSatisfy { $0.contentEquals($1) }, "Reparse keeps hotkey content")

        // Statements rebuilt from the model keep their meaning after a second parse.
        var canonical = document
        canonical.items = canonical.items.map { item in
            switch item {
            case .hotkey(var hotkey): hotkey.sourceText = nil; return .hotkey(hotkey)
            case .mode(var mode): mode.sourceText = nil; return .mode(mode)
            case .load(var load): load.sourceText = nil; return .load(load)
            case .blacklist(var list): list.sourceText = nil; return .blacklist(list)
            default: return item
            }
        }
        let canonicalText = SkhdSerializer.serialize(canonical)
        let canonicalDocument = SkhdParser.parse(canonicalText)
        check(canonicalDocument.rawItems.isEmpty, "Canonical output parses without errors: \(canonicalDocument.rawItems.map(\.error))")
        check(zip(canonicalDocument.hotkeys, document.hotkeys).allSatisfy { $0.contentEquals($1) }, "Canonical output keeps hotkey content")
        check(canonicalDocument.modeDeclarations.map(\.name) == ["resize", "launcher", "default"], "Canonical output keeps modes")
        check(canonicalDocument.blacklists.first?.processes == ["kitty", "Terminal"], "Canonical output keeps the blacklist")
        check(canonicalDocument.loadDirectives.first?.path == "partial_skhdrc", "Canonical output keeps load directives")
        check(SkhdSerializer.serialize(SkhdParser.parse(canonicalText)) == canonicalText, "Canonical output is stable")

        // Individual constructs, in fixture order. First: hex key codes, comment titles, commands.
        let hotkeys = document.hotkeys
        let passwords = hotkeys[0]
        check(passwords.modifiers == [.alt, .shift] && passwords.key == .code(0x27), "Hex key codes parse")
        check(passwords.title == "Focus Passwords" && passwords.titleHasShortcutPrefix, "Comment titles drop the shortcut prefix")
        check(passwords.shortcutSymbols == "⌥⇧'", "Shortcut symbols use key labels")
        // A plain command is the only valid action here.
        if case .command(let command) = passwords.action {
            check(command == "/usr/bin/open -b com.apple.Passwords", "Commands run to the end of the line")
        } else {
            // Any other action means this command was parsed incorrectly.
            fatalError("Expected a command")
        }

        // Per-app command lists with an unbound app and a wildcard entry.
        let utm = hotkeys[2]
        // A bracketed list must parse into a process map.
        if case .processMap(let mappings) = utm.action {
            check(mappings.count == 2 && mappings[0].process == "UTM" && mappings[0].isUnbound, "Unbound app entries parse")
            check(mappings[1].isWildcard && mappings[1].command == "/usr/bin/open -b com.utmapp.UTM", "Wildcard entries parse")
        } else {
            // Losing the process map would change which apps handle the shortcut.
            fatalError("Expected per-app commands")
        }
        check(utm.title == "Focus UTM; pass through when UTM is active.", "Titles keep punctuation")

        // Letter keys convert to key codes and back.
        let firefox = hotkeys[3]
        check(firefox.key == .character("f") && firefox.key.label == "F", "Single-letter keys parse")
        check(firefox.key.asKeyCode == .code(0x03), "Letters convert to key codes")
        check(SkhdKey.code(0x03).asKeyword == .character("f"), "Key codes convert back to letters")

        // Literal keys such as arrows.
        let terminalLeft = hotkeys[5]
        check(terminalLeft.key == .literal("left") && terminalLeft.key.hasImplicitFn, "Navigation literals carry the implicit fn flag")
        check(terminalLeft.key.capLabel == "←", "Literal keys have cap symbols")

        // Passthrough bindings keep their modifiers.
        let passthrough = hotkeys[8]
        check(passthrough.passthrough && passthrough.modifiers == [.ctrl, .alt, .shift], "Passthrough arrows parse")

        // Multi-line commands keep their continuations through parsing and serializing.
        let multiline = hotkeys[9]
        // A continued command is still a plain command.
        if case .command(let command) = multiline.action {
            check(command.contains("\\\n"), "Multi-line commands keep their continuations")
            check(SkhdSerializer.commandText("a\nb") == "a ; \\\nb", "Typed line breaks become command separators")
            check(SkhdSerializer.commandText(command) == command, "Escaped line breaks are unchanged")
        } else {
            // Continuation lines must not turn the binding into another action type.
            fatalError("Expected a command")
        }

        // Modes: activation, scoping, mode lists, media keys, side-specific and combined modifiers.
        let activate = hotkeys[10]
        check(activate.action == .activateMode("resize") && activate.modes.isEmpty, "Mode activation parses")
        let escape = hotkeys[11]
        check(escape.modes == ["resize"] && escape.key == .literal("escape"), "Mode-scoped bindings parse")
        let shared = hotkeys[12]
        check(shared.modes == ["resize", "launcher"], "Mode lists parse")
        let passthroughActivate = hotkeys[13]
        check(passthroughActivate.passthrough && passthroughActivate.action == .activateMode("default"), "Passthrough before mode activation parses")
        check(hotkeys[15].modifiers == [.fn] && hotkeys[15].key == .literal("sound_up"), "Media keys parse")
        check(hotkeys[16].modifiers.isEmpty && hotkeys[16].key == .literal("play"), "Bare literals parse")
        check(hotkeys[17].modifiers == [.lcmd, .ralt], "Side-specific modifiers parse")
        check(hotkeys[18].modifiers == [.meh] && hotkeys[18].key == .code(0x7E), "Combined modifiers parse")

        // Mode declarations keep their capture flag, command, and comment.
        let modes = document.modeDeclarations
        check(modes[0].name == "resize" && modes[0].capture && modes[0].command == "echo \"resize mode\"", "Capturing modes parse")
        check(modes[1].name == "launcher" && !modes[1].capture, "Plain modes parse")
        check(modes[0].comment == [" Resize mode captures keys and runs a command when entered."], "Comments attach to declarations")

        // The trailing commented-out binding stays a standalone comment.
        if case .comment(let block)? = document.items.last {
            check(block.lines == ["ctrl + alt - c : \"$HOME/.local/bin/spotlight-clipboard\""], "Trailing comments are preserved")
        } else {
            // Treating it as a live binding or dropping it would lose fixture content.
            fatalError("Expected a trailing comment block")
        }

        // Serializer output for rebuilt statements.
        var rebuilt = utm
        rebuilt.sourceText = nil
        check(SkhdSerializer.hotkeyText(rebuilt) == "alt + shift - 0x0B [\n    \"UTM\" ~\n    *     : /usr/bin/open -b com.utmapp.UTM\n]", "Per-app commands align their entries")
        check(SkhdSerializer.keysymText(shared) == "resize, launcher < cmd - return", "Mode lists serialize")
        check(SkhdSerializer.modeText(modes[0]) == ":: resize @ : echo \"resize mode\"", "Mode declarations serialize")
        check(SkhdKeyCodes.source(for: 0x2F) == "0x2F", "Key codes are written in uppercase hex")

        // Editing through the document API drops verbatim text only for changed statements.
        var edited = document
        var renamed = passwords
        renamed.setTitle("Open Passwords", keepPrefix: renamed.titleHasShortcutPrefix)
        edited.update(renamed)
        check(edited.hotkeys[0].sourceText != nil, "Comment edits keep the statement text")
        check(edited.hotkeys[0].comment == [" ⌥⇧' — Open Passwords"], "Titles keep the shortcut prefix")
        var rekeyed = renamed
        rekeyed.key = .code(0x2F)
        edited.update(rekeyed)
        check(edited.hotkeys[0].sourceText == nil, "Statement edits rebuild the statement text")
        check(SkhdSerializer.serialize(edited).contains("alt + shift - 0x2F : /usr/bin/open -b com.apple.Passwords"), "Edited bindings serialize canonically")
        // Text fields write every keystroke back, so spaces must survive the round trip.
        var spaced = passwords
        spaced.setTitle("Open Passwords ", keepPrefix: true)
        check(spaced.title == "Open Passwords ", "Titles keep a trailing space while typing: '\(spaced.title)'")
        spaced.setNotes(["first note", "second  note "])
        check(spaced.noteText == "first note\nsecond  note ", "Notes keep their spaces: '\(spaced.noteText)'")
        check(spaced.comment == [" ⌥⇧' — Open Passwords ", " first note", " second  note "], "Notes are stored as comment lines")
        spaced.setTitle("", keepPrefix: true)
        check(spaced.title.isEmpty && spaced.noteText == "first note\nsecond  note ", "Clearing the title keeps the notes as notes")
        spaced.setNotes([])
        check(spaced.comment.isEmpty, "Removing the notes after the title leaves no empty comment")
        var plain = firefox
        plain.setTitle("Firefox Dev ", keepPrefix: plain.titleHasShortcutPrefix)
        check(plain.title == "Firefox Dev " && plain.comment == [" ⌥⇧F — Firefox Dev "], "Prefixed titles keep trailing spaces too")
        // Removing a binding closes the gap it leaves.
        edited.remove(passwords.id)
        check(edited.hotkeys.count == hotkeys.count - 1, "Bindings can be removed")
        check(!SkhdSerializer.serialize(edited).contains("\n\n\n"), "Removal leaves no double blank lines")

        // Diagnostics.
        check(document.diagnostics().isEmpty, "A valid fixture has no diagnostics: \(document.diagnostics().map(\.message))")
        // A broken copy: a duplicate shortcut, an empty command, and an undeclared mode.
        var broken = document
        var duplicate = passwords
        duplicate.id = UUID()
        duplicate.key = .code(0x27)
        broken.append(.hotkey(duplicate))
        var empty = firefox
        empty.action = .command("   ")
        broken.update(empty)
        var undeclared = activate
        undeclared.action = .activateMode("missing")
        broken.update(undeclared)
        let diagnostics = broken.diagnostics()
        check(diagnostics.contains { $0.severity == .warning && $0.message.contains("bound more than once") }, "Duplicates are reported")
        check(diagnostics.contains { $0.severity == .error && $0.message == "The command is empty." }, "Empty commands are reported")
        check(diagnostics.contains { $0.severity == .error && $0.message.contains("missing") }, "Undeclared modes are reported")
        check(diagnostics.first?.severity == .error, "Errors sort before warnings")

        // A bare key is only a hazard where it is live without entering a mode first.
        let bareKeys = SkhdParser.parse(":: resize\nh : echo default\nresize < l : echo resize\ndefault, resize < j : echo both\n")
        let bareWarnings = bareKeys.diagnostics().filter { $0.message.contains("no modifier") }
        check(bareWarnings.count == 2, "Bare keys live in the default mode are reported, keys inside another mode are not")
        check(!bareWarnings.contains { diagnostic in bareKeys.hotkeys.first { $0.id == diagnostic.itemID }?.modes == ["resize"] }, "A bare key scoped to another mode gets no warning")

        // Errors keep the rest of the file and preserve the bad text.
        let partial = SkhdParser.parse("""
        # good
        cmd - a : echo a
        # bad
        cmd + - b : echo b
        cmd - c [
            "Finder" : echo finder
        ]
        .unknown "x"
        cmd - d : echo d
        """)
        check(partial.hotkeys.count == 3, "Parsing continues after errors: \(partial.hotkeys.count)")
        check(partial.rawItems.count == 2, "Bad statements become raw items: \(partial.rawItems.count)")
        check(partial.rawItems[0].text == "cmd + - b : echo b" && partial.rawItems[0].line == 4, "Raw items keep their text and line")
        check(partial.rawItems[0].comment == [" bad"], "Raw items keep their comment")
        check(partial.rawItems[1].error.contains(".unknown"), "Unknown options are reported")
        check(SkhdSerializer.serialize(partial).contains("# bad\ncmd + - b : echo b\n"), "Raw items are written back verbatim")
        check(!partial.diagnostics().isEmpty && partial.diagnostics()[0].line == 4, "Raw items appear in diagnostics with their line")

        // A list without a named app is rejected like skhd does.
        let wildcardOnly = SkhdParser.parse("cmd - a [\n    * : echo a\n]\n")
        check(wildcardOnly.rawItems.count == 1 && wildcardOnly.rawItems[0].text.hasSuffix("]"), "Wildcard-only lists are raw items spanning the block")

        // Windows line endings and a missing trailing newline normalize.
        let windows = SkhdParser.parse("cmd - a : echo a\r\ncmd - b : echo b")
        check(windows.hotkeys.count == 2 && SkhdSerializer.serialize(windows) == "cmd - a : echo a\ncmd - b : echo b\n", "Line endings normalize")

        // The simple "Open an app" editor recognizes only commands that open exactly one app.
        check(OpenAppCommand.parse("/usr/bin/open -b com.apple.Passwords")?.bundleIdentifier == "com.apple.Passwords", "open -b is recognized")
        check(OpenAppCommand.parse("  open -b com.apple.Safari  ")?.bundleIdentifier == "com.apple.Safari", "Bare open with padding is recognized")
        check(OpenAppCommand.parse("open -a \"Google Chat\"")?.target == .application("Google Chat"), "Quoted app names are unquoted")
        check(OpenAppCommand.parse("/usr/bin/open -a '/Users/me/Applications/Chrome Apps.localized/Google Chat.app'")?.target == .application("/Users/me/Applications/Chrome Apps.localized/Google Chat.app"), "Quoted paths keep their spaces")
        check(OpenAppCommand.parse("/usr/bin/open -b com.apple.Safari https://example.com") == nil, "Extra arguments are not the simple form")
        check(OpenAppCommand.parse("open -na /Applications/Terminal.app") == nil, "Other open flags are not the simple form")
        check(OpenAppCommand.parse("echo open -b x") == nil && OpenAppCommand.parse("") == nil, "Other commands are not recognized")
        check(OpenAppCommand.command(opening: "com.apple.Passwords") == "/usr/bin/open -b com.apple.Passwords", "Chosen apps are written with the full launcher path")
        check(OpenAppCommand.shellWords("a \"b c\" d\\ e 'f g'") == ["a", "b c", "d e", "f g"], "Shell words honor quotes and escapes")

        // Shortcut text helpers.
        check(SkhdShortcutText.splitTitle("⌃⌥⇧5 — Open Virtualmin Active Users")?.title == "Open Virtualmin Active Users", "Prefixed titles split")
        check(SkhdShortcutText.splitTitle("Browser Find and Find Next") == nil, "Plain titles do not split")
        check(SkhdModifier.canonical([.cmd, .shift, .alt, .shift]) == [.alt, .shift, .cmd], "Modifiers sort canonically without duplicates")
        check(SkhdModifier.keyword(for: .alt, side: .right) == .ralt && SkhdModifier.ralt.base == .alt, "Side-specific keywords map both ways")
        check(SkhdTokenizer.isIdentifier("win_mode2") && !SkhdTokenizer.isIdentifier("2win") && !SkhdTokenizer.isIdentifier("a1b"), "Identifiers follow skhd rules")

        // skhd starts a word only on a letter, so a mode name cannot begin with an underscore.
        check(!SkhdTokenizer.isIdentifier("_resize") && SkhdTokenizer.isIdentifier("re_size"), "Mode names start with a letter")
        let underscored = SkhdParser.parse(":: _resize\ncmd - r ; _resize\ncmd - a : echo a\n")
        check(underscored.modeDeclarations.isEmpty, "A declaration with a leading underscore is not a mode")
        check(underscored.hotkeys.map(\.key) == [.character("a")], "Bindings that switch to such a mode are rejected, the rest still parse")
        check(underscored.diagnostics().filter { $0.severity == .error }.count == 2, "Both rejected lines are reported as errors")

        // Words skhd reads as keys or modifiers cannot name a mode.
        check(SkhdTokenizer.isModeName("resize") && SkhdTokenizer.isModeName("win_mode2"), "Ordinary words name modes")
        check(!["home", "space", "fn", "w", "hyper", "f1"].contains(where: SkhdTokenizer.isModeName), "Keys, modifiers, and single letters do not name modes")
        var keywordMode = SkhdParser.parse(":: resize\n")
        // Replace the parsed declaration with a reserved name to exercise validation.
        if var mode = keywordMode.modeDeclarations.first {
            mode.name = "home"
            keywordMode.update(mode)
        }
        check(keywordMode.diagnostics().contains { $0.severity == .error && $0.message.contains("cannot name a mode") }, "A mode named after a key is an error")

        // A statement that runs to the end of the file parses without stepping past the last line.
        for text in ["cmd - b :\n", ":: resize :\n", "cmd - a : echo a \\\n", ".load \"x\n", "cmd - a : echo a \\"] {
            _ = SkhdParser.parse(text)
        }
        check(true, "Statements that end at the end of the file do not crash the parser")

        // A trailing Return in a command never joins the next statement to it.
        check(SkhdSerializer.commandText("open -a Safari\n") == "open -a Safari", "Trailing line breaks are trimmed before escaping")
        check(SkhdSerializer.commandText("echo a\necho b\n") == "echo a ; \\\necho b", "Inner line breaks separate commands")
        var trailing = SkhdParser.parse("cmd - a : echo a\nalt - t : open -a Terminal\n")
        // Simulate Return at the end of the first command editor.
        if var first = trailing.hotkeys.first {
            first.action = .command("open -a Safari\n")
            trailing.update(first)
        }
        let trailingSaved = SkhdParser.parse(SkhdSerializer.serialize(trailing))
        check(trailingSaved.hotkeys.count == 2 && trailingSaved.rawItems.isEmpty, "A command ending in Return keeps the next binding after a save")
        var backslash = SkhdParser.parse("cmd - a : echo a\n")
        // Force regeneration of a command whose final slash would continue the next line.
        if var first = backslash.hotkeys.first {
            first.action = .command("echo a \\")
            backslash.update(first)
        }
        check(backslash.diagnostics().contains { $0.severity == .error && $0.message.contains("ends with a backslash") }, "An edited command ending in a backslash is an error")
        check(SkhdParser.parse("cmd - a : echo a \\\n\ncmd - b : echo b\n").diagnostics().isEmpty, "An unchanged continued command from the file is left alone")
        var blankMode = SkhdParser.parse(":: resize\n:: launcher\n")
        // A whitespace-only entry command should disappear without joining declarations.
        if var mode = blankMode.modeDeclarations.first {
            mode.command = " \n"
            blankMode.update(mode)
        }
        check(SkhdParser.parse(SkhdSerializer.serialize(blankMode)).modeDeclarations.count == 2, "A blank mode command does not swallow the next declaration")

        // The title starts after the prefix, even when the key letter also begins the title.
        var titled = SkhdParser.parse("# ⌥⇧F — Firefox\nalt + shift - f : open -a Firefox\n").hotkeys[0]
        check(titled.title == "Firefox", "The title is read after the shortcut prefix")
        titled.setTitle("Firefo", keepPrefix: true)
        check(titled.title == "Firefo" && titled.comment.first == " ⌥⇧F — Firefo", "Editing the title does not grow it")
        check(SkhdShortcutText.splitTitle("Finder - open home folder") == nil, "An ordinary word is not a shortcut prefix")
        check(SkhdShortcutText.splitTitle("F5 - Reload")?.title == "Reload", "A bare function key is a shortcut prefix")

        // Keys written by code carry an explicit fn where skhd needs one, and only there.
        var arrow = SkhdParser.parse("alt - left : echo left\n").hotkeys[0]
        check(arrow.key.hasImplicitFn && !SkhdKey.code(0x7B).hasImplicitFn, "Only key names get the implicit fn flag")
        arrow.setKey(.code(0x7B))
        check(arrow.modifiers == [.alt, .fn], "Writing an arrow as a key code adds fn")
        arrow.setKey(.literal("left"))
        check(arrow.modifiers == [.alt], "Writing it by name again drops the redundant fn")
        check(SkhdParser.parse("alt - left : echo a\nalt - 0x7B : echo b\n").diagnostics().isEmpty, "A name and a bare code for the same key are different shortcuts in skhd")

        // A failed statement on the last line, with no final newline, is kept once and parsing ends
        // instead of starting over on that line.
        let lastLineFailures: [(text: String, raw: String, hotkeys: Int)] = [
            ("alt - a", "alt - a", 0),
            (":", ":", 0),
            ("alt - a : echo ok\nalt - b", "alt - b", 1),
            ("alt - a : echo ok\n.foo", ".foo", 1),
            ("alt - a : echo ok\nshift + cmd - ", "shift + cmd - ", 1),
            ("alt - a : echo ok\nctrl + alt - r ;", "ctrl + alt - r ;", 1),
        ]
        let failedTexts = lastLineFailures.flatMap { [$0.text, $0.text + "\n"] }
        let failedDocuments = parseInTime(failedTexts, seconds: 2, "A failed last line ends parsing")
        // Each case was parsed twice, without and with the final newline.
        for (offset, document) in failedDocuments.enumerated() {
            let expected = lastLineFailures[offset / 2]
            check(document.rawItems.map(\.text) == [expected.raw], "The bad last line is one raw item: \(document.rawItems.map(\.text))")
            check(document.hotkeys.count == expected.hotkeys, "Bindings above the bad line still parse")
            check(SkhdSerializer.serialize(document) == expected.text.trimmingCharacters(in: .newlines) + "\n", "The bad last line is written back verbatim")
        }

        // Every prefix of the fixtures, with and without a final newline, parses to the end.
        let fixtureFolder = URL(fileURLWithPath: arguments[1]).deletingLastPathComponent()
        let fixtureNames = try! FileManager.default.contentsOfDirectory(atPath: fixtureFolder.path).sorted()
        var truncated: [String] = []
        for name in fixtureNames {
            let characters = Array(try! String(contentsOf: fixtureFolder.appendingPathComponent(name), encoding: .utf8))
            for length in 0...characters.count {
                let text = String(characters[..<length])
                truncated += [text, text + "\n"]
            }
        }
        let started = Date()
        let fuzzed = parseInTime(truncated, seconds: 30, "Every truncated fixture parses to the end")
        check(fuzzed.count == truncated.count && fixtureNames.count >= 2, "The fuzz covered every fixture: \(fixtureNames)")
        print("Parsed \(truncated.count) truncated fixtures in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")

        // skhd skips only the ASCII spaces C isspace() accepts, so any other space between words,
        // such as a no-break space from Option-Space or a byte order mark, rejects the line.
        let noBreak = SkhdParser.parse("alt\u{00A0}- a : echo a\ncmd - b : echo b\n")
        check(noBreak.rawItems.count == 1 && noBreak.rawItems[0].text == "alt\u{00A0}- a : echo a", "A no-break space between words is an error")
        check(noBreak.rawItems[0].error.contains("U+00A0") && noBreak.hotkeys.count == 1, "The error names the invisible character and the next line still parses")
        let byteOrderMark = SkhdParser.parse("\u{FEFF}alt - a : echo a\n")
        check(byteOrderMark.hotkeys.isEmpty && byteOrderMark.rawItems.first?.error.contains("U+FEFF") == true, "A leading byte order mark is an error")
        check(!SkhdParser.parse("cmd -\u{3000}a : echo a\n").diagnostics().isEmpty, "An ideographic space between words is an error")
        let asciiSpaces = SkhdParser.parse("alt\u{0B}-\u{0C}a\t:\techo a\r\ncmd - b : echo b\r\n")
        check(asciiSpaces.rawItems.isEmpty && asciiSpaces.hotkeys.count == 2, "Tabs, vertical tabs, form feeds, and CRLF line ends are spaces")
        check(command(SkhdParser.parse("alt - a : echo\u{00A0}a\u{3000}b\n")) == "echo\u{00A0}a\u{3000}b", "Commands still run to the end of the line unchanged")
        // The tokenizer on its own reads "\r\n", one Swift character, as a line break.
        var crlfTokens = SkhdTokenizer("alt - a : echo a\r\nalt - b : echo b")
        var crlfKinds: [(SkhdToken.Kind, String, Int)] = []
        // Collect tokens up to the end of the text.
        while true {
            let token = crlfTokens.next()
            // The end of the text stops the collection.
            if token.kind == .endOfStream { break }
            crlfKinds.append((token.kind, token.text, token.line))
        }
        check(crlfKinds.count == 8 && crlfKinds[3].1 == "echo a" && crlfKinds[4].2 == 2, "CRLF ends commands and lines in the tokenizer: \(crlfKinds)")

        // skhd creates the default mode only for a binding without a mode list, a mode list that
        // names it, or `:: default`, and `; default` before any of these is rejected.
        let defaultMessage = "The default mode does not exist yet"
        let earlyDefault = SkhdParser.parse(":: resize\nresize < escape ; default\nalt - r ; resize\n").diagnostics()
        check(earlyDefault.contains { $0.severity == .error && $0.message.contains(defaultMessage) }, "Switching to default above any default binding is an error")
        let lateDefault = ":: resize\nalt - r ; resize\nresize < escape ; default\n"
        check(SkhdParser.parse(lateDefault).diagnostics().isEmpty, "Switching to default after a default binding is fine")
        check(SkhdParser.parse(":: default\n:: resize\nresize < escape ; default\n").diagnostics().isEmpty, "`:: default` creates the default mode")
        check(SkhdParser.parse(":: resize\ndefault, resize < escape ; default\n").diagnostics().isEmpty, "A mode list naming default creates it before the action")
        check(SkhdParser.parse("alt - d ; default\n").diagnostics().isEmpty, "A default binding creates the mode before its own action")
        check(SkhdParser.parse("alt - a : echo a\n:: default : echo back\n").diagnostics().isEmpty, "`:: default` is allowed once after the mode was created")
        for text in ["alt - a : echo a\n:: default\n:: default\n", ":: default\n:: default\nalt - a : echo a\n"] {
            check(SkhdParser.parse(text).diagnostics().contains { $0.message.contains("declared more than once") }, "A second `:: default` is an error")
        }
        let perApp = SkhdParser.parse(":: resize\nresize < 0x35 [\n    \"Finder\" : echo f\n]\nresize < q ; default\n").diagnostics()
        check(perApp.filter { $0.message.contains(defaultMessage) }.count == 1, "A per-app binding inside another mode does not create default")

        // Line breaks typed in a command separate commands; lines that already continue keep that.
        let commandCases: [(typed: String, written: String)] = [
            ("echo a\necho b", "echo a ; \\\necho b"),
            ("echo a  \n\n   \necho b\n", "echo a ; \\\necho b"),
            ("echo a &&\necho b", "echo a && \\\necho b"),
            ("echo a ||  \necho b", "echo a || \\\necho b"),
            ("ps ax |\ngrep skhd", "ps ax | \\\ngrep skhd"),
            ("sleep 1 &\necho b", "sleep 1 & \\\necho b"),
            ("echo a;\necho b", "echo a; \\\necho b"),
            ("echo a \\\n  echo b", "echo a \\\n  echo b"),
            ("echo a \\  \necho b", "echo a \\   ; \\\necho b"),
            ("echo a\\\n\necho b", "echo a ; \\\necho b"),
            ("printf x\n| cat", "printf x \\\n| cat"),
            ("true\n&& echo b", "true \\\n&& echo b"),
            ("if true; then\n  echo a\nfi", "if true; then \\\n  echo a ; \\\nfi"),
            ("for i in 1 2\ndo\n  echo $i\ndone", "for i in 1 2 ; \\\ndo \\\n  echo $i ; \\\ndone"),
            ("case x in\nx) echo x;;\nesac", "case x in \\\nx) echo x;; \\\nesac"),
            ("f() {\n  echo a\n}\nf", "f() { \\\n  echo a ; \\\n} ; \\\nf"),
            ("x=$(\necho a\n)", "x=$( \\\necho a ; \\\n)"),
            ("echo what to do\necho logged in", "echo what to do ; \\\necho logged in"),
            ("echo a\\\\\necho b", "echo a\\\\ ; \\\necho b"),
            ("find . -exec rm {} \\;\necho b", "find . -exec rm {} \\; ; \\\necho b"),
            ("echo a\r\necho b\r\n", "echo a ; \\\necho b"),
            ("echo one", "echo one"),
        ]
        for (typed, written) in commandCases {
            check(SkhdSerializer.commandText(typed) == written, "Command \(typed.debugDescription) is written as \(written.debugDescription): \(SkhdSerializer.commandText(typed).debugDescription)")
            check(SkhdSerializer.commandText(written) == written, "Written command \(written.debugDescription) is stable")
            // The written command parses back to itself in a file.
            let reread = SkhdParser.parse("alt - a : \(written)\ncmd - b : echo b\n")
            check(command(reread) == written && reread.hotkeys.count == 2, "Command \(written.debugDescription) round-trips through a file")
        }
        // Through the document: an edited two-line command keeps the next binding and is stable.
        var twoLines = SkhdParser.parse("alt - a : echo a\ncmd - b : echo b\n")
        // Type two lines into the first binding's command.
        if var first = twoLines.hotkeys.first {
            first.action = .command("echo one\necho two")
            twoLines.update(first)
        }
        let twoLinesText = SkhdSerializer.serialize(twoLines)
        check(twoLinesText == "alt - a : echo one ; \\\necho two\ncmd - b : echo b\n", "A two-line command is saved as two commands: \(twoLinesText.debugDescription)")
        check(SkhdSerializer.serialize(SkhdParser.parse(twoLinesText)) == twoLinesText, "A saved two-line command is stable")

        // Only an odd run of backslashes continues a command; an even run ends in a literal one.
        check(SkhdTokenizer.endsWithContinuation("echo a\\") && SkhdTokenizer.endsWithContinuation("echo a\\\\\\  "), "An odd run of backslashes continues the command")
        var evenRun = SkhdParser.parse("alt - a : echo a\\\\\n")
        // Rewrite the binding from its fields, as an edit would.
        if var first = evenRun.hotkeys.first {
            first.sourceText = nil
            evenRun.items = [.hotkey(first)]
        }
        check(command(evenRun) == "echo a\\\\" && !SkhdTokenizer.endsWithContinuation("echo a\\\\") && evenRun.diagnostics().isEmpty, "An even run of backslashes is text, so the rewritten binding can be saved")

        // A line break inside quotes or a here-document cannot be written for skhd as typed.
        for quoted in ["echo 'a\nb'", "echo \"a\nb\"", "cat <<EOF\nx\nEOF"] {
            check(SkhdSerializer.breaksQuotedText(quoted), "A line break in \(quoted.debugDescription) is quoted")
        }
        for plain in ["echo 'a'\necho \"b\"", "# don't\necho b", "echo a \\\nb", "echo \"a \\\nb\"", "cat <<< x\necho b", "echo 'one'"] {
            check(!SkhdSerializer.breaksQuotedText(plain), "No line break in \(plain.debugDescription) is quoted")
        }
        var quotedBreak = SkhdParser.parse("alt - a : echo a\n")
        // Type a line break inside single quotes.
        if var first = quotedBreak.hotkeys.first {
            first.action = .command("echo 'a\nb'")
            quotedBreak.update(first)
        }
        check(quotedBreak.diagnostics().contains { $0.severity == .warning && $0.message.contains("inside quotes") }, "A typed line break inside quotes is a warning")

        // skhd reads key codes only with uppercase hex digits and rejects the whole file otherwise.
        let lowerHex = SkhdParser.parse("alt - 0x2c : echo y\n0x2C : echo x\n")
        check(lowerHex.rawItems.count == 1 && lowerHex.rawItems[0].error.contains("0x2C") && lowerHex.hotkeys.count == 1, "A key code with lowercase hex digits is an error that names the uppercase spelling: \(lowerHex.rawItems.map(\.error))")
        check(SkhdParser.parse("0xff : echo x\n").rawItems.first?.error.contains("0xFF") == true, "A key code of lowercase digits only is the same error")

        // skhd's strings have no escapes, so a quote in a blacklisted name or a .load path breaks
        // the file.
        var quotedNames = SkhdParser.parse(".blacklist [\n    \"kitty\"\n]\n.load \"other\"\n")
        // Put a quote into both, as the editors could.
        quotedNames.items = quotedNames.items.map { item in
            switch item {
            case .blacklist(var list): list.processes = ["Foo\"Bar"]; list.sourceText = nil; return .blacklist(list)
            case .load(var load): load.path = "my\"file"; load.sourceText = nil; return .load(load)
            default: return item
            }
        }
        let quotedErrors = quotedNames.diagnostics().filter { $0.severity == .error }.map(\.message)
        check(quotedErrors.contains("App names cannot contain quotation marks.") && quotedErrors.contains("File paths cannot contain quotation marks."), "Quotes in blacklisted names and .load paths are errors: \(quotedErrors)")

        // Statements that share a line are written on lines of their own instead of twice.
        let sharedLine = SkhdParser.parse(":: resize\ncmd - x ; resize alt - b : echo b\n")
        let sharedText = SkhdSerializer.serialize(sharedLine)
        check(sharedLine.hotkeys.count == 2 && sharedText == ":: resize\ncmd - x ; resize\nalt - b : echo b\n", "Statements sharing a line are split: \(sharedText.debugDescription)")
        check(SkhdSerializer.serialize(SkhdParser.parse(sharedText)) == sharedText, "Split statements are stable")
        let sharedRaw = SkhdParser.parse(":: resize\nalt - r ; resize\u{00A0}\nalt - b : echo b\n")
        check(sharedRaw.rawItems.count == 1 && sharedRaw.rawItems[0].text == "alt - r ; resize\u{00A0}" && sharedRaw.hotkeys.count == 1, "A line whose second statement fails becomes one raw item")
        check(SkhdSerializer.serialize(sharedRaw) == ":: resize\nalt - r ; resize\u{00A0}\nalt - b : echo b\n", "That line is written back once")

        // Carriage returns are read as skhd reads them: only a line feed ends a line.
        let escapedReturn = SkhdParser.parse("alt - a : echo a \\\r\n  b\r\nalt - b : echo c\r\n")
        check(escapedReturn.rawItems.count == 1 && escapedReturn.rawItems[0].line == 3, "A backslash before CRLF escapes only the carriage return: \(escapedReturn.rawItems.map(\.error))")
        check(SkhdParser.parse("# a\ralt - b : echo y\n").hotkeys.isEmpty, "A lone carriage return does not end a comment")
        let loneReturn = SkhdParser.parse("alt - a : echo a\ralt - b : echo b\n")
        check(loneReturn.hotkeys.count == 1 && command(loneReturn) == "echo a\ralt - b : echo b", "A lone carriage return stays inside a command")
        check(SkhdSerializer.serialize(loneReturn) == "alt - a : echo a\ralt - b : echo b\n", "A lone carriage return is written back")
        check(SkhdParser.parse("alt\r- a : echo a\n").hotkeys.count == 1, "A lone carriage return separates words")
        check(SkhdSerializer.serialize(SkhdParser.parse("alt - a : echo a\r\r\nalt - b : echo b\r\n")) == "alt - a : echo a\nalt - b : echo b\n", "Several carriage returns before a line feed end one line")
        check(SkhdSerializer.serialize(SkhdParser.parse("alt - a : echo a\r")) == "alt - a : echo a\n", "A carriage return at the very end ends the last line")

        // Comment lines that start with a vertical tab or form feed are comments to skhd too.
        let feeds = SkhdParser.parse("\u{0B}# note\nalt - a : echo x\n\u{0C}# page\nalt - b : echo y\n")
        check(feeds.hotkeys.count == 2 && feeds.hotkeys[0].comment == [" note"] && feeds.hotkeys[1].comment == [" page"], "Comments after a vertical tab or form feed are kept: \(feeds.hotkeys.map(\.comment))")

        // Leaving an arrow or function key code drops the fn it needed; a chosen fn stays.
        var leaving = SkhdParser.parse("alt - 0x7B : echo a\n").hotkeys[0]
        leaving.setKey(.code(0x7B))
        check(leaving.modifiers == [.alt, .fn], "An arrow key code gets fn")
        leaving.setKey(.code(0x7C))
        check(leaving.modifiers == [.alt, .fn], "Another arrow key code keeps fn")
        leaving.setKey(.character("a"))
        check(leaving.modifiers == [.alt], "Changing the arrow code to a letter drops the added fn")
        leaving.setKey(.code(0x60))
        leaving.setKey(.code(0x00))
        check(leaving.modifiers == [.alt], "Changing a function key code to a letter code drops fn")
        var chosenFn = SkhdParser.parse("fn - a : echo a\n").hotkeys[0]
        chosenFn.setKey(.character("b"))
        check(chosenFn.modifiers == [.fn], "An fn the user chose for an ordinary key stays")

        // A new mode goes above the first binding, so any binding can be moved into it.
        var lateModes = SkhdParser.parse(":: resize\n\nalt - a : echo a\n\n:: launcher\nlauncher < b : echo b\n")
        lateModes.insertModeDeclaration(SkhdModeDeclaration(name: "mode1"))
        check(SkhdSerializer.serialize(lateModes) == ":: resize\n:: mode1\n\nalt - a : echo a\n\n:: launcher\nlauncher < b : echo b\n", "A new mode joins the declarations above the first binding")
        var belowBindings = SkhdParser.parse("# Header\n\n# Focus\nalt - a : echo a\n\n:: resize\nresize < h : echo h\n")
        belowBindings.insertModeDeclaration(SkhdModeDeclaration(name: "mode1"))
        check(SkhdSerializer.serialize(belowBindings) == "# Header\n\n:: mode1\n\n# Focus\nalt - a : echo a\n\n:: resize\nresize < h : echo h\n", "Without earlier declarations a new mode goes directly above the first binding")
        // Move the first binding into the new mode.
        if var first = belowBindings.hotkeys.first {
            first.modes = ["mode1"]
            belowBindings.update(first)
        }
        check(belowBindings.diagnostics().isEmpty, "A binding moved into the new mode is not used before its declaration")
        var noBindings = SkhdParser.parse(":: resize\n")
        noBindings.insertModeDeclaration(SkhdModeDeclaration(name: "mode1"))
        check(SkhdSerializer.serialize(noBindings) == ":: resize\n:: mode1\n", "Without bindings a new mode follows the last declaration")

        // Every prefix Keymin writes before a title is read back, so the title survives a rewrite.
        let prefixCases: [(source: String, prefix: String)] = [
            ("hyper - m : echo m", "✦M"),
            ("meh - 0x7E : echo up", "◆Up Arrow"),
            ("a : echo a", "A"),
            ("f5 : echo reload", "F5"),
            ("return : echo run", "Return"),
            ("play : echo play", "Play/Pause"),
            ("fn - sound_up : echo up", "fnVolume Up"),
            ("fn - a : echo a", "fnA"),
            ("lcmd + ralt - space : echo s", "R⌥L⌘Space"),
            ("hyper - 0x6F : echo f12", "✦F12"),
            ("ctrl + alt + shift + cmd - illumination_down : echo d", "⌃⌥⇧⌘Keyboard Backlight Down"),
            ("alt - 0x7F : echo x", "⌥0x7F"),
            ("0x7F : echo x", "0x7F"),
        ]
        for (source, prefix) in prefixCases {
            var hotkey = SkhdParser.parse(source + "\n").hotkeys[0]
            hotkey.setTitle("Focus - Safari ", keepPrefix: true)
            check(hotkey.comment.first == " \(prefix) — Focus - Safari ", "Prefix for \(source): \(hotkey.comment)")
            check(hotkey.titleHasShortcutPrefix && hotkey.title == "Focus - Safari ", "The title after \(prefix) is read back: '\(hotkey.title)'")
        }
        check(SkhdShortcutText.splitTitle("fn - a : echo a") == nil, "A commented-out fn binding is not a title")
        check(SkhdShortcutText.splitTitle("fnord - x") == nil && SkhdShortcutText.splitTitle("Finder — open") == nil, "Ordinary words are not prefixes with any dash")
        check(SkhdShortcutText.splitTitle("A - first") == nil && SkhdShortcutText.splitTitle("Return - run") == nil, "Bare keys need Keymin's dash")
        check(SkhdShortcutText.splitTitle("fnA - x")?.prefix == "fnA" && SkhdShortcutText.splitTitle("✦M – x")?.title == "x", "fn with a key, hyper, and meh prefixes pass the strict dashes")
        check(SkhdShortcutText.splitTitle("⌥⇧← — Move left")?.title == "Move left", "Hand-written symbol prefixes still count")

        // Spaces around a blacklisted name mean skhd never matches it.
        let spacedBlacklist = SkhdParser.parse(".blacklist [\n    \" Safari\"\n    \"kitty \"\n    \"Terminal\"\n]\n").diagnostics()
        let spacedNames = spacedBlacklist.filter { $0.severity == .warning && $0.message.contains("spaces before or after") }
        check(spacedNames.count == 2 && spacedNames.contains { $0.message.contains("“Safari”") } && spacedNames.contains { $0.message.contains("“kitty”") }, "Blacklisted names with spaces around them are warnings: \(spacedBlacklist.map(\.message))")
        check(!spacedBlacklist.contains { $0.severity == .error }, "Spaces around a name are not an error")

        print("Keymin syntax: \(checks) parser, serializer, and diagnostic checks passed")
    }
}
