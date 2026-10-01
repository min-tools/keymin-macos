import AppKit
import SwiftUI

/// Status colors used by chips, pills, notice cards, and status dots.
enum Tone { case neutral, accent, positive, warning, negative }

/// Design tokens shared by every screen. Text and status colors are macOS semantic colors;
/// branded surfaces use fixed Light/Dark pairs so controls keep their hierarchy.
enum Theme {
    static let background = adaptive(light: 0xFBFBFD, dark: 0x1C1C1E)
    static let sidebarBackground = adaptive(light: 0xF5F5F7, dark: 0x232325)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceRaised = Color(nsColor: .underPageBackgroundColor)
    static let surfaceSunken = Color(nsColor: .textBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let borderStrong = Color(nsColor: .gridColor)
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let accent = Color(nsColor: .controlAccentColor)
    static let onAccent = Color(nsColor: .alternateSelectedControlTextColor)
    static let accentBright = Color(nsColor: .controlAccentColor)
    static let accentDeep = Color(nsColor: .controlAccentColor)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)
    static let cyan = Color(nsColor: .systemTeal)

    // Fixed Light/Dark pairs for sidebar states, inputs, badges, segments, and key caps.
    static let sidebarSelection = adaptive(light: 0xE3ECFA, dark: 0x22324A)
    static let sidebarHover = adaptive(light: 0xEDEDF0, dark: 0x2C2C2E)
    static let labelText = adaptive(light: 0x86868B, dark: 0xA1A1A6)
    static let inputBackground = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let inputBorder = adaptive(light: 0xC7C7CC, dark: 0x545458)
    static let checkboxBorder = adaptive(light: 0x86868B, dark: 0x8E8E93)
    static let inputPlaceholderNSColor = adaptiveNSColor(light: 0x86868B, dark: 0xA1A1A6)
    static let inputPlaceholder = Color(nsColor: inputPlaceholderNSColor)
    static let badgeBackground = adaptive(light: 0xFFFFFF, dark: 0x303033)
    static let badgeBorder = adaptive(light: 0xD1D1D6, dark: 0x545458)
    static let badgeText = adaptive(light: 0x3A3A3C, dark: 0xE5E5EA)
    static let badgeActiveBackground = adaptive(light: 0xEEF4FF, dark: 0x16304F)
    static let badgeActiveBorder = adaptive(light: 0xB9D2F7, dark: 0x2F5A8F)
    static let badgeActiveText = adaptive(light: 0x0A5FCC, dark: 0x64A8FF)
    static let segmentTrack = adaptive(light: 0xE5E5EA, dark: 0x2C2C2E)
    static let segmentSelected = adaptive(light: 0xFFFFFF, dark: 0x5A5A5E)
    static let keyCapTop = adaptive(light: 0xFFFFFF, dark: 0x3A3A3E)
    static let keyCapBottom = adaptive(light: 0xEBEBEF, dark: 0x2A2A2E)
    static let keyCapEdge = adaptive(light: 0xC2C2C8, dark: 0x1A1A1C)

    // Corner radii and control heights shared by every control.
    static let radius: CGFloat = 10
    static let cardRadius: CGFloat = 12
    static let controlHeight: CGFloat = 34
    static let smallControlHeight: CGFloat = 28

    /// The top-to-bottom accent fill of primary buttons, switches, and checked boxes.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent.opacity(0.88), accent], startPoint: .top, endPoint: .bottom)
    }

    // mono([size = 12.5], [weight = .regular]): The monospaced system font used for shortcuts,
    // commands, and paths.
    static func mono(_ size: CGFloat = 12.5, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // color(for tone): The text or tint color that stands for a status tone.
    static func color(for tone: Tone) -> Color {
        switch tone {
        case .neutral: return textPrimary
        case .accent: return accent
        case .positive: return success
        case .warning: return warning
        case .negative: return danger
        }
    }

    // adaptive(light, dark): A SwiftUI color from two 0xRRGGBB values, resolved through AppKit so
    // windows update immediately when macOS changes appearance. High-contrast appearances keep
    // the same pair; components add stronger strokes themselves.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: adaptiveNSColor(light: light, dark: dark))
    }

    // adaptiveNSColor(light, dark): The AppKit form of adaptive(light:dark:), for custom controls
    // that cannot take a SwiftUI `Color`, such as the placeholder drawn by `StableInputTextView`.
    static func adaptiveNSColor(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            // Both dark appearances take the dark value; anything else, including an unknown
            // appearance, takes the light one.
            let match = appearance.bestMatch(from: [
                .accessibilityHighContrastDarkAqua,
                .darkAqua,
                .accessibilityHighContrastAqua,
                .aqua,
            ])
            let value = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
                ? dark : light
            // Unpack 0xRRGGBB into sRGB components.
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}

// MARK: - Chips, caps, and pills

/// A keyboard-shortcut cap. A standalone cap sits beside a control, such as the search field's
/// ⌘F; embedded and on-accent caps sit inside buttons.
struct KeyCap: View {
    enum Style { case standalone, embedded, onAccent }
    let text: String
    var style: Style = .standalone

    // init(text, [style = .standalone]): Allow the cap text as an unlabeled first argument.
    init(_ text: String, style: Style = .standalone) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(localized(text))
            .font(Theme.mono(11, weight: .medium))
            .foregroundStyle(style == .onAccent ? Theme.onAccent.opacity(0.92) : Theme.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            // On the accent fill the cap is translucent white; an embedded cap sinks into its
            // button, while a standalone cap rises from the surface.
            .background(
                style == .onAccent ? Color.white.opacity(0.16) : style == .embedded ? Theme.surfaceSunken : Theme.surfaceRaised,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(style == .onAccent ? Color.white.opacity(0.14) : Theme.borderStrong, lineWidth: 1))
    }
}

/// A physical-looking key cap used to show a binding's shortcut.
struct PhysicalKeyCap: View {
    let text: String
    var size: CGFloat = 13
    var emphasized = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(emphasized ? Theme.badgeActiveText : Theme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, max(5, size * 0.55))
            .frame(minWidth: size * 2.1, minHeight: size * 2.0)
            // A top-lit gradient, a solid edge below, and a soft drop shadow give the cap depth;
            // the edge stroke is fully opaque in Increase Contrast.
            .background(
                LinearGradient(colors: [Theme.keyCapTop, Theme.keyCapBottom], startPoint: .top, endPoint: .bottom),
                in: shape
            )
            .overlay(shape.stroke(Theme.keyCapEdge.opacity(contrast == .increased ? 1 : 0.7), lineWidth: 1))
            .shadow(color: Theme.keyCapEdge.opacity(0.9), radius: 0, y: 1.5)
            .shadow(color: Color.black.opacity(0.08), radius: 2, y: 2)
    }
}

/// A row of key caps for a shortcut, such as ⌥ ⇧ A.
struct ShortcutCaps: View {
    let modifiers: [SkhdModifier]
    let key: SkhdKey
    var size: CGFloat = 13
    var spacing: CGFloat = 5

    var body: some View {
        // Modifiers appear in canonical order and the key cap is emphasized; VoiceOver reads the
        // whole shortcut as one element.
        HStack(spacing: spacing) {
            ForEach(SkhdModifier.canonical(modifiers), id: \.self) { modifier in
                PhysicalKeyCap(text: modifier.symbol, size: size)
            }
            PhysicalKeyCap(text: key.capLabel, size: size, emphasized: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SkhdShortcutText.symbols(modifiers: modifiers, key: key))
    }
}
