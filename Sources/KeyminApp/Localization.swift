import Foundation

// localized(english): The translation of an English source string from Keymin's bundled strings,
// or the English text itself when there is none. The English text is the key, so SwiftUI literals
// and AppKit-created views share one localization catalog.
func localized(_ english: String) -> String {
    // The Swift Package build keeps resources in its own module bundle; the Xcode app uses the
    // main bundle.
    #if KEYMIN_SWIFTPM
    Bundle.module.localizedString(forKey: english, value: english, table: nil)
    #else
    // Xcode places the app's localization catalog in the main bundle.
    Bundle.main.localizedString(forKey: english, value: english, table: nil)
    #endif
}

// localizedFormat(english, arguments...): Format a localized printf-style string with the user's
// current number and date conventions.
func localizedFormat(_ english: String, _ arguments: CVarArg...) -> String {
    String(format: localized(english), locale: .current, arguments: arguments)
}

/// Locates bundled resources for both the Swift Package and Xcode layouts.
enum AppResources {
    /// The resource folder of the module bundle under SwiftPM, or of the main bundle in Xcode
    /// builds; nil when the bundle has no resources.
    static var resourcesURL: URL? {
        #if KEYMIN_SWIFTPM
        // SwiftPM packages processed resources in a separate module bundle.
        Bundle.module.resourceURL
        #else
        // The Xcode target copies resources into the application bundle.
        Bundle.main.resourceURL
        #endif
    }
}
