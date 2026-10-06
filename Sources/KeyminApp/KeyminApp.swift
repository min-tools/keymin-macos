import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by the Record Shortcut menu item; the key recorder starts listening when it arrives.
    static let recordShortcut = Notification.Name("tools.min.keymin.record-shortcut")
}

/// The small About panel shared by the min.tools apps: icon, name, version, copyright, and a link
/// to the author's profile.
@MainActor
private final class MinToolsAboutPanelController: NSWindowController {
    static let shared = MinToolsAboutPanelController()

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    private let copyrightLabel = NSTextField(labelWithString: "")
    private let profileButton = NSButton()

    // init(): Build the fixed-size panel and stack the icon, labels, and link vertically.
    private init() {
        let size = NSSize(width: 280, height: 174)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        // A title-less panel pinned to one size and draggable anywhere, kept alive when closed so
        // it can be shown again.
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = false

        // The icon and three centered labels.
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        versionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        copyrightLabel.font = .systemFont(ofSize: 11, weight: .medium)
        for label in [nameLabel, versionLabel, copyrightLabel] {
            label.alignment = .center
            label.textColor = .labelColor
        }

        // The profile link is a borderless button drawn as a hyperlink.
        profileButton.isBordered = false
        profileButton.attributedTitle = NSAttributedString(
            string: "GitHub.com/iliaross",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        profileButton.target = self
        profileButton.action = #selector(openProfile(_:))

        // Stack everything vertically with hand-tuned gaps.
        let stack = NSStackView(views: [
            iconView,
            nameLabel,
            versionLabel,
            copyrightLabel,
            profileButton
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(8, after: iconView)
        stack.setCustomSpacing(7, after: nameLabel)
        stack.setCustomSpacing(8, after: versionLabel)
        stack.setCustomSpacing(0, after: copyrightLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Pin the icon size and center the stack near the top of the panel.
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.addSubview(stack)
        panel.contentView = content
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 54),
            iconView.heightAnchor.constraint(equalToConstant: 54),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10)
        ])
    }

    // init(coder): Unsupported; the panel is only built in code.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // show(applicationName): Refresh the bundle details and present the About panel.
    func show(applicationName: String) {
        // Version, build, and copyright come from Info.plist; the copyright has a fallback.
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let copyright = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 Ilia Ross"

        iconView.image = NSApp.applicationIconImage
        nameLabel.stringValue = applicationName
        versionLabel.stringValue = "Version \(version) (\(build))"
        copyrightLabel.stringValue = copyright

        // Bring the app forward and center the panel before showing it.
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // openProfile(sender): Open the author's public GitHub profile.
    @objc private func openProfile(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/iliaross") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Owns the model, the launch-time setup, the quit confirmation, and the app menu's actions.
@MainActor
final class KeyminAppDelegate: NSObject, NSApplicationDelegate {
    private static let didShowTrialWelcomeKey = "KeyminDidShowTrialWelcome"
    let model = AppModel()

    // applicationDidFinishLaunching(notification): Set the Dock icon, start the Pro store, and show
    // the trial welcome when it has not been shown yet.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIcon.make()
        // Store setup and the welcome alert run after this method returns and launch completes.
        Task { @MainActor in
            KeyminProStore.shared.start()
            presentTrialWelcomeIfNeeded()
        }
    }

    // applicationShouldTerminateAfterLastWindowClosed(sender): Quit when the editor window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // presentTrialWelcomeIfNeeded(): Explain the trial once and resolve its clock.
    // Later launches resolve quietly; production keeps Apple's acquisition date.
    private func presentTrialWelcomeIfNeeded() {
        let store = KeyminProStore.shared
        // Unlocked private builds and expired-trial previews skip the explanation and the trial.
        guard !store.isLocalBuild,
              !KeyminEdition.isExpiredTrialPreview else {
            return
        }
        // Already shown: begin or resume the trial quietly. This also resolves the trial for
        // preferences carried over from an earlier build.
        if UserDefaults.standard.bool(forKey: Self.didShowTrialWelcomeKey) {
            store.beginAppTrial()
            return
        }
        // First launch: disclose the trial and Free tier before resolving access.
        // This starts a local trial where allowed; it does not reset a signed date.
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = localized("30 days of full access")
        let trialDetails = [
            localized("Keymin is fully unlocked for your first 30 days. No subscription starts, and you will not be charged."),
            localizedFormat("After the trial, Keymin shows and edits only the first %lld bindings. The others are hidden but kept in the file.", Int64(KeyminFreeAccessPolicy.freeBindingLimit)),
            localized("Choose a yearly subscription or lifetime purchase at any time to edit every binding again."),
        ]
        alert.informativeText = trialDetails.joined(separator: "\n\n")
        alert.addButton(withTitle: localized("Continue"))
        NSApp.activate(ignoringOtherApps: true)
        _ = alert.runModal()
        store.beginAppTrial()
        UserDefaults.standard.set(true, forKey: Self.didShowTrialWelcomeKey)
    }

    // applicationShouldTerminate(sender): Offer to save before quitting with unsaved work,
    // including unapplied Source text. A failed save keeps the app open so the error stays visible.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let mayQuit = model.resolveUnsavedChanges(
            discardTitle: localized("Quit Without Saving"),
            consequence: localized("Unsaved edits will be lost if you quit without saving.")
        )
        return mayQuit ? .terminateNow : .terminateCancel
    }

    // showAbout(): Show the About panel with the bundle details and the author link.
    func showAbout() {
        MinToolsAboutPanelController.shared.show(applicationName: "Keymin")
    }

    // showPrivacyPolicy(sender): Show the privacy policy window.
    @objc func showPrivacyPolicy(_ sender: Any?) {
        PrivacyPolicyController.shared.show()
    }

    // forgetAccess(): Confirm and drop the saved file permission.
    func forgetAccess() {
        let alert = NSAlert()
        alert.messageText = localized("Forget access to the configuration file?")
        alert.informativeText = localized("Keymin removes its saved permission for the file. Nothing is deleted. Choose the file again to keep editing it.")
        alert.addButton(withTitle: localized("Forget Access"))
        alert.addButton(withTitle: localized("Cancel"))
        // Forget Access is the first button.
        if alert.runModal() == .alertFirstButtonReturn { model.forgetAccess() }
    }
}
