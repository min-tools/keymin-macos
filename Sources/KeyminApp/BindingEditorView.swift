import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The form for one binding. Most controls update the model immediately; the hex key-code
/// field waits for Return.
struct BindingEditorView: View {
    @ObservedObject var model: AppModel
    let binding: SkhdHotkey
    @StateObject private var recorder = KeyRecorder()
    @State private var showsNotes: Bool
    @State private var showsAdvancedModifiers: Bool
    /// The hex text in the key-code field; it is applied on Return, not on every keystroke.
    @State private var codeDraft: String
    /// The simple editor is the default for new bindings and for commands that only open an app.
    @State private var prefersOpenApp: Bool
    /// The last value of each action type in this editor, so switching back to a type restores
    /// what it held instead of starting over.
    @State private var actionMemory: ActionMemory

    // init(model, binding): Seed the view state from the binding: the notes and advanced
    // modifier controls open when the binding already uses them, and the binding's action is
    // remembered for its type.
    init(model: AppModel, binding: SkhdHotkey) {
        self.model = model
        self.binding = binding
        _showsNotes = State(initialValue: !binding.notes.isEmpty)
        _showsAdvancedModifiers = State(initialValue: binding.modifiers.contains { $0.side != nil || $0 == .hyper || $0 == .meh })
        // Remember the action the binding opens with, so switching away and back restores it.
        var memory = ActionMemory()
        memory.remember(binding.action)
        _actionMemory = State(initialValue: memory)
        // A plain command starts in the simple editor when it is empty or only opens an app.
        if case .command(let command) = binding.action {
            _prefersOpenApp = State(initialValue: command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || OpenAppCommand.parse(command) != nil)
        } else {
            // Per-app lists and mode switches have no simple editor.
            _prefersOpenApp = State(initialValue: false)
        }
        // Show the current key code in the hex field.
        if case .code(let code) = binding.key {
            _codeDraft = State(initialValue: SkhdKeyCodes.source(for: code))
        } else {
            // The field stays empty until a key code is chosen.
            _codeDraft = State(initialValue: "")
        }
    }

    /// The live copy of this editor's binding, found by id. Following the selection instead would
    /// let the outgoing editor, which re-renders once with the next selection before it goes away,
    /// write its fields into the newly selected binding.
    private var current: SkhdHotkey {
        model.editableHotkeys.first { $0.id == binding.id } ?? binding
    }

    // change(update): Apply a mutation to the current binding and write it back to the model.
    private func change(_ update: (inout SkhdHotkey) -> Void) {
        var updated = current
        update(&updated)
        model.update(updated)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                problems
                shortcutSection
                actionSection
                footer
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 40)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            // The shortcut as key caps.
            HStack(alignment: .center, spacing: 18) {
                ShortcutCaps(modifiers: current.modifiers, key: current.key, size: 19, spacing: 7)
                // A chip flags bindings whose keypress also reaches the app.
                if current.passthrough {
                    Chip(text: "Passes through", mono: false, tone: .accent, compact: true)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                // The name is the first comment line; a shortcut prefix in the file is preserved.
                InputField(placeholder: "Name this binding (saved as a comment)", text: Binding(
                    get: { current.title },
                    set: { title in change { $0.setTitle(title, keepPrefix: $0.titleHasShortcutPrefix) } }
                ))
                HStack(spacing: 14) {
                    Button(localized(showsNotes ? "Hide Notes" : "Add Notes")) { showsNotes.toggle() }
                        .buttonStyle(.keymin(.link, size: .small))
                        .keyboardFocusable()
                    // Explain why the comment in the file changes on its own when keys change.
                    if current.titleHasShortcutPrefix {
                        Text(localized("The comment starts with the shortcut, so it is updated when the keys change."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                // Extra comment lines above the binding, one note per line.
                if showsNotes {
                    CodeField(text: Binding(
                        get: { current.noteText },
                        set: { text in
                            change { $0.setNotes(text.isEmpty ? [] : text.components(separatedBy: "\n")) }
                        }
                    ), placeholder: localized("Extra comment lines above the binding"), minHeight: 52, maxHeight: 120)
                }
            }
        }
    }

    /// Real problems appear at the top; fields that are merely unfilled are hinted at inside the
    /// Action card instead, so switching action types never looks like a mistake.
    @ViewBuilder private var problems: some View {
        let diagnostics = model.diagnostics(for: current.id).filter { !$0.isIncomplete }
        // One card per diagnostic, styled by severity.
        if !diagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(diagnostics) { diagnostic in
                    NoticeCard(
                        tone: diagnostic.severity == .error ? .negative : .warning,
                        symbol: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                        title: diagnostic.message
                    )
                }
            }
        }
    }

    /// The unfilled fields, listed inside the Action card as a reminder that saving waits for them.
    @ViewBuilder private var unfinishedHint: some View {
        let unfinished = model.diagnostics(for: current.id).filter(\.isIncomplete)
        // Shown only while something is still missing.
        if !unfinished.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Not finished yet"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    ForEach(unfinished) { diagnostic in
                        Text(diagnostic.message)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(localized("The file can be saved once this binding is complete."))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: Shortcut

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Shortcut")
            // A recorded press replaces both the modifiers and the key; the hex field follows.
            HStack(spacing: 12) {
                RecordShortcutButton(recorder: recorder) { modifiers, key in
                    change { hotkey in
                        hotkey.modifiers = SkhdModifier.canonical(modifiers)
                        hotkey.setKey(key)
                        // Refresh only names that already carry a generated shortcut prefix.
                        if hotkey.titleHasShortcutPrefix { hotkey.setTitle(hotkey.title, keepPrefix: true) }
                    }
                    // Keep the manual hex field in step with a recorded physical key.
                    if case .code(let code) = key { codeDraft = SkhdKeyCodes.source(for: code) }
                }
                Text(localized("Press the keys you want to bind. Modifiers and the key can also be set by hand below."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            // Explain a possible intercepted press or a focus change during recording.
            if let notice = recorder.notice {
                recordingNotice(notice)
            }

            // Generic modifier chips; sides, Hyper, and Meh are behind More Options.
            VStack(alignment: .leading, spacing: 10) {
                Text(localized("Modifiers"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    ForEach(SkhdModifier.generic, id: \.self) { modifier in
                        ToggleChip(
                            text: modifier.symbol + " " + localized(modifier.title),
                            isOn: isOn(modifier),
                            help: modifier.title
                        ) { toggle(modifier) }
                    }
                    Spacer(minLength: 0)
                    Button(localized(showsAdvancedModifiers ? "Fewer Options" : "More Options")) {
                        showsAdvancedModifiers.toggle()
                    }
                    .buttonStyle(.keymin(.link, size: .small))
                    .keyboardFocusable()
                }
                // Side-specific and combined modifiers stay hidden until requested.
                if showsAdvancedModifiers { advancedModifiers }
            }

            keySection

            CheckRow(
                title: "Also send the keypress to the app",
                subtitle: "Written as “->”. The app receives the key as if skhd had not intercepted it.",
                isOn: Binding(get: { current.passthrough }, set: { value in change { $0.passthrough = value } })
            )

            // Mode membership only matters once the file declares modes or the binding names one.
            if !model.modes.isEmpty || !current.modes.isEmpty { modesSection }
        }
        .card(padding: 22)
    }

    // recordingNotice(notice): Explain a possible intercepted press or a lost-focus event.
    // Count bindings with the held modifier families; recording cannot prove skhd intercepted it.
    private func recordingNotice(_ notice: KeyRecorder.Notice) -> some View {
        let modifiers: [SkhdModifier]
        let title: String
        switch notice {
        case .intercepted(let held):
            modifiers = held
            title = localizedFormat("Only %@ reached Keymin.", held.map(\.symbol).joined())
        case .lostFocus(let held):
            modifiers = held
            title = localized("Recording stopped because another app came to the front.")
        }
        // Bindings using exactly the held set, with Hyper and Meh expanded and sides ignored.
        let symbols = modifiers.map(\.symbol).joined()
        let taken = model.document.hotkeys.filter { Set($0.modifiers.flatMap(\.expanded)) == Set(modifiers) }
        var detail = localized("A shortcut already used by skhd may not reach Keymin. Set the key below, or record a combination skhd does not use.")
        // Only count when modifiers were held; an empty set would match every unmodified binding.
        if !modifiers.isEmpty, !taken.isEmpty {
            detail += " " + (taken.count == 1
                ? localizedFormat("This file binds %@ with one key.", symbols)
                : localizedFormat("This file binds %@ with %lld keys.", symbols, Int64(taken.count)))
        }
        return NoticeCard(tone: .warning, symbol: "exclamationmark.triangle.fill", title: title, detail: detail)
    }

    // isOn(modifier): Whether the binding uses this modifier family, on either side.
    private func isOn(_ modifier: SkhdModifier) -> Bool {
        current.modifiers.contains { $0.base == modifier }
    }

    // toggle(modifier): Add or remove a modifier family and keep a shortcut-prefixed name in step.
    private func toggle(_ modifier: SkhdModifier) {
        change { hotkey in
            // Removing drops every side variant of the family.
            if hotkey.modifiers.contains(where: { $0.base == modifier }) {
                hotkey.modifiers.removeAll { $0.base == modifier }
            } else {
                // Adding uses the generic keyword; a side can then be chosen under More Options.
                hotkey.modifiers.append(modifier)
            }
            hotkey.modifiers = SkhdModifier.canonical(hotkey.modifiers)
            // User-written names stay intact; generated prefixes follow the new modifiers.
            if hotkey.titleHasShortcutPrefix { hotkey.setTitle(hotkey.title, keepPrefix: true) }
        }
    }

    private var advancedModifiers: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Hyper and Meh are single keywords that stand for a whole combination.
            HStack(spacing: 8) {
                ToggleChip(text: "✦ " + localized("Hyper"), isOn: current.modifiers.contains(.hyper), help: "Hyper: ⌃⌥⇧⌘ together") { toggle(.hyper) }
                ToggleChip(text: "◆ " + localized("Meh"), isOn: current.modifiers.contains(.meh), help: "Meh: ⌃⌥⇧ together") { toggle(.meh) }
                Text(localized("Hyper stands for ⌃⌥⇧⌘ and Meh for ⌃⌥⇧."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            let sided = current.modifiers.filter { $0.base != .fn && $0.base != .hyper && $0.base != .meh }
            // A side choice exists for the four modifiers that have left and right keys.
            if !sided.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("Which side of the keyboard counts"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(sided, id: \.self) { modifier in
                        HStack(spacing: 12) {
                            Text(localized(modifier.base.title))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 90, alignment: .leading)
                            SegmentedControl(options: ["Either", "Left", "Right"], selection: Binding(
                                get: {
                                    switch modifier.side {
                                    case nil: return 0
                                    case .left?: return 1
                                    case .right?: return 2
                                    }
                                },
                                set: { index in
                                    // Swap this keyword for the chosen side's and re-sort the list.
                                    let side: SkhdModifier.Side? = index == 1 ? .left : index == 2 ? .right : nil
                                    change { hotkey in
                                        hotkey.modifiers = SkhdModifier.canonical(hotkey.modifiers.map {
                                            $0 == modifier ? SkhdModifier.keyword(for: modifier.base, side: side) : $0
                                        })
                                        // Preserve a generated title's agreement with the shortcut.
                                        if hotkey.titleHasShortcutPrefix { hotkey.setTitle(hotkey.title, keepPrefix: true) }
                                    }
                                }
                            ))
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Key"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            // The picker sets the key; the hex field follows when a key code is picked.
            HStack(spacing: 12) {
                KeyPickerMenu(key: current.key) { key in
                    change { hotkey in
                        hotkey.setKey(key)
                        // Update the generated prefix without replacing a custom name.
                        if hotkey.titleHasShortcutPrefix { hotkey.setTitle(hotkey.title, keepPrefix: true) }
                    }
                    // A physical-key choice also supplies the manual field's hex value.
                    if case .code(let code) = key { codeDraft = SkhdKeyCodes.source(for: code) }
                }
                representationControl
                Spacer(minLength: 0)
            }
            // A key code can also be typed in hex; it is applied on Return.
            if case .code = current.key {
                HStack(spacing: 10) {
                    InputField(placeholder: "0x27", text: $codeDraft, mono: true, onSubmit: applyCodeDraft)
                        .frame(width: 110)
                    Text(localized("Apple key code in hex, such as 0x27 for the quote key. Press Return to apply."))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Text(keyExplanation)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // applyCodeDraft(): Parse the hex field, with or without a 0x prefix, into a one-byte key code.
    // Bad input beeps and leaves the text for correction.
    private func applyCodeDraft() {
        let text = codeDraft.trimmingCharacters(in: .whitespaces)
        let digits = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
        guard let value = UInt32(digits, radix: 16), value <= 0xFF else {
            NSSound.beep()
            return
        }
        // Normalize the field to skhd's spelling and store the code.
        codeDraft = SkhdKeyCodes.source(for: value)
        change { hotkey in
            hotkey.setKey(.code(value))
            // A generated title must follow the newly typed key code.
            if hotkey.titleHasShortcutPrefix { hotkey.setTitle(hotkey.title, keepPrefix: true) }
        }
    }

    /// A switch between writing the key by name and by key code.
    @ViewBuilder private var representationControl: some View {
        let key = current.key
        let canUseKeyword = key.asKeyword != nil
        let canUseCode = key.asKeyCode != nil
        // Offer the switch only when the key has both a name and a known code.
        if canUseKeyword && canUseCode {
            SegmentedControl(options: ["By name", "By key code"], selection: Binding(
                get: {
                    // Physical codes select the hex representation.
                    if case .code = key { return 1 } else {
                        // Characters and keywords both use the named representation.
                        return 0
                    }
                },
                set: { index in
                    change { hotkey in
                        // Use the US-layout code approximation; setKey also adjusts fn.
                        if index == 1, let code = hotkey.key.asKeyCode {
                            hotkey.setKey(code)
                        } else if index == 0, let keyword = hotkey.key.asKeyword {
                            // By name: a character or keyword.
                            hotkey.setKey(keyword)
                        }
                    }
                    // Seed the hex field when switching to the code form.
                    if case .code(let code)? = index == 1 ? key.asKeyCode : nil { codeDraft = SkhdKeyCodes.source(for: code) }
                }
            ))
        }
    }

    /// Explains how skhd matches the current kind of key, under the key controls.
    private var keyExplanation: String {
        switch current.key {
        case .character:
            return localized("Letters and digits follow the active keyboard layout.")
        case .literal(let keyword):
            // Media keys arrive as system events, not key codes.
            if SkhdLiteralKey.byKeyword[keyword]?.kind == .media {
                return localized("Media keys are matched by their function, not by position.")
            }
            return localized("Named keys are matched by position and are independent of the keyboard layout.")
        case .code:
            return localized("A key code names a physical key. It stays the same when the keyboard layout changes.")
        }
    }

    private var modesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Active in modes"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            // One chip per declared mode, plus chips for modes the binding names but the file
            // never declares, so those can still be switched off.
            HStack(spacing: 8) {
                ToggleChip(text: localized("default"), isOn: current.modes.isEmpty || current.modes.contains("default"), help: "Default mode") {
                    toggleMode("default")
                }
                ForEach(model.modes.map(\.name).filter { $0 != "default" }, id: \.self) { mode in
                    ToggleChip(text: mode, isOn: current.modes.contains(mode)) { toggleMode(mode) }
                }
                ForEach(current.modes.filter { $0 != "default" && !model.modes.map(\.name).contains($0) }, id: \.self) { mode in
                    ToggleChip(text: mode, isOn: true, help: "Mode is not declared") { toggleMode(mode) }
                }
            }
            Text(localized("Bindings outside the default mode only work after a binding switches skhd into that mode."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // toggleMode(mode): Add or remove a mode. An empty list stands for the default mode, and a
    // binding always keeps at least one mode.
    private func toggleMode(_ mode: String) {
        change { hotkey in
            var modes = hotkey.modes.isEmpty ? ["default"] : hotkey.modes
            // Remove the mode when it is already on; otherwise add it.
            if modes.contains(mode) {
                modes.removeAll { $0 == mode }
            } else {
                // Append so the file keeps the order the user chose.
                modes.append(mode)
            }
            // Removing the last named mode returns the binding to the default layer.
            if modes.isEmpty { modes = ["default"] }
            hotkey.modes = modes == ["default"] ? [] : modes
        }
    }

    // MARK: Action

    /// "Open an app" and "Run a command" are two views of the same command; the choice between
    /// them is the user's and is only seeded from the command when the binding opens.
    private var actionIndex: Int {
        switch current.action {
        case .command: return prefersOpenApp ? 0 : 1
        case .processMap: return 2
        case .activateMode: return 3
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Action")
            SegmentedControl(options: ["Open an app", "Run a command", "Per-app commands", "Switch mode"], selection: Binding(
                get: { actionIndex },
                set: { index in
                    guard index != actionIndex else { return }
                    // The first two segments share the command; only the editor differs.
                    prefersOpenApp = index == 0
                    // Keep what the outgoing type holds, so switching back to it restores it.
                    actionMemory.remember(current.action)
                    let memory = actionMemory
                    // A type used before in this editor gets its last value back. A type never
                    // used, or one left empty, starts from the first command instead: a new
                    // per-app list has one empty app row and an unbound wildcard, so other apps
                    // keep the key; a mode switch targets the first declared mode other than
                    // default, or default when there is none.
                    change { hotkey in
                        switch index {
                        case 0, 1:
                            hotkey.action = .command(memory.filledCommand ?? hotkey.actionSummaryCommand)
                        case 2:
                            hotkey.action = .processMap(memory.filledMappings ?? [
                                SkhdProcessMapping(process: "", command: hotkey.actionSummaryCommand),
                                SkhdProcessMapping(process: nil, command: nil),
                            ])
                        default:
                            hotkey.action = .activateMode(memory.mode ?? model.modes.first { $0.name != "default" }?.name ?? "default")
                        }
                    }
                }
            ))
            switch current.action {
            case .command(let command):
                // The user's choice between the app picker and the free-form command field.
                if actionIndex == 0 {
                    OpenAppEditorView(command: command) { updated in change { $0.action = .command(updated) } }
                } else {
                    // Free-form command.
                    commandEditor(command)
                }
            case .processMap(let mappings):
                ProcessMapEditor(mappings: mappings) { updated in change { $0.action = .processMap(updated) } }
            case .activateMode(let mode):
                activateEditor(mode)
            }
            unfinishedHint
        }
        .card(padding: 22)
    }

    // commandEditor(command): The free-form command field with a note on how skhd runs it.
    private func commandEditor(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CodeField(text: Binding(
                get: { command },
                set: { text in change { $0.action = .command(text) } }
            ), placeholder: localized("open -a Safari"), minHeight: 64)
            Text(localized("skhd runs this with “$SHELL -c”. Use line breaks to separate commands."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // activateEditor(mode): One chip per declared mode to switch into, plus the current target
    // when the file never declares it.
    private func activateEditor(_ mode: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(["default"] + model.modes.map(\.name).filter { $0 != "default" }, id: \.self) { candidate in
                    ToggleChip(text: candidate, isOn: candidate == mode) { change { $0.action = .activateMode(candidate) } }
                }
                // Keep an undeclared target visible so the user sees what the file says.
                if mode != "default", !model.modes.map(\.name).contains(mode) {
                    ToggleChip(text: mode, isOn: true, help: "Mode is not declared") {}
                }
            }
            Text(localized("Create modes on the Modes page. Give each mode a binding to switch back, such as Escape; otherwise, skhd stays in that mode until reloaded."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button(localized("Duplicate")) { model.duplicateSelected() }
                .buttonStyle(.keymin(.secondary, shortcut: "⌘D"))
                .keyboardFocusable()
            Button(localized("Copy as Text")) { model.copyToPasteboard(SkhdSerializer.hotkeyText(current)) }
                .buttonStyle(.keymin(.secondary))
                .keyboardFocusable()
            Spacer()
            Button(localized("Delete Binding")) { model.confirmDeleteSelected() }
                .buttonStyle(.keymin(.danger, shortcut: "⌘⌫"))
                .keyboardFocusable()
        }
    }
}

private extension SkhdHotkey {
    /// The first command found in the current action, reused when the action type changes.
    var actionSummaryCommand: String {
        switch action {
        case .command(let command): return command
        case .processMap(let mappings): return mappings.compactMap(\.command).first ?? ""
        case .activateMode: return ""
        }
    }
}

/// The last value the binding editor saw for each action type; a type stays nil until the binding
/// has used it in this editor.
private struct ActionMemory {
    var command: String?
    var mappings: [SkhdProcessMapping]?
    var mode: String?

    // remember(action): Store the action's value under its own type, replacing the older one.
    mutating func remember(_ action: SkhdAction) {
        switch action {
        case .command(let value): command = value
        case .processMap(let value): mappings = value
        case .activateMode(let value): mode = value
        }
    }

    /// The remembered command, or nil when there is none or it is blank, so the first command of
    /// another type can be carried over instead.
    var filledCommand: String? {
        command.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    /// The remembered per-app list, or nil when there is none or no row has an app name or a
    /// command yet, so a fresh list can carry the first command over instead.
    var filledMappings: [SkhdProcessMapping]? {
        // A row counts once it names an app or holds a command that is not blank.
        let filled = mappings?.contains { mapping in
            !(mapping.process ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                || !(mapping.command ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        return filled ? mappings : nil
    }
}

// MARK: - Key picker

/// A menu of every key skhd can name, grouped the way people look for them.
struct KeyPickerMenu: View {
    let key: SkhdKey
    let onPick: (SkhdKey) -> Void

    private static let letters = Array("abcdefghijklmnopqrstuvwxyz")
    private static let digits = Array("0123456789")

    // isFunctionKey(literal): Whether the keyword is `f1` through `f20`, which get their own
    // submenu.
    private static func isFunctionKey(_ literal: SkhdLiteralKey) -> Bool {
        literal.keyword.hasPrefix("f") && literal.keyword.dropFirst().allSatisfy(\.isNumber)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous) }

    var body: some View {
        PopUpMenuButton(accessibilityLabel: localized("Key") + ": " + key.label) {
            HStack(spacing: 8) {
                PhysicalKeyCap(text: key.capLabel, size: 12, emphasized: true)
                Text(key.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(key.source)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: Theme.controlHeight)
            .background(Theme.surfaceRaised, in: shape)
            .overlay(shape.stroke(Theme.borderStrong, lineWidth: 1))
        } entries: {
            entries
        }
    }

    /// The submenus: characters, then keywords split into named, function, and media keys, then
    /// the keys that only have a key code, and finally a way to enter any code by hand.
    private var entries: [PopUpMenuEntry] {
        [
            .submenu(localized("Letters"), Self.letters.map { letter in
                .item(String(letter).uppercased()) { onPick(.character(letter)) }
            }),
            .submenu(localized("Digits"), Self.digits.map { digit in
                .item(String(digit)) { onPick(.character(digit)) }
            }),
            .submenu(localized("Named keys"), SkhdLiteralKey.all.filter { $0.kind != .media && !Self.isFunctionKey($0) }.map { literal in
                .item(literal.title + (literal.symbol.map { "  " + $0 } ?? "")) { onPick(.literal(literal.keyword)) }
            }),
            .submenu(localized("Function keys"), SkhdLiteralKey.all.filter(Self.isFunctionKey).map { literal in
                .item(literal.title) { onPick(.literal(literal.keyword)) }
            }),
            .submenu(localized("Media keys"), SkhdLiteralKey.all.filter { $0.kind == .media }.map { literal in
                .item(literal.title) { onPick(.literal(literal.keyword)) }
            }),
            .submenu(localized("Punctuation and keypad"), SkhdKeyCodes.labels.sorted { $0.key < $1.key }.map { code, label in
                .item(label + "  " + SkhdKeyCodes.source(for: code)) { onPick(.code(code)) }
            }),
            .separator,
            // Switch to the code form, starting from the current key's code when it is known; the
            // hex field in the editor then takes the typed value. Already a code: nothing to do.
            .item(localized("Other key code…")) {
                // The existing hex field already handles this selection.
                if case .code = key { return }
                onPick(.code(key.resolvedKeyCode ?? 0x00))
            },
        ]
    }
}

// MARK: - Per-app commands

/// Rows for `[ "App" : command ]` lists, with a pick list of running apps.
struct ProcessMapEditor: View {
    let mappings: [SkhdProcessMapping]
    let onChange: ([SkhdProcessMapping]) -> Void

    /// The rows for named apps, in file order.
    private var named: [SkhdProcessMapping] { mappings.filter { !$0.isWildcard } }
    /// The `*` row; the last one counts when the file has several.
    private var wildcard: SkhdProcessMapping? { mappings.last { $0.isWildcard } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Each named row edits itself in place or removes itself from the list.
            ForEach(named) { mapping in
                ProcessMappingRow(mapping: mapping, onChange: { updated in
                    onChange(mappings.map { $0.id == updated.id ? updated : $0 })
                }, onRemove: {
                    onChange(mappings.filter { $0.id != mapping.id })
                })
            }
            // A new row goes after the last named app so the wildcard stays last.
            Button {
                var updated = mappings
                let index = updated.lastIndex(where: { !$0.isWildcard }).map { $0 + 1 } ?? 0
                updated.insert(SkhdProcessMapping(process: "", command: ""), at: index)
                onChange(updated)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(localized("Add App"))
                }
            }
            .buttonStyle(.keymin(.secondary, size: .small))
            .keyboardFocusable()

            Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 4)

            // The wildcard: switching it on appends an unbound `*` row (the key passes through);
            // switching it off drops every wildcard row.
            VStack(alignment: .leading, spacing: 8) {
                CheckRow(
                    title: "Every other app",
                    subtitle: "Written as “*”. Without it, the shortcut does nothing in apps that are not listed.",
                    isOn: Binding(
                        get: { wildcard != nil },
                        set: { enabled in
                            var updated = mappings.filter { !$0.isWildcard }
                            // An enabled wildcard starts unbound so other apps receive the key.
                            if enabled { updated.append(SkhdProcessMapping(process: nil, command: nil)) }
                            onChange(updated)
                        }
                    )
                )
                // The wildcard row has no name field; the checkbox above is what removes it.
                if let wildcard {
                    ProcessMappingRow(mapping: wildcard, onChange: { updated in
                        onChange(mappings.map { $0.id == updated.id ? updated : $0 })
                    }, onRemove: nil)
                    .padding(.leading, 30)
                }
            }
            Text(localized("skhd matches the app name as shown in the menu bar, ignoring case."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

/// One per-app row: the app name (or the wildcard label), the run-or-pass-through choice, and
/// the command field when the row runs one.
private struct ProcessMappingRow: View {
    let mapping: SkhdProcessMapping
    let onChange: (SkhdProcessMapping) -> Void
    /// Nil for the wildcard row, which has no remove button.
    let onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // The wildcard has a fixed label instead of a name field.
                if mapping.isWildcard {
                    Text(localized("Other apps"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 200, alignment: .leading)
                } else {
                    // Named apps get a text field plus a pick list of running apps.
                    InputField(placeholder: "App name", text: Binding(
                        get: { mapping.process ?? "" },
                        set: { name in var updated = mapping; updated.process = name; onChange(updated) }
                    ))
                    .frame(width: 200)
                    AppNameMenu { name in
                        var updated = mapping
                        updated.process = name
                        onChange(updated)
                    }
                }
                // Pass through stores no command, written as `~`; switching back starts empty.
                SegmentedControl(options: ["Run command", "Pass through"], selection: Binding(
                    get: { mapping.isUnbound ? 1 : 0 },
                    set: { index in
                        var updated = mapping
                        updated.command = index == 1 ? nil : (mapping.command ?? "")
                        onChange(updated)
                    }
                ))
                Spacer(minLength: 0)
                // Only named rows can be removed here.
                if let onRemove {
                    IconButton(symbol: "minus", help: "Remove app", action: onRemove)
                }
            }
            // The command field exists only while the row runs a command.
            if let command = mapping.command {
                CodeField(text: Binding(
                    get: { command },
                    set: { text in var updated = mapping; updated.command = text; onChange(updated) }
                ), placeholder: localized("Command for this app"), minHeight: 44, maxHeight: 160)
            }
        }
        .padding(12)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// A compact pick list of running apps by display name, with an Open panel for any other app
/// bundle. Used wherever skhd wants an app's name: per-app lists and the blacklist.
struct AppNameMenu: View {
    /// Receives the app's display name, as shown in the menu bar.
    let onPick: (String) -> Void

    /// The button is square, matching the small control height.
    private let side = Theme.smallControlHeight + 2

    var body: some View {
        PopUpMenuButton(accessibilityLabel: localized("Pick an app")) {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: side, height: side)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
        } entries: {
            var entries: [PopUpMenuEntry] = [.header(localized("Running apps"))]
            for application in AppResolver.runningApplications() {
                entries.append(.item(application.name, image: AppChooserMenu.menuIcon(application.icon)) { onPick(application.name) })
            }
            entries.append(.separator)
            entries.append(.item(localized("Choose Application…")) { chooseApplication() })
            return entries
        }
        .help(localized("Pick an app"))
    }

    // chooseApplication(): Open a panel for any app bundle and report its display name the way
    // the menu bar shows it, which is what skhd compares.
    private func chooseApplication() {
        // An Open panel limited to app bundles, starting in the Applications folder.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = localized("Choose an app to fill in its name.")
        panel.prompt = localized("Choose")
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            // Prefer the localized display name, then the bundle name, then the file name.
            let bundle = Bundle(url: url)
            let name = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle?.localizedInfoDictionary?["CFBundleName"] as? String)
                ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            onPick(name)
        }
        // Attach the panel to the key window as a sheet when there is one.
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            // No key window: run the panel as a standalone modal.
            handler(panel.runModal())
        }
    }
}

private extension SkhdHotkey {
    /// Whether the command only opens an app, which the simple editor can show.
    var opensApp: Bool {
        // Only a plain command can be represented by the simple app picker.
        if case .command(let command) = action { return OpenAppCommand.parse(command) != nil }
        return false
    }
}
