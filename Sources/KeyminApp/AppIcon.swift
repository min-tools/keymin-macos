import AppKit

/// The app icon as an image, used for the Dock icon and the welcome screen.
enum AppIcon {
    // make([size = 128]): The bundled icon when resources are present, at its own size; otherwise
    // a drawn stand-in of the given size, for isolated source fixtures without resources.
    static func make(size: CGFloat = 128) -> NSImage {
        // Use the bundled icon for shipped builds and previews that include resources.
        if let url = AppResources.resourcesURL?.appendingPathComponent("KeyminIcon.icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // Keep a development fallback for isolated source fixtures without bundled resources:
        // a rounded accent-colored square with a white keyboard symbol.
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                     xRadius: size * 0.23, yRadius: size * 0.23).fill()
        // The command symbol is only a fallback for a symbol set without the keyboard glyph.
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keymin")?
            .withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: "command", accessibilityDescription: "Keymin")!
        symbol.draw(in: NSRect(x: size * 0.2, y: size * 0.26, width: size * 0.6, height: size * 0.48))
        image.unlockFocus()
        return image
    }
}
