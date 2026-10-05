import AppKit
import SwiftUI

/// The shared page layout: an icon, a title, and a summary above the page's own content.
private struct PageFrame<Content: View>: View {
    let symbol: String
    let title: String
    let summary: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Icon, title and summary, then the page's own content below.
                HStack(spacing: 18) {
                    IconTile(symbol: symbol, size: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localized(title))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(localized(summary))
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content()
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 40)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

// MARK: - Modes

/// The Modes page: one card per declared mode and a button to add another.
struct ModesEditorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PageFrame(
            symbol: "square.stack.3d.up",
            title: "Modes",
            summary: "Modes group shortcuts into layers. Switching modes activates that layer's bindings."
        ) {
            // Explain what a mode is while there is none to show.
            if model.modes.isEmpty {
                NoticeCard(
                    tone: .neutral,
                    symbol: "info.circle",
                    title: localized("No modes are declared."),
                    detail: localized("Add a mode for another layer of shortcuts, such as a resize mode that you enter with a hotkey and leave with Escape.")
                )
            }
            // Cards are keyed by declaration ID so a card's name draft follows its mode.
            ForEach(model.modes) { mode in
                ModeCard(model: model, mode: mode)
                    .id(mode.id)
            }
            // Adds a declaration named modeN, with the next free number, after the existing
            // declarations or, when there are none, above the first binding.
            Button {
                model.addMode()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(localized("Add Mode"))
                }
            }
            .buttonStyle(.keymin(.secondary))
            .keyboardFocusable()
            Text(localized("Modes are written as “:: name” and must appear before the bindings that use them. Keymin adds a new declaration after the existing ones, or above the first binding."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One mode's card: the name with an explicit Rename step, its binding count, the capture
/// switch, the entry command, and any problems with the declaration.
private struct ModeCard: View {
    @ObservedObject var model: AppModel
    /// The declaration as passed in; `current` is the live one.
    let mode: SkhdModeDeclaration
    /// The name field's text. Typing changes nothing until Rename or Return confirms it.
    @State private var nameDraft: String
    /// The trimmed name the model last refused. Its reason shows under the field while the draft
    /// still holds that name.
    @State private var refusedName: String?

    // init(model, mode): Seed the name draft from the declaration.
    init(model: AppModel, mode: SkhdModeDeclaration) {
        self.model = model
        self.mode = mode
        _nameDraft = State(initialValue: mode.name)
    }

    /// The declaration as the model has it now, or the passed-in copy once it was removed.
    private var current: SkhdModeDeclaration {
        model.modes.first { $0.id == mode.id } ?? mode
    }

    /// The draft without surrounding spaces, which is the name a rename would use.
    private var trimmedDraft: String {
        nameDraft.trimmingCharacters(in: .whitespaces)
    }

    /// Why the model refused the name in the field, or nil while the draft holds another name.
    private var renameProblem: String? {
        guard let refusedName, refusedName == trimmedDraft else { return nil }
        return model.renameProblem(for: current.id, to: refusedName)
    }

    /// Bindings in this mode. Bindings without a mode belong to the default mode.
    private var bindingCount: Int {
        model.document.hotkeys.filter { $0.modes.contains(current.name) || (current.name == "default" && $0.modes.isEmpty) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                InputField(placeholder: "Mode name", text: $nameDraft, mono: true, onSubmit: commitName)
                    .frame(width: 220)
                Chip(text: bindingCountText(bindingCount), mono: false, compact: true)
                Spacer()
                IconButton(symbol: "trash", help: "Remove mode", variant: .danger) { model.removeMode(current.id) }
            }
            // A refused rename explains itself under the name field.
            if let renameProblem {
                FieldProblem(message: renameProblem)
            }
            // Renaming is a deliberate step because it rewrites every binding that uses the mode.
            // Surrounding spaces are not part of the name, so they alone do not offer it.
            if trimmedDraft != current.name {
                HStack(spacing: 10) {
                    Button(localized("Rename")) { commitName() }
                        .buttonStyle(.keymin(.primary, size: .small))
                        .keyboardFocusable()
                    Text(localized("Bindings in this mode and bindings that switch to it are updated too."))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            // The capture flag, written as @ after the name.
            CheckRow(
                title: "Capture every keypress while active",
                subtitle: "Written as “@”. Keys without a binding in this mode are swallowed instead of reaching the app.",
                isOn: Binding(get: { current.capture }, set: { value in var updated = current; updated.capture = value; model.update(updated) })
            )
            // The optional entry command; clearing the field removes it from the declaration.
            VStack(alignment: .leading, spacing: 8) {
                Text(localized("Command to run when the mode is entered"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                CodeField(text: Binding(
                    get: { current.command ?? "" },
                    set: { text in
                        var updated = current
                        updated.command = text.isEmpty ? nil : text
                        model.update(updated)
                    }
                ), placeholder: localized("Optional, for example a notification"), minHeight: 44, maxHeight: 120)
            }
            // Problems with this declaration: an invalid name or a duplicate.
            let problems = model.diagnostics(for: current.id)
            ForEach(problems) { diagnostic in
                NoticeCard(tone: .negative, symbol: "xmark.octagon.fill", title: diagnostic.message)
            }
        }
        .card(padding: 20)
    }

    // commitName(): Rename the mode to the trimmed draft when the model accepts the name, then
    // show the name as stored. A refused name beeps, keeps the draft, and shows the model's
    // reason under the field.
    private func commitName() {
        let name = trimmedDraft
        // The model decides which names are valid and free; its reason stays visible.
        if model.renameProblem(for: current.id, to: name) != nil {
            refusedName = name
            NSSound.beep()
            return
        }
        refusedName = nil
        model.renameMode(current.id, to: name)
        // Drop surrounding spaces from the field once the mode carries the name.
        if current.name == name { nameDraft = name }
    }
}

/// The reason a typed name or path was refused, in red under its field.
private struct FieldProblem: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.danger)
    }
}
