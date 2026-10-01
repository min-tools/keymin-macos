import AppKit
import Foundation

/// Where the configuration lives: the file the user chose, and the real file behind it when the
/// chosen path is a symbolic link.
struct ConfigLocation: Equatable {
    let chosenURL: URL
    let resolvedURL: URL
    /// Whether macOS granted access to the link target itself, not only to the link.
    var hasTargetAccess: Bool

    var isSymbolicLink: Bool { chosenURL.standardizedFileURL.path != resolvedURL.path }
    var displayPath: String { ConfigStore.abbreviate(chosenURL.path) }
    var resolvedDisplayPath: String { ConfigStore.abbreviate(resolvedURL.path) }
    var fileName: String { chosenURL.lastPathComponent }
}

/// Errors the store reports in the user's language.
struct ConfigStoreError: LocalizedError {
    /// `wrongTarget` means the file picked when granting link access is not the link's target.
    enum Kind { case noFile, cannotRead, cannotWrite, needsTargetAccess, notUTF8, wrongTarget }
    let kind: Kind
    let detail: String?

    var errorDescription: String? {
        switch kind {
        case .noFile: return localized("No configuration file is selected.")
        case .cannotRead: return detail.map { localizedFormat("The configuration could not be read. %@", $0) } ?? localized("The configuration could not be read.")
        case .cannotWrite: return detail.map { localizedFormat("The configuration could not be saved. %@", $0) } ?? localized("The configuration could not be saved.")
        case .needsTargetAccess: return localized("The selected file is a symbolic link. Grant access to the file it points to.")
        case .notUTF8: return localized("The file is not UTF-8 text.")
        case .wrongTarget: return localized("That is not the file the link points to.")
        }
    }
}

/// Owns file permissions, configuration reads and writes, and change notifications.
/// Uses the chosen file and any link target the user separately grants access to.
@MainActor
final class ConfigStore: ObservableObject {
    @Published private(set) var location: ConfigLocation?
    /// Called when another program changed the file on disk.
    var onExternalChange: (() -> Void)?
    /// Called whenever the current file changes: restored, chosen, created, granted, or forgotten.
    var onLocationChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    /// URLs whose security scope is open; closed again before the next adopt or on forget.
    private var accessedURLs: [URL] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherDescriptor: Int32 = -1
    /// The delayed callback that folds a burst of file events into one notification.
    private var rearmWork: DispatchWorkItem?

    private static let bookmarkKey = "KeyminConfigBookmark"
    private static let targetBookmarkKey = "KeyminConfigTargetBookmark"

    /// The real home directory, because the sandbox container reports its own home.
    nonisolated static var realHomeDirectory: URL {
        // The password database knows the real home; Foundation's answer is the fallback.
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// The directory of skhd's default file, `~/.config/skhd/skhdrc`, where the panels start.
    nonisolated static var defaultDirectory: URL {
        realHomeDirectory.appendingPathComponent(".config/skhd", isDirectory: true)
    }

    /// Stands in for the real home directory in displayed paths. The screenshot renderer sets it
    /// so a fixture path reads like a user's own; the app leaves it nil.
    nonisolated(unsafe) static var displayHomeOverride: String?

    // abbreviate(path): Shorten the path with `~` when it is the home directory or lies inside it.
    nonisolated static func abbreviate(_ path: String) -> String {
        let home = displayHomeOverride ?? realHomeDirectory.path
        // The home directory itself.
        if path == home { return "~" }
        // Inside it; the slash keeps a sibling such as `/Users/ilia2` from matching.
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    // MARK: Restore and forget

    // restore(): Resolve the bookmarks saved on an earlier launch and adopt that file, or leave the
    // location empty when there is none.
    func restore() {
        // An absent or unresolvable bookmark leaves the file chooser visible.
        guard let data = defaults.data(forKey: Self.bookmarkKey),
              let chosen = resolveBookmark(data, key: Self.bookmarkKey) else {
            location = nil
            return
        }
        var target: URL?
        // A link target granted earlier comes back too, so no new permission is needed.
        if let targetData = defaults.data(forKey: Self.targetBookmarkKey) {
            target = resolveBookmark(targetData, key: Self.targetBookmarkKey)
        }
        adopt(chosen: chosen, target: target)
    }

    // adoptWithoutBookmark(url): Open the file without a bookmark, so nothing is remembered for the
    // next launch. The screenshot renderer and tests use this with fixture files; the app itself
    // only adopts files the user picked in a panel or that a saved bookmark resolves to.
    func adoptWithoutBookmark(_ url: URL) {
        adopt(chosen: url.standardizedFileURL, target: nil)
    }

    // forgetAccess(): Stop watching, close the scopes, and clear the saved bookmarks, so the file
    // cannot be opened again without a new choice.
    func forgetAccess() {
        stopWatching()
        stopAccessing()
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.targetBookmarkKey)
        location = nil
        onLocationChange?()
    }

    // resolveBookmark(data, key): Resolve a security-scoped bookmark without prompting, and store a
    // fresh one under the key when macOS reports it stale.
    private func resolveBookmark(_ data: Data, key: String) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        // A stale bookmark still resolves; a fresh one spares later launches the same repair. When
        // the fresh one cannot be made, the old one stays.
        if stale, let refreshed = try? url.bookmarkData(options: .withSecurityScope) {
            defaults.set(refreshed, forKey: key)
        }
        return url
    }

    // adopt(chosen, target): Release the old file, open scopes, and watch the new one.
    // Pass nil for target when no separate link-target grant exists.
    private func adopt(chosen: URL, target: URL?) {
        stopWatching()
        stopAccessing()
        // Only URLs that actually grant a scope are remembered for release.
        for url in [chosen, target].compactMap({ $0 }) where url.startAccessingSecurityScopedResource() {
            accessedURLs.append(url)
        }
        // Use a granted target as the real file, or resolve the link as far as the sandbox allows.
        let resolved = target?.standardizedFileURL ?? Self.resolveLink(chosen)
        location = ConfigLocation(chosenURL: chosen, resolvedURL: resolved, hasTargetAccess: target != nil)
        startWatching()
        onLocationChange?()
    }

    // stopAccessing(): Close every open security scope.
    private func stopAccessing() {
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
        accessedURLs = []
    }

    // resolveLink(url): Follow symbolic links one hop at a time, stopping where the sandbox hides
    // the next hop, then let the system resolve links in the parent directories as well.
    nonisolated static func resolveLink(_ url: URL) -> URL {
        var current = url.standardizedFileURL
        // Bound the explicit walk so a link cycle cannot keep this loop running.
        for _ in 0..<8 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else { break }
            // A relative link target is taken from the link's own directory.
            let next = destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : current.deletingLastPathComponent().appendingPathComponent(destination)
            current = next.standardizedFileURL
        }
        return current.resolvingSymlinksInPath().standardizedFileURL
    }

    // MARK: Choosing files

    // chooseFile(in window): Pick an existing file; nil uses an app-modal panel.
    func chooseFile(in window: NSWindow?) {
        // A single-file picker: dotfiles must be visible, and a symbolic link must come back as
        // itself rather than its target, so the link can be recognized and kept.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = Self.defaultDirectory
        panel.message = localized("Choose the skhd configuration file to edit. It is usually ~/.config/skhd/skhdrc.")
        panel.prompt = localized("Choose")
        present(panel, in: window) { [weak self] url in
            self?.saveChoice(url)
        }
    }

    // createFile(in window): Choose, create, and adopt a configuration file.
    // Pass nil for window to use an app-modal Save panel.
    func createFile(in window: NSWindow?) {
        // Suggest skhd's default name and folder, and allow creating the folder on the way.
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "skhdrc"
        panel.showsHiddenFiles = true
        panel.canCreateDirectories = true
        panel.directoryURL = Self.defaultDirectory
        panel.message = localized("Choose where to create the new skhd configuration. skhd reads ~/.config/skhd/skhdrc by default.")
        panel.prompt = localized("Create")
        present(panel, in: window) { [weak self] url in
            guard let self else { return }
            // Start the file with a two-line comment that explains the syntax; skhd ignores it.
            let template = localized("# skhd configuration edited with Keymin.\n# Each binding is written as: modifiers - key : command\n") + "\n"
            do {
                try Data(template.utf8).write(to: url)
                self.saveChoice(url)
            } catch {
                // A file that could not be written is not adopted.
                self.presentError(ConfigStoreError(kind: .cannotWrite, detail: error.localizedDescription))
            }
        }
    }

    // grantTargetAccess(in window): Ask for read/write access to the link target.
    // Pass nil for window to use an app-modal Open panel.
    func grantTargetAccess(in window: NSWindow?) {
        guard let location else { return }
        // The picker opens in the target's directory, with links shown as themselves.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = location.resolvedURL.deletingLastPathComponent()
        panel.message = localizedFormat("%@ is a link to %@. Select that file so Keymin can read and write it.", location.displayPath, location.resolvedDisplayPath)
        panel.prompt = localized("Grant Access")
        present(panel, in: window) { [weak self] url in
            guard let self else { return }
            // Accept the target itself or another link leading to it; anything else is a mistake.
            let resolved = Self.resolveLink(url)
            guard resolved.path == location.resolvedURL.path || url.standardizedFileURL.path == location.resolvedURL.path else {
                self.presentError(ConfigStoreError(kind: .wrongTarget, detail: nil))
                return
            }
            guard let bookmark = try? url.bookmarkData(options: .withSecurityScope) else {
                self.presentError(ConfigStoreError(kind: .cannotRead, detail: nil))
                return
            }
            // Remember the target beside the chosen file and reopen both scopes.
            self.defaults.set(bookmark, forKey: Self.targetBookmarkKey)
            self.adopt(chosen: location.chosenURL, target: url)
        }
    }

    // present(panel, in window, completion): Present a file panel, using a sheet
    // when window is non-nil. Call completion with the chosen URL only on acceptance.
    private func present(_ panel: NSSavePanel, in window: NSWindow?, completion: @escaping (URL) -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
        // A window makes a sheet possible.
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            // Without one the panel runs app-modally.
            handler(panel.runModal())
        }
    }

    // saveChoice(url): Bookmark a newly chosen file, drop any old link-target grant, and adopt it.
    private func saveChoice(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope) else {
            presentError(ConfigStoreError(kind: .cannotRead, detail: nil))
            return
        }
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.targetBookmarkKey)
        adopt(chosen: url, target: nil)
    }

    // presentError(error): Show the error's description in a modal alert.
    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localized("Keymin could not use that file")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: localized("OK"))
        alert.runModal()
    }

    // MARK: Reading and writing

    // read(): Read the configuration text. A symbolic link whose target is still out of reach
    // throws `needsTargetAccess` so the interface can ask for it.
    func read() throws -> String {
        guard let location else { throw ConfigStoreError(kind: .noFile, detail: nil) }
        // Try the file the grant most likely covers first: the target once granted, else the link.
        let candidates = location.hasTargetAccess ? [location.resolvedURL, location.chosenURL] : [location.chosenURL, location.resolvedURL]
        var lastError: Error?
        for url in candidates {
            do {
                let data = try Data(contentsOf: url)
                guard String(data: data, encoding: .utf8) != nil else { throw ConfigStoreError(kind: .notUTF8, detail: nil) }
                // Decode again keeping a leading byte order mark. Foundation drops it, but skhd
                // rejects the file for it, so the parser must see it to report it.
                return String(decoding: data, as: UTF8.self)
            } catch let error as ConfigStoreError {
                // Bad encoding is final; the other path holds the same bytes.
                throw error
            } catch {
                // Keep the system error and try the other path.
                lastError = error
            }
        }
        // Neither path could be read. A link without a granted target needs the extra permission
        // rather than a generic failure.
        if location.isSymbolicLink, !location.hasTargetAccess {
            throw ConfigStoreError(kind: .needsTargetAccess, detail: lastError?.localizedDescription)
        }
        throw ConfigStoreError(kind: .cannotRead, detail: lastError?.localizedDescription)
    }

    // write(text): Write the text to the real file. The link itself is never replaced, so a
    // configuration kept in a dotfiles repository keeps its link.
    func write(_ text: String) throws {
        guard let location else { throw ConfigStoreError(kind: .noFile, detail: nil) }
        let data = Data(text.utf8)
        // Pause the watcher during the app's own write so it is not reported as an external change.
        suspendWatcher()
        defer { resumeWatcher() }
        do {
            try Self.replaceAtomically(data, at: location.resolvedURL)
            return
        } catch {
            // Fall back when atomic replacement fails, including when a file-only
            // grant denies the sibling temporary file. This preserves the link and
            // permissions, but writes in place and is not atomic.
            do {
                try data.write(to: location.chosenURL, options: [])
                return
            } catch let inPlaceError {
                // As in read(): a link without a granted target is a permission problem.
                if location.isSymbolicLink, !location.hasTargetAccess {
                    throw ConfigStoreError(kind: .needsTargetAccess, detail: inPlaceError.localizedDescription)
                }
                throw ConfigStoreError(kind: .cannotWrite, detail: inPlaceError.localizedDescription)
            }
        }
    }

    // replaceAtomically(data, at target): Write a hidden sibling file and swap it in,
    // so the target keeps its permissions and a crash mid-write cannot leave it half written.
    nonisolated static func replaceAtomically(_ data: Data, at target: URL) throws {
        let manager = FileManager.default
        let temporary = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).keymin-\(UUID().uuidString.prefix(8))")
        try data.write(to: temporary, options: [])
        do {
            _ = try manager.replaceItemAt(target, withItemAt: temporary, backupItemName: nil, options: [])
        } catch {
            // Do not leave the temporary file behind.
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    // revealInFinder(): Show the chosen file in Finder.
    func revealInFinder() {
        guard let location else { return }
        NSWorkspace.shared.activateFileViewerSelecting([location.chosenURL])
    }

    // MARK: Watching

    // startWatching(): Replace the watcher with a dispatch source on the file, following the link
    // target once it is granted. A file that cannot be opened is simply not watched.
    private func startWatching() {
        stopWatching()
        guard let location else { return }
        // Opening for events only does not read the file.
        let path = location.hasTargetAccess ? location.resolvedURL.path : location.chosenURL.path
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        watcherDescriptor = descriptor
        // Writes, truncation, replacement, and attribute changes all count as a change.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            let events = source.data
            MainActor.assumeIsolated {
                self?.handleFileEvent(events)
            }
        }
        // The descriptor belongs to the source and is closed when the source is canceled.
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        watcher = source
    }

    // handleFileEvent(events): Fold a burst of events into one callback after a short delay, and
    // re-arm the watcher first when the file was replaced.
    private func handleFileEvent(_ events: DispatchSource.FileSystemEvent) {
        // A save often arrives as several events; only the last one within 0.35 s is acted on.
        rearmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // An atomic save replaces the file, so the watcher must follow the new one.
                if events.contains(.delete) || events.contains(.rename) { self.startWatching() }
                self.onExternalChange?()
            }
        }
        rearmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // suspendWatcher(): Pause event delivery during the app's own write.
    private func suspendWatcher() {
        watcher?.suspend()
    }

    // resumeWatcher(): Discard the paused watcher and start a new one on the freshly written file.
    private func resumeWatcher() {
        // The app's own save also replaces the file, so the watcher is reset instead of resumed.
        // A suspended source must be resumed before it can be canceled.
        if let watcher {
            watcher.resume()
            watcher.cancel()
        }
        watcher = nil
        startWatching()
    }

    // stopWatching(): Cancel the watcher and any pending callback; the cancel handler closes the
    // descriptor.
    private func stopWatching() {
        rearmWork?.cancel()
        rearmWork = nil
        watcher?.cancel()
        watcher = nil
        watcherDescriptor = -1
    }
}
