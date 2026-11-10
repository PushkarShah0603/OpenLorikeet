import Foundation
import CoreGraphics
import ImageIO
import zlib
import ConversionCore

func checkCompression() async throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("compress-check-\(UUID())")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }
    let input = folder.appendingPathComponent("Oversized PNG.png")
    func be(_ value: UInt32) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    func chunk(_ type: String, _ bytes: Data) -> Data {
        let payload = Data(type.utf8) + bytes
        let checksum = payload.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(payload.count)) }
        return be(UInt32(bytes.count)) + payload + be(UInt32(checksum))
    }
    // A valid flat 8-bit grayscale PNG encoded at zlib level zero.
    let width = 1_800, height = 320
    let row = Data([0]) + Data(repeating: 125, count: width)
    var raw = Data()
    for _ in 0..<height { raw.append(row) }
    var size = compressBound(uLong(raw.count))
    var packed = Data(count: Int(size))
    let result = packed.withUnsafeMutableBytes { dest in
        raw.withUnsafeBytes { src in
            compress2(dest.bindMemory(to: UInt8.self).baseAddress, &size,
                      src.bindMemory(to: UInt8.self).baseAddress, uLong(raw.count), Z_NO_COMPRESSION)
        }
    }
    check(result == Z_OK, "PNG fixture deflated")
    packed.count = Int(size)
    let header = be(UInt32(width)) + be(UInt32(height)) + Data([8, 0, 0, 0, 0])
    let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10]) + chunk("IHDR", header) +
        chunk("tEXt", Data("Comment\u{0000}Keep metadata".utf8)) + chunk("IDAT", packed) + chunk("IEND", Data())
    try bytes.write(to: input)
    let queue = ConversionQueue(registry: .local())
    let actions: [ConversionChoice] = [.compress, .fit500KB, .resize1600]
    let jobs = try actions.map { try ConversionRequest(inputs: [input], choice: $0) }
    await queue.submit(jobs)
    await queue.waitUntilIdle()
    let states = await queue.states(for: jobs.map(\.id))
    guard case .succeeded(let compressed) = states[0], case .succeeded(let fitted) = states[1],
          case .succeeded(let resized) = states[2] else { fatalError("Compression routes failed: \(states)") }
    let compressedData = try Data(contentsOf: compressed)
    check(compressedData.count < bytes.count && compressedData.range(of: Data("Keep metadata".utf8)) != nil, "Lossless PNG shrinks and preserves metadata")
    func decode(_ url: URL) -> CGImage {
        CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
    }
    check(decode(input).dataProvider?.data == decode(compressed).dataProvider?.data, "Lossless compression preserves decoded bytes")
    check((try Data(contentsOf: fitted)).count <= 500_000, "Target size met")
    check(decode(resized).width == 1_600, "Resize respects maximum edge")
    let repeatJob = try ConversionRequest(inputs: [fitted], choice: .fit500KB)
    await queue.submit([repeatJob])
    await queue.waitUntilIdle()
    guard case .failed(let message) = await queue.state(for: repeatJob.id) else { fatalError("Already-small image should not be replaced") }
    check(message.contains("already below"), "Already-small image yields a clear result")
    print("PASS: lossless PNG metadata/pixels, target-size cap, resizing, and already-small handling")
}
