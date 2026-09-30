import Foundation

/// A feature the Free tier does not include, named when the Pro panel opens. The raw value is the
/// English phrase that completes the panel's "Unlock …" sentence; it is localized before display.
enum KeyminProFeature: String {
    /// Editing bindings beyond the Free tier's limit.
    case allBindings = "every binding"
    /// The Source page, which edits the whole configuration as text.
    case sourceEditing = "the Source page"
}
