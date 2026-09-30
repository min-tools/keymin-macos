import Foundation

/// Build-time identity and access switches. The identity is shared by public, App Store, and
/// private local builds; the flags below choose the trial and unlock rules.
enum KeyminEdition {
    static let bundleIdentifier = "tools.min.keymin"
    static let displayName = "Keymin"

    #if KEYMIN_APP_STORE
    // App Store builds resolve the trial clock through verified app transactions.
    static let isAppStoreBuild = true
    #else
    // Non-Store builds do not use Apple's signed acquisition date.
    static let isAppStoreBuild = false
    #endif

    // Only the ignored private input can bypass verified access locally. Every branch defines the
    // same four values: localProAccess (nil means the normal rules apply), localAccessStatus (the
    // panel's status text in unlocked builds), forcedTrialStartedAt (a trial start that is never
    // written to preferences), and isExpiredTrialPreview.
    #if KEYMIN_LOCAL_BUILD && KEYMIN_APP_STORE
    // Refuse an archive that combines distribution code with a local unlock.
    #error("Local access must not be included in an App Store build.")
    #elseif KEYMIN_LOCAL_BUILD && KEYMIN_EXPIRED_TRIAL_BUILD
    // Preview the public post-trial state without granting local Pro access.
    static let localProAccess: Bool? = nil
    static let localAccessStatus: String? = nil
    static let forcedTrialStartedAt: Date? = KeyminLocalAccess.expiredTrialStartedAt
    static let isExpiredTrialPreview = true
    #elseif KEYMIN_LOCAL_BUILD
    // The everyday Unlocked build: Pro on, trial and StoreKit skipped.
    static let localProAccess: Bool? = KeyminLocalAccess.isPro
    static let localAccessStatus: String? = KeyminLocalAccess.status
    static let forcedTrialStartedAt: Date? = nil
    static let isExpiredTrialPreview = false
    #else
    // Public source and App Store builds use the normal trial and purchase rules.
    static let localProAccess: Bool? = nil
    static let localAccessStatus: String? = nil
    static let forcedTrialStartedAt: Date? = nil
    static let isExpiredTrialPreview = false
    #endif
}

/// Pages the app links to. The release checker's online mode verifies that the website, privacy,
/// terms, and support pages are reachable.
enum AppLinks {
    static let website = URL(string: "https://min.tools/keymin/")!
    static let privacyPolicy = URL(string: "https://min.tools/keymin/privacy/")!
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let support = URL(string: "https://min.tools/keymin/support/")!
    static let skhd = URL(string: "https://github.com/asmvik/skhd")!
    static let skhdZig = URL(string: "https://github.com/jackielii/skhd.zig")!
}
