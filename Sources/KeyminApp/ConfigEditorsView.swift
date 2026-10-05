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

// MARK: - Blacklist

/// The Blacklist page: one row per app name, each with a picker of running apps.
struct BlacklistEditorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PageFrame(
            symbol: "hand.raised",
            title: "Blacklist",
            summary: "skhd ignores every keypress while one of these apps is in front. Use it for terminals, virtual machines, and remote desktops that need the raw keys."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // Rows are keyed by position: names are plain strings that may repeat or be empty.
                // A row's position can outlive a reload that shortens the list, for example while
                // the Choose Application panel is open, so every write checks it first.
                ForEach(Array(model.blacklist.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 10) {
                        InputField(placeholder: "App name", text: Binding(
                            get: { name },
                            set: { updated in
                                var list = model.blacklist
                                guard list.indices.contains(index) else { return }
                                list[index] = updated
                                model.setBlacklist(list)
                            }
                        ))
                        .frame(width: 320)
                        AppNameMenu { picked in
                            var list = model.blacklist
                            guard list.indices.contains(index) else { return }
                            list[index] = picked
                            model.setBlacklist(list)
                        }
                        Spacer()
                        IconButton(symbol: "minus", help: "Remove app") {
                            var list = model.blacklist
                            guard list.indices.contains(index) else { return }
                            list.remove(at: index)
                            model.setBlacklist(list)
                        }
                    }
                }
                // Empty state where the rows would be.
                if model.blacklist.isEmpty {
                    Text(localized("No apps are blacklisted."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                // A new row starts empty for the user to type or pick a name.
                Button {
                    model.setBlacklist(model.blacklist + [""])
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text(localized("Add App"))
                    }
                }
                .buttonStyle(.keymin(.secondary, size: .small))
                .keyboardFocusable()
                .padding(.top, 4)
            }
            .card(padding: 20)
            Text(localized("Written as “.blacklist [ … ]”. skhd matches each name as shown in the menu bar, ignoring case."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Included files

/// The Included Files page: one row per .load directive, with an Open panel to pick a file.
struct IncludesEditorView: View {
    @ObservedObject var model: AppModel
    /// The path in the row that Add Path opens, or nil while that row is closed. The model
    /// refuses empty paths, so the row joins the file only once its path is added.
    @State private var newPath: String?
    /// The path the model last refused for the new row. Its reason shows under the row while
    /// the row still holds that path.
    @State private var refusedNewPath: String?

    var body: some View {
        PageFrame(
            symbol: "doc.on.doc",
            title: "Included Files",
            summary: "skhd also reads these files, so a long configuration can be split into parts. Relative paths are resolved from the folder of the main file."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // One row per directive, keyed by its ID so the row's own path draft follows it.
                ForEach(model.includes) { directive in
                    IncludeRow(model: model, directive: directive, choose: choose)
                }
                // The row for a path that is not in the file yet.
                if newPath != nil {
                    newPathRow
                }
                // Empty state where the rows would be.
                if model.includes.isEmpty && newPath == nil {
                    Text(localized("No files are included."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                // Add Path opens an empty row to type into; Add File picks one in the Open panel.
                HStack(spacing: 10) {
                    Button {
                        // An open new row keeps what was typed into it.
                        if newPath == nil { newPath = "" }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text(localized("Add Path"))
                        }
                    }
                    .buttonStyle(.keymin(.secondary, size: .small))
                    .keyboardFocusable()
                    Button(localized("Add File")) { choose { addPath($0, fromNewRow: false) } }
                        .buttonStyle(.keymin(.secondary, size: .small))
                        .keyboardFocusable()
                }
                .padding(.top, 4)
            }
            .card(padding: 20)
            Text(localized("Written as “.load \"file\"”. Keymin edits only the main file; included files are not opened here."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    /// The new row: the path field, an Open panel, Add, and a button that closes the row. Return
    /// in the field adds the path as well.
    private var newPathRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                InputField(placeholder: "path/to/file", text: Binding(
                    get: { newPath ?? "" },
                    set: { newPath = $0 }
                ), mono: true, onSubmit: { addPath(newPath ?? "", fromNewRow: true) })
                Button(localized("Choose")) { choose { addPath($0, fromNewRow: true) } }
                    .buttonStyle(.keymin(.secondary, size: .small))
                    .keyboardFocusable()
                Button(localized("Add")) { addPath(newPath ?? "", fromNewRow: true) }
                    .buttonStyle(.keymin(.primary, size: .small))
                    .keyboardFocusable()
                IconButton(symbol: "minus", help: "Remove file") {
                    newPath = nil
                    refusedNewPath = nil
                }
            }
            // A refused path explains itself until the row holds another one.
            if let refusedNewPath, refusedNewPath == newPath, let problem = model.includeProblem(for: refusedNewPath) {
                FieldProblem(message: problem)
            }
        }
    }

    // addPath(path, fromNewRow): Add a typed or chosen path as a new directive; a path from the
    // new row closes that row. A path the model refuses goes into the new row, opening it when
    // needed, with the reason under it.
    private func addPath(_ path: String, fromNewRow: Bool) {
        // Refused: keep the path in the new row so the user can see and correct it.
        if model.includeProblem(for: path) != nil {
            newPath = path
            refusedNewPath = path
            NSSound.beep()
            return
        }
        model.addInclude(path)
        // Only the new row's own path closes it; Add File leaves a half-typed row alone.
        if fromNewRow {
            newPath = nil
            refusedNewPath = nil
        }
    }

    // choose(completion): Show an Open panel for a file skhd should also read and pass its path
    // to completion. Only the path is used; skhd reads the file, not Keymin.
    private func choose(_ completion: @escaping (String) -> Void) {
        // Files only, hidden ones included, starting in the main file's folder because relative
        // paths resolve from there.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = model.store.location?.resolvedURL.deletingLastPathComponent() ?? ConfigStore.defaultDirectory
        panel.message = localized("Choose a file skhd should also read.")
        panel.prompt = localized("Choose")
        // Both ways of running the panel share one result handler.
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url.path)
        }
        // Attach the panel to the key window as a sheet when there is one.
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            // No key window, so run the panel on its own.
            handler(panel.runModal())
        }
    }
}

/// One .load directive: the path field, an Open panel, and removal. The field holds its own draft,
/// which changes the file only when Return, Apply, or Choose commits it, so a half-typed path
/// never reaches the file. A path the model refuses stays visible with the reason under it, while
/// the file keeps its current path.
private struct IncludeRow: View {
    @ObservedObject var model: AppModel
    let directive: SkhdLoadDirective
    /// Shows the Open panel and passes the chosen path to its completion.
    let choose: (@escaping (String) -> Void) -> Void
    /// The path in the field, seeded from the directive.
    @State private var draft: String

    // init(model, directive, choose): Seed the draft from the directive's path.
    init(model: AppModel, directive: SkhdLoadDirective, choose: @escaping (@escaping (String) -> Void) -> Void) {
        self.model = model
        self.directive = directive
        self.choose = choose
        _draft = State(initialValue: directive.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                InputField(placeholder: "path/to/file", text: $draft, mono: true, onSubmit: { commit(draft) })
                Button(localized("Choose")) { choose { commit($0) } }
                    .buttonStyle(.keymin(.secondary, size: .small))
                    .keyboardFocusable()
                IconButton(symbol: "minus", help: "Remove file") { model.removeInclude(directive.id) }
            }
            // The model's reason for refusing the path in the field, which also flags a path
            // the file already had.
            if let problem = model.includeProblem(for: draft) {
                FieldProblem(message: problem)
            }
            // A typed path waits for an explicit step, like a mode's new name.
            if draft != directive.path {
                HStack(spacing: 10) {
                    Button(localized("Apply")) { commit(draft) }
                        .buttonStyle(.keymin(.primary, size: .small))
                        .keyboardFocusable()
                    Text(localizedFormat("The file keeps “%@” until you apply the new path.", directive.path))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    // commit(path): Show a typed or chosen path in the field and pass it to the model, which
    // applies it only when it accepts it. A refused path beeps and stays in the field with its
    // reason.
    private func commit(_ path: String) {
        draft = path
        // The model's reason is already shown under the field.
        if model.includeProblem(for: path) != nil {
            NSSound.beep()
            return
        }
        model.updateInclude(directive.id, path: path)
    }
}

// MARK: - Source

/// The Source page: the file text in a code editor, applied back to the document on demand.
struct SourceEditorView: View {
    @ObservedObject var model: AppModel

    /// Whether the editor holds edits that have not been applied yet.
    private var draftDiffers: Bool { model.hasUnappliedSourceEdits }

    var body: some View {
        // The source shows every binding, so it belongs to Pro once the trial has ended.
        if model.isLimitedToFreeBindings {
            VStack(spacing: 16) {
                IconTile(symbol: "lock.fill", size: 64, tint: Theme.warning)
                Text(localized("The Source page needs Keymin Pro"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(localizedFormat("Source editing gives access to the whole file. Without Pro, use the forms to edit the first %lld bindings. Hidden bindings stay in the file.", Int64(KeyminFreeAccessPolicy.freeBindingLimit)))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button(localized("Keymin Pro")) { model.presentPro(for: .sourceEditing) }
                    .buttonStyle(.keymin(.primary))
                    .keyboardFocusable()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Full access: the editor itself.
            editor
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            // Toolbar: heading, the last parse error, and the Discard and Apply buttons.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Source"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(localized("The exact text Keymin writes. Edit it here for anything the forms cannot express, then apply it."))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                // The error from the last Apply. A clean Apply or any draft refresh, such as
                // Discard Edits, clears it.
                if let error = model.sourceDraftError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                        .lineLimit(2)
                        .frame(maxWidth: 320, alignment: .trailing)
                }
                Button(localized("Discard Edits")) { model.refreshSourceDraft() }
                    .buttonStyle(.keymin(.secondary))
                    .keyboardFocusable()
                    .disabled(!draftDiffers)
                Button(localized("Apply")) { model.applySourceDraft() }
                    .buttonStyle(.keymin(.primary))
                    .keyboardFocusable()
                    .disabled(!draftDiffers)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Rectangle().fill(Theme.border).frame(height: 1)
            // The editor binds straight to the draft. Apply, Save, leaving the page, or any other
            // change to the document applies unapplied text; without any, the draft follows the
            // document.
            CodeTextView(text: $model.sourceDraft, placeholder: localized("# Empty configuration"), minHeight: 200, fontSize: 12.5, highlightsSkhd: true, showsLineNumbers: true)
                .background(Theme.surfaceSunken)
        }
        .onAppear {
            // Refresh a clean draft; keep unapplied text across page appearances.
            if !draftDiffers { model.refreshSourceDraft() }
        }
    }
}
