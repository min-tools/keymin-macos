import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
