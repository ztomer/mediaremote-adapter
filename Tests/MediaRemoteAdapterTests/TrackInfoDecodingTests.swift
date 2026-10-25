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
        let line = WireFixtures.playing
        let wire = WireFixtures.payload(line)
        let payload = try decode(line)
        XCTAssertEqual(payload.title, "Fixture Tone")
        XCTAssertEqual(payload.artist, "mediaremote-adapter")
        XCTAssertEqual(payload.album, "Recorded Fixtures")
        XCTAssertEqual(payload.isPlaying, true)
        XCTAssertEqual(payload.durationMicros, 120_000_000)
        XCTAssertEqual(payload.elapsedTimeMicros, wire["elapsedTimeMicros"] as? Double)
        XCTAssertEqual(payload.timestampEpochMicros, wire["timestampEpochMicros"] as? Double)
        XCTAssertEqual(payload.applicationName, "Fixture Player")
        XCTAssertEqual(payload.bundleIdentifier, "com.ztomer.mediaremote-adapter.fixture-player")
        let pidString = try XCTUnwrap(wire["PID"] as? String, "PID arrives as a decimal STRING on the wire")
        XCTAssertEqual(payload.PID, Int32(pidString))
        XCTAssertNil(payload.shuffleMode, "recorded: null")
        XCTAssertNil(payload.repeatMode, "recorded: null")
        XCTAssertEqual(payload.playbackRate, 1)
        XCTAssertEqual(payload.artworkMimeType, "image/jpeg")
        XCTAssertNotNil(payload.artwork)
    }

    func testPausedLineDecodesAsNotPlaying() throws {
        let payload = try decode(WireFixtures.paused)
        XCTAssertEqual(payload.isPlaying, false)
        XCTAssertEqual(payload.playbackRate, 0)
    }

    func testEveryRecordedLineDecodes() throws {
        for line in WireFixtures.bundledSession + WireFixtures.bareSession {
            XCTAssertNoThrow(try decode(line), String(line.prefix(120)))
        }
        XCTAssertGreaterThanOrEqual(WireFixtures.bundledSession.count, 5, "the recording lost its subject")
        XCTAssertGreaterThanOrEqual(WireFixtures.bareSession.count, 3, "the recording lost its subject")
    }

    func testAPlayerWithoutABundleOmitsItsIdentityKeysAndStillDecodes() throws {
        let line = WireFixtures.barePlaying
        let wire = WireFixtures.payload(line)
        XCTAssertNil(wire["bundleIdentifier"], "recorded: the key is ABSENT, not null")
        XCTAssertNil(wire["PID"])
        let payload = try decode(line)
        XCTAssertEqual(payload.title, "Fixture Tone")
        XCTAssertNil(payload.bundleIdentifier)
        XCTAssertNil(payload.applicationName)
        XCTAssertNil(payload.PID)
        XCTAssertNotNil(payload.artwork)
    }

    func testArtworkPendingLineHasAMimeTypeAndNoImage() throws {
        let payload = try decode(WireFixtures.artworkPending)
        XCTAssertEqual(payload.artworkMimeType, "image/jpeg", "recorded: the type arrives before the data")
        XCTAssertNil(payload.artworkDataBase64)
        XCTAssertNil(payload.artwork)
    }

    func testShuffleAndRepeatModesDecode() throws {
        let reported = try decode(WireFixtures.modesReported)
        XCTAssertEqual(reported.shuffleMode, .songs)
        XCTAssertEqual(reported.repeatMode, .all)
        let off = try decode(WireFixtures.modesOff)
        XCTAssertEqual(off.shuffleMode, .off)
        XCTAssertEqual(off.repeatMode, .off)
    }

    func testArtworkLineDecodesTheEscapedBase64IntoAnImage() throws {
        let line = WireFixtures.playing
        XCTAssertTrue(line.contains("\\/"), "the recording holds the wire's \\/ escapes verbatim")
        let payload = try decode(line)
        let expected = try XCTUnwrap(WireFixtures.payload(line)["artworkDataBase64"] as? String)
        XCTAssertTrue(expected.contains("/"))
        XCTAssertEqual(payload.artworkDataBase64, expected, "the wire's \\/ escapes must come back as plain /")
        XCTAssertEqual(payload.artworkMimeType, "image/jpeg")
        let image = try XCTUnwrap(payload.artwork, "valid artwork base64 must become an NSImage")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testUndecodableArtworkBase64LeavesNoImageButStillDecodes() throws {
        let line = WireFixtures.edited(WireFixtures.playing, ["artworkDataBase64": "!!not base64!!"])
        let payload = try decode(line)
        XCTAssertNil(payload.artwork)
        XCTAssertEqual(payload.title, "Fixture Tone")
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
        XCTAssertEqual(try decode(WireFixtures.playing).uniqueIdentifier,
                       "Fixture Tone-mediaremote-adapter-Recorded Fixtures")
        XCTAssertEqual(try decode(WireFixtures.sparse).uniqueIdentifier, "Podcast--")
    }

    func testEncodeRoundTripKeepsTheWireKeys() throws {
        let info = try JSONDecoder().decode(TrackInfo.self, from: Data(WireFixtures.playing.utf8))
        let again = try JSONDecoder().decode(TrackInfo.self, from: JSONEncoder().encode(info))
        XCTAssertEqual(again.payload.title, "Fixture Tone")
        XCTAssertEqual(again.payload.PID, info.payload.PID)
        XCTAssertNotNil(again.payload.PID)
        XCTAssertEqual(again.payload.durationMicros, 120_000_000)
    }

    // MARK: - currentElapsedTime

    func testElapsedTimeIsFrozenWhenPaused() throws {
        let payload = try decode(WireFixtures.paused)
        let elapsed = try XCTUnwrap(WireFixtures.payload(WireFixtures.paused)["elapsedTimeMicros"] as? Double)
        XCTAssertGreaterThan(elapsed, 0, "recorded mid-track")
        XCTAssertEqual(try XCTUnwrap(payload.currentElapsedTime), elapsed / 1_000_000, accuracy: 0.001)
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
