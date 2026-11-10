import AppKit
import Foundation

// Temporary vector-drawn icon; replace with approved branding in phase 17.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Could not allocate placeholder icon")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.20, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: Double(pixels) * 0.04, dy: Double(pixels) * 0.04),
                     xRadius: Double(pixels) * 0.22, yRadius: Double(pixels) * 0.22).fill()
        let label = "OL" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: Double(pixels) * 0.43),
            .foregroundColor: NSColor(calibratedRed: 0.4, green: 0.9, blue: 0.45, alpha: 1),
        ]
        let textSize = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: (Double(pixels) - textSize.width) / 2,
                               y: (Double(pixels) - textSize.height) / 2), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not render placeholder icon")
        }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
// ICNS stores PNG representations in typed, big-endian length-prefixed chunks.
// Write the container directly so packaging needs no iconutil image decoder.
func bigEndianBytes(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}
let representations = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
    ("ic11", "icon_16x16@2x.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic13", "icon_128x128@2x.png"), ("ic14", "icon_256x256@2x.png"),
]
var chunks = Data()
for (type, filename) in representations {
    let png = try Data(contentsOf: iconset.appendingPathComponent(filename))
    chunks.append(Data(type.utf8))
    chunks.append(bigEndianBytes(UInt32(png.count + 8)))
    chunks.append(png)
}
var container = Data("icns".utf8)
container.append(bigEndianBytes(UInt32(chunks.count + 8)))
container.append(chunks)
try container.write(to: output.appendingPathComponent("AppIcon.icns"), options: .atomic)
try FileManager.default.removeItem(at: iconset)
