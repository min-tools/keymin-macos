import AppKit
import SwiftUI

// Compiled with every app source except KeyminApp.swift, which owns this name.
extension Notification.Name {
    static let recordShortcut = Notification.Name("tools.min.keymin.record-shortcut")
}

/// Renders the README hero images: the main window with the fictional hero configuration loaded,
/// drawn offscreen at 2x with the real title bar, active traffic lights, and a window shadow.
///
/// Usage: render-hero <hero.skhdrc> <output directory> <scratch directory>
@main
enum RenderHero {
    // Window size in points, output scale, canvas margin that holds the shadow, and corner radius.
    static let windowSize = NSSize(width: 1000, height: 650)
    static let scale: CGFloat = 2
    static let margin: CGFloat = 56
    static let cornerRadius: CGFloat = 10

    // main(): Stage the fixture in a scratch home, load it into the model, and write both images.
    @MainActor static func main() {
        setvbuf(stdout, nil, _IONBF, 0)
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            print("usage: render-hero <hero.skhdrc> <output directory> <scratch directory>")
            exit(2)
        }
        let fixture = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let scratch = URL(fileURLWithPath: arguments[3], isDirectory: true)
        NSApplication.shared.setActivationPolicy(.prohibited)

        // This process has its own defaults domain; anything the views store is removed at the end.
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }

        // Place the fixture where a user would keep it, inside a throwaway home directory, so the
        // header reads ~/.config/skhd/skhdrc.
        let home = scratch.appendingPathComponent("home", isDirectory: true)
        let configDirectory = home.appendingPathComponent(".config/skhd", isDirectory: true)
        let config = configDirectory.appendingPathComponent("skhdrc")
        defer { try? FileManager.default.removeItem(at: home) }
        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixture, to: config)
        } catch {
            print("could not stage the fixture: \(error)")
            exit(1)
        }
        ConfigStore.displayHomeOverride = home.standardizedFileURL.path

        // Open the fixture like a chosen file, without a bookmark, and report any diagnostics.
        let model = AppModel()
        model.store.adoptWithoutBookmark(config)
        guard model.fileState == .loaded else {
            print("the fixture did not load: \(model.fileState)")
            exit(1)
        }
        for diagnostic in model.diagnostics {
            print("fixture \(diagnostic.severity): \(diagnostic.message)")
        }
        // Select the binding the screenshots show in the editor.
        if let binding = model.document.hotkeys.first(where: { $0.title == "Focus Safari" }) {
            model.select(binding.id)
        }

        // Render the light and dark variants into the output directory.
        for dark in [false, true] {
            let name = dark ? "hero-dark.png" : "hero-light.png"
            let data = render(model: model, dark: dark)
            do {
                try data.write(to: output.appendingPathComponent(name))
                print("wrote \(name)")
            } catch {
                print("could not write \(name): \(error)")
                exit(1)
            }
        }
    }

    // render(model, dark): Draw the window into a bitmap, compose it with a shadow and hairline on
    // a transparent canvas, and return the PNG data.
    @MainActor static func render(model: AppModel, dark: Bool) -> Data {
        // An offscreen window in the requested appearance; a short run loop lets SwiftUI lay out.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Keymin"
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: RootView(model: model))
        host.frame = NSRect(origin: .zero, size: windowSize)
        window.contentView = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        // The frame view draws the title bar and content together, as the window looks on screen.
        guard let frameView = window.contentView?.superview else { fatalError("no window frame view") }
        let frameRect = frameView.bounds
        let frameImage = bitmap(size: frameRect.size)
        frameView.cacheDisplay(in: frameRect, to: frameImage)
        overdrawTrafficLights(of: window, in: frameView, onto: frameImage)
        window.close()

        // A canvas with room for the shadow; all drawing goes through its bitmap context.
        let canvasSize = NSSize(width: frameRect.width + margin * 2, height: frameRect.height + margin * 2)
        let canvas = bitmap(size: canvasSize)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: canvas) else { fatalError("no drawing context") }
        NSGraphicsContext.current = context
        let cg = context.cgContext
        let windowRect = NSRect(x: margin, y: margin, width: frameRect.width, height: frameRect.height)
        let shape = NSBezierPath(roundedRect: windowRect, xRadius: cornerRadius, yRadius: cornerRadius)

        // A key window's shadow: soft, large, and slightly below the window.
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 54, color: NSColor.black.withAlphaComponent(dark ? 0.62 : 0.45).cgColor)
        NSColor.black.setFill()
        shape.fill()
        cg.restoreGState()

        // The window image, clipped to its rounded corners.
        shape.addClip()
        frameImage.draw(in: windowRect)
        cg.resetClip()

        // The hairline macOS draws around every window.
        let border = NSBezierPath(roundedRect: windowRect.insetBy(dx: 0.25, dy: 0.25), xRadius: cornerRadius, yRadius: cornerRadius)
        border.lineWidth = 0.5
        (dark ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.28)).setStroke()
        border.stroke()

        guard let data = canvas.representation(using: .png, properties: [:]) else { fatalError("no png") }
        return data
    }

    // bitmap(size): A transparent 2x bitmap whose point size matches the drawing coordinates.
    static func bitmap(size: NSSize) -> NSBitmapImageRep {
        guard let image = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { fatalError("no bitmap") }
        image.size = size
        return image
    }

    // overdrawTrafficLights(of window, in frameView, onto image): Paint active button
    // colors onto the bitmap; AppKit draws this offscreen window's buttons gray.
    @MainActor static func overdrawTrafficLights(of window: NSWindow, in frameView: NSView, onto image: NSBitmapImageRep) {
        // Fill and edge colors of the close, minimize, and zoom buttons of a key window.
        let buttons: [(NSWindow.ButtonType, NSColor, NSColor)] = [
            (.closeButton, NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1), NSColor(srgbRed: 0.88, green: 0.28, blue: 0.25, alpha: 1)),
            (.miniaturizeButton, NSColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1), NSColor(srgbRed: 0.87, green: 0.62, blue: 0.11, alpha: 1)),
            (.zoomButton, NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1), NSColor(srgbRed: 0.11, green: 0.65, blue: 0.19, alpha: 1)),
        ]
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: image) else { return }
        NSGraphicsContext.current = context
        // Each button's frame is converted into the frame view, which the bitmap was drawn from.
        for (type, fill, stroke) in buttons {
            guard let button = window.standardWindowButton(type), let superview = button.superview else { continue }
            let frame = superview.convert(button.frame, to: frameView)
            let diameter: CGFloat = 12
            let circle = NSBezierPath(ovalIn: NSRect(x: frame.midX - diameter / 2, y: frame.midY - diameter / 2, width: diameter, height: diameter))
            fill.setFill()
            circle.fill()
            stroke.setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
        }
    }
}
