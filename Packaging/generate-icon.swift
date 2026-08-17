import AppKit

let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconsetDir = scriptDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colors = [
        NSColor(calibratedRed: 0.34, green: 0.55, blue: 0.95, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.11, green: 0.22, blue: 0.52, alpha: 1.0).cgColor
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    ctx.restoreGState()

    // Subtle top highlight for depth
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor.white.withAlphaComponent(0.16).cgColor, NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(highlight, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: size * 0.45), options: [])
    ctx.restoreGState()

    // Terminal glyph, centered
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let symbolRect = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        symbolRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let drawSize = symbol.size
        let origin = CGPoint(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2)
        tinted.draw(in: CGRect(origin: origin, size: drawSize))
    }

    image.unlockFocus()
    return image
}

for (name, px) in sizes {
    let img = drawIcon(size: px)
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(name)")
    }
    let outURL = iconsetDir.appendingPathComponent("\(name).png")
    try! png.write(to: outURL)
    print("Wrote \(outURL.lastPathComponent)")
}
