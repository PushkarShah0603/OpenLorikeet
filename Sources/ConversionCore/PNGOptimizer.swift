import Foundation
import zlib

/// Recompress only the filtered IDAT bytes. Profiles, metadata, and pixel depth stay intact.
enum PNGOptimizer {
    static func optimize(_ data: Data) throws -> Data {
        let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        guard data.starts(with: signature) else { throw WorkerError.invalidInput }
        var offset = 8, compressed = Data(), chunks: [(String, Range<Int>)] = []
        var ended = false
        while offset + 12 <= data.count {
            try Task.checkCancellation()
            let length = data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard chunks.count < 100_000, length <= data.count - offset - 12,
                  let type = String(data: data[offset + 4..<offset + 8], encoding: .ascii) else { throw WorkerError.invalidInput }
            let payload = offset + 4..<offset + 8 + length
            let checksum = data[offset + 8 + length..<offset + 12 + length].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let actual = data.withUnsafeBytes { bytes in
                crc32(0, bytes.bindMemory(to: UInt8.self).baseAddress?.advanced(by: payload.lowerBound), uInt(payload.count))
            }
            guard checksum == UInt32(actual) else { throw WorkerError.invalidInput }
            if type == "IDAT" { compressed.append(data[offset + 8..<offset + 8 + length]) }
            chunks.append((type, offset..<offset + 12 + length))
            offset += 12 + length
            if type == "IEND" { ended = true; break }
        }
        guard ended, offset == data.count, !compressed.isEmpty, chunks.first?.0 == "IHDR",
              !chunks.contains(where: { $0.0 == "acTL" }) else { throw WorkerError.invalidInput }
        let packed = try recompress(compressed, limit: data.count)
        var result = signature
        var inserted = false
        for (type, chunk) in chunks {
            if type == "IDAT" {
                guard !inserted else { continue }
                inserted = true
                let name = Data("IDAT".utf8)
                let payload = name + packed
                let crc = payload.withUnsafeBytes {
                    crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(payload.count))
                }
                result.append(bigEndian(UInt32(packed.count)))
                result.append(payload)
                result.append(bigEndian(UInt32(crc)))
            } else {
                result.append(data[chunk])
            }
        }
        return result
    }

    private static func recompress(_ input: Data, limit: Int) throws -> Data {
        let blockSize = 64 * 1024
        var decoder = z_stream(), encoder = z_stream()
        let streamSize = Int32(MemoryLayout<z_stream>.size)
        guard inflateInit_(&decoder, zlibVersion(), streamSize) == Z_OK else { throw WorkerError.invalidInput }
        defer { inflateEnd(&decoder) }
        guard deflateInit_(&encoder, Z_BEST_COMPRESSION, zlibVersion(), streamSize) == Z_OK else {
            throw WorkerError.invalidOutput
        }
        defer { deflateEnd(&encoder) }

        var result = Data()
        var raw = [UInt8](repeating: 0, count: blockSize)
        var packed = [UInt8](repeating: 0, count: blockSize)

        func encode(_ bytes: UnsafeMutablePointer<UInt8>?, count: Int, finish: Bool) throws {
            encoder.next_in = bytes
            encoder.avail_in = uInt(count)
            repeat {
                try Task.checkCancellation()
                let code = packed.withUnsafeMutableBufferPointer { buffer in
                    encoder.next_out = buffer.baseAddress
                    encoder.avail_out = uInt(blockSize)
                    return deflate(&encoder, finish ? Z_FINISH : Z_NO_FLUSH)
                }
                guard code == Z_OK || code == Z_STREAM_END else { throw WorkerError.invalidOutput }
                let written = blockSize - Int(encoder.avail_out)
                guard result.count + written <= limit else {
                    throw WorkerError.engineUnavailable("The image is already optimized at these settings.")
                }
                result.append(contentsOf: packed.prefix(written))
                if code == Z_STREAM_END { return }
            } while finish || encoder.avail_in > 0
        }

        try input.withUnsafeBytes { source in
            decoder.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress)
            decoder.avail_in = uInt(input.count)
            while true {
                try Task.checkCancellation()
                let code = try raw.withUnsafeMutableBufferPointer { buffer in
                    decoder.next_out = buffer.baseAddress
                    decoder.avail_out = uInt(blockSize)
                    let code = inflate(&decoder, Z_NO_FLUSH)
                    guard code == Z_OK || code == Z_STREAM_END,
                          decoder.total_out <= 520 * 1024 * 1024 else { throw WorkerError.invalidInput }
                    let count = blockSize - Int(decoder.avail_out)
                    if count > 0 { try encode(buffer.baseAddress, count: count, finish: false) }
                    return code
                }
                if code == Z_STREAM_END { break }
            }
            guard decoder.avail_in == 0 else { throw WorkerError.invalidInput }
        }
        try encode(nil, count: 0, finish: true)
        return result
    }

    private static func bigEndian(_ number: UInt32) -> Data {
        var value = number.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}
