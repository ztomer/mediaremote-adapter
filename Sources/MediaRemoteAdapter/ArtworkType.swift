import Foundation

/// The MIME type of artwork BYTES, read from their signature. A player's label is a claim, and a
/// wrong one was seen live: `image/jpeg` over TIFF data (2026-10-24, a third-party player, through
/// ungive's core, which passes the label through as MediaRemote gave it). `NSImage` decodes either,
/// so the image was fine; anything trusting the label was not.
enum ArtworkType {

    /// The type the bytes say, or `declared` when the bytes are not a format named here (or not
    /// base64 at all): no worse than the label.
    static func mimeType(ofBase64 base64: String?, declared: String?) -> String? {
        guard let base64, let head = prefix(ofBase64: base64), let sniffed = mimeType(of: head) else {
            return declared
        }
        return sniffed
    }

    /// The first bytes, from only the first characters of the base64: artwork is hundreds of KB and
    /// a signature is at most 12 bytes.
    private static func prefix(ofBase64 base64: String) -> [UInt8]? {
        let quads = base64.prefix(24)
        guard quads.count % 4 == 0, let data = Data(base64Encoded: String(quads)) else { return nil }
        return [UInt8](data)
    }

    private static func mimeType(of head: [UInt8]) -> String? {
        func starts(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            head.count >= offset + signature.count && Array(head[offset..<offset + signature.count]) == signature
        }
        if starts([0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8)) { return "image/gif" }
        if starts([0x4D, 0x4D, 0x00, 0x2A]) || starts([0x49, 0x49, 0x2A, 0x00]) { return "image/tiff" }
        if starts(Array("RIFF".utf8)) && starts(Array("WEBP".utf8), at: 8) { return "image/webp" }
        if starts(Array("ftyp".utf8), at: 4) {
            if starts(Array("heic".utf8), at: 8) || starts(Array("heix".utf8), at: 8) { return "image/heic" }
            if starts(Array("avif".utf8), at: 8) { return "image/avif" }
        }
        if starts(Array("BM".utf8)) { return "image/bmp" }
        return nil
    }
}
