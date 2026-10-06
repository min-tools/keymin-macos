import AppKit
import SwiftUI

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
