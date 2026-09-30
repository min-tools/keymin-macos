import Foundation

/// Modifier keywords accepted by skhd. The case order is the canonical order the editor writes them
/// in through `canonical(_:)`: ctrl, alt, shift, cmd, fn, then the combined keywords.
enum SkhdModifier: String, CaseIterable, Hashable {
    case ctrl, lctrl, rctrl
    case alt, lalt, ralt
    case shift, lshift, rshift
    case cmd, lcmd, rcmd
    case fn
    case hyper, meh

    /// The physical side a keyword such as `lalt` is limited to.
    enum Side { case left, right }

    /// Every keyword, used by the tokenizer to classify words.
    static let keywords = Set(allCases.map(\.rawValue))

    /// The generic modifiers shown as the primary toggles in the editor.
    static let generic: [SkhdModifier] = [.ctrl, .alt, .shift, .cmd, .fn]

    /// The keyword's position in the canonical output order.
    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// The generic family a side-specific keyword belongs to.
    var base: SkhdModifier {
        switch self {
        case .lctrl, .rctrl: return .ctrl
        case .lalt, .ralt: return .alt
        case .lshift, .rshift: return .shift
        case .lcmd, .rcmd: return .cmd
        default: return self
        }
    }

    /// Which physical side a keyword restricts itself to, if any.
    var side: Side? {
        switch self {
        case .lctrl, .lalt, .lshift, .lcmd: return .left
        case .rctrl, .ralt, .rshift, .rcmd: return .right
        default: return nil
        }
    }

    // keyword(for base, side): The side-specific keyword, or the generic family when
    // side is nil or the family has no sides.
    static func keyword(for base: SkhdModifier, side: Side?) -> SkhdModifier {
        switch (base, side) {
        case (.ctrl, .left): return .lctrl
        case (.ctrl, .right): return .rctrl
        case (.alt, .left): return .lalt
        case (.alt, .right): return .ralt
        case (.shift, .left): return .lshift
        case (.shift, .right): return .rshift
        case (.cmd, .left): return .lcmd
        case (.cmd, .right): return .rcmd
        default: return base
        }
    }

    /// The macOS menu symbol for the modifier. Side-specific keywords add a side letter.
    var symbol: String {
        switch base {
        case .ctrl: return sideMarked("⌃")
        case .alt: return sideMarked("⌥")
        case .shift: return sideMarked("⇧")
        case .cmd: return sideMarked("⌘")
        case .fn: return "fn"
        case .hyper: return "✦"
        case .meh: return "◆"
        default: return rawValue
        }
    }

    // sideMarked(symbol): Prefix the symbol with L or R for side-specific keywords.
    private func sideMarked(_ symbol: String) -> String {
        switch side {
        case .left: return "L" + symbol
        case .right: return "R" + symbol
        case nil: return symbol
        }
    }

    /// The English name used in the editor.
    var title: String {
        switch self {
        case .ctrl: return "Control"
        case .lctrl: return "Left Control"
        case .rctrl: return "Right Control"
        case .alt: return "Option"
        case .lalt: return "Left Option"
        case .ralt: return "Right Option"
        case .shift: return "Shift"
        case .lshift: return "Left Shift"
        case .rshift: return "Right Shift"
        case .cmd: return "Command"
        case .lcmd: return "Left Command"
        case .rcmd: return "Right Command"
        case .fn: return "Function"
        case .hyper: return "Hyper"
        case .meh: return "Meh"
        }
    }

    /// The generic flags a keyword stands for, used to find duplicate bindings.
    var expanded: Set<SkhdModifier> {
        switch self {
        case .hyper: return [.cmd, .alt, .shift, .ctrl]
        case .meh: return [.ctrl, .shift, .alt]
        default: return [base]
        }
    }

    // canonical(modifiers): Drop repeated keywords and sort the rest into the canonical order.
    static func canonical(_ modifiers: some Sequence<SkhdModifier>) -> [SkhdModifier] {
        var seen = Set<SkhdModifier>()
        return modifiers.filter { seen.insert($0).inserted }.sorted { $0.sortOrder < $1.sortOrder }
    }
}
