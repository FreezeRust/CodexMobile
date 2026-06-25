import Foundation

/// Minimal ZIP (store, no compression) writer — no external dependencies.
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
}
