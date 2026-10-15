import AppKit
import SwiftUI

// Compiled with every app source except KeyminApp.swift, which owns this name.
extension Notification.Name {
    static let recordShortcut = Notification.Name("tools.min.keymin.record-shortcut")
}

/// Renders the README hero images and the Mac App Store screenshots: the main window with the
/// fictional hero configuration loaded, drawn offscreen at 2x with the real title bar, active
/// traffic lights, and a window shadow.
///
/// Usage: render-hero <hero.skhdrc> <output directory> <scratch directory> [--app-store <directory>]
@main
enum RenderHero {
    // Window sizes in points for the README and the App Store, the canvas margin that holds the
    // README shadow, and its corner radius. The App Store window is taller so a scrolled editor
    // shows its Action switcher, and wider so every modifier chip has room.
    static let windowSize = NSSize(width: 1000, height: 650)
    static let appStoreWindowSize = NSSize(width: 1060, height: 720)
    static let margin: CGFloat = 56
    static let cornerRadius: CGFloat = 10

    /// A Mac App Store screenshot: the page and binding to show, whether the editor is scrolled
    /// to its end, the appearance, and the caption.
    struct Screenshot {
        let file: String
        let dark: Bool
        let page: AppModel.Page
        let bindingTitle: String?
        let scrollsEditorToEnd: Bool
        let caption: HeroCanvas.Caption
    }

    // The App Store set, in listing order: the editor, per-app commands, modes, and the source.
    static let screenshots = [
        Screenshot(
            file: "keymin-1-shortcuts-light.png", dark: false, page: .binding,
            bindingTitle: "Focus Safari", scrollsEditorToEnd: false,
            caption: HeroCanvas.Caption(
                headline: "Hotkeys for skhd, without the syntax.",
                subtitle: "Pick the keys, name the shortcut, and Keymin writes the line."
            )
        ),
        Screenshot(
            file: "keymin-2-per-app-dark.png", dark: true, page: .binding,
            bindingTitle: "Jump to the address bar in every browser", scrollsEditorToEnd: true,
            caption: HeroCanvas.Caption(
                headline: "One shortcut, a different command in each app.",
                subtitle: "Per-app commands, pass-through, and mode switches from a form."
            )
        ),
        Screenshot(
            file: "keymin-3-modes-light.png", dark: false, page: .modes,
            bindingTitle: nil, scrollsEditorToEnd: false,
            caption: HeroCanvas.Caption(
                headline: "Group shortcuts into modes.",
                subtitle: "Enter a layer with one key and leave it with Escape."
            )
        ),
        Screenshot(
            file: "keymin-4-source-dark.png", dark: true, page: .source,
            bindingTitle: nil, scrollsEditorToEnd: false,
            caption: HeroCanvas.Caption(
                headline: "The file stays yours.",
                subtitle: "Every change is plain skhd text you can read, edit, and apply."
            )
        ),
    ]

    // main(): Stage the fixture in a scratch home, load it into the model, and write the images.
    @MainActor static func main() {
        setvbuf(stdout, nil, _IONBF, 0)
        var arguments = Array(CommandLine.arguments.dropFirst())
        let usage = "usage: render-hero <hero.skhdrc> <output directory> <scratch directory> [--app-store <directory>]"
        guard arguments.count >= 3 else {
            print(usage)
            exit(2)
        }
        let fixture = URL(fileURLWithPath: arguments.removeFirst()).standardizedFileURL
        let output = URL(fileURLWithPath: arguments.removeFirst(), isDirectory: true)
        let scratch = URL(fileURLWithPath: arguments.removeFirst(), isDirectory: true)
        var appStore: URL?
        if arguments.first == "--app-store", arguments.count == 2 {
            appStore = URL(fileURLWithPath: arguments[1], isDirectory: true)
        } else if !arguments.isEmpty {
            print(usage)
            exit(2)
        }
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

        // The README heroes show the Focus Safari binding in the editor.
        show(page: .binding, bindingTitle: "Focus Safari", in: model)
        for dark in [false, true] {
            let name = dark ? "hero-dark.png" : "hero-light.png"
            HeroCanvas.write(render(model: model, dark: dark), to: output.appendingPathComponent(name))
        }

        // The App Store set at 2880x1800, each scene over the wallpaper with its caption.
        if let appStore {
            try? FileManager.default.createDirectory(at: appStore, withIntermediateDirectories: true)
            for screenshot in screenshots {
                show(page: screenshot.page, bindingTitle: screenshot.bindingTitle, in: model)
                let window = capture(
                    model: model, dark: screenshot.dark, size: appStoreWindowSize,
                    scrollsEditorToEnd: screenshot.scrollsEditorToEnd
                )
                let canvas = HeroCanvas.appStoreScreenshot(
                    window: window, windowSize: window.size, caption: screenshot.caption, dark: screenshot.dark
                )
                HeroCanvas.write(HeroCanvas.png(canvas), to: appStore.appendingPathComponent(screenshot.file))
            }
        }
    }

    // show(page, bindingTitle, in model): Select the named binding, if any, and open the page.
    @MainActor static func show(page: AppModel.Page, bindingTitle: String?, in model: AppModel) {
        if let bindingTitle {
            guard let binding = model.document.hotkeys.first(where: { $0.title == bindingTitle }) else {
                print("no binding titled \(bindingTitle)")
                exit(1)
            }
            model.select(binding.id)
        }
        model.page = page
    }

    // capture(model, dark, size, scrollsEditorToEnd): Host the root view in an offscreen window
    // of the given content size in the requested appearance and draw its frame view, title bar
    // included, into a 2x bitmap.
    @MainActor static func capture(model: AppModel, dark: Bool, size: NSSize, scrollsEditorToEnd: Bool) -> NSBitmapImageRep {
        // An offscreen window in the requested appearance; a short run loop lets SwiftUI lay out.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // The window is closed after capture while this function still holds it.
        window.isReleasedWhenClosed = false
        window.title = "Keymin"
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: RootView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        if scrollsEditorToEnd {
            scrollEditorToEnd(in: host)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        }

        // The frame view draws the title bar and content together, as the window looks on screen.
        guard let frameView = window.contentView?.superview else { fatalError("no window frame view") }
        let frameRect = frameView.bounds
        let frameImage = HeroCanvas.bitmap(size: frameRect.size)
        frameView.cacheDisplay(in: frameRect, to: frameImage)
        overdrawTrafficLights(of: window, in: frameView, onto: frameImage)
        window.close()
        return frameImage
    }

    // scrollEditorToEnd(in host): Scroll the editor, the largest scroll view right of the sidebar,
    // to its last content, so a binding's Action section is in view.
    @MainActor static func scrollEditorToEnd(in host: NSView) {
        let editors = scrollViews(in: host).filter { $0.convert($0.bounds, to: host).minX >= 320 }
        guard let editor = editors.max(by: { $0.bounds.height < $1.bounds.height }),
              let document = editor.documentView else {
            print("no editor scroll view to scroll")
            return
        }
        let overflow = max(0, document.frame.height - editor.contentView.bounds.height)
        // A flipped document scrolls down by raising y; an unflipped one by lowering it.
        editor.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? overflow : 0))
        editor.reflectScrolledClipView(editor.contentView)
    }

    // scrollViews(in view): Every scroll view in the hierarchy, depth first.
    static func scrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scrollView = view as? NSScrollView { found.append(scrollView) }
        for subview in view.subviews { found += scrollViews(in: subview) }
        return found
    }

    // render(model, dark): Draw the window into a bitmap, compose it with a shadow and hairline on
    // a transparent canvas, and return the PNG data.
    @MainActor static func render(model: AppModel, dark: Bool) -> Data {
        let frameImage = capture(model: model, dark: dark, size: windowSize, scrollsEditorToEnd: false)
        let frameRect = NSRect(origin: .zero, size: frameImage.size)

        // A canvas with room for the shadow; all drawing goes through its bitmap context.
        let canvasSize = NSSize(width: frameRect.width + margin * 2, height: frameRect.height + margin * 2)
        let canvas = HeroCanvas.bitmap(size: canvasSize)
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
