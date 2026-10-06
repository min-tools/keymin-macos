import AppKit
import SwiftUI

// bindingCountText(count): A binding count in words, singular for one and "No bindings" for zero.
// Also used by the mode cards.
func bindingCountText(_ count: Int) -> String {
    // Zero reads as words, one as singular, anything else as plural.
    switch count {
    case 0: return localized("No bindings")
    case 1: return localized("1 binding")
    default: return localizedFormat("%lld bindings", Int64(count))
    }
}

/// A sidebar row: a binding or a configuration page.
private enum SidebarRowID: Hashable {
    case binding(UUID)
    case page(AppModel.Page)
}

/// The left pane: a filter field, the configuration pages, the bindings grouped by mode, and a
/// footer with the New Binding button and the binding count.
struct SidebarView: View {
    @ObservedObject var model: AppModel
    /// True once the native table's own selection highlight is turned off. Until then the list
    /// gets no selection, so the default blue fill can never flash before the rows take over.
    @State private var listAppearanceReady = false
    /// IDs of the folded sections, saved so the layout survives a relaunch.
    @State private var collapsedSections: Set<String>
    private static let collapsedSectionsKey = "KeyminCollapsedSidebarSections"
    private static let configurationSection = "configuration"

    // init(model): Restore which sections were folded the last time the app ran.
    init(model: AppModel) {
        self.model = model
        _collapsedSections = State(initialValue: Set(
            UserDefaults.standard.stringArray(forKey: Self.collapsedSectionsKey) ?? []
        ))
    }

    // expansionBinding(for sectionID): Expand or fold this section and save
    // the result. The change applies without animation, because animating lazy list rows can
    // briefly overlap the following header.
    private func expansionBinding(for sectionID: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(sectionID) },
            set: { expanded in
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    var updated = collapsedSections
                    // Only folded sections are stored, so expanding removes the ID.
                    if expanded {
                        updated.remove(sectionID)
                    } else {
                        // Folding records the ID.
                        updated.insert(sectionID)
                    }
                    collapsedSections = updated
                    UserDefaults.standard.set(updated.sorted(), forKey: Self.collapsedSectionsKey)
                }
            }
        )
    }

    // pageRow(symbol, title, page, count): One configuration page row, tagged so the list
    // selection maps back to the page. A nil or zero count shows no number.
    private func pageRow(_ symbol: String, _ title: String, _ page: AppModel.Page, count: Int?) -> some View {
        PageRow(symbol: symbol, title: title, count: count, selected: model.page == page)
            .tag(SidebarRowID.page(page))
            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
            .listRowSeparator(.hidden)
    }

    var body: some View {
        // Diagnostics cover the whole document, so they are computed once per render and looked
        // up per row; recomputing them for every row made typing lag in large files.
        let problems = Dictionary(grouping: model.diagnostics) { $0.itemID }
        VStack(spacing: 0) {
            // The filter field. Its placeholder doubles as the total binding count.
            SearchField(
                placeholder: filterPlaceholder,
                text: $model.sidebarQuery,
                trailing: "⌘F",
                focusOnWindowOpen: true,
                textVerticalOffset: 0
            )
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)

            // A native selection list is one Tab stop and owns arrow-key navigation, scrolling,
            // focus transfer and accessibility without manually moving focus between views.
            List(selection: listAppearanceReady ? selection : .constant(nil)) {
                // The configuration pages come first, in a section the user can fold away.
                Section(isExpanded: expansionBinding(for: Self.configurationSection)) {
                    pageRow("square.stack.3d.up", "Modes", .modes, count: model.modes.count)
                    pageRow("hand.raised", "Blacklist", .blacklist, count: model.blacklist.count)
                    pageRow("doc.on.doc", "Included Files", .includes, count: model.includes.count)
                    pageRow("arrow.triangle.2.circlepath", "After Saving", .afterSave, count: model.afterSave.isConfigured ? 1 : nil)
                    pageRow("chevron.left.forwardslash.chevron.right", "Source", .source, count: nil)
                } header: {
                    // Equal top and bottom padding keeps the label centered on the native chevron.
                    SectionLabel("Configuration")
                        .padding(.leading, 4)
                        .padding(.vertical, 6)
                        .background(SidebarListSelectionAppearance {
                            listAppearanceReady = true
                        })
                }

                // One section per mode, default mode first; the filter has already been applied.
                ForEach(model.visibleGroups) { group in
                    Section(isExpanded: expansionBinding(for: "mode:" + group.mode)) {
                        ForEach(group.bindings) { binding in
                            BindingRow(
                                binding: binding,
                                selected: model.selectedBindingID == binding.id && model.page == .binding,
                                problem: problemTone(for: problems[binding.id] ?? [])
                            )
                            .tag(SidebarRowID.binding(binding.id))
                            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        SectionLabel(group.mode == "default" ? "Bindings" : localizedFormat("Mode %@", group.mode))
                            .padding(.leading, 4)
                            .padding(.vertical, 10)
                    }
                }

                // Nothing to list: the file has no bindings, or the filter matched none of them.
                if model.visibleGroups.isEmpty {
                    Text(localized(model.document.hotkeys.isEmpty ? "No bindings yet" : "No matching bindings"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 16)
                        .listRowSeparator(.hidden)
                }

                // Hidden bindings stay in the file; this row counts them and opens the Pro panel.
                if model.hiddenBindingCount > 0 {
                    Button {
                        model.presentPro(for: .allBindings)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.warning)
                            Text(model.hiddenBindingCount == 1
                                 ? localized("1 more binding needs Keymin Pro")
                                 : localizedFormat("%lld more bindings need Keymin Pro", Int64(model.hiddenBindingCount)))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bare)
                    .keyboardFocusable()
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            // Inset the scroll content four points to separate chevrons from the scroller.
            .contentMargins(.trailing, 4, for: .scrollContent)
            .focusEffectDisabled()
            .accessibilityLabel(localized("Bindings"))
            .animation(nil, value: listAppearanceReady)

            // Footer: the New Binding button and a count that also reveals how many bindings the
            // Free tier is hiding. Both keep their full width; the spacer between them shrinks,
            // because the stack would otherwise truncate the button to make room.
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 8) {
                Button {
                    model.addBinding()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text(localized("New Binding"))
                    }
                }
                .buttonStyle(.keymin(.secondary, size: .small, shortcut: "⌘N"))
                .keyboardFocusable()
                .fixedSize()
                Spacer()
                // Hidden bindings make the total at least two, so "of" always takes the plural.
                Text(model.hiddenBindingCount > 0
                     ? localizedFormat("%lld of %lld bindings", Int64(model.editableHotkeys.count), Int64(model.document.hotkeys.count))
                     : bindingCountText(model.document.hotkeys.count))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.sidebarBackground)
        // While the user types a filter, select its first match so the editor follows along.
        .onChange(of: model.sidebarQuery) {
            let query = model.sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty,
                  let firstMatch = model.visibleGroups.first?.bindings.first,
                  firstMatch.id != model.selectedBindingID else { return }
            model.select(firstMatch.id)
        }
    }

    /// The filter field's placeholder, which also counts the bindings in the file.
    private var filterPlaceholder: String {
        let count = model.document.hotkeys.count
        // Without bindings there is nothing to count; one binding is singular.
        switch count {
        case 0: return localized("Filter bindings")
        case 1: return localized("Filter 1 binding")
        default: return localizedFormat("Filter %lld bindings", Int64(count))
        }
    }

    // problemTone(for problems): The color of a binding's diagnostic dot: red for real
    // errors, amber for warnings and for fields that are merely unfilled, nil when there is nothing.
    private func problemTone(for problems: [SkhdDiagnostic]) -> Tone? {
        // Unfilled fields are errors too, but the editor hints at those; only the rest turn red.
        if problems.contains(where: { $0.severity == .error && !$0.isIncomplete }) { return .negative }
        // Whatever remains is a warning or an unfinished field.
        if !problems.isEmpty { return .warning }
        return nil
    }

    /// Mirrors the model's page and selected binding as one list selection.
    private var selection: Binding<SidebarRowID?> {
        Binding(
            get: {
                switch model.page {
                case .binding:
                    guard let id = model.selectedBindingID,
                          model.visibleGroups.contains(where: { $0.bindings.contains { $0.id == id } }) else { return nil }
                    return .binding(id)
                case .modes, .blacklist, .includes, .afterSave, .source:
                    return .page(model.page)
                }
            },
            set: { row in
                switch row {
                case .binding(let id)?:
                    model.select(id)
                case .page(let page)?:
                    // The Source page refreshes its own draft on appearing, keeping unapplied edits.
                    model.page = page
                case nil:
                    break
                }
            }
        )
    }
}

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
