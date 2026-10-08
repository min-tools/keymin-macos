import Foundation

/// Checks of the first screen's skhd detection: the candidate paths, the status decision, and the
/// live process list.
@main
struct SkhdPresenceTests {
    static var checks = 0

    // check(condition, message): Stop at the first failed check with its message; count the rest.
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }

    // scan(existing, [running = []], [searchPath = nil]): Run the pure scan for a fake home where
    // only the listed paths exist.
    static func scan(existing: Set<String>, running: [String] = [], searchPath: String? = nil) -> SkhdPresence {
        SkhdPresence.scan(home: "/Users/test", searchPath: searchPath, exists: { existing.contains($0) }, runningProcessNames: running)
    }

    // main(): Check the candidate lists, each status outcome, and the real process list.
    static func main() {
        // The usual install places of both projects are covered, in a stable order, once each.
        let candidates = SkhdPresence.programCandidates(home: "/Users/test", searchPath: "/usr/local/bin:/Users/test/tools::/opt/homebrew/bin")
        check(candidates.first == "/opt/homebrew/bin/skhd", "Homebrew on Apple silicon is checked first")
        check(candidates.contains("/usr/local/bin/skhd"), "Homebrew on Intel and manual installs are checked")
        check(candidates.contains("/Applications/skhd.app/Contents/MacOS/skhd"), "skhd.zig's app bundle is checked")
        check(candidates.contains("/Users/test/.local/bin/skhd"), "Installs in the home directory are checked")
        check(candidates.contains("/Users/test/tools/skhd"), "Directories from the app's PATH are checked")
        check(Set(candidates).count == candidates.count, "PATH entries already in the list are not repeated")
        check(!candidates.contains("/skhd"), "Empty PATH entries are ignored")

        let services = SkhdPresence.serviceCandidates(home: "/Users/test")
        check(services.contains("/Users/test/Library/LaunchAgents/com.asmvik.skhd.plist"), "skhd's own launch agent is checked")
        check(services.contains("/Users/test/Library/LaunchAgents/com.jackielii.skhd.plist"), "skhd.zig's legacy launch agent is checked")
        check(services.allSatisfy { $0.hasPrefix("/Users/test/Library/LaunchAgents/") }, "Only the user's launch agents are checked")

        // Nothing found anywhere.
        let missing = scan(existing: [])
        check(missing.status == .missing && missing.programPath == nil, "No program, agent, or process means skhd is missing")

        // A program without a process is installed but stopped.
        let stopped = scan(existing: ["/usr/local/bin/skhd"])
        check(stopped.status == .installed, "A program without a running process is installed")
        check(stopped.programPath == "/usr/local/bin/skhd", "The program that was found is reported")

        // A launch agent alone also counts as installed.
        let agentOnly = scan(existing: ["/Users/test/Library/LaunchAgents/com.asmvik.skhd.plist"])
        check(agentOnly.status == .installed && agentOnly.programPath == nil && agentOnly.serviceInstalled, "A launch agent without a program is installed")

        // A running process wins even when nothing was found on disk, and names must match exactly.
        check(scan(existing: [], running: ["launchd", "skhd"]).status == .running, "A running skhd process is reported as running")
        check(scan(existing: [], running: ["skhd-helper", "myskhd"]).status == .missing, "Other process names do not count")
        let both = scan(existing: ["/opt/homebrew/bin/skhd"], running: ["skhd"])
        check(both.status == .running && both.programPath == "/opt/homebrew/bin/skhd", "Running keeps the program path for display")

        // The process list really comes from the kernel: this test binary is in it.
        let names = SkhdProcessList.names()
        let own = String(ProcessInfo.processInfo.processName.prefix(Int(MAXCOMLEN)))
        check(names.contains(own), "The process list includes this process (\(own))")
        check(names.contains("launchd"), "The process list includes launchd")

        print("\(checks) skhd presence checks passed")
    }
}
