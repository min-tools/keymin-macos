import AppKit
import SwiftUI

/// One binding in the list: its shortcut caps, the title or action, a passthrough mark, and a
/// problem dot when diagnostics exist.
private struct BindingRow: View {
    let binding: SkhdHotkey
    let selected: Bool
    /// The dot color from the binding's diagnostics; nil hides the dot.
    let problem: Tone?
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    /// The action in words. It also stands in for the title when the binding has none.
    private var subtitle: String {
        let summary = binding.actionSummary
        switch binding.action {
        case .processMap(let mappings):
            let named = mappings.filter { !$0.isWildcard }.count
            return named == 1 ? localizedFormat("In %@", summary) : localizedFormat("%lld apps: %@", Int64(named), summary)
        case .activateMode(let mode):
            return localizedFormat("Switch to mode %@", mode)
        case .command:
            return summary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ShortcutCaps(modifiers: binding.modifiers, key: binding.key, size: 10.5, spacing: 3)
                .frame(minWidth: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(binding.title.isEmpty ? subtitle : binding.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                // With a title, the action moves to a second monospace line.
                if !binding.title.isEmpty {
                    Text(subtitle)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            // Passthrough bindings also let the keypress reach the app in front.
            if binding.passthrough {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .help(localized("Keypress passes through to the app"))
            }
            // The diagnostics dot; its color says whether they are errors or warnings.
            if let problem {
                Circle()
                    .fill(Theme.color(for: problem))
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(localized(problem == .negative ? "Has errors" : "Has warnings"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        // Rows draw their own selection and hover fill; the table's highlight is turned off.
        .background(
            selected ? Theme.sidebarSelection
                : hovering ? Theme.sidebarHover : Color.clear,
            in: shape
        )
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

/// One configuration page in the list: an icon tile, the page name, and an optional count.
private struct PageRow: View {
    let symbol: String
    let title: String
    /// Items on the page; nil or zero shows nothing.
    let count: Int?
    let selected: Bool
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 11) {
            IconTile(symbol: symbol, size: 28, tint: Theme.textSecondary)
            Text(localized(title))
                .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            // Only a positive count is worth a number.
            if let count, count > 0 {
                Text(String(count))
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        // Same self-drawn selection and hover fill as the binding rows.
        .background(
            selected ? Theme.sidebarSelection
                : hovering ? Theme.sidebarHover : Color.clear,
            in: shape
        )
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}
