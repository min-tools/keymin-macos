/// Checks that a public source or App Store build keeps the shared identity and the normal access
/// rules. Compiled with BuildEdition.swift alone. Usage: test [source|app-store], naming the flag
/// the binary was compiled with.
@main
struct EditionTests {
    // main(): Compare the compiled edition with the one named on the command line.
    static func main() {
        // The runner names the edition it compiled; a plain source build is the default.
        let expected = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "source"
        precondition(KeyminEdition.bundleIdentifier == "tools.min.keymin")
        precondition(KeyminEdition.displayName == "Keymin")
        precondition(KeyminEdition.isAppStoreBuild == (expected == "app-store"))
        // Local overrides must be absent from both public editions.
        precondition(KeyminEdition.localProAccess == nil)
        precondition(KeyminEdition.localAccessStatus == nil)
        precondition(KeyminEdition.forcedTrialStartedAt == nil)
        precondition(!KeyminEdition.isExpiredTrialPreview)
        precondition(AppLinks.privacyPolicy.host == "min.tools")
        precondition(AppLinks.termsOfUse.host == "www.apple.com")
        print("\(expected) build keeps the shared identity and normal access rules")
    }
}
