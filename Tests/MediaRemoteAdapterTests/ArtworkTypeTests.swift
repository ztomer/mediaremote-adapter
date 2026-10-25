import AppKit
import Foundation
import XCTest
@testable import MediaRemoteAdapter

/// `artworkMimeType` is the type of the BYTES, not the player's label. Seen live (2026-10-24, a
/// third-party player, through ungive's core at the vendored commit): `image/jpeg` over TIFF data.
/// ungive's #36 carries the label along with the data; it does not check it, so the check is here.
final class ArtworkTypeTests: XCTestCase {

    private func decode(_ line: String) throws -> TrackInfo.Payload {
        try XCTUnwrap(try CoreCLI.decodeStreamLine(Data(line.utf8))).payload
    }

    func testTIFFBytesLabelledJPEGAreReportedAsTIFF() throws {
        XCTAssertEqual(WireFixtures.payload(WireFixtures.tiffLabelledJPEG)["artworkMimeType"] as? String, "image/jpeg")
        let payload = try decode(WireFixtures.tiffLabelledJPEG)
        XCTAssertEqual(payload.artworkMimeType, "image/tiff")
        XCTAssertNotNil(payload.artwork, "the image itself was always fine")
    }

    func testARecordedJPEGKeepsItsLabel() throws {
        XCTAssertEqual(try decode(WireFixtures.playing).artworkMimeType, "image/jpeg")
    }

    func testEachKnownSignatureNamesItsType() {
        let cases: [(bytes: [UInt8], type: String)] = [
            ([0xFF, 0xD8, 0xFF, 0xE0], "image/jpeg"),
            ([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "image/png"),
            (Array("GIF89a".utf8), "image/gif"),
            ([0x4D, 0x4D, 0x00, 0x2A], "image/tiff"),
            ([0x49, 0x49, 0x2A, 0x00], "image/tiff"),
            (Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBP".utf8), "image/webp"),
            ([0, 0, 0, 0x18] + Array("ftypheic".utf8), "image/heic"),
            (Array("BM".utf8) + [0, 0, 0, 0], "image/bmp")
        ]
        for (bytes, type) in cases {
            let base64 = Data(bytes + [UInt8](repeating: 0, count: 16)).base64EncodedString()
            XCTAssertEqual(ArtworkType.mimeType(ofBase64: base64, declared: "image/jpeg"), type, "\(bytes)")
        }
    }

    /// Bytes this cannot name keep whatever the player said: no worse than before.
    func testUnknownBytesKeepTheDeclaredLabel() {
        let base64 = Data("data".utf8).base64EncodedString()
        XCTAssertEqual(ArtworkType.mimeType(ofBase64: base64, declared: "image/png"), "image/png")
        XCTAssertNil(ArtworkType.mimeType(ofBase64: base64, declared: nil))
        XCTAssertEqual(ArtworkType.mimeType(ofBase64: nil, declared: "image/png"), "image/png")
        XCTAssertEqual(ArtworkType.mimeType(ofBase64: "!!", declared: "image/png"), "image/png")
    }

    /// A consumer building a payload by hand gets the same answer as the wire.
    func testTheMemberwiseInitializerChecksTheBytesToo() {
        let tiff = TrackInfo.Payload(artworkDataBase64: WireFixtures.tiffImageBase64, artworkMimeType: "image/jpeg")
        XCTAssertEqual(tiff.artworkMimeType, "image/tiff")
        let opaque = TrackInfo.Payload(artworkDataBase64: Data("data".utf8).base64EncodedString(),
                                       artworkMimeType: "image/png")
        XCTAssertEqual(opaque.artworkMimeType, "image/png")
    }
}
