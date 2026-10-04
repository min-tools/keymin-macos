import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What the editor shows for an app: its name and icon as macOS knows them.
struct ResolvedApp {
    let title: String
    let subtitle: String?
    let icon: NSImage
    /// False when a bundle identifier is not found on this Mac; the editor then shows a warning.
    let isInstalled: Bool
}

/// Looks apps up for the editor: by bundle identifier or path, from the running-app list, or
/// through an Open panel.
enum AppResolver {
    // resolve(command): Describe the app a parsed open-app command targets. A bundle identifier
    // is looked up through Launch Services, which finds apps anywhere on the Mac even when the
    // sandbox cannot read their folder.
    static func resolve(_ command: OpenAppCommand) -> ResolvedApp {
        let workspace = NSWorkspace.shared
        switch command.target {
        case .bundleIdentifier(let identifier):
            guard let url = workspace.urlForApplication(withBundleIdentifier: identifier) else {
                return ResolvedApp(
                    title: identifier,
                    subtitle: localized("App not found on this Mac"),
                    icon: workspace.icon(for: .applicationBundle),
                    isInstalled: false
                )
            }
            return ResolvedApp(title: displayName(of: url), subtitle: identifier, icon: workspace.icon(forFile: url.path), isInstalled: true)
        case .application(let name):
            // An absolute path names the bundle directly, so its real name and icon can be shown.
            if name.hasPrefix("/") {
                let url = URL(fileURLWithPath: name)
                return ResolvedApp(title: displayName(of: url), subtitle: name, icon: workspace.icon(forFile: url.path), isInstalled: true)
            }
            // A bare name is resolved by `open` at run time, so only the name itself is known.
            return ResolvedApp(title: name, subtitle: localized("Opened by name"), icon: workspace.icon(for: .applicationBundle), isInstalled: true)
        }
    }

    // displayName(of url): Return the Finder name without a trailing `.app`.
    private static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    // chooseApplication(completion): Let the user pick any app bundle and report its bundle
    // identifier. An app without one gets an alert pointing at the command editor instead.
    static func chooseApplication(completion: @escaping (String) -> Void) {
        // An Open panel limited to app bundles, starting in the Applications folder.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = localized("Choose the app to open.")
        panel.prompt = localized("Choose")
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            // `open -b` needs an identifier; explain the `open -a` alternative when there is none.
            guard let identifier = Bundle(url: url)?.bundleIdentifier, !identifier.isEmpty else {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = localized("This app has no bundle identifier")
                alert.informativeText = localized("Use Run a command with “open -a” and the app's path instead.")
                alert.addButton(withTitle: localized("OK"))
                alert.runModal()
                return
            }
            completion(identifier)
        }
        // Attach the panel to the key window as a sheet when there is one.
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            // No key window: run the panel as a standalone modal.
            handler(panel.runModal())
        }
    }

    // runningApplications(): Ordinary running apps (those with a Dock tile) that have a bundle
    // identifier, sorted by name for the quick pick list.
    static func runningApplications() -> [(name: String, identifier: String, icon: NSImage)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application in
                guard let identifier = application.bundleIdentifier, let name = application.localizedName else { return nil }
                let icon = application.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
                return (name, identifier, icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// A small drawn button that opens a native pop-up menu.
struct MenuButton: View {
    /// A localization key; the button localizes it itself.
    let title: String
    /// Built on every click, so the list is always current.
    let entries: () -> [PopUpMenuEntry]
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    var body: some View {
        PopUpMenuButton(accessibilityLabel: localized(title)) {
            HStack(spacing: 6) {
                Text(localized(title))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 11)
            .frame(height: Theme.smallControlHeight)
            .background(Theme.surfaceRaised, in: shape)
            .overlay(shape.stroke(Theme.borderStrong, lineWidth: contrast == .increased ? 1.5 : 1))
        } entries: {
            entries()
        }
    }
}

/// Lists running apps with their icons and offers the Open panel for any other app. Reports the
/// chosen app's bundle identifier, which is what `open -b` needs.
struct AppChooserMenu: View {
    let title: String
    /// Receives the bundle identifier of the chosen app.
    let onPick: (String) -> Void

    var body: some View {
        MenuButton(title: title) {
            var entries: [PopUpMenuEntry] = [.header(localized("Running apps"))]
            for application in AppResolver.runningApplications() {
                entries.append(.item(application.name, image: Self.menuIcon(application.icon)) { onPick(application.identifier) })
            }
            entries.append(.separator)
            entries.append(.item(localized("Choose Application…")) { AppResolver.chooseApplication(completion: onPick) })
            return entries
        }
    }

    // menuIcon(icon): Size a copy for a 16-point menu row; fall back to the supplied
    // image if copying does not return an NSImage.
    static func menuIcon(_ icon: NSImage) -> NSImage {
        let copy = icon.copy() as? NSImage ?? icon
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}
