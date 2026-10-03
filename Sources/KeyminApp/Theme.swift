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

// MARK: - Surfaces

/// Card chrome: padding, a plain or sunken surface, and a hairline border.
struct CardModifier: ViewModifier {
    var padding: CGFloat
    var sunken: Bool

    // body(content): Pad the content, then draw the card surface and border behind it.
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(sunken ? Theme.surfaceSunken : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

extension View {
    // card([padding = 0], [sunken = false]): Wrap the view in card chrome; a sunken card uses the
    // text background for inset areas.
    func card(padding: CGFloat = 0, sunken: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, sunken: sunken))
    }

    // hoverHighlight([cornerRadius = 8]): Row hover highlight for lists and tables.
    func hoverHighlight(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}

/// Fades a faint fill in behind the content while the pointer is over it.
private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @State private var hovering = false

    // body(content): Draw the hover fill behind the content and track the pointer.
    func body(content: Content) -> some View {
        content
            .background(Theme.textPrimary.opacity(hovering ? 0.055 : 0), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering = $0 }
    }
}

/// A tinted symbol tile used for page headers, sidebar rows, and empty states.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 56
    var tint: Color = Theme.accent
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        // Symbol size, corner radius, and padding all scale with the tile; the stroke is stronger
        // in Increase Contrast so the tile keeps an edge.
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: shape)
            .overlay(shape.stroke(
                tint.opacity(contrast == .increased ? 0.42 : 0.12),
                lineWidth: contrast == .increased ? 1.5 : 1
            ))
    }
}

/// A message card for errors, warnings, and notes.
struct NoticeCard: View {
    let tone: Tone
    let symbol: String
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.color(for: tone))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                // The optional detail wraps under the title.
                if let detail {
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color(for: tone).opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.color(for: tone).opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Controls

/// A capsule switch in the accent color.
struct SwitchControl: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            // The knob springs to the side that matches the state; the track takes the accent
            // when on.
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.borderStrong))
                Circle()
                    .fill(.white)
                    .padding(3)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .frame(width: 44, height: 24)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(.bare)
        .keyboardFocusable()
        .accessibilityValue(localized(isOn ? "On" : "Off"))
    }
}

/// A switch inside a card with a title and one line of explanation.
struct ToggleCard: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        // The whole card is the button, so clicking the text toggles the switch as well.
        Button { isOn.toggle() } label: {
            HStack(spacing: 16) {
                SwitchControl(isOn: $isOn)
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized(title)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(localized(subtitle)).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bare)
        .keyboardFocusable()
        .card()
    }
}

/// A unified segmented control with an inset selected segment on a quiet shared track.
struct SegmentedControl: View {
    let options: [String]
    @Binding var selection: Int
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // Each segment is its own focusable button; only the selected one draws the inset fill.
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button { selection = index } label: {
                    Text(localized(option))
                        .font(.system(size: 13, weight: selection == index ? .semibold : .medium))
                        .foregroundStyle(selection == index ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: Theme.controlHeight - 4)
                        .background(
                            selection == index ? Theme.segmentSelected : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.radius - 2, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Theme.radius - 2, style: .continuous))
                }
                .buttonStyle(.bare)
                .keyboardFocusable()
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: Theme.controlHeight)
        // The track hugs its segments instead of stretching to the available width.
        .fixedSize(horizontal: true, vertical: true)
        .background(Theme.segmentTrack)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .stroke(Theme.badgeBorder, lineWidth: contrast == .increased ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// A checkbox in the accent color, drawn by `CheckRow`.
struct CheckMark: View {
    let checked: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            // Keep empty boxes distinct from the surrounding surface in both appearances.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(checked ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.inputBackground))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(checked ? Theme.accentDeep : Theme.checkboxBorder,
                        lineWidth: checked ? 1 : contrast == .increased ? 2 : 1.5)
            // The tick only exists while checked, so it animates in and out with the fill.
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
            }
        }
        .frame(width: 20, height: 20)
        .animation(.easeOut(duration: 0.12), value: checked)
    }
}

/// A labeled checkbox row.
struct CheckRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                CheckMark(checked: isOn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized(title))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    // The optional subtitle wraps under the title.
                    if let subtitle {
                        Text(localized(subtitle))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bare)
        .keyboardFocusable()
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A toggle chip used for modifier keys and modes.
struct ToggleChip: View {
    let text: String
    let isOn: Bool
    var help: String? = nil
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 9, style: .continuous) }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isOn ? Theme.onAccent : Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: Theme.smallControlHeight + 2)
                .background(
                    isOn ? AnyShapeStyle(Theme.accentGradient)
                        : AnyShapeStyle(hovering ? Theme.textPrimary.opacity(0.08) : Theme.surfaceRaised),
                    in: shape
                )
                .overlay(shape.stroke(isOn ? Theme.accentDeep.opacity(0.9) : Theme.borderStrong,
                                      lineWidth: contrast == .increased ? 1.5 : 1))
                .contentShape(shape)
        }
        .buttonStyle(.bare)
        .keyboardFocusable()
        .onHover { hovering = $0 }
        // The tooltip and VoiceOver label prefer the help text, since the visible text is often
        // a bare symbol or mode name.
        .help(help.map(localized) ?? text)
        .accessibilityLabel(help.map(localized) ?? text)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.easeOut(duration: 0.12), value: isOn)
    }
}

/// A single-line text field with custom chrome, used for names, key codes, and paths.
struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var mono = false
    var onSubmit: (() -> Void)? = nil
    @State private var isFocused = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    var body: some View {
        StableTextInput(
            placeholder: localized(placeholder),
            text: $text,
            font: mono ? .monospacedSystemFont(ofSize: 12.5, weight: .regular) : .systemFont(ofSize: 13),
            contentHeight: 20,
            textVerticalOffset: -1,
            onFocusChange: { isFocused = $0 },
            onSubmit: onSubmit
        )
        .frame(height: 20)
        .padding(.horizontal, 10)
        .frame(height: Theme.smallControlHeight + 2)
        // Focus switches the border to the accent.
        .background(Theme.inputBackground, in: shape)
        .overlay(shape.stroke(isFocused ? Theme.accent : Theme.inputBorder, lineWidth: isFocused ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// A single-line input built on its own text view, used behind every custom field. Unlike a text
/// field it never hands editing to the window's shared field editor, so text and placeholder keep
/// one baseline whether focused or not.
struct StableTextInput: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let font: NSFont
    let contentHeight: CGFloat
    /// Nudge of the text from the mathematical center; most field chrome reads best 2 pt up.
    var textVerticalOffset: CGFloat = -2
    var focusOnWindowOpen = false
    var handlesSidebarSearchCommand = false
    /// Moves keyboard focus into the field on the update where it turns true. Only that rising
    /// edge counts, so set it back to false before requesting focus again.
    var requestedFocus = false
    var onFocusChange: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?

    // makeCoordinator(): The delegate that pushes edits into the binding.
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    // makeNSView(context): Build the scroll view and text view pair, then wire up the delegate,
    // placeholder, focus options, callbacks, and accessibility.
    func makeNSView(context: Context) -> StableInputScrollView {
        let scrollView = StableInputScrollView(
            font: font,
            contentHeight: contentHeight,
            textVerticalOffset: textVerticalOffset
        )
        let textView = scrollView.textView
        textView.delegate = context.coordinator
        textView.placeholderAttributedString = placeholderText
        textView.focusOnWindowOpen = focusOnWindowOpen
        textView.handlesSidebarSearchCommand = handlesSidebarSearchCommand
        textView.onFocusChange = onFocusChange
        textView.onSubmit = onSubmit
        textView.setAccessibilityRole(.textField)
        textView.setAccessibilityLabel(placeholder)
        return scrollView
    }

    // updateNSView(scrollView, context): Push the latest binding, placeholder, options, and
    // callbacks into the text view, and move focus in when requestedFocus rises.
    func updateNSView(_ scrollView: StableInputScrollView, context: Context) {
        context.coordinator.text = $text
        let textView = scrollView.textView
        textView.placeholderAttributedString = placeholderText
        textView.focusOnWindowOpen = focusOnWindowOpen
        textView.handlesSidebarSearchCommand = handlesSidebarSearchCommand
        textView.onFocusChange = onFocusChange
        textView.onSubmit = onSubmit
        textView.setAccessibilityLabel(placeholder)
        // Replace the text only when it differs, so typing is never interrupted; a change from
        // outside puts the caret at the end and clears the field's undo history, whose ranges
        // refer to the old text. Never while an input method is composing (marked text):
        // replacing the text then would put the composed characters in the wrong place. The
        // update that follows the end of the composition applies any difference that remains.
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
            context.coordinator.undoManager.removeAllActions()
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            textView.needsDisplay = true
        }
        // Only a rising edge of requestedFocus moves focus, so one request cannot keep stealing
        // it back on every later update.
        let shouldRequestFocus = requestedFocus && !context.coordinator.lastRequestedFocus
        context.coordinator.lastRequestedFocus = requestedFocus
        // Defer the responder change so the view is in its window by the time it runs.
        if shouldRequestFocus, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { [weak textView] in
                guard let textView, let window = textView.window else { return }
                _ = window.makeFirstResponder(textView)
            }
        }
    }

    /// The placeholder in the field's font and the shared placeholder color.
    private var placeholderText: NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [
                .font: font,
                .foregroundColor: Theme.inputPlaceholderNSColor
            ]
        )
    }

    /// Receives text view edits and writes them to the SwiftUI binding.
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        /// The requestedFocus value seen on the last update, for edge detection.
        var lastRequestedFocus = false
        /// This field's own undo history. Sharing the window's would let ⌘Z replay typing from
        /// another field, or from text the model has since replaced, and corrupt it.
        let undoManager = UndoManager()

        // init(text): Keep the binding; updateNSView replaces it when SwiftUI passes a new one.
        init(text: Binding<String>) { self.text = text }

        // undoManager(for view): Give the text view this field's own undo history.
        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        // textDidChange(notification): Flatten line breaks to spaces, keep the caret after the same
        // character, and push the text to the binding.
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let normalized = Self.singleLine(textView.string)
            // Pasted text can carry line breaks the single-line container cannot show; replace
            // them and put the caret where the text before it now ends. Not while an input method
            // is composing, which the replacement would break; its final edit comes back here.
            if normalized != textView.string, !textView.hasMarkedText() {
                let current = textView.string as NSString
                let selection = textView.selectedRange()
                let before = current.substring(to: min(selection.location, current.length))
                let caret = (Self.singleLine(before) as NSString).length
                textView.string = normalized
                // The replacement is not undoable, so earlier steps would point at the old text.
                undoManager.removeAllActions()
                textView.setSelectedRange(NSRange(
                    location: min(caret, (normalized as NSString).length),
                    length: 0
                ))
            }
            text.wrappedValue = normalized
        }

        // singleLine(text): The text with each line break, whether "\r\n", "\r", or "\n", replaced
        // by one space. The pair goes first so a Windows line break becomes a single space.
        static func singleLine(_ text: String) -> String {
            text.replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
        }
    }
}

/// A borderless scroll view without scrollers that hosts one `StableInputTextView` at a fixed
/// height. The SwiftUI chrome draws around it.
final class StableInputScrollView: NSScrollView {
    let textView = StableInputTextView(frame: .zero)

    // init(font, contentHeight, textVerticalOffset): Set the text view up as a single clipped
    // line centered in contentHeight, with every automatic text substitution turned off.
    init(font: NSFont, contentHeight: CGFloat, textVerticalOffset: CGFloat) {
        super.init(frame: .zero)
        // No border, background, scrollers, or inset adjustment; the field chrome is SwiftUI's.
        borderType = .noBorder
        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = false
        automaticallyAdjustsContentInsets = false

        // Plain text that grows sideways only; the scroll view clips what does not fit.
        textView.font = font
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.height]
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        // Center the line in the content height, then apply the caller's optical nudge.
        textView.textContainerInset = NSSize(
            width: 0,
            height: floor((contentHeight - lineHeight) / 2) + textVerticalOffset
        )
        // One unbounded line that never wraps: overflow is clipped instead.
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.maximumNumberOfLines = 1
        textView.textContainer?.lineBreakMode = .byClipping
        // These fields hold names, paths, and queries, so no spelling or substitution help.
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false

        // Pin the height so the intrinsic size below matches the content height exactly.
        textView.minSize = NSSize(width: 0, height: contentHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: contentHeight)
        textView.frame = NSRect(x: 0, y: 0, width: 1, height: contentHeight)
        documentView = textView
    }

    /// Exactly the content height; the width comes from the SwiftUI frame.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: textView.minSize.height)
    }

    // init(coder): Unsupported; the view is only ever built in code.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// The single-line text view behind every custom field. It draws its own placeholder, submits on
/// Return, moves focus with Tab, and can take focus when its window opens or when the Find
/// Binding command fires.
final class StableInputTextView: NSTextView {
    var placeholderAttributedString: NSAttributedString? {
        didSet { needsDisplay = true }
    }
    /// Takes keyboard focus once, the first time its window is key.
    var focusOnWindowOpen = false {
        didSet {
            guard focusOnWindowOpen != oldValue else { return }
            configureInitialFocus()
        }
    }
    /// Answers the Find Binding command for its own window.
    var handlesSidebarSearchCommand = false {
        didSet {
            guard handlesSidebarSearchCommand != oldValue else { return }
            configureSearchCommand()
        }
    }
    var onFocusChange: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?

    private var keyWindowObserver: NSObjectProtocol?
    private var searchCommandObserver: NSObjectProtocol?
    /// True while a deferred focus attempt is queued.
    private var focusScheduled = false
    /// Set once the initial focus has landed, so later key changes do not steal focus back.
    private var appliedInitialFocus = false

    // preferredTextAccessoryPlacement(): Hide the cursor accessory to avoid its empty
    // translucent placeholder appearing beside the caret during cold launch.
    override func preferredTextAccessoryPlacement() -> NSTextCursorAccessoryPlacement { .invisible }

    // viewDidMoveToWindow(): Re-arm the window-bound observers for the new window, or drop them
    // when the view is detached.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureInitialFocus()
        configureSearchCommand()
    }

    // configureSearchCommand(): Observe the Find Binding command for this view's window only. The
    // command is posted with the key window as its object, so another open Keymin window never
    // receives the focus unexpectedly.
    private func configureSearchCommand() {
        removeSearchCommandObserver()
        guard handlesSidebarSearchCommand, let window else { return }
        searchCommandObserver = NotificationCenter.default.addObserver(
            forName: .focusSidebarSearch,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusFromMenuCommand() }
        }
    }

    // focusFromMenuCommand(): Focus the field and select the current query so typing replaces it.
    private func focusFromMenuCommand() {
        guard let window, window.isVisible, window.makeFirstResponder(self) else { return }
        selectAll(nil)
    }

    // configureInitialFocus(): Arrange a one-time focus for when the window becomes key, and try
    // right away in case it already is.
    private func configureInitialFocus() {
        removeKeyWindowObserver()
        guard focusOnWindowOpen, !appliedInitialFocus, let window else { return }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusWhenWindowIsReady() }
        }
        focusWhenWindowIsReady()
    }

    // focusWhenWindowIsReady(): Take first responder on the next run-loop turn once the window
    // is visible and key. A call while an attempt is already queued does nothing.
    private func focusWhenWindowIsReady() {
        guard !focusScheduled,
              !appliedInitialFocus,
              let window,
              window.isVisible,
              window.isKeyWindow else { return }
        focusScheduled = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self else { return }
            self.focusScheduled = false
            // The view may have changed windows, or the window lost key status, while waiting.
            guard let window,
                  self.window === window,
                  window.isVisible,
                  window.isKeyWindow else { return }
            // Once focus lands, stop listening so later key changes leave the user's focus alone.
            if window.makeFirstResponder(self) {
                self.appliedInitialFocus = true
                self.removeKeyWindowObserver()
            }
        }
    }

    // keyDown(with event): Let Return submit and Tab move focus; all other keys and keys while an
    // input method is composing, go to the text view.
    override func keyDown(with event: NSEvent) {
        // An input method is composing marked text, so Return and Tab belong to it.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 36, 76:
            // Return and keypad Enter submit instead of inserting a newline.
            onSubmit?()
            return
        case 48 where modifiers.isEmpty || modifiers == .shift:
            // Tab and Shift-Tab move between key views instead of inserting a tab character.
            // Shift reverses the navigation direction.
            if modifiers.contains(.shift) {
                window?.selectPreviousKeyView(nil)
            } else {
                // Plain Tab walks forward.
                window?.selectNextKeyView(nil)
            }
            return
        default:
            break
        }
        super.keyDown(with: event)
    }

    // becomeFirstResponder(): Report focus to SwiftUI once AppKit has accepted it.
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        // Only a responder change AppKit actually made is worth reporting.
        if accepted { reportFocus(true) }
        return accepted
    }

    // resignFirstResponder(): Report the loss of focus to SwiftUI once AppKit has accepted it.
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        // Only a responder change AppKit actually made is worth reporting.
        if resigned { reportFocus(false) }
        return resigned
    }

    // reportFocus(focused): Deliver the focus change on the next turn, so SwiftUI state is not
    // changed in the middle of AppKit's responder change.
    private func reportFocus(_ focused: Bool) {
        guard let onFocusChange else { return }
        DispatchQueue.main.async { onFocusChange(focused) }
    }

    // didChangeText(): Redraw so the placeholder appears or disappears with the text.
    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    // draw(dirtyRect): After the text, draw the placeholder in an empty field, starting where
    // the text itself would start.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholderAttributedString else { return }
        let origin = textContainerOrigin
        placeholderAttributedString.draw(in: NSRect(
            x: origin.x,
            y: origin.y,
            width: max(0, bounds.width - origin.x),
            height: bounds.height - origin.y
        ))
    }

    // removeKeyWindowObserver(): Stop waiting for the window to become key.
    private func removeKeyWindowObserver() {
        guard let keyWindowObserver else { return }
        NotificationCenter.default.removeObserver(keyWindowObserver)
        self.keyWindowObserver = nil
    }

    // removeSearchCommandObserver(): Stop answering the Find Binding command.
    private func removeSearchCommandObserver() {
        guard let searchCommandObserver else { return }
        NotificationCenter.default.removeObserver(searchCommandObserver)
        self.searchCommandObserver = nil
    }

    // deinit(): Drop both observers.
    deinit {
        removeKeyWindowObserver()
        removeSearchCommandObserver()
    }
}
