import AppKit
import Foundation

// Rasterize the supplied artwork at the exact icon representation sizes.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
guard let artwork = NSImage(contentsOfFile: CommandLine.arguments[2]) else {
    fatalError("Could not load OpenLorikeet icon artwork")
}
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
        context.imageInterpolation = .high
        artwork.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
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
