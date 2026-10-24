import AppKit
import Foundation
import XCTest
@testable import MediaRemoteAdapter

/// Each recorded `run.pl` line, decoded straight through `TrackInfo`: the payload is asserted
/// field by field, so a renamed key, a changed type or a dropped fallback goes red here.
final class TrackInfoDecodingTests: XCTestCase {

    private func decode(_ line: String) throws -> TrackInfo.Payload {
        try JSONDecoder().decode(TrackInfo.self, from: Data(line.utf8)).payload
    }

    func testPlayingLineDecodesEveryField() throws {
        let payload = try decode(WireFixtures.playing)
        XCTAssertEqual(payload.title, "Weightless")
        XCTAssertEqual(payload.artist, "Marconi Union")
        XCTAssertEqual(payload.album, "Weightless")
        XCTAssertEqual(payload.isPlaying, true)
        XCTAssertEqual(payload.durationMicros, 480_000_000)
        XCTAssertEqual(payload.elapsedTimeMicros, 12_345_678)
        XCTAssertEqual(payload.timestampEpochMicros, 1_792_800_000_000_000)
        XCTAssertEqual(payload.applicationName, "Music")
        XCTAssertEqual(payload.bundleIdentifier, "com.apple.Music")
        XCTAssertEqual(payload.PID, 1234, "PID arrives as a decimal STRING on the wire")
        XCTAssertEqual(payload.shuffleMode, .songs)
        XCTAssertEqual(payload.repeatMode, .all)
        XCTAssertEqual(payload.playbackRate, 1)
        XCTAssertNil(payload.artworkDataBase64)
        XCTAssertNil(payload.artwork)
    }

    func testPausedLineDecodesAsNotPlaying() throws {
        let payload = try decode(WireFixtures.paused)
        XCTAssertEqual(payload.isPlaying, false)
        XCTAssertEqual(payload.shuffleMode, .off)
        XCTAssertEqual(payload.repeatMode, .off)
        XCTAssertEqual(payload.playbackRate, 0)
    }

    func testArtworkLineDecodesTheEscapedBase64IntoAnImage() throws {
        let payload = try decode(WireFixtures.withArtwork())
        XCTAssertEqual(payload.artworkDataBase64, WireFixtures.artworkBase64,
                       "the wire's \\/ escapes must come back as plain /")
        XCTAssertEqual(payload.artworkMimeType, "image/png")
        let image = try XCTUnwrap(payload.artwork, "valid artwork base64 must become an NSImage")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testUndecodableArtworkBase64LeavesNoImageButStillDecodes() throws {
        let line = WireFixtures.withArtwork()
            .replacingOccurrences(of: WireFixtures.artworkBase64.replacingOccurrences(of: "/", with: "\\/"),
                                  with: "!!not base64!!")
        let payload = try decode(line)
        XCTAssertNil(payload.artwork)
        XCTAssertEqual(payload.title, "Weightless")
    }

    func testSparseLineAcceptsNumericPIDAndIntegerPlayerFlag() throws {
        let payload = try decode(WireFixtures.sparse)
        XCTAssertEqual(payload.title, "Podcast")
        XCTAssertEqual(payload.isPlaying, true, "isPlaying 1 means playing")
        XCTAssertEqual(payload.PID, 4321, "a numeric PID is accepted as well as the string form")
        XCTAssertNil(payload.artist)
        XCTAssertNil(payload.durationMicros)
        XCTAssertNil(payload.shuffleMode)
    }

    func testIntegerPlayerFlagZeroMeansPausedAndUnknownEnumsAreNil() throws {
        let line = "{\"payload\":{\"isPlaying\":0,\"PID\":\"not-a-pid\",\"shuffleMode\":9,\"repeatMode\":\"x\"}}"
        let payload = try decode(line)
        XCTAssertEqual(payload.isPlaying, false)
        XCTAssertNil(payload.PID)
        XCTAssertNil(payload.shuffleMode, "an unknown shuffle mode must not fail the whole line")
        XCTAssertNil(payload.repeatMode)
    }

    func testMalformedLinesThrow() {
        for line in [WireFixtures.truncated, WireFixtures.wrongType, WireFixtures.noPayload, WireFixtures.notJSON] {
            XCTAssertThrowsError(try decode(line), "must not decode: \(line)")
        }
    }

    func testUniqueIdentifierJoinsTitleArtistAlbum() throws {
        XCTAssertEqual(try decode(WireFixtures.playing).uniqueIdentifier, "Weightless-Marconi Union-Weightless")
        XCTAssertEqual(try decode(WireFixtures.sparse).uniqueIdentifier, "Podcast--")
    }

    func testEncodeRoundTripKeepsTheWireKeys() throws {
        let info = try JSONDecoder().decode(TrackInfo.self, from: Data(WireFixtures.playing.utf8))
        let again = try JSONDecoder().decode(TrackInfo.self, from: JSONEncoder().encode(info))
        XCTAssertEqual(again.payload.title, "Weightless")
        XCTAssertEqual(again.payload.PID, 1234)
        XCTAssertEqual(again.payload.durationMicros, 480_000_000)
    }

    // MARK: - currentElapsedTime

    func testElapsedTimeIsFrozenWhenPaused() throws {
        let payload = try decode(WireFixtures.paused)
        XCTAssertEqual(try XCTUnwrap(payload.currentElapsedTime), 99, accuracy: 0.001)
    }

    func testElapsedTimeAdvancesByRateTimesAgeWhilePlaying() {
        let stamp = Date().timeIntervalSince1970 - 10
        let payload = TrackInfo.Payload(isPlaying: true, elapsedTimeMicros: 5_000_000,
                                        timestampEpochMicros: stamp * 1_000_000, playbackRate: 2)
        // 5 s elapsed at the stamp, then 10 s of wall time at 2x.
        XCTAssertEqual(payload.currentElapsedTime ?? 0, 25, accuracy: 0.5)
    }

    func testElapsedTimeWithoutARateDoesNotAdvance() {
        let stamp = Date().timeIntervalSince1970 - 10
        let payload = TrackInfo.Payload(isPlaying: true, elapsedTimeMicros: 5_000_000,
                                        timestampEpochMicros: stamp * 1_000_000)
        XCTAssertEqual(payload.currentElapsedTime ?? 0, 5, accuracy: 0.001)
    }

    func testElapsedTimeIsNilWithoutElapsedOrTimestamp() {
        XCTAssertNil(TrackInfo.Payload(elapsedTimeMicros: 1).currentElapsedTime)
        XCTAssertNil(TrackInfo.Payload(timestampEpochMicros: 1).currentElapsedTime)
    }
}
