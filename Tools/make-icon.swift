// Regenerates App/AppIcon.icns. Run: ./Tools/make-icon.swift

import AppKit

let sizes: [(name: String, pixels: Int)] = [
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

func icon(pixels: Int) -> Data {
    let side = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = side * 0.09
    let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let platePath = NSBezierPath(
        roundedRect: plate,
        xRadius: plate.width * 0.23,
        yRadius: plate.width * 0.23
    )
    NSGradient(
        colors: [
            NSColor(srgbRed: 0.35, green: 0.30, blue: 0.90, alpha: 1),
            NSColor(srgbRed: 0.16, green: 0.51, blue: 0.96, alpha: 1)
        ]
    )!.draw(in: platePath, angle: -90)

    // A chart where one bar has run over: colour carries the limit, no crossbar to read as a cross.
    let field = plate.insetBy(dx: plate.width * 0.16, dy: plate.height * 0.19)
    let heights: [CGFloat] = [0.50, 0.82, 0.58, 1.0]
    let overIndex = 3

    let barWidth = field.width * 0.17
    let gap = (field.width - barWidth * CGFloat(heights.count)) / CGFloat(heights.count - 1)

    for (index, height) in heights.enumerated() {
        let x = field.minX + CGFloat(index) * (barWidth + gap)
        let bar = NSRect(x: x, y: field.minY, width: barWidth, height: field.height * height)
        if index == overIndex {
            // Lifted towards coral: a deeper red sits too close to the plate in luminance.
            NSColor(srgbRed: 1.0, green: 0.50, blue: 0.42, alpha: 1).setFill()
        } else {
            NSColor.white.setFill()
        }
        NSBezierPath(roundedRect: bar, xRadius: barWidth * 0.34, yRadius: barWidth * 0.34).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iconset = root.appending(path: "App/AppIcon.iconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in sizes {
    try icon(pixels: size.pixels).write(to: iconset.appending(path: "\(size.name).png"))
}

print("Wrote \(iconset.path)")
