import AppKit
import SwiftUI

/// Runs an optional Shortcuts action after saving. Disabled by default.
/// Shortcuts runs the action with its own permissions, outside Keymin's sandbox.
@MainActor
final class AfterSavePreferences: ObservableObject {
    /// Whether a shortcut runs after each save. Saved on every change.
    @Published var runsShortcut: Bool {
        didSet { defaults.set(runsShortcut, forKey: Keys.runsShortcut) }
    }
    /// The shortcut's exact name in the Shortcuts app. Saved on every change.
    @Published var shortcutName: String {
        didSet { defaults.set(shortcutName, forKey: Keys.shortcutName) }
    }
    /// A one-line note about the last attempt, shown on the After Saving page.
    @Published private(set) var lastResult: String?

    private let defaults: UserDefaults

    /// UserDefaults keys.
    private enum Keys {
        static let runsShortcut = "KeyminAfterSaveRunsShortcut"
        static let shortcutName = "KeyminAfterSaveShortcutName"
    }

    // init([defaults = .standard]): Load both settings from the given defaults.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        runsShortcut = defaults.bool(forKey: Keys.runsShortcut)
        shortcutName = defaults.string(forKey: Keys.shortcutName) ?? ""
    }

    /// The name without surrounding whitespace; what is actually sent to Shortcuts.
    var trimmedName: String { shortcutName.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// True when the option is on and a name is set, so a save will run something.
    var isConfigured: Bool { runsShortcut && !trimmedName.isEmpty }

    // runURL(shortcut name, input): Encode the named Shortcuts shortcut as a URL.
    // Pass the file path as text input; nil or an empty string omits input entirely.
    static func runURL(shortcut name: String, input: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        var items = [URLQueryItem(name: "name", value: name)]
        // Shortcuts needs both items: the kind of input and the text itself.
        if let input, !input.isEmpty {
            items.append(URLQueryItem(name: "input", value: "text"))
            items.append(URLQueryItem(name: "text", value: input))
        }
        components.queryItems = items
        return components.url
    }

    // runAfterSave(path): Run the configured hook after a successful save.
    // Pass nil when no file path is available, so Shortcuts receives no text input.
    func runAfterSave(path: String?) {
        // Saves must not launch Shortcuts until the user enables and names the hook.
        guard isConfigured else { return }
        run(path: path)
    }

    // run(path): Ask Shortcuts to run, optionally passing a non-nil file path.
    // Return whether macOS opened the URL, not whether the shortcut succeeded.
    @discardableResult
    func run(path: String?) -> Bool {
        let name = trimmedName
        guard !name.isEmpty, let url = Self.runURL(shortcut: name, input: path) else {
            lastResult = localized("Enter the name of a shortcut first.")
            return false
        }
        let opened = NSWorkspace.shared.open(url)
        lastResult = opened
            ? localizedFormat("Asked Shortcuts to run “%@”.", name)
            : localized("Shortcuts could not be opened.")
        return opened
    }

    // openShortcutsApp(): Bring up the Shortcuts app so the user can create or edit the shortcut.
    static func openShortcutsApp() {
        // The bare scheme just opens the app.
        if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) }
    }
}

/// The After Saving page: explains skhd's own reload and offers the Shortcuts hook.
struct AfterSaveEditorView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var preferences: AfterSavePreferences

    // init(model): Observe the model's after-save preferences directly so this page refreshes
    // when they change.
    init(model: AppModel) {
        self.model = model
        _preferences = ObservedObject(wrappedValue: model.afterSave)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header, laid out like the other configuration pages.
                HStack(spacing: 18) {
                    IconTile(symbol: "arrow.triangle.2.circlepath", size: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localized("After Saving"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(localized("With hot loading enabled, skhd applies saved changes automatically. To restart it or run another action after saving, choose a Shortcuts shortcut."))
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Enabling this reveals the shortcut settings below.
                ToggleCard(
                    title: "Run a shortcut after every save",
                    subtitle: "Pass the saved file's path to a shortcut in the Shortcuts app.",
                    isOn: $preferences.runsShortcut
                )

                // The name field, a test run, and a way into the Shortcuts app.
                if preferences.runsShortcut {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localized("Shortcut name"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            HStack(spacing: 10) {
                                InputField(placeholder: "Restart skhd", text: $preferences.shortcutName, onSubmit: runNow)
                                    .frame(width: 320)
                                Button(localized("Run Now")) { runNow() }
                                    .buttonStyle(.keymin(.secondary, size: .small))
                                    .keyboardFocusable()
                                    .disabled(preferences.trimmedName.isEmpty)
                                Button(localized("Open Shortcuts")) { AfterSavePreferences.openShortcutsApp() }
                                    .buttonStyle(.keymin(.secondary, size: .small))
                                    .keyboardFocusable()
                            }
                            // The note from the last run, whether after a save or from Run Now.
                            if let result = preferences.lastResult {
                                Text(result)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Text(localized("Use the exact shortcut name. Keymin cannot check the result; add a Show Notification action in Shortcuts to confirm it ran."))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .card(padding: 20)
                }

                // A recipe for the common case, since the sandbox keeps Keymin from restarting
                // skhd itself.
                NoticeCard(
                    tone: .neutral,
                    symbol: "info.circle",
                    title: localized("Restart skhd with Shortcuts"),
                    detail: localized("Create “Restart skhd” in Shortcuts. Add a Run Shell Script action with “skhd --restart-service”, using the full path to skhd. Shortcuts does not load your shell profile. Enable Allow Running Scripts in Shortcuts → Settings → Advanced.")
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 40)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // runNow(): Run the shortcut right away with the current file's path, as a save would.
    private func runNow() {
        preferences.run(path: model.store.location?.resolvedURL.path)
    }
}
