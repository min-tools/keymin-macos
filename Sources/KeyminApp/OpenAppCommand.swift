import Foundation

/// The simple "Open an app" form of a command: `open -b <bundle identifier>` or `open -a <app>`.
/// The binding still stores an ordinary command; this only recognizes and writes that shape.
struct OpenAppCommand: Equatable {
    /// How the command names the app to open.
    enum Target: Equatable {
        /// `open -b com.apple.Safari`
        case bundleIdentifier(String)
        /// `open -a Safari` or `open -a "/Applications/Safari.app"`
        case application(String)
    }

    /// The absolute path of `open`. `parse` accepts either this path or the bare name.
    static let launcher = "/usr/bin/open"

    var target: Target

    // parse(command): Recognize a command that only opens one app, with nothing else on the line.
    // Returns nil for any other command, including `open` with extra arguments.
    static func parse(_ command: String) -> OpenAppCommand? {
        let words = shellWords(command.trimmingCharacters(in: .whitespacesAndNewlines))
        guard words.count == 3, words[0] == "open" || words[0] == launcher else { return nil }
        switch words[1] {
        case "-b": return OpenAppCommand(target: .bundleIdentifier(words[2]))
        case "-a": return OpenAppCommand(target: .application(words[2]))
        default: return nil
        }
    }

    // command(opening bundleIdentifier): Build a command for the chosen app. The full
    // launcher path works whatever PATH the user's shell has.
    static func command(opening bundleIdentifier: String) -> String {
        "\(launcher) -b \(bundleIdentifier)"
    }

    /// The identifier of an `open -b` target; nil for an `open -a` target.
    var bundleIdentifier: String? {
        // Only identifier-based commands can supply an identifier directly.
        if case .bundleIdentifier(let identifier) = target { return identifier }
        return nil
    }

    // shellWords(text): Tokenize the limited command form used by the app picker.
    // Quotes group words; backslashes escape outside single quotes. Substitutions
    // stay literal, and an unfinished quote still yields a word.
    static func shellWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaping = false
        for character in text {
            // The previous character was a backslash: take this one literally.
            if escaping {
                current.append(character)
                escaping = false
                inWord = true
            } else if character == "\\", quote != "'" {
                // A backslash escapes the next character, except inside single quotes.
                escaping = true
            } else if let open = quote {
                // Inside a quoted word, only the matching quote closes the group.
                if character == open { quote = nil } else {
                    // Keep other characters inside the quoted word.
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                // An opening quote starts a group; an empty pair still counts as a word.
                quote = character
                inWord = true
            } else if character.isWhitespace {
                // End the word without creating empty arguments for repeated separators.
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                // An ordinary character extends the current word.
                current.append(character)
                inWord = true
            }
        }
        // Flush the last word. A trailing backslash escapes nothing and is dropped.
        if inWord { words.append(current) }
        return words
    }
}
