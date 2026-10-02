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

// MARK: - Buttons

/// How a button is filled: `primary` is the accent call to action, `secondary` the default,
/// `ghost` has no resting fill, `danger` is tinted red, and `link` reads as text.
enum ButtonVariant { case primary, secondary, ghost, danger, link }
/// Regular buttons are `Theme.controlHeight` tall, small ones `Theme.smallControlHeight`.
enum ButtonSize { case regular, small }

/// The single button style of the app. Hover changes the fill or glow but never the shape, and a
/// button's own shortcut is printed on it as a chip.
struct KeyminButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var shortcut: String? = nil

    // makeBody(configuration): Hand the label to KeyminButtonBody, a view that can track hover.
    func makeBody(configuration: Configuration) -> some View {
        KeyminButtonBody(configuration: configuration, variant: variant, size: size, shortcut: shortcut)
    }
}

extension ButtonStyle where Self == KeyminButtonStyle {
    // keymin([variant = .secondary], [size = .regular], [shortcut = nil]): Dot-syntax access to the
    // style, as in `.buttonStyle(.keymin(.primary))`.
    static func keymin(_ variant: ButtonVariant = .secondary, size: ButtonSize = .regular, shortcut: String? = nil) -> KeyminButtonStyle {
        KeyminButtonStyle(variant: variant, size: size, shortcut: shortcut)
    }
}

/// A label-only style for rows, chips, and segments that draw their own states. Unlike the
/// system's plain style it adds no hover capsule, so custom fills keep their exact shape.
struct BareButtonStyle: ButtonStyle {
    // makeBody(configuration): Show the label as is and only dim it while pressed.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == BareButtonStyle {
    static var bare: BareButtonStyle { BareButtonStyle() }
}

extension View {
    // keyboardFocusable(): Opt a custom control into macOS keyboard navigation even when the
    // system preference only tabs between text fields. Buttons keep their native Space and Return
    // activation behavior.
    func keyboardFocusable() -> some View {
        focusable(true, interactions: .activate)
    }
}

/// The drawn body of `KeyminButtonStyle`, a separate view so it can track hover.
private struct KeyminButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: ButtonVariant
    let size: ButtonSize
    let shortcut: String?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size == .small ? 8 : Theme.radius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 8) {
            configuration.label
                .lineLimit(1)
            // Print the owned shortcut as a chip; on the accent fill it uses the lighter cap style.
            if let shortcut {
                KeyCap(shortcut, style: variant == .primary ? .onAccent : .embedded)
            }
        }
        .font(.system(size: size == .small ? 12 : 13, weight: .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, variant == .link ? 2 : (size == .small ? 11 : 14))
        .frame(height: size == .small ? Theme.smallControlHeight : Theme.controlHeight)
        // Fill, border, top highlight, and glow all follow the variant and the hover and pressed
        // state; the whole shape is the hit area.
        .background(AnyShapeStyle(fill), in: shape)
        .overlay(shape.stroke(borderColor, lineWidth: 1))
        .overlay(topHighlight)
        .shadow(color: glowColor, radius: hovering ? 14 : 9, y: 3)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    /// Hover and pressing shift the fill by variant; a disabled button goes flat, and ghost and
    /// link buttons have no resting fill.
    private var fill: any ShapeStyle {
        let pressed = configuration.isPressed
        switch variant {
        case .primary:
            // A disabled primary button fades to a flat tint without the gradient.
            if !isEnabled { return Theme.accent.opacity(0.22) }
            return Theme.accentGradient
        case .secondary:
            // A disabled secondary button sits flat on the base surface.
            if !isEnabled { return Theme.surface }
            return pressed ? Theme.surface : hovering ? Theme.textPrimary.opacity(0.10) : Theme.surfaceRaised
        case .ghost:
            return pressed ? Theme.textPrimary.opacity(0.12) : hovering ? Theme.textPrimary.opacity(0.07) : Color.clear
        case .danger:
            return Theme.danger.opacity(pressed ? 0.24 : hovering ? 0.18 : 0.12)
        case .link:
            return Color.clear
        }
    }

    /// Disabled buttons drop to the tertiary label color or a faded tint; pressed filled and
    /// ghost buttons dim slightly.
    private var foreground: Color {
        switch variant {
        case .primary:
            return Theme.onAccent.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.42)
        case .secondary, .ghost:
            return isEnabled ? Theme.textPrimary.opacity(configuration.isPressed ? 0.8 : 1) : Theme.textTertiary
        case .danger:
            return isEnabled ? Theme.danger : Theme.danger.opacity(0.4)
        case .link:
            return isEnabled ? (hovering ? Theme.accentBright : Theme.accent) : Theme.textTertiary
        }
    }

    /// Only filled and danger buttons draw a border; it lightens when disabled, and a disabled
    /// primary button has none.
    private var borderColor: Color {
        switch variant {
        case .primary: return isEnabled ? Theme.accentDeep.opacity(0.9) : Color.clear
        case .secondary: return isEnabled ? Theme.borderStrong : Theme.border
        case .ghost, .link: return Color.clear
        case .danger: return Theme.danger.opacity(isEnabled ? 0.45 : 0.2)
        }
    }

    /// Only enabled primary buttons glow, and hover strengthens it.
    private var glowColor: Color {
        guard isEnabled, variant == .primary else { return .clear }
        return Theme.accent.opacity(hovering ? 0.5 : 0.35)
    }

    /// The one-point highlight along the top edge that gives controls their lift.
    @ViewBuilder private var topHighlight: some View {
        // Only enabled filled buttons get the highlight; it is brighter on the accent fill.
        if variant == .primary || variant == .secondary, isEnabled {
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(variant == .primary ? 0.32 : 0.09), .clear, .clear],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
            .padding(0.5)
        }
    }
}

/// A 34 pt square icon button that lines up with text buttons.
struct IconButton: View {
    let symbol: String
    /// The tooltip and accessibility label, as English source text.
    var help: String
    var variant: ButtonVariant = .secondary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.keymin(variant))
        .keyboardFocusable()
        .frame(width: Theme.controlHeight, height: Theme.controlHeight)
        .help(localized(help))
        .accessibilityLabel(localized(help))
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

/// A small value chip, optionally with a lighter secondary label.
struct Chip: View {
    let text: String
    var secondary: String? = nil
    var selected = false
    var mono = true
    var tone: Tone = .neutral
    var compact = false
    var interactive = false
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    private var emphasized: Bool { selected || (interactive && hovering) }

    var body: some View {
        HStack(spacing: 6) {
            Text(localized(text))
                .font(mono ? Theme.mono(compact ? 11 : 12, weight: .medium) : .system(size: compact ? 11 : 12, weight: .medium))
                .foregroundStyle(chipText)
                .lineLimit(1)
            // The optional secondary label sits beside the value in a lighter weight.
            if let secondary {
                Text(localized(secondary))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 5)
        // Only interactive chips track hover; the stroke thickens in Increase Contrast.
        .background(chipBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(chipBorder, lineWidth: contrast == .increased ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering = interactive && $0 }
        .animation(.easeOut(duration: 0.12), value: emphasized)
    }

    // Toned chips take text, fill, and border from the tone at fixed opacities. Neutral chips use
    // the badge palette and switch to its active set when selected or hovered.
    private var chipText: Color {
        guard tone == .neutral else { return Theme.color(for: tone) }
        return emphasized ? Theme.badgeActiveText : Theme.badgeText
    }

    private var chipBackground: Color {
        guard tone == .neutral else { return Theme.color(for: tone).opacity(0.1) }
        return emphasized ? Theme.badgeActiveBackground : Theme.badgeBackground
    }

    private var chipBorder: Color {
        guard tone == .neutral else { return Theme.color(for: tone).opacity(0.35) }
        return emphasized ? Theme.badgeActiveBorder : Theme.badgeBorder
    }
}

/// A status dot with a label, such as Saved or Unsaved changes.
struct StatusPill: View {
    let tone: Tone
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            // The dot carries the tone and glows faintly so the state reads at a glance.
            Circle()
                .fill(Theme.color(for: tone))
                .frame(width: 7, height: 7)
                .shadow(color: Theme.color(for: tone).opacity(0.8), radius: 2)
            Text(localized(text))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.controlHeight)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
    }
}

/// Uppercase, tracked labels that head a group of controls or a card.
struct SectionLabel: View {
    let text: String
    // init(text): Allow the label text as an unlabeled argument.
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(localized(text).uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.labelText)
    }
}
