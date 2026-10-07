import Foundation

/// Link resolution and link-preserving writes, checked on a dotfiles layout built under the
/// empty directory given on the command line. Usage: tests <directory>
@main
struct ConfigStoreTests {
    static var checks = 0

    // check(condition, message): Stop at the first failed check with its message; count the rest.
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }

    // isSymbolicLink(url): True when the path itself is a link, without following it.
    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    // mode(url): The POSIX permission bits, or -1 when they cannot be read.
    static func mode(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? -1
    }

    // main(): Build the fixture layout, then check resolution, both write paths, ~ display, and
    // reading a file that starts with a byte order mark.
    @MainActor static func main() throws {
        // Two trees: a dotfiles repository with the real file, and a home directory linking to it.
        let manager = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let repository = root.appendingPathComponent("dotfiles/.config/skhd", isDirectory: true)
        let home = root.appendingPathComponent("home/.config/skhd", isDirectory: true)
        try manager.createDirectory(at: repository, withIntermediateDirectories: true)
        try manager.createDirectory(at: home, withIntermediateDirectories: true)

        // A dotfiles layout: ~/.config/skhd/skhdrc -> link -> repository file with strict permissions.
        let target = repository.appendingPathComponent("skhdrc")
        try Data("cmd - a : echo a\n".utf8).write(to: target)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let middle = root.appendingPathComponent("dotfiles/skhdrc-link")
        try manager.createSymbolicLink(atPath: middle.path, withDestinationPath: ".config/skhd/skhdrc")
        let chosen = home.appendingPathComponent("skhdrc")
        try manager.createSymbolicLink(atPath: chosen.path, withDestinationPath: "../../../dotfiles/skhdrc-link")

        // Links are followed hop by hop, including relative destinations.
        let resolved = ConfigStore.resolveLink(chosen)
        check(resolved.path == target.resolvingSymlinksInPath().path, "Two relative hops resolve to the repository file: \(resolved.path)")
        check(ConfigStore.resolveLink(target).path == target.resolvingSymlinksInPath().path, "A regular file resolves to itself")

        // Saving replaces the target's contents while every link survives and the mode is kept.
        try ConfigStore.replaceAtomically(Data("cmd - b : echo b\n".utf8), at: resolved)
        check(isSymbolicLink(chosen) && isSymbolicLink(middle), "Atomic replacement keeps the links")
        let replaced = try String(contentsOf: chosen, encoding: .utf8)
        check(replaced == "cmd - b : echo b\n", "The target holds the new text")
        check(mode(target) == 0o600, "Atomic replacement keeps the file mode: \(mode(target))")

        // The in-place fallback also writes through the link without replacing it.
        try Data("cmd - c : echo c\n".utf8).write(to: chosen, options: [])
        check(isSymbolicLink(chosen), "In-place writes keep the link")
        let written = try String(contentsOf: target, encoding: .utf8)
        check(written == "cmd - c : echo c\n", "In-place writes reach the target")
        check(mode(target) == 0o600, "In-place writes keep the file mode")

        // The abbreviated path uses the real home directory.
        let homePath = ConfigStore.realHomeDirectory.path
        check(ConfigStore.abbreviate(homePath + "/.config/skhd/skhdrc") == "~/.config/skhd/skhdrc", "Home paths abbreviate to ~")
        check(ConfigStore.abbreviate("/etc/skhdrc") == "/etc/skhdrc", "Other paths are unchanged")
        check(ConfigStore.defaultDirectory.path == homePath + "/.config/skhd", "The default directory is skhd's")

        // Reading keeps a leading byte order mark, which skhd rejects, so the parser can report it.
        let marked = root.appendingPathComponent("marked-skhdrc")
        try Data([0xEF, 0xBB, 0xBF] + Array("alt - a : echo a\n".utf8)).write(to: marked)
        let store = ConfigStore()
        store.adoptWithoutBookmark(marked)
        let markedText = try store.read()
        check(markedText == "\u{FEFF}alt - a : echo a\n", "Reading keeps a leading byte order mark: \(markedText.debugDescription)")

        print("Keymin config store: \(checks) link and write checks passed")
    }
}
