import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
