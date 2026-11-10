import Foundation
import zlib

/// Recompress only the filtered IDAT bytes. Profiles, metadata, and pixel depth stay intact.
enum PNGOptimizer {
    static func optimize(_ data: Data) throws -> Data {
        let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        guard data.starts(with: signature) else { throw WorkerError.invalidInput }
        var offset = 8, compressed = Data(), chunks: [(String, Data)] = []
        var ended = false
        while offset + 12 <= data.count {
            try Task.checkCancellation()
            let length = data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= data.count - offset - 12,
                  let type = String(data: data[offset + 4..<offset + 8], encoding: .ascii) else { throw WorkerError.invalidInput }
            let chunk = data.subdata(in: offset..<offset + 12 + length)
            if type == "IDAT" { compressed.append(data[offset + 8..<offset + 8 + length]) }
            chunks.append((type, chunk))
            offset += 12 + length
            if type == "IEND" { ended = true; break }
        }
        guard ended, !compressed.isEmpty, chunks.first?.0 == "IHDR",
              !chunks.contains(where: { $0.0 == "acTL" }) else { throw WorkerError.invalidInput }
        var capacity = max(4096, compressed.count * 2)
        var raw = Data()
        while capacity <= 520 * 1024 * 1024 {
            try Task.checkCancellation()
            raw = Data(count: capacity)
            var size = uLongf(capacity)
            let status = raw.withUnsafeMutableBytes { dest in
                compressed.withUnsafeBytes { src in
                    uncompress(dest.bindMemory(to: UInt8.self).baseAddress, &size,
                               src.bindMemory(to: UInt8.self).baseAddress, uLong(compressed.count))
                }
            }
            if status == Z_OK { raw.count = Int(size); break }
            guard status == Z_BUF_ERROR else { throw WorkerError.invalidInput }
            raw = Data()
            capacity *= 2
        }
        guard !raw.isEmpty else { throw WorkerError.invalidInput }
        try Task.checkCancellation()
        var size = compressBound(uLong(raw.count))
        var packed = Data(count: Int(size))
        let code = packed.withUnsafeMutableBytes { dest in
            raw.withUnsafeBytes { src in
                compress2(dest.bindMemory(to: UInt8.self).baseAddress, &size,
                          src.bindMemory(to: UInt8.self).baseAddress, uLong(raw.count), Z_BEST_COMPRESSION)
            }
        }
        guard code == Z_OK else { throw WorkerError.invalidOutput }
        packed.count = Int(size)
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
                result.append(chunk)
            }
        }
        return result
    }

    private static func bigEndian(_ number: UInt32) -> Data {
        var value = number.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}
