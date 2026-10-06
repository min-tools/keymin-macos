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

/// SwiftUI's sidebar list supplies native selection and keyboard behavior, while this public
/// AppKit setting leaves the selected-row drawing to the rows instead of adding a solid fill.
private struct SidebarListSelectionAppearance: NSViewRepresentable {
    /// Called once, after the table has been configured, so the list can enable selection.
    let onConfigured: () -> Void

    // makeNSView(context): Create the invisible view that will look for the table.
    func makeNSView(context: Context) -> ConfigurationView {
        let view = ConfigurationView()
        view.onConfigured = onConfigured
        return view
    }

    // updateNSView(nsView, context): Re-apply the table settings on every SwiftUI update, in
    // case the list rebuilt its table.
    func updateNSView(_ nsView: ConfigurationView, context: Context) {
        nsView.onConfigured = onConfigured
        nsView.configureTable()
    }

    /// An empty view placed inside a section header, so it sits in the list's table hierarchy.
    final class ConfigurationView: NSView {
        var onConfigured: (() -> Void)?
        /// Guards the one-time callback; the settings themselves may be applied again.
        private var configuredTable = false

        /// No intrinsic size, so the view never affects the header layout.
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        // viewDidMoveToSuperview(): Configure as soon as the view is attached to the list.
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureTable()
        }

        // configureTable(): Find the enclosing table on the next run loop turn, when the view is
        // fully attached, then turn off its selection highlight and focus ring.
        func configureTable() {
            DispatchQueue.main.async { [weak self] in
                var ancestor = self?.superview
                while let view = ancestor {
                    // The first table up the chain is the sidebar list's own.
                    if let table = view as? NSTableView {
                        table.selectionHighlightStyle = .none
                        table.focusRingType = .none
                        // Tell the list once; it can now enable selection safely.
                        if self?.configuredTable == false {
                            self?.configuredTable = true
                            self?.onConfigured?()
                        }
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
}
