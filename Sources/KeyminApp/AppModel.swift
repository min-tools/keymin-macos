import AppKit
import Combine
import Foundation

/// Bindings that share a mode, shown as one sidebar section.
struct BindingGroup: Identifiable {
    let mode: String
    let bindings: [SkhdHotkey]
    var id: String { mode }
}

/// The editor's state and actions: the parsed document, the file's status, the selection, and
/// everything the views and menus call. The app delegate owns the one instance.
@MainActor
final class AppModel: ObservableObject {
    /// What the content area shows.
    enum Page: Hashable {
        case binding, modes, blacklist, includes, afterSave, source
    }

    /// Whether a configuration is open and, when it is not, why.
    enum FileState: Equatable {
        /// No file has been chosen.
        case none
        /// The chosen file is a symbolic link, and macOS has not granted access to its target yet.
        case needsTargetAccess
        case loaded
        /// The file could not be read; the message is shown on the welcome screen.
        case failed(String)
    }

    let store = ConfigStore()
    let afterSave = AfterSavePreferences()
    private let proStore = KeyminProStore.shared
    /// Forwards Pro store changes so views observing the model redraw.
    private var accessSubscription: AnyCancellable?

    /// The parsed configuration. A Source draft without unapplied edits follows every change, so
    /// the Source page never shows an older document that later typing would bring back.
    @Published private(set) var document = SkhdDocument() {
        didSet {
            // Only a draft without unapplied edits follows. applySourceDraft() sets the document
            // while its draft still differs from the base, so typed text is never replaced here.
            // The error from the last Apply stays.
            if sourceDraft == sourceDraftBase {
                sourceDraft = serializedText
                sourceDraftBase = sourceDraft
            }
        }
    }
    /// The text as it was last read from or written to disk.
    @Published private(set) var loadedText: String?
    @Published private(set) var fileState: FileState = .none
    @Published var selectedBindingID: UUID?
    /// The page the content area shows. Leaving the Source page applies its unapplied text, so
    /// edits made on other pages build on it instead of being replaced by it later.
    @Published var page: Page = .binding {
        didSet {
            // Only a move away from the Source page commits the draft.
            if oldValue == .source, page != .source { commitSourceDraftIfNeeded() }
        }
    }
    @Published var sidebarQuery = ""
    /// True when the file changed on disk during unsaved edits; a banner then offers to reload.
    @Published private(set) var externalChangePending = false
    /// Why the last save failed, shown in the header until the next load or successful save.
    @Published var saveError: String?
    @Published private(set) var lastSavedAt: Date?
    /// True for eight seconds after a save, so the status pill can say what followed it.
    @Published private(set) var savedRecently = false
    private var savedRecentlyTask: Task<Void, Never>?
    /// The Source page's text. It replaces the document when the user applies it, saves, leaves
    /// the Source page, or makes any other change to the document. Without unapplied edits it
    /// follows the document.
    @Published var sourceDraft = ""
    /// The parse error for the first line of the draft that could not be read, or nil.
    @Published var sourceDraftError: String?
    /// The document's text as of the last load or save; nil without a loaded file.
    private var baselineText: String?
    /// The draft as it was last taken from the document or applied to it. The draft holds
    /// unapplied edits only while it differs from this.
    private var sourceDraftBase = ""
    /// The errors the document had at the last load or save on bindings and unreadable lines,
    /// counted by errorKey(_:in:). Under the Free limit only these may stay without blocking a
    /// save; an error the user's later edits cause on a hidden binding still blocks it.
    private var preexistingErrors: [String: Int] = [:]

    // init(): Connect the store callbacks and Pro store updates, then restore the saved file and
    // load it.
    init() {
        store.onExternalChange = { [weak self] in self?.handleExternalChange() }
        store.onLocationChange = { [weak self] in self?.load() }
        // Trial expiry, purchases, and restores change which bindings are shown.
        accessSubscription = proStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        store.restore()
        load()
    }

    // MARK: Derived state

    var hasConfiguration: Bool { fileState == .loaded }
    var serializedText: String { SkhdSerializer.serialize(document) }
    /// True when the document no longer matches what was last loaded or saved. The comparison
    /// uses the text Keymin would write for that file, so a file it would only tidy (trailing
    /// blank lines, a missing final newline) does not look changed on opening. Carriage returns
    /// that end a line are the exception: skhd passes them into commands, so a file with them
    /// stays unsaved until Save writes it without them.
    var isDirty: Bool {
        // An unopened or unreadable file has no saved document to compare.
        guard let baselineText else { return false }
        let text = serializedText
        // Any edit since the last load or save.
        if text != baselineText { return true }
        // No edit, but the file on disk still has line ends with carriage returns that Save would
        // remove, before a line feed or at the very end.
        return loadedText.map { ($0.contains("\r\n") || $0.hasSuffix("\r")) && $0 != text } ?? false
    }
    /// True while the Source page holds typed text that has not been applied to the document.
    /// Never true while the Free limit locks the Source page: a draft typed before the limit
    /// began is then ignored, neither applied nor asked about.
    var hasUnappliedSourceEdits: Bool {
        hasConfiguration && !isLimitedToFreeBindings && sourceDraft != sourceDraftBase
    }
    /// True when quitting, reloading, or switching files would lose work.
    var hasUnsavedChanges: Bool { isDirty || hasUnappliedSourceEdits }
    /// The document's problems, led by an error for each .load of the configuration itself.
    var diagnostics: [SkhdDiagnostic] { diagnostics(of: document) }
    /// The errors that keep the document from being saved.
    var blockingErrors: [SkhdDiagnostic] { blockingErrors(in: document, limited: isLimitedToFreeBindings) }

    // diagnostics(of document): The document's own diagnostics, preceded by an error for each .load
    // directive that leads back to the configuration file, which skhd would load until it fails.
    // Those errors go first, keeping the list's errors-before-warnings order.
    private func diagnostics(of document: SkhdDocument) -> [SkhdDiagnostic] {
        let selfLoads = document.loadDirectives.filter { loadsConfigurationItself($0.path) }.map {
            SkhdDiagnostic(severity: .error, message: Self.selfLoadMessage, itemID: $0.id)
        }
        return selfLoads + document.diagnostics()
    }

    // blockingErrors(in document, limited): The errors that keep the document from being saved.
    // While limited to the Free bindings, an error on a hidden binding or on a line skhd cannot
    // read is left out when the file already had it at the last load or save: Free users cannot
    // see or fix those statements, which are written back as they are. An error that the user's
    // own edits cause there, such as removing a mode a hidden binding uses, still blocks saving,
    // because skhd would then reject the whole file.
    func blockingErrors(in document: SkhdDocument, limited: Bool) -> [SkhdDiagnostic] {
        let errors = diagnostics(of: document).filter { $0.severity == .error }
        // With full access every error counts.
        guard limited else { return errors }
        // Bindings past the Free limit and unreadable raw lines are out of the user's reach.
        let visible = Set(KeyminFreeAccessPolicy.editableBindings(document.hotkeys, limited: true).map(\.id))
        let unreachable = Set(document.hotkeys.map(\.id)).subtracting(visible).union(document.rawItems.map(\.id))
        // Each error the file already had excuses one current error with the same key.
        var allowance = preexistingErrors
        return errors.filter { error in
            // Errors on no item or a reachable one, and new errors, still block saving.
            guard let itemID = error.itemID, unreachable.contains(itemID),
                  let key = errorKey(error, in: document), let count = allowance[key], count > 0 else { return true }
            // A known error is used up and left out.
            allowance[key] = count - 1
            return false
        }
    }

    // errorKey(error, in document): The error's message with the text of the binding or raw line
    // it belongs to. Unlike item ids, the key survives reading the file again. Nil for an error on
    // any other item.
    private func errorKey(_ error: SkhdDiagnostic, in document: SkhdDocument) -> String? {
        // File-level errors and items removed by an edit cannot use an allowance.
        guard let itemID = error.itemID, let index = document.index(of: itemID) else { return nil }
        switch document.items[index] {
        case .hotkey(let hotkey): return (hotkey.sourceText ?? SkhdSerializer.hotkeyText(hotkey)) + "\u{0}" + error.message
        case .raw(let raw): return raw.text + "\u{0}" + error.message
        default: return nil
        }
    }

    // recordPreexistingErrors(): Remember the errors on bindings and raw lines the document has at
    // a load or save, so the Free limit can tell them from errors caused by later edits.
    private func recordPreexistingErrors() {
        var counts: [String: Int] = [:]
        for error in diagnostics where error.severity == .error {
            // Errors on other items have no key and always block.
            if let key = errorKey(error, in: document) { counts[key, default: 0] += 1 }
        }
        preexistingErrors = counts
    }

    /// True once the trial ended without Pro: only the first few bindings are shown and editable.
    var isLimitedToFreeBindings: Bool { proStore.isLimitedToFreeBindings }

    /// Bindings available in the editor. Hidden ones remain in the saved document;
    /// mode renames still update their references.
    var editableHotkeys: [SkhdHotkey] {
        KeyminFreeAccessPolicy.editableBindings(document.hotkeys, limited: isLimitedToFreeBindings)
    }

    var hiddenBindingCount: Int {
        KeyminFreeAccessPolicy.hiddenBindingCount(total: document.hotkeys.count, limited: isLimitedToFreeBindings)
    }

    var canAddBinding: Bool {
        KeyminFreeAccessPolicy.canAddBinding(total: document.hotkeys.count, limited: isLimitedToFreeBindings)
    }

    var selectedBinding: SkhdHotkey? {
        guard let selectedBindingID else { return nil }
        return editableHotkeys.first { $0.id == selectedBindingID }
    }

    // presentPro(for feature): Explain the requested feature in the Pro panel.
    func presentPro(for feature: KeyminProFeature) {
        proStore.present(feature: feature)
    }

    // diagnostics(for id): Return the diagnostics attached to this document item.
    func diagnostics(for id: UUID) -> [SkhdDiagnostic] {
        diagnostics.filter { $0.itemID == id }
    }

    /// Bindings grouped by mode, filtered by the sidebar search.
    var visibleGroups: [BindingGroup] {
        let needle = sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let editable = editableHotkeys
        let visible = needle.isEmpty ? editable : editable.filter { matches($0, needle) }
        // A binding listed under several modes appears in each of them; bindings without a mode
        // belong to `default`.
        var order: [String] = []
        var grouped: [String: [SkhdHotkey]] = [:]
        for hotkey in visible {
            let modes = hotkey.modes.isEmpty ? ["default"] : hotkey.modes
            for mode in modes {
                // Remember each mode the first time it appears so groups keep file order.
                if grouped[mode] == nil { order.append(mode) }
                grouped[mode, default: []].append(hotkey)
            }
        }
        // The default mode comes first; other modes keep the order in which they first appear.
        let sorted = order.sorted { lhs, rhs in
            // `default` goes first.
            if lhs == "default" { return true }
            // Nothing goes before `default`.
            if rhs == "default" { return false }
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
        return sorted.map { BindingGroup(mode: $0, bindings: grouped[$0] ?? []) }
    }

    // matches(hotkey, needle): Whether the search text appears in the binding's title, action,
    // shortcut, keysym text, key, modes, or comments, ignoring case.
    private func matches(_ hotkey: SkhdHotkey, _ needle: String) -> Bool {
        let haystack = [
            hotkey.title, hotkey.actionSummary, hotkey.shortcutSymbols,
            SkhdSerializer.keysymText(hotkey), hotkey.key.label, hotkey.modes.joined(separator: " "),
        ] + hotkey.comment
        return haystack.contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    // MARK: File lifecycle

    // load(): Read the file and replace the document, or record why it could not be read.
    func load() {
        // No file chosen: clear the document and selection so the welcome screen shows.
        guard store.location != nil else {
            clearDocument()
            fileState = .none
            return
        }
        do {
            let text = try store.read()
            apply(text: text)
            fileState = .loaded
        } catch let error as ConfigStoreError where error.kind == .needsTargetAccess {
            // A link whose target was not granted gets its own screen with a Grant Access button.
            clearDocument()
            fileState = .needsTargetAccess
        } catch {
            // The previous file's document must not linger as unsaved work for a file that failed.
            clearDocument()
            fileState = .failed(error.localizedDescription)
        }
        // A fresh load supersedes any pending external change and any earlier save error.
        externalChangePending = false
        saveError = nil
    }

    // apply(text): Parse the text into the document, make it the new baseline, and keep the same
    // binding selected when it still exists.
    private func apply(text: String) {
        // Parsing assigns new ids, so the selection is remembered by its keysym text.
        let previous = selectedBinding.map { SkhdSerializer.keysymText($0) }
        document = SkhdParser.parse(text)
        loadedText = text
        // The baseline and the Source page show the text Keymin would write for this file.
        baselineText = serializedText
        sourceDraft = serializedText
        sourceDraftBase = sourceDraft
        sourceDraftError = nil
        recordPreexistingErrors()
        // Reselect the binding with the same shortcut when it survived the reload.
        if let previous, let match = editableHotkeys.first(where: { SkhdSerializer.keysymText($0) == previous }) {
            selectedBindingID = match.id
        } else if page == .binding {
            // The Bindings page should not be left empty: fall back to the first visible binding.
            selectedBindingID = editableHotkeys.first?.id
        } else {
            // Other pages have no binding editor, so nothing is selected.
            selectedBindingID = nil
        }
    }

    // clearDocument(): Drop the document, its baseline, the Source draft, and the selection.
    private func clearDocument() {
        document = SkhdDocument()
        loadedText = nil
        baselineText = nil
        sourceDraft = ""
        sourceDraftBase = ""
        sourceDraftError = nil
        preexistingErrors = [:]
        selectedBindingID = nil
    }

    // reload(): Discard unsaved edits and read the file again.
    func reload() {
        load()
    }

    // resolveUnsavedChanges(discardTitle, consequence): Ask what to do with unsaved work before it
    // would be lost, and return true when it is safe to go on: nothing was unsaved, the save
    // succeeded, or the user chose to discard. Save is offered only when it could succeed.
    func resolveUnsavedChanges(discardTitle: String, consequence: String) -> Bool {
        // Continue without a prompt when neither the document nor its draft changed.
        guard hasUnsavedChanges else { return true }
        // Unapplied Source text is what Save would write, so its problems count too.
        let pending = hasUnappliedSourceEdits
            ? blockingErrors(in: SkhdParser.parse(sourceDraft), limited: isLimitedToFreeBindings)
            : blockingErrors
        let canSave = pending.isEmpty
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localized("Save changes to the skhd configuration?")
        alert.informativeText = canSave
            ? consequence
            : localized("The configuration still has problems skhd would reject, so it cannot be saved yet.")
        // Offer Save only when a save could succeed.
        if canSave {
            alert.addButton(withTitle: localized("Save"))
        }
        alert.addButton(withTitle: discardTitle)
        alert.addButton(withTitle: localized("Cancel"))
        let response = alert.runModal()
        // Three buttons: Save, discard, Cancel. A failed save keeps the current state.
        if canSave {
            switch response {
            case .alertFirstButtonReturn:
                save()
                return saveError == nil
            case .alertSecondButtonReturn: return true
            default: return false
            }
        }
        // Two buttons: discard, Cancel.
        return response == .alertFirstButtonReturn
    }

    // confirmReload(): Reload from disk, asking first when edits would be lost.
    func confirmReload() {
        // With no edits to discard, reload without asking.
        guard hasUnsavedChanges else {
            reload()
            return
        }
        let alert = NSAlert()
        alert.messageText = localized("Discard unsaved changes?")
        alert.informativeText = localized("The configuration is read again from disk and your edits are lost.")
        alert.addButton(withTitle: localized("Discard Changes"))
        alert.addButton(withTitle: localized("Cancel"))
        // Discard Changes is the first button.
        if alert.runModal() == .alertFirstButtonReturn { reload() }
    }

    // save(): Write the document to disk, unless it still has a problem skhd would reject.
    func save() {
        // The welcome and error screens have no writable document.
        guard hasConfiguration else { return }
        // Typed Source text is what the user sees, so it goes into the document before saving.
        commitSourceDraftIfNeeded()
        // Blocking problems are reported in the header instead of being written out.
        let errors = blockingErrors
        guard errors.isEmpty else {
            saveError = errors.count == 1
                ? errors[0].message
                : localizedFormat("Fix %lld problems before saving.", Int64(errors.count))
            return
        }
        // Serialize the whole document, including bindings hidden by the Free limit.
        let text = serializedText
        do {
            try store.write(text)
            // The written text is the new baseline: the document is clean again, and a change
            // noticed on disk before the save has now been overwritten.
            loadedText = text
            baselineText = text
            sourceDraft = text
            sourceDraftBase = text
            recordPreexistingErrors()
            lastSavedAt = Date()
            saveError = nil
            externalChangePending = false
            // Show the saved status for eight seconds, restarting the timer on every save.
            savedRecently = true
            savedRecentlyTask?.cancel()
            savedRecentlyTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                // An older timer must not clear the status of a newer save.
                guard !Task.isCancelled else { return }
                self?.savedRecently = false
            }
            // The optional Shortcuts hook runs only after the file is safely on disk.
            afterSave.runAfterSave(path: store.location?.resolvedURL.path)
        } catch {
            // The document stays dirty and the header shows why the save failed.
            saveError = error.localizedDescription
        }
    }

    // The four actions below hand off to the store; when the file changes, its location callback
    // runs load(). The ones that replace the current file ask first when work would be lost.
    // chooseFile(in window): Pick an existing file; nil presents without a sheet.
    func chooseFile(in window: NSWindow?) {
        guard resolveBeforeLeavingFile() else { return }
        store.chooseFile(in: window)
    }

    // createFile(in window): Choose a new file; nil presents without a sheet.
    func createFile(in window: NSWindow?) {
        guard resolveBeforeLeavingFile() else { return }
        store.createFile(in: window)
    }

    // resolveBeforeLeavingFile(): The unsaved-changes question for actions that replace the file.
    private func resolveBeforeLeavingFile() -> Bool {
        resolveUnsavedChanges(
            discardTitle: localized("Don't Save"),
            consequence: localized("Unsaved edits will be lost if you continue without saving.")
        )
    }

    // grantTargetAccess(in window): Ask for the link target; nil uses a modal panel.
    func grantTargetAccess(in window: NSWindow?) {
        store.grantTargetAccess(in: window)
    }

    // forgetAccess(): Drop the saved file permission, asking first when work would be lost; the
    // callback then clears the document.
    func forgetAccess() {
        guard resolveBeforeLeavingFile() else { return }
        store.forgetAccess()
    }

    // handleExternalChange(): Apply a change another program made on disk, or flag it when unsaved
    // edits would be lost.
    private func handleExternalChange() {
        // Only text that differs from the loaded copy matters; an unreadable file is ignored here.
        guard hasConfiguration, let text = try? store.read(), text != loadedText else { return }
        // Unsaved edits, including unapplied Source text: show the banner and let the user choose.
        if hasUnsavedChanges {
            externalChangePending = true
        } else {
            // Nothing to lose, so take the new contents right away.
            apply(text: text)
        }
    }

    // dismissExternalChange(): Keep the unsaved edits and hide the banner; the next save overwrites
    // the file.
    func dismissExternalChange() {
        externalChangePending = false
    }

    // MARK: Bindings

    // select(id): Select a visible binding and show the Bindings page, or pass nil to clear the
    // selection. Hidden bindings are refused.
    func select(_ id: UUID?) {
        guard id == nil || editableHotkeys.contains(where: { $0.id == id }) else { return }
        selectedBindingID = id
        // A selected binding is always shown in its editor.
        if id != nil { page = .binding }
    }

    // update(hotkey): Replace a visible binding in the document. Hidden bindings are refused.
    func update(_ hotkey: SkhdHotkey) {
        commitSourceDraftIfNeeded()
        guard editableHotkeys.contains(where: { $0.id == hotkey.id }) else { return }
        document.update(hotkey)
    }

    // addBinding(): Add a binding after the selected one with a shortcut that is not taken yet, or
    // offer Pro when the Free limit is reached.
    func addBinding() {
        commitSourceDraftIfNeeded()
        guard canAddBinding else {
            presentPro(for: .allBindings)
            return
        }
        // Use alt-shift with the first letter not already bound that way in the default mode.
        let modifiers: [SkhdModifier] = [.alt, .shift]
        let used = Set(document.hotkeys.filter { $0.modes.isEmpty && Set($0.modifiers) == Set(modifiers) }.map(\.key.identity))
        let letter = "abcdefghijklmnopqrstuvwxyz".first { !used.contains(SkhdKey.character($0).identity) } ?? "a"
        let hotkey = SkhdHotkey(modifiers: modifiers, key: .character(letter), action: .command(""))
        // Place the new binding next to the selected one, where the user is looking.
        if let selectedBindingID, document.index(of: selectedBindingID) != nil {
            document.insert(.hotkey(hotkey), after: selectedBindingID)
        } else {
            // No selection: append at the end of the file.
            document.append(.hotkey(hotkey))
        }
        select(hotkey.id)
    }

    // duplicateSelected(): Insert a copy right after the selected binding and select the copy, or
    // offer Pro when the Free limit is reached.
    func duplicateSelected() {
        guard commitSourceDraftIfNeeded(), let binding = selectedBinding else { return }
        guard canAddBinding else {
            presentPro(for: .allBindings)
            return
        }
        // The copy needs its own id and no verbatim source text, so it is written from its fields.
        var copy = binding
        copy.id = UUID()
        copy.sourceText = nil
        // Process map rows carry ids of their own, which must not be shared either.
        if case .processMap(let mappings) = copy.action {
            copy.action = .processMap(mappings.map { var row = $0; row.id = UUID(); return row })
        }
        document.insert(.hotkey(copy), after: binding.id)
        select(copy.id)
    }

    // confirmDeleteSelected(): Ask before removing the selected binding, then remove it. Typed
    // Source text is applied first, so the question names the binding that would be removed.
    func confirmDeleteSelected() {
        guard commitSourceDraftIfNeeded(), let binding = selectedBinding else { return }
        let alert = NSAlert()
        alert.messageText = localizedFormat("Delete the %@ binding?", binding.shortcutSymbols)
        alert.informativeText = localized("The binding is removed from the configuration when you save.")
        alert.addButton(withTitle: localized("Delete"))
        alert.addButton(withTitle: localized("Cancel"))
        // Delete is the first button.
        if alert.runModal() == .alertFirstButtonReturn { deleteSelected() }
    }

    // deleteSelected(): Remove the selected binding and select the one now at its position, or the
    // last one when it was last.
    func deleteSelected() {
        guard commitSourceDraftIfNeeded(), let binding = selectedBinding else { return }
        let hotkeys = editableHotkeys
        let index = hotkeys.firstIndex { $0.id == binding.id } ?? 0
        document.remove(binding.id)
        let remaining = editableHotkeys
        selectedBindingID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    // moveSelected(by offset): Swap with the previous (-1) or next (1) hotkey in the
    // file. Free users can only move within the visible bindings, so a hidden one never surfaces
    // by accident.
    func moveSelected(by offset: Int) {
        guard commitSourceDraftIfNeeded(),
              let binding = selectedBinding,
              offset < 0 ? canMoveSelected.up : canMoveSelected.down,
              let index = document.index(of: binding.id) else { return }
        // Only hotkeys count as positions; comments, modes, and blank lines between them stay put.
        let hotkeyIndexes = document.items.indices.filter { document.items[$0].hotkey != nil }
        guard let position = hotkeyIndexes.firstIndex(of: index) else { return }
        let targetPosition = position + offset
        guard hotkeyIndexes.indices.contains(targetPosition) else { return }
        let targetIndex = hotkeyIndexes[targetPosition]
        var items = document.items
        items.swapAt(index, targetIndex)
        document.items = items
    }

    /// Whether the selected binding has a visible neighbor above it and below it.
    var canMoveSelected: (up: Bool, down: Bool) {
        guard let binding = selectedBinding else { return (false, false) }
        let hotkeys = editableHotkeys
        guard let index = hotkeys.firstIndex(where: { $0.id == binding.id }) else { return (false, false) }
        return (index > 0, index < hotkeys.count - 1)
    }

    // MARK: Modes

    var modes: [SkhdModeDeclaration] { document.modeDeclarations }

    // addMode(): Declare a new mode named mode1, mode2, and so on, using the first free number.
    func addMode() {
        commitSourceDraftIfNeeded()
        var number = 1
        while document.declaredModeNames.contains("mode\(number)") { number += 1 }
        document.insertModeDeclaration(SkhdModeDeclaration(name: "mode\(number)"))
    }

    // update(mode): Replace a mode declaration in the document.
    func update(_ mode: SkhdModeDeclaration) {
        commitSourceDraftIfNeeded()
        document.update(mode)
    }

    // renameProblem(for id, to name): Return a rejection reason, or nil for a valid name.
    // Prevent mode collisions and changes to skhd's default mode.
    func renameProblem(for id: UUID, to name: String) -> String? {
        guard let mode = document.modeDeclarations.first(where: { $0.id == id }) else { return nil }
        // Keeping the current name is not a rename.
        if name == mode.name { return nil }
        // `:: default` only adds a command or capture to skhd's own default mode.
        if mode.name == "default" { return localized("The default mode cannot be renamed.") }
        // Taking the name would turn this mode into the default one.
        if name == "default" { return localized("The name “default” belongs to the mode skhd starts in.") }
        // Mode names must follow skhd's identifier rules.
        if !SkhdTokenizer.isIdentifier(name) {
            return localizedFormat("Mode name “%@” must start with a letter, contain only letters and underscores, and may end with digits.", name)
        }
        // Single letters, modifiers, and key names are reserved as keys.
        if !SkhdTokenizer.isModeName(name) {
            return localizedFormat("“%@” is a key or modifier name in skhd and cannot name a mode.", name)
        }
        // A second declaration with the name would merge the two modes.
        if document.modeDeclarations.contains(where: { $0.id != id && $0.name == name }) {
            return localizedFormat("A mode named “%@” already exists.", name)
        }
        return nil
    }

    // renameMode(id, to newName): Validate the name, then rename the mode and all
    // binding references, including those hidden by the Free limit.
    func renameMode(_ id: UUID, to newName: String) {
        commitSourceDraftIfNeeded()
        guard renameProblem(for: id, to: newName) == nil,
              let index = document.index(of: id), case .mode(var mode) = document.items[index],
              mode.name != newName else { return }
        let oldName = mode.name
        mode.name = newName
        // Apply one copy so Source serialization runs once, not for every binding.
        var updated = document
        updated.update(mode)
        for var hotkey in updated.hotkeys {
            var changed = false
            // Bindings scoped to the old mode.
            if hotkey.modes.contains(oldName) {
                hotkey.modes = hotkey.modes.map { $0 == oldName ? newName : $0 }
                changed = true
            }
            // Bindings whose action switches to the old mode.
            if case .activateMode(let target) = hotkey.action, target == oldName {
                hotkey.action = .activateMode(newName)
                changed = true
            }
            // Untouched bindings are left alone.
            if changed { updated.update(hotkey) }
        }
        document = updated
    }

    // removeMode(id): Remove a mode declaration. Bindings that use the mode are not changed.
    func removeMode(_ id: UUID) {
        commitSourceDraftIfNeeded()
        document.remove(id)
    }

    // MARK: Blacklist and includes

    /// Every blacklisted process, in file order.
    var blacklist: [String] {
        document.blacklists.flatMap(\.processes)
    }

    // setBlacklist(processes): Replace the blacklist with a single block holding these processes,
    // or remove the block when the list is empty.
    func setBlacklist(_ processes: [String]) {
        commitSourceDraftIfNeeded()
        // Apply one copy so Source serialization runs once for the whole update.
        var updated = document
        // The editor keeps a single block, so extra ones from the file are removed.
        for list in updated.blacklists.dropFirst() { updated.remove(list.id) }
        // An existing block is removed or rewritten in place, keeping its comment.
        if let first = updated.blacklists.first, let index = updated.index(of: first.id) {
            // An empty list means no blacklist at all.
            if processes.isEmpty {
                updated.remove(first.id)
            } else if first.processes != processes {
                // Rewrite only when the list changed, so an untouched block keeps its source text.
                updated.items[index] = .blacklist(SkhdBlacklist(id: first.id, comment: first.comment, processes: processes))
            }
        } else if !processes.isEmpty {
            // No block yet: create one.
            let list = SkhdBlacklist(processes: processes)
            // Directives go before the first binding, separated by a blank line.
            if let firstHotkey = updated.items.firstIndex(where: { $0.hotkey != nil }) {
                updated.items.insert(contentsOf: [.blacklist(list), .blank(SkhdBlankLines(count: 1))], at: firstHotkey)
            } else {
                // A file without bindings gets it at the end.
                updated.append(.blacklist(list))
            }
        }
        document = updated
    }

    var includes: [SkhdLoadDirective] { document.loadDirectives }

    /// Why a .load directive must not name the configuration file itself.
    private static var selfLoadMessage: String {
        localized("This path points to the current configuration. Including it would make skhd load the file repeatedly and fail.")
    }

    // includeProblem(for path): Why the path cannot be included, or nil when it can: it is empty,
    // it holds a quotation mark, or it leads back to the configuration file itself.
    func includeProblem(for path: String) -> String? {
        // An empty path has nothing to load.
        if path.trimmingCharacters(in: .whitespaces).isEmpty {
            return localized("The load directive needs a file path.")
        }
        // skhd's string token has no escapes, so a quote would end the path early.
        if path.contains("\"") { return localized("File paths cannot contain quotation marks.") }
        // skhd follows .load recursively, so the file loading itself never ends well.
        if loadsConfigurationItself(path) { return Self.selfLoadMessage }
        return nil
    }

    // loadsConfigurationItself(path): Whether a .load path leads to the open configuration file,
    // as chosen or as its link target. skhd resolves a relative path from the folder of the file
    // that holds the directive; both the chosen file's folder and its target's folder are tried,
    // with ~ expanded and symbolic links followed as far as the sandbox allows.
    private func loadsConfigurationItself(_ path: String) -> Bool {
        guard let location = store.location, !path.isEmpty else { return false }
        // The sandbox gives the app its own home, so ~ is expanded with the real one.
        let home = ConfigStore.realHomeDirectory.path
        let expanded = path == "~" ? home : (path.hasPrefix("~/") ? home + path.dropFirst() : path)
        // The configuration's own paths, before and after following links.
        var own = Set<String>()
        for url in [location.chosenURL, location.resolvedURL] {
            own.insert(url.standardizedFileURL.path)
            own.insert(ConfigStore.resolveLink(url).path)
        }
        // An absolute path is taken as is; a relative one from either folder.
        let candidates = expanded.hasPrefix("/")
            ? [URL(fileURLWithPath: expanded)]
            : [location.chosenURL, location.resolvedURL].map {
                $0.deletingLastPathComponent().appendingPathComponent(expanded)
            }
        return candidates.contains { candidate in
            own.contains(candidate.standardizedFileURL.path) || own.contains(ConfigStore.resolveLink(candidate).path)
        }
    }

    // addInclude(path): Add a .load directive for the path, grouped with the existing directives.
    // Paths that includeProblem(for:) rejects are refused.
    func addInclude(_ path: String) {
        commitSourceDraftIfNeeded()
        guard includeProblem(for: path) == nil else { return }
        let directive = SkhdLoadDirective(path: path)
        // Keep the directives together, after the last one.
        if let last = document.loadDirectives.last {
            document.insert(.load(directive), after: last.id)
        } else if let firstHotkey = document.items.firstIndex(where: { $0.hotkey != nil }) {
            // The first directive goes before the first binding, separated by a blank line.
            document.items.insert(contentsOf: [.load(directive), .blank(SkhdBlankLines(count: 1))], at: firstHotkey)
        } else {
            // A file without bindings gets it at the end.
            document.append(.load(directive))
        }
    }

    // updateInclude(id, path): Change a directive's path, keeping its comment. An unchanged path is
    // ignored, and paths that includeProblem(for:) rejects are refused.
    func updateInclude(_ id: UUID, path: String) {
        commitSourceDraftIfNeeded()
        guard includeProblem(for: path) == nil,
              let index = document.index(of: id), case .load(let existing) = document.items[index], existing.path != path else { return }
        document.items[index] = .load(SkhdLoadDirective(id: id, comment: existing.comment, path: path))
    }

    // removeInclude(id): Remove a .load directive.
    func removeInclude(_ id: UUID) {
        commitSourceDraftIfNeeded()
        document.remove(id)
    }

    // MARK: Source

    // applySourceDraft(): Replace the document with the parsed source editor text, or offer Pro
    // when source editing is locked.
    func applySourceDraft() {
        guard !isLimitedToFreeBindings else {
            presentPro(for: .sourceEditing)
            return
        }
        let parsed = SkhdParser.parse(sourceDraft)
        // Lines the parser could not read are kept as raw text; report the first one's error.
        if let raw = parsed.rawItems.first {
            sourceDraftError = raw.error
        } else {
            // A clean parse clears an earlier error.
            sourceDraftError = nil
        }
        // Parsing assigns new ids, so the selection is remembered by its keysym text.
        let previous = selectedBinding.map { SkhdSerializer.keysymText($0) }
        document = parsed
        // The draft is now applied; it stays as typed and counts as unedited from here.
        sourceDraftBase = sourceDraft
        // Keep the same shortcut selected when it still exists.
        if let previous, let match = editableHotkeys.first(where: { SkhdSerializer.keysymText($0) == previous }) {
            selectedBindingID = match.id
        } else {
            // Otherwise fall back to the first visible binding.
            selectedBindingID = editableHotkeys.first?.id
        }
    }

    // commitSourceDraftIfNeeded(): Apply unapplied Source text before anything else changes the
    // document, so later edits build on it instead of being replaced by it. Returns false when it
    // applied text and the selected binding did not survive it, so an action on the selection can
    // stop instead of acting on the binding selected in its place.
    @discardableResult
    private func commitSourceDraftIfNeeded() -> Bool {
        // While the Free limit locks the Source page, a draft typed before it is never applied.
        // It is dropped once the document changes, so it cannot return over newer edits later.
        if isLimitedToFreeBindings, sourceDraft != sourceDraftBase {
            refreshSourceDraft()
            return true
        }
        // Nothing typed, so nothing to apply.
        guard hasUnappliedSourceEdits else { return true }
        // applySourceDraft() reselects the same shortcut when the text still has it.
        let previous = selectedBinding.map { SkhdSerializer.keysymText($0) }
        applySourceDraft()
        return previous != nil && selectedBinding.map { SkhdSerializer.keysymText($0) } == previous
    }

    // refreshSourceDraft(): Reset the source editor to the current document, dropping an unapplied
    // draft. Used by Discard Edits, when the Source page appears without unapplied edits, and to
    // drop a draft the Free limit keeps from being applied.
    func refreshSourceDraft() {
        sourceDraft = serializedText
        sourceDraftBase = sourceDraft
        sourceDraftError = nil
    }

    // copyToPasteboard(text): Replace the general pasteboard contents with the text.
    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
