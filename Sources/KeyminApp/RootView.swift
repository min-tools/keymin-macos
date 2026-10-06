import AppKit
import SwiftUI

/// The file path, save state, and primary actions above the editor.
private struct HeaderBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var store: ConfigStore

    // init(model): Observe the model and its store, so the path and save state stay current.
    init(model: AppModel) {
        self.model = model
        _store = ObservedObject(wrappedValue: model.store)
    }

    var body: some View {
        HStack(spacing: 12) {
            // The path, where a link leads, and the Change button.
            if let location = store.location {
                HStack(spacing: 8) {
                    Image(systemName: location.isSymbolicLink ? "link" : "doc.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(location.displayPath)
                            .font(Theme.mono(12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        // Show where a link leads.
                        if location.isSymbolicLink {
                            Text(localizedFormat("Link to %@", location.resolvedDisplayPath))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .help(location.resolvedURL.path)
                Button(localized("Change")) { model.chooseFile(in: NSApp.keyWindow) }
                    .buttonStyle(.keymin(.secondary, size: .small))
                    .keyboardFocusable()
                    .help(localized("Choose another configuration file"))
            }
            Spacer(minLength: 12)
            // The last save error, kept short next to the status pill; the tooltip holds all of it.
            if let error = model.saveError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
                    .frame(maxWidth: 360, alignment: .trailing)
                    .help(error)
            }
            statusPill
            // Save is disabled while nothing is unsaved; its help text explains a blocked save.
            Button(localized("Save")) { model.save() }
                .buttonStyle(.keymin(.primary, shortcut: "⌘S"))
                .keyboardFocusable()
                .disabled(!model.hasUnsavedChanges)
                .help(localized(model.blockingErrors.isEmpty ? "Write the configuration to disk" : "Fix the listed problems before saving"))
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .zoomsWindowOnDoubleClick()
    }

    @ViewBuilder private var statusPill: some View {
        // Free users' blocking errors leave out problems they cannot reach, so warnings are counted
        // on their own rather than as the remainder.
        let errors = model.blockingErrors.count
        let warnings = model.diagnostics.filter { $0.severity == .warning }.count
        // Problems block saving, so they outrank everything else.
        if errors > 0 {
            StatusPill(tone: .negative, text: errors == 1 ? localized("1 problem") : localizedFormat("%lld problems", Int64(errors)))
        } else if model.hasUnsavedChanges {
            // Unsaved edits, including unapplied Source text, noting warnings when there are any.
            StatusPill(tone: .warning, text: warnings > 0 ? localized("Unsaved · warnings") : localized("Unsaved changes"))
        } else if warnings > 0 {
            // Clean, but the editor noticed something worth a look.
            StatusPill(tone: .warning, text: warnings == 1 ? localized("1 warning") : localizedFormat("%lld warnings", Int64(warnings)))
        } else if model.savedRecently {
            // Confirm the save and name any requested shortcut. Its result is unknown.
            StatusPill(tone: .positive, text: model.afterSave.isConfigured
                ? localizedFormat("Saved · requested “%@”", model.afterSave.trimmedName)
                : localized("Saved"))
        } else {
            // Clean and quiet.
            StatusPill(tone: .positive, text: localized("Saved"))
        }
    }
}

/// Shown when another program changed the file while there are unsaved edits.
private struct ExternalChangeBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("The file changed on disk"))
                    .font(.system(size: 12, weight: .semibold))
                Text(localized("Reload to see the new contents, or keep your unsaved edits and overwrite the file when you save."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Button(localized("Keep Mine")) { model.dismissExternalChange() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardFocusable()
            Button(localized("Reload")) { model.reload() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardFocusable()
        }
        // Plain bordered buttons on the orange banner rather than accent-tinted ones.
        .tint(nil)
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(Color(nsColor: .systemOrange).opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .systemOrange).opacity(0.48)).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The welcome screen: first run, a link awaiting access, or a file that could not be read.
private struct WelcomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var store: ConfigStore
    @Environment(\.skhdPresenceScanner) private var scanPresence
    /// What the last look for skhd found; nil until the first look.
    @State private var presence: SkhdPresence?

    // init(model): Observe the model and its store, so the file state and path stay current.
    init(model: AppModel) {
        self.model = model
        _store = ObservedObject(wrappedValue: model.store)
    }

    var body: some View {
        // Centered when there is room, scrollable when the window is at its smallest.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    // The app icon, then a heading and explanation that depend on the file state.
                    Image(nsImage: AppIcon.make())
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 84, height: 84)
                    VStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(detail)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 540)
                    }
                    // Only the first-run screen asks whether skhd is present.
                    if model.fileState == .none {
                        SkhdRequirementCard(presence: presence, onRefresh: refreshPresence)
                            .padding(.top, 4)
                    }
                    actions
                        .padding(.top, 4)
                    // The hint about the usual path belongs to the first-run screen too.
                    if model.fileState == .none {
                        Text(localized("Your file is usually at ~/.config/skhd/skhdrc. Keymin edits only the configuration you choose."))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    // Access and read problems name the file they are about.
                    if let location = store.location, model.fileState != .none {
                        Text(location.displayPath)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .onAppear(perform: refreshPresence)
        // Installing or starting skhd happens in another app; look again when the user comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPresence()
        }
    }

    // refreshPresence(): Look for skhd again, but only while the first-run screen shows the card.
    private func refreshPresence() {
        guard model.fileState == .none else { return }
        presence = scanPresence()
    }

    /// The heading for the current file state.
    private var title: String {
        switch model.fileState {
        case .none: return localized("Hotkeys for skhd, without the syntax")
        case .needsTargetAccess: return localized("One more permission")
        case .failed: return localized("The configuration could not be opened")
        case .loaded: return ""
        }
    }

    /// The explanation under the heading; a read failure shows its error message.
    private var detail: String {
        switch model.fileState {
        case .none:
            return localized("Keymin edits your skhd configuration. Install and start skhd on this Mac to use the shortcuts.")
        case .needsTargetAccess:
            let target = store.location?.resolvedDisplayPath ?? ""
            return localizedFormat("The chosen file is a link to %@. macOS needs your permission for that file as well before Keymin can read and write it.", target)
        case .failed(let message):
            return message
        case .loaded:
            return ""
        }
    }

    /// The buttons for the current file state.
    @ViewBuilder private var actions: some View {
        switch model.fileState {
        case .none:
            HStack(spacing: 12) {
                Button(localized("Choose skhdrc")) { model.chooseFile(in: NSApp.keyWindow) }
                    .buttonStyle(.keymin(.primary, shortcut: "⌘O"))
                    .keyboardFocusable()
                Button(localized("Create New")) { model.createFile(in: NSApp.keyWindow) }
                    .buttonStyle(.keymin(.secondary))
                    .keyboardFocusable()
            }
        case .needsTargetAccess:
            HStack(spacing: 12) {
                Button(localized("Grant Access")) { model.grantTargetAccess(in: NSApp.keyWindow) }
                    .buttonStyle(.keymin(.primary))
                    .keyboardFocusable()
                Button(localized("Choose Another File")) { model.chooseFile(in: NSApp.keyWindow) }
                    .buttonStyle(.keymin(.secondary))
                    .keyboardFocusable()
            }
        case .failed:
            HStack(spacing: 12) {
                Button(localized("Try Again")) { model.reload() }
                    .buttonStyle(.keymin(.primary))
                    .keyboardFocusable()
                Button(localized("Choose Another File")) { model.chooseFile(in: NSApp.keyWindow) }
                    .buttonStyle(.keymin(.secondary))
                    .keyboardFocusable()
            }
        case .loaded:
            EmptyView()
        }
    }
}
