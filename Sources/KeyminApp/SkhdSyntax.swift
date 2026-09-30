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

/// A built-in key keyword such as `return`, `f1`, or `sound_up`.
struct SkhdLiteralKey: Hashable {
    enum Kind {
        /// Ordinary keys such as `return` or `space`.
        case standard
        /// Keys skhd matches with an implicit `fn` flag: navigation and function keys.
        case navigation
        /// Media keys delivered through system-defined events rather than key codes.
        case media
    }

    let keyword: String
    let title: String
    /// The menu symbol, when the key has one.
    let symbol: String?
    /// The Apple virtual key code. Media keys have none; skhd matches them by system event.
    let keyCode: UInt32?
    let kind: Kind

    /// Every keyword in the order skhd declares them. Entries after `escape` up to the media keys
    /// receive the implicit `fn` flag, matching `handle_implicit_literal_flags` in skhd.
    static let all: [SkhdLiteralKey] = [
        SkhdLiteralKey(keyword: "return", title: "Return", symbol: "⏎", keyCode: 0x24, kind: .standard),
        SkhdLiteralKey(keyword: "tab", title: "Tab", symbol: "⇥", keyCode: 0x30, kind: .standard),
        SkhdLiteralKey(keyword: "space", title: "Space", symbol: "␣", keyCode: 0x31, kind: .standard),
        SkhdLiteralKey(keyword: "backspace", title: "Delete", symbol: "⌫", keyCode: 0x33, kind: .standard),
        SkhdLiteralKey(keyword: "escape", title: "Escape", symbol: "⎋", keyCode: 0x35, kind: .standard),
        SkhdLiteralKey(keyword: "delete", title: "Forward Delete", symbol: "⌦", keyCode: 0x75, kind: .navigation),
        SkhdLiteralKey(keyword: "home", title: "Home", symbol: "↖", keyCode: 0x73, kind: .navigation),
        SkhdLiteralKey(keyword: "end", title: "End", symbol: "↘", keyCode: 0x77, kind: .navigation),
        SkhdLiteralKey(keyword: "pageup", title: "Page Up", symbol: "⇞", keyCode: 0x74, kind: .navigation),
        SkhdLiteralKey(keyword: "pagedown", title: "Page Down", symbol: "⇟", keyCode: 0x79, kind: .navigation),
        SkhdLiteralKey(keyword: "insert", title: "Insert", symbol: nil, keyCode: 0x72, kind: .navigation),
        SkhdLiteralKey(keyword: "left", title: "Left Arrow", symbol: "←", keyCode: 0x7B, kind: .navigation),
        SkhdLiteralKey(keyword: "right", title: "Right Arrow", symbol: "→", keyCode: 0x7C, kind: .navigation),
        SkhdLiteralKey(keyword: "up", title: "Up Arrow", symbol: "↑", keyCode: 0x7E, kind: .navigation),
        SkhdLiteralKey(keyword: "down", title: "Down Arrow", symbol: "↓", keyCode: 0x7D, kind: .navigation),
        SkhdLiteralKey(keyword: "f1", title: "F1", symbol: nil, keyCode: 0x7A, kind: .navigation),
        SkhdLiteralKey(keyword: "f2", title: "F2", symbol: nil, keyCode: 0x78, kind: .navigation),
        SkhdLiteralKey(keyword: "f3", title: "F3", symbol: nil, keyCode: 0x63, kind: .navigation),
        SkhdLiteralKey(keyword: "f4", title: "F4", symbol: nil, keyCode: 0x76, kind: .navigation),
        SkhdLiteralKey(keyword: "f5", title: "F5", symbol: nil, keyCode: 0x60, kind: .navigation),
        SkhdLiteralKey(keyword: "f6", title: "F6", symbol: nil, keyCode: 0x61, kind: .navigation),
        SkhdLiteralKey(keyword: "f7", title: "F7", symbol: nil, keyCode: 0x62, kind: .navigation),
        SkhdLiteralKey(keyword: "f8", title: "F8", symbol: nil, keyCode: 0x64, kind: .navigation),
        SkhdLiteralKey(keyword: "f9", title: "F9", symbol: nil, keyCode: 0x65, kind: .navigation),
        SkhdLiteralKey(keyword: "f10", title: "F10", symbol: nil, keyCode: 0x6D, kind: .navigation),
        SkhdLiteralKey(keyword: "f11", title: "F11", symbol: nil, keyCode: 0x67, kind: .navigation),
        SkhdLiteralKey(keyword: "f12", title: "F12", symbol: nil, keyCode: 0x6F, kind: .navigation),
        SkhdLiteralKey(keyword: "f13", title: "F13", symbol: nil, keyCode: 0x69, kind: .navigation),
        SkhdLiteralKey(keyword: "f14", title: "F14", symbol: nil, keyCode: 0x6B, kind: .navigation),
        SkhdLiteralKey(keyword: "f15", title: "F15", symbol: nil, keyCode: 0x71, kind: .navigation),
        SkhdLiteralKey(keyword: "f16", title: "F16", symbol: nil, keyCode: 0x6A, kind: .navigation),
        SkhdLiteralKey(keyword: "f17", title: "F17", symbol: nil, keyCode: 0x40, kind: .navigation),
        SkhdLiteralKey(keyword: "f18", title: "F18", symbol: nil, keyCode: 0x4F, kind: .navigation),
        SkhdLiteralKey(keyword: "f19", title: "F19", symbol: nil, keyCode: 0x50, kind: .navigation),
        SkhdLiteralKey(keyword: "f20", title: "F20", symbol: nil, keyCode: 0x5A, kind: .navigation),
        SkhdLiteralKey(keyword: "sound_up", title: "Volume Up", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "sound_down", title: "Volume Down", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "mute", title: "Mute", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "play", title: "Play/Pause", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "previous", title: "Previous Track", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "next", title: "Next Track", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "rewind", title: "Rewind", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "fast", title: "Fast Forward", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "brightness_up", title: "Brightness Up", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "brightness_down", title: "Brightness Down", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "illumination_up", title: "Keyboard Backlight Up", symbol: nil, keyCode: nil, kind: .media),
        SkhdLiteralKey(keyword: "illumination_down", title: "Keyboard Backlight Down", symbol: nil, keyCode: nil, kind: .media),
    ]

    static let byKeyword: [String: SkhdLiteralKey] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.keyword, $0) }
    )

    /// Lookup by key code. Media keys have none, so they are absent here.
    static let byKeyCode: [UInt32: SkhdLiteralKey] = Dictionary(
        all.compactMap { literal in literal.keyCode.map { ($0, literal) } },
        uniquingKeysWith: { first, _ in first }
    )

    static let keywords = Set(all.map(\.keyword))
}

/// Apple virtual key codes for keys without a keyword. Labels use the US keyboard layout.
enum SkhdKeyCodes {
    /// Letters and digits in Apple's ANSI key-code positions. skhd resolves single characters
    /// through the active keyboard layout, so this map is only a readable approximation.
    static let characters: [UInt32: Character] = [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e", 0x03: "f", 0x05: "g", 0x04: "h",
        0x22: "i", 0x26: "j", 0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n", 0x1F: "o", 0x23: "p",
        0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t", 0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x",
        0x10: "y", 0x06: "z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7",
        0x1C: "8", 0x19: "9",
    ]

    /// The reverse of `characters`.
    static let codes: [Character: UInt32] = Dictionary(
        uniqueKeysWithValues: characters.map { ($1, $0) }
    )

    /// Keys without a keyword, which can only be written as key codes: punctuation, the keypad, and
    /// a few special keys.
    static let labels: [UInt32: String] = [
        0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[", 0x27: "'", 0x29: ";", 0x2A: "\\", 0x2B: ",",
        0x2C: "/", 0x2F: ".", 0x32: "`", 0x0A: "§",
        0x41: "Keypad .", 0x43: "Keypad *", 0x45: "Keypad +", 0x47: "Keypad Clear", 0x4B: "Keypad /",
        0x4C: "Keypad Enter", 0x4E: "Keypad -", 0x51: "Keypad =", 0x52: "Keypad 0", 0x53: "Keypad 1",
        0x54: "Keypad 2", 0x55: "Keypad 3", 0x56: "Keypad 4", 0x57: "Keypad 5", 0x58: "Keypad 6",
        0x59: "Keypad 7", 0x5B: "Keypad 8", 0x5C: "Keypad 9",
        0x39: "Caps Lock", 0x5D: "¥", 0x5E: "_", 0x5F: "Keypad ,", 0x66: "英数", 0x68: "かな",
        0x48: "Volume Up", 0x49: "Volume Down", 0x4A: "Mute",
    ]

    // label(for code): Describe a virtual key using the US layout, a named-key
    // title, or hexadecimal when the code has no known label.
    static func label(for code: UInt32) -> String {
        // Letter and digit codes use their familiar uppercase key-cap labels.
        if let character = characters[code] { return String(character).uppercased() }
        // Punctuation and keypad keys have labels even without skhd keywords.
        if let label = labels[code] { return label }
        // Named navigation and function keys use the same title as the picker.
        if let literal = SkhdLiteralKey.byKeyCode[code] { return literal.title }
        return String(format: "0x%02X", code)
    }

    // source(for code): Write the `0x` prefix followed by uppercase
    // hex digits.
    static func source(for code: UInt32) -> String {
        String(format: "0x%02X", code)
    }
}
