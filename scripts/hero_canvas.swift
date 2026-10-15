import AppKit

/// Shared drawing for the marketing images of the min.tools apps: an original wallpaper, the
/// caption above a Mac App Store screenshot, a window with its shadow and corners, and PNG
/// output. Everything draws in points on 2x bitmaps through Core Graphics, which works inside a
/// sandbox where Core Image and screen capture do not. Each app keeps its own copy of this file.
enum HeroCanvas {
    static let scale: CGFloat = 2
    /// 2880x1800 pixels, one of the sizes App Store Connect accepts for Mac screenshots.
    static let appStoreSize = NSSize(width: 1440, height: 900)
    /// The corner radius of a titled window on macOS 26 and later.
    static let windowCornerRadius: CGFloat = 12

    /// The marketing text above a screenshot's window.
    struct Caption {
        let headline: String
        let subtitle: String
    }

    // MARK: Compositions

    // appStoreScreenshot(window, windowSize, caption, dark, [cornerRadius]): A full-bleed
    // wallpaper with the caption at the top and the window centered in the space below it. A
    // window too large for that space is drawn smaller, keeping its aspect ratio.
    static func appStoreScreenshot(
        window: NSBitmapImageRep, windowSize: NSSize, caption: Caption, dark: Bool,
        cornerRadius: CGFloat = windowCornerRadius
    ) -> NSBitmapImageRep {
        let canvasSize = appStoreSize
        let canvas = bitmap(size: canvasSize)
        draw(into: canvas) { cg in
            drawWallpaper(in: cg, size: canvasSize, dark: dark)
            let captionBottom = drawCaption(caption, canvasSize: canvasSize, dark: dark)
            // The window sits centered between the caption and the bottom margin.
            let regionTop = captionBottom + 28
            let regionHeight = canvasSize.height - regionTop - 48
            let fit = min(1, regionHeight / windowSize.height, (canvasSize.width - 120) / windowSize.width)
            let size = NSSize(width: (windowSize.width * fit).rounded(), height: (windowSize.height * fit).rounded())
            let origin = NSPoint(
                x: ((canvasSize.width - size.width) / 2).rounded(),
                y: (canvasSize.height - regionTop - (regionHeight + size.height) / 2).rounded()
            )
            drawWindow(in: cg, image: window, at: origin, size: size, cornerRadius: cornerRadius * fit, dark: dark)
        }
        return canvas
    }

    // drawWindow(in cg, image, at origin, size, cornerRadius, dark): A captured window on the
    // canvas: a soft shadow below it, the image clipped to its corners, and the hairline macOS
    // draws around every window.
    static func drawWindow(
        in cg: CGContext, image: NSBitmapImageRep, at origin: NSPoint, size: NSSize,
        cornerRadius: CGFloat, dark: Bool
    ) {
        let rect = CGRect(origin: origin, size: size)
        let shape = continuousRoundedRect(rect, radius: cornerRadius)

        // A key window's shadow: soft, large, and slightly below the window.
        cg.saveGState()
        cg.setShadow(
            offset: CGSize(width: 0, height: -22), blur: 60,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: dark ? 0.55 : 0.32)
        )
        cg.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        cg.addPath(shape)
        cg.fillPath()
        cg.restoreGState()

        // Core Graphics composites source-over; NSBitmapImageRep.draw would copy transparency.
        guard let content = image.cgImage else { fatalError("no window image") }
        cg.saveGState()
        cg.addPath(shape)
        cg.clip()
        cg.interpolationQuality = .high
        cg.draw(content, in: rect)
        cg.restoreGState()

        cg.saveGState()
        cg.addPath(shape)
        cg.setLineWidth(0.5)
        cg.setStrokeColor(CGColor(gray: dark ? 1 : 0, alpha: dark ? 0.22 : 0.28))
        cg.strokePath()
        cg.restoreGState()
    }

    // drawCaption(caption, canvasSize, dark): Centered marketing text at the top of the canvas.
    // Returns how far down from the top the text reaches, in points.
    @discardableResult
    static func drawCaption(_ caption: Caption, canvasSize: NSSize, dark: Bool) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let title = NSAttributedString(string: caption.headline, attributes: [
            .font: NSFont.systemFont(ofSize: 46, weight: .semibold),
            .foregroundColor: dark ? NSColor.white : NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
            .kern: -0.6,
            .paragraphStyle: paragraph,
        ])
        let detail = NSAttributedString(string: caption.subtitle, attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .regular),
            .foregroundColor: dark
                ? NSColor.white.withAlphaComponent(0.72)
                : NSColor(srgbRed: 0.24, green: 0.24, blue: 0.27, alpha: 0.9),
            .paragraphStyle: paragraph,
        ])
        // Rects are measured from the top of the canvas and converted to AppKit's bottom origin.
        let titleHeight = ceil(title.size().height)
        let detailHeight = ceil(detail.size().height)
        let titleTop: CGFloat = 60
        title.draw(in: NSRect(x: 0, y: canvasSize.height - titleTop - titleHeight, width: canvasSize.width, height: titleHeight))
        let detailTop = titleTop + titleHeight + 10
        detail.draw(in: NSRect(x: 0, y: canvasSize.height - detailTop - detailHeight, width: canvasSize.width, height: detailHeight))
        return detailTop + detailHeight
    }

    // drawWallpaper(in cg, size, dark): An original desktop background, a dusk or daylight
    // gradient with soft color fields.
    static func drawWallpaper(in cg: CGContext, size: NSSize, dark: Bool) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bounds = CGRect(origin: .zero, size: size)
        let base: [CGColor] = dark
            ? [CGColor(srgbRed: 0.05, green: 0.08, blue: 0.20, alpha: 1), CGColor(srgbRed: 0.12, green: 0.06, blue: 0.24, alpha: 1)]
            : [CGColor(srgbRed: 0.90, green: 0.93, blue: 0.98, alpha: 1), CGColor(srgbRed: 0.96, green: 0.91, blue: 0.95, alpha: 1)]
        let gradient = CGGradient(colorsSpace: space, colors: base as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])

        // Color fields as unit positions, radii relative to the width, and peak alpha.
        let fields: [(CGFloat, CGFloat, CGFloat, CGColor, CGFloat)] = dark
            ? [
                (0.16, 0.80, 0.55, CGColor(srgbRed: 0.18, green: 0.42, blue: 1.00, alpha: 1), 0.60),
                (0.86, 0.72, 0.52, CGColor(srgbRed: 0.49, green: 0.30, blue: 1.00, alpha: 1), 0.55),
                (0.74, 0.08, 0.48, CGColor(srgbRed: 1.00, green: 0.30, blue: 0.55, alpha: 1), 0.38),
                (0.22, 0.10, 0.50, CGColor(srgbRed: 0.10, green: 0.78, blue: 0.84, alpha: 1), 0.42),
            ]
            : [
                (0.14, 0.82, 0.55, CGColor(srgbRed: 0.49, green: 0.70, blue: 1.00, alpha: 1), 0.80),
                (0.86, 0.74, 0.52, CGColor(srgbRed: 0.78, green: 0.70, blue: 1.00, alpha: 1), 0.75),
                (0.74, 0.08, 0.48, CGColor(srgbRed: 1.00, green: 0.78, blue: 0.70, alpha: 1), 0.70),
                (0.22, 0.10, 0.50, CGColor(srgbRed: 0.62, green: 0.91, blue: 0.87, alpha: 1), 0.65),
            ]
        for (x, y, radius, color, alpha) in fields {
            let components = color.components ?? [0, 0, 0, 1]
            let stops = [alpha, alpha * 0.38, 0].map {
                CGColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: $0)
            }
            let field = CGGradient(colorsSpace: space, colors: stops as CFArray, locations: [0, 0.42, 1])!
            let center = CGPoint(x: bounds.width * x, y: bounds.height * y)
            // Slightly flattened fields read as light on a surface rather than spotlights.
            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y)
            cg.scaleBy(x: 1, y: 0.82)
            cg.drawRadialGradient(field, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: bounds.width * radius, options: [])
            cg.restoreGState()
        }
    }

    // MARK: Output

    // png(canvas, [scaledToWidth]): Encode a canvas, optionally resampled to a pixel width.
    static func png(_ canvas: NSBitmapImageRep, scaledToWidth width: CGFloat? = nil) -> Data {
        var rep = canvas
        if let width, let source = canvas.cgImage {
            let factor = width / CGFloat(source.width)
            let size = NSSize(width: width.rounded(), height: (CGFloat(source.height) * factor).rounded())
            let small = bitmap(size: size, scale: 1)
            draw(into: small) { cg in
                cg.interpolationQuality = .high
                cg.draw(source, in: CGRect(origin: .zero, size: size))
            }
            rep = small
        }
        guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
        return data
    }

    // write(data, to url): Save one image and stop on failure, so a half-finished set is noticed.
    static func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: [])
            print("wrote \(url.path)")
        } catch {
            print("could not write \(url.lastPathComponent): \(error)")
            exit(1)
        }
    }

    // MARK: Helpers

    // bitmap(size, [scale]): A transparent bitmap, 2x by default, whose point size matches the
    // drawing coordinates.
    static func bitmap(size: NSSize, scale: CGFloat = HeroCanvas.scale) -> NSBitmapImageRep {
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

    // draw(into canvas, body): Run drawing code with the canvas as the current context, so both
    // Core Graphics calls and AppKit string drawing land on it.
    static func draw(into canvas: NSBitmapImageRep, _ body: (CGContext) -> Void) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: canvas) else { fatalError("no drawing context") }
        NSGraphicsContext.current = context
        body(context.cgContext)
        context.flushGraphics()
    }

    // continuousRoundedRect(rect, radius): The corner curve macOS uses for windows and panels,
    // three cubic segments per corner that ease into the straight edges instead of an arc.
    static func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, rect.width / 3.06, rect.height / 3.06)
        let path = CGMutablePath()
        // Offsets along the edge from each corner, as fractions of the radius.
        let a: CGFloat = 1.528665 * r
        let b: CGFloat = 1.08849 * r
        let c: CGFloat = 0.868407 * r
        let d: CGFloat = 0.631494 * r
        let e: CGFloat = 0.372824 * r
        let f: CGFloat = 0.169060 * r
        let g: CGFloat = 0.074911 * r
        let (x0, x1, y0, y1) = (rect.minX, rect.maxX, rect.minY, rect.maxY)

        path.move(to: CGPoint(x: x0 + a, y: y1))
        path.addLine(to: CGPoint(x: x1 - a, y: y1))
        // Top right.
        path.addCurve(to: CGPoint(x: x1 - d, y: y1 - g), control1: CGPoint(x: x1 - b, y: y1), control2: CGPoint(x: x1 - c, y: y1))
        path.addCurve(to: CGPoint(x: x1 - g, y: y1 - d), control1: CGPoint(x: x1 - e, y: y1 - f), control2: CGPoint(x: x1 - f, y: y1 - e))
        path.addCurve(to: CGPoint(x: x1, y: y1 - a), control1: CGPoint(x: x1, y: y1 - c), control2: CGPoint(x: x1, y: y1 - b))
        path.addLine(to: CGPoint(x: x1, y: y0 + a))
        // Bottom right.
        path.addCurve(to: CGPoint(x: x1 - g, y: y0 + d), control1: CGPoint(x: x1, y: y0 + b), control2: CGPoint(x: x1, y: y0 + c))
        path.addCurve(to: CGPoint(x: x1 - d, y: y0 + g), control1: CGPoint(x: x1 - f, y: y0 + e), control2: CGPoint(x: x1 - e, y: y0 + f))
        path.addCurve(to: CGPoint(x: x1 - a, y: y0), control1: CGPoint(x: x1 - c, y: y0), control2: CGPoint(x: x1 - b, y: y0))
        path.addLine(to: CGPoint(x: x0 + a, y: y0))
        // Bottom left.
        path.addCurve(to: CGPoint(x: x0 + d, y: y0 + g), control1: CGPoint(x: x0 + b, y: y0), control2: CGPoint(x: x0 + c, y: y0))
        path.addCurve(to: CGPoint(x: x0 + g, y: y0 + d), control1: CGPoint(x: x0 + e, y: y0 + f), control2: CGPoint(x: x0 + f, y: y0 + e))
        path.addCurve(to: CGPoint(x: x0, y: y0 + a), control1: CGPoint(x: x0, y: y0 + c), control2: CGPoint(x: x0, y: y0 + b))
        path.addLine(to: CGPoint(x: x0, y: y1 - a))
        // Top left.
        path.addCurve(to: CGPoint(x: x0 + g, y: y1 - d), control1: CGPoint(x: x0, y: y1 - b), control2: CGPoint(x: x0, y: y1 - c))
        path.addCurve(to: CGPoint(x: x0 + d, y: y1 - g), control1: CGPoint(x: x0 + f, y: y1 - e), control2: CGPoint(x: x0 + e, y: y1 - f))
        path.addCurve(to: CGPoint(x: x0 + a, y: y1), control1: CGPoint(x: x0 + c, y: y1), control2: CGPoint(x: x0 + b, y: y1))
        path.closeSubpath()
        return path
    }
}
