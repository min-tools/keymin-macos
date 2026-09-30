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
