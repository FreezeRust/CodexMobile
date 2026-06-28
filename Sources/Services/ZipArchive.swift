import Foundation
import Compression

/// Minimal ZIP writer (store) + reader (store & deflate) — no external dependencies.
/// Good enough to bundle text/code/image files into a .zip for export.
enum ZipArchive {
    private struct Entry { let name: String; let data: Data; let crc: UInt32; let offset: UInt32 }

    static func make(files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var entries: [Entry] = []

        for f in files {
            let nameData = Data(f.name.utf8)
            let crc = crc32(f.data)
            let offset = UInt32(out.count)

            // Local file header
            out.append(le32(0x04034b50))      // signature
            out.append(le16(20))              // version needed
            out.append(le16(0))               // flags
            out.append(le16(0))               // method = store
            out.append(le16(0)); out.append(le16(0))   // mod time/date
            out.append(le32(crc))
            out.append(le32(UInt32(f.data.count)))   // compressed
            out.append(le32(UInt32(f.data.count)))   // uncompressed
            out.append(le16(UInt16(nameData.count)))
            out.append(le16(0))               // extra len
            out.append(nameData)
            out.append(f.data)

            entries.append(Entry(name: f.name, data: f.data, crc: crc, offset: offset))
        }

        // Central directory
        let cdStart = UInt32(out.count)
        for e in entries {
            let nameData = Data(e.name.utf8)
            out.append(le32(0x02014b50))      // central dir signature
            out.append(le16(20)); out.append(le16(20))
            out.append(le16(0)); out.append(le16(0))
            out.append(le16(0)); out.append(le16(0))
            out.append(le32(e.crc))
            out.append(le32(UInt32(e.data.count)))
            out.append(le32(UInt32(e.data.count)))
            out.append(le16(UInt16(nameData.count)))
            out.append(le16(0)); out.append(le16(0))
            out.append(le16(0)); out.append(le16(0))
            out.append(le32(0))
            out.append(le32(e.offset))
            out.append(nameData)
        }
        let cdSize = UInt32(out.count) - cdStart

        // End of central directory
        out.append(le32(0x06054b50))
        out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(cdSize))
        out.append(le32(cdStart))
        out.append(le16(0))
        return out
    }

    // little-endian helpers
    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8 & 0xff)]) }
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24 & 0xff)])
    }

    // CRC32
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()
    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xffffffff
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xffffffff
    }

    // MARK: - Reading

    struct ExtractedFile { let path: String; let data: Data }

    /// Parses a .zip archive and returns its files (supports STORE and DEFLATE).
    static func read(_ zip: Data) -> [ExtractedFile] {
        var out: [ExtractedFile] = []
        let bytes = [UInt8](zip)
        let n = bytes.count
        var i = 0
        // Iterate local file headers (signature 0x04034b50).
        while i + 30 <= n {
            let sig = u32(bytes, i)
            guard sig == 0x04034b50 else { break }
            let method = u16(bytes, i + 8)
            var compSize = Int(u32(bytes, i + 18))
            var uncompSize = Int(u32(bytes, i + 22))
            let nameLen = Int(u16(bytes, i + 26))
            let extraLen = Int(u16(bytes, i + 28))
            let flags = u16(bytes, i + 6)
            let nameStart = i + 30
            guard nameStart + nameLen <= n else { break }
            let name = String(bytes: bytes[nameStart..<nameStart + nameLen], encoding: .utf8) ?? ""
            var dataStart = nameStart + nameLen + extraLen

            // If sizes are in a data descriptor (bit 3), find next signature.
            if (flags & 0x08) != 0 && compSize == 0 {
                var j = dataStart
                while j + 4 <= n {
                    let s = u32(bytes, j)
                    if s == 0x08074b50 || s == 0x04034b50 || s == 0x02014b50 {
                        compSize = j - dataStart
                        break
                    }
                    j += 1
                }
            }
            guard dataStart + compSize <= n else { break }
            let chunk = Data(bytes[dataStart..<dataStart + compSize])

            if !name.hasSuffix("/") {   // skip directory entries
                if method == 0 {
                    out.append(ExtractedFile(path: name, data: chunk))
                } else if method == 8 {
                    if let inflated = inflate(chunk, expected: uncompSize > 0 ? uncompSize : max(compSize * 4, 1024)) {
                        out.append(ExtractedFile(path: name, data: inflated))
                    }
                }
            }
            _ = uncompSize
            dataStart += compSize
            // skip optional data descriptor (12 or 16 bytes)
            if (flags & 0x08) != 0 {
                if dataStart + 4 <= n, u32(bytes, dataStart) == 0x08074b50 { dataStart += 16 }
                else { dataStart += 12 }
            }
            i = dataStart
        }
        return out
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | (UInt16(b[i+1]) << 8) }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i+1]) << 8) | (UInt32(b[i+2]) << 16) | (UInt32(b[i+3]) << 24)
    }

    /// Raw DEFLATE inflate via Apple's Compression framework.
    private static func inflate(_ data: Data, expected: Int) -> Data? {
        guard !data.isEmpty else { return Data() }
        var dst = Data(count: max(expected, 64))
        let result: Int = dst.withUnsafeMutableBytes { dstRaw in
            data.withUnsafeBytes { srcRaw in
                compression_decode_buffer(
                    dstRaw.bindMemory(to: UInt8.self).baseAddress!, dst.count,
                    srcRaw.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        if result > 0 { return dst.prefix(result) }
        // grow buffer once if it was too small
        if result == 0 || result == dst.count {
            var big = Data(count: max(expected * 4, 1 << 20))
            let r2: Int = big.withUnsafeMutableBytes { dstRaw in
                data.withUnsafeBytes { srcRaw in
                    compression_decode_buffer(
                        dstRaw.bindMemory(to: UInt8.self).baseAddress!, big.count,
                        srcRaw.bindMemory(to: UInt8.self).baseAddress!, data.count,
                        nil, COMPRESSION_ZLIB)
                }
            }
            if r2 > 0 { return big.prefix(r2) }
        }
        return nil
    }
}
