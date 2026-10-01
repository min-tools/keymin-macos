import Foundation

/// Best-effort skhd detection inside the App Sandbox, using file-existence checks
/// and process names from sysctl. Denied or unavailable queries look like missing
/// files or processes. No file contents are read and no daemon is launched or signaled.
struct SkhdPresence: Equatable {
    enum Status: Equatable {
        /// A process named skhd is running.
        case running
        /// A program or launch agent was found, but no running process was detected.
        case installed
        /// Nothing was found at the usual places.
        case missing
    }

    /// The first program found, shown so the user knows which install Keymin saw.
    var programPath: String?
    /// A launch agent for skhd exists in the user's LaunchAgents folder.
    var serviceInstalled = false
    /// A process named skhd is in the process list.
    var isRunning = false

    var status: Status {
        // Running outranks whatever files were found.
        if isRunning { return .running }
        return programPath != nil || serviceInstalled ? .installed : .missing
    }

    /// The process name both skhd and skhd.zig run under.
    static let processName = "skhd"

    // scan(): Look at this Mac's file system, PATH, and process list.
    static func scan() -> SkhdPresence {
        scan(
            home: ConfigStore.realHomeDirectory.path,
            searchPath: ProcessInfo.processInfo.environment["PATH"],
            exists: { FileManager.default.fileExists(atPath: $0) },
            runningProcessNames: SkhdProcessList.names()
        )
    }

    // scan(home, searchPath, exists, runningProcessNames): The pure part of scan(), so tests can
    // supply existence checks and process names. A nil searchPath adds no PATH entries.
    static func scan(home: String, searchPath: String?, exists: (String) -> Bool, runningProcessNames: [String]) -> SkhdPresence {
        SkhdPresence(
            programPath: programCandidates(home: home, searchPath: searchPath).first(where: exists),
            serviceInstalled: serviceCandidates(home: home).contains(where: exists),
            isRunning: runningProcessNames.contains(processName)
        )
    }

    // programCandidates(home, searchPath): Where the two projects put the `skhd` program: Homebrew
    // on Apple silicon and Intel, MacPorts, skhd.zig's app bundle, hand-made installs in the home
    // directory, and whatever the app's own PATH lists.
    // A nil searchPath limits the result to the known installation locations.
    static func programCandidates(home: String, searchPath: String?) -> [String] {
        var directories = [
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
            "/Applications/skhd.app/Contents/MacOS", home + "/Applications/skhd.app/Contents/MacOS",
            home + "/.local/bin", home + "/bin",
        ]
        // PATH entries come last, so a well-known location wins as the displayed path.
        for entry in (searchPath ?? "").split(separator: ":") where !entry.isEmpty {
            directories.append(String(entry))
        }
        // Drop repeats, keeping the first occurrence's position.
        var seen = Set<String>()
        return directories.filter { seen.insert($0).inserted }.map { $0 + "/" + processName }
    }

    // serviceCandidates(home): Launch agents written by skhd's `--install-service`, the original
    // koekeishiya skhd, Homebrew services, and skhd.zig before it moved to SMAppService.
    static func serviceCandidates(home: String) -> [String] {
        ["com.asmvik.skhd", "com.koekeishiya.skhd", "homebrew.mxcl.skhd", "com.jackielii.skhd"]
            .map { home + "/Library/LaunchAgents/" + $0 + ".plist" }
    }
}

/// The names of running processes, read with `sysctl kern.proc.all`. Only the short command
/// name of each process is used, and nothing is kept.
enum SkhdProcessList {
    // names(): Read the process table with sysctl and return each process's short command name.
    static func names() -> [String] {
        // The first call only reports how large the table is.
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&request, UInt32(request.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Processes can start between the two calls, so ask for a little more than reported.
        let stride = MemoryLayout<kinfo_proc>.stride
        var entries = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 16)
        size = entries.count * stride
        guard sysctl(&request, UInt32(request.count), &entries, &size, nil, 0) == 0 else { return [] }
        // The kernel reports how much it filled; p_comm is a fixed C array, read as a C string.
        return entries.prefix(size / stride).map { entry in
            withUnsafePointer(to: entry.kp_proc.p_comm) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
            }
        }
    }
}
