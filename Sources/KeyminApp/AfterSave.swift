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
