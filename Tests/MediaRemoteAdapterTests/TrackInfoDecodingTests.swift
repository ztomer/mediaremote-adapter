import AppKit
import Foundation
import XCTest
@testable import MediaRemoteAdapter

/// Each recorded core line, decoded the way `MediaController` decodes it (`CoreCLI`): the payload
/// is asserted field by field, so a renamed key, a changed type or a dropped fallback goes red here.
final class TrackInfoDecodingTests: XCTestCase {

    private func decode(_ line: String) throws -> TrackInfo.Payload {
        let info = try CoreCLI.decodeStreamLine(Data(line.utf8))
        return try XCTUnwrap(info, "a track line decoded to 'nothing playing'").payload
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
        XCTAssertNil(payload.applicationName, "the core reports no name; MediaController adds it")
        XCTAssertEqual(payload.bundleIdentifier, "com.ztomer.mediaremote-adapter.fixture-player")
        let pid = try XCTUnwrap(wire["processIdentifier"] as? Int, "the PID arrives as a NUMBER")
        XCTAssertEqual(payload.PID, pid_t(pid))
        XCTAssertNil(payload.shuffleMode, "recorded: absent")
        XCTAssertNil(payload.repeatMode, "recorded: absent")
        XCTAssertEqual(payload.playbackRate, 1)
        XCTAssertEqual(payload.artworkMimeType, "image/jpeg")
        XCTAssertNotNil(payload.artwork)
    }

    func testPausedLineDecodesAsNotPlaying() throws {
        XCTAssertEqual(try decode(WireFixtures.paused).isPlaying, false)
    }

    func testEveryRecordedLineDecodes() throws {
        for line in WireFixtures.bundledSession + WireFixtures.bareSession {
            XCTAssertNoThrow(try CoreCLI.decodeStreamLine(Data(line.utf8)), String(line.prefix(120)))
        }
        XCTAssertGreaterThanOrEqual(WireFixtures.bundledSession.count, 6, "the recording lost its subject")
        XCTAssertGreaterThanOrEqual(WireFixtures.bareSession.count, 4, "the recording lost its subject")
    }

    func testTheEmptyPayloadIsNothingPlaying() throws {
        XCTAssertTrue(WireFixtures.payload(WireFixtures.noPlayer).isEmpty, "recorded: an empty payload")
        XCTAssertNil(try CoreCLI.decodeStreamLine(Data(WireFixtures.noPlayer.utf8)))
    }

    func testAPlayerWithoutABundleOmitsItsBundleIdentifierAndStillDecodes() throws {
        let line = WireFixtures.barePlaying
        let wire = WireFixtures.payload(line)
        XCTAssertNil(wire["bundleIdentifier"], "recorded: the key is ABSENT, not null")
        let payload = try decode(line)
        XCTAssertEqual(payload.title, "Fixture Tone")
        XCTAssertNil(payload.bundleIdentifier)
        XCTAssertEqual(payload.PID, (wire["processIdentifier"] as? Int).map { pid_t($0) })
        XCTAssertNotNil(payload.PID, "recorded: the process is reported without a bundle")
        XCTAssertNotNil(payload.artwork)
    }

    func testArtworkPendingLineHasAMimeTypeAndNoImage() throws {
        let payload = try decode(WireFixtures.artworkPending)
        XCTAssertEqual(payload.artworkMimeType, "image/jpeg", "recorded: the type arrives before the data")
        XCTAssertNil(payload.artworkDataBase64)
        XCTAssertNil(payload.artwork)
    }

    /// The wire numbers are MediaRemote's (1 off, 2 albums/one, 3 songs/all), the same numbering
    /// `commands.tsv` records the player receiving. The enums' raw values are MediaPlayer's (from
    /// 0), so reading the number as a raw value was off by one, and 0 meant "off" on the way in.
    func testShuffleAndRepeatModesDecodeFromMediaRemotesNumbering() throws {
        let reported = try decode(WireFixtures.modesReported)
        XCTAssertEqual(reported.shuffleMode, .songs)
        XCTAssertEqual(reported.repeatMode, .all)
        let middle = try decode(WireFixtures.modesMiddle)
        XCTAssertEqual(middle.shuffleMode, .albums)
        XCTAssertEqual(middle.repeatMode, .one)
        let off = try decode(WireFixtures.modesOff)
        XCTAssertEqual(off.shuffleMode, .off)
        XCTAssertEqual(off.repeatMode, .off)
        let zero = try decode(WireFixtures.modesZero)
        XCTAssertNil(zero.shuffleMode, "0 is no MediaRemote mode")
        XCTAssertNil(zero.repeatMode)
    }

    func testArtworkLineDecodesTheEscapedBase64IntoAnImage() throws {
        let line = WireFixtures.playing
        XCTAssertTrue(line.contains("\\/"), "the recording holds the wire's \\/ escapes verbatim")
        let payload = try decode(line)
        let expected = try XCTUnwrap(WireFixtures.payload(line)["artworkData"] as? String)
        XCTAssertTrue(expected.contains("/"))
        XCTAssertEqual(payload.artworkDataBase64, expected, "the wire's \\/ escapes must come back as plain /")
        let image = try XCTUnwrap(payload.artwork, "valid artwork base64 must become an NSImage")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testUndecodableArtworkBase64LeavesNoImageButStillDecodes() throws {
        let payload = try decode(WireFixtures.edited(WireFixtures.playing, ["artworkData": "!!not base64!!"]))
        XCTAssertNil(payload.artwork)
        XCTAssertEqual(payload.title, "Fixture Tone")
    }

    func testAnUnknownModeOrAWrongTypedFlagDoesNotFailTheLine() throws {
        let line = "{\"type\":\"data\",\"diff\":false,\"payload\":{\"title\":\"T\",\"playing\":0,"
            + "\"processIdentifier\":\"not-a-pid\",\"shuffleMode\":9,\"repeatMode\":\"x\"}}"
        let payload = try decode(line)
        XCTAssertEqual(payload.isPlaying, false, "a 0/1 flag is read as a bool")
        XCTAssertNil(payload.PID)
        XCTAssertNil(payload.shuffleMode, "an unknown shuffle mode must not fail the whole line")
        XCTAssertNil(payload.repeatMode)
    }

    func testMalformedAndUnexpectedLinesThrow() {
        for line in [WireFixtures.truncated, WireFixtures.wrongType, WireFixtures.noPayload, WireFixtures.notJSON,
                     WireFixtures.diffLine, WireFixtures.unknownType] {
            XCTAssertThrowsError(try CoreCLI.decodeStreamLine(Data(line.utf8)), "must not decode: \(line)")
        }
    }

    // MARK: - get

    func testGetPrintsThePayloadWithoutAnEnvelope() throws {
        let wire = WireFixtures.payload(WireFixtures.getPlaying)
        XCTAssertNil(wire["payload"], "recorded: `get` has no envelope")
        let payload = try XCTUnwrap(try CoreCLI.decodeGet(Data(WireFixtures.getPlaying.utf8))).payload
        XCTAssertEqual(payload.title, "Fixture Tone")
        XCTAssertEqual(payload.isPlaying, true)
        XCTAssertNotNil(payload.artwork)
        XCTAssertEqual(payload.PID, (wire["processIdentifier"] as? Int).map { pid_t($0) })
    }

    func testGetsNullAndAnEmptyObjectAreNothingPlaying() throws {
        XCTAssertNil(try CoreCLI.decodeGet(Data(WireFixtures.getNoPlayer.utf8)))
        XCTAssertNil(try CoreCLI.decodeGet(Data("{}".utf8)))
        XCTAssertThrowsError(try CoreCLI.decodeGet(Data(WireFixtures.truncated.utf8)))
    }

    // MARK: - the old run.pl spelling and the round trip

    func testTheOldRunPlSpellingStillDecodes() throws {
        let line = WireFixtures.legacyPlaying
        let wire = WireFixtures.payload(line)
        let payload = try JSONDecoder().decode(TrackInfo.self, from: Data(line.utf8)).payload
        XCTAssertEqual(payload.isPlaying, true)
        XCTAssertEqual(payload.applicationName, "Fixture Player")
        let pidString = try XCTUnwrap(wire["PID"] as? String, "the old shim printed the PID as a string")
        XCTAssertEqual(payload.PID, Int32(pidString))
        XCTAssertEqual(payload.artworkDataBase64, wire["artworkDataBase64"] as? String)
        XCTAssertNotNil(payload.artwork)
    }

    func testEncodeRoundTripWritesTheCoresSpelling() throws {
        let info = try XCTUnwrap(try CoreCLI.decodeStreamLine(Data(WireFixtures.playing.utf8)))
            .namingApplication { _ in "Fixture Player" }
        let modes = TrackInfo(payload: TrackInfo.Payload(title: "M", shuffleMode: .songs, repeatMode: .one))
        for original in [info, modes] {
            let encoded = try JSONEncoder().encode(original)
            let keys = try XCTUnwrap(
                (try JSONSerialization.jsonObject(with: encoded) as? [String: Any])?["payload"] as? [String: Any]
            ).keys
            XCTAssertFalse(keys.contains("isPlaying") || keys.contains("PID") || keys.contains("artworkDataBase64"),
                           "encoded in the old spelling: \(keys.sorted())")
            let again = try JSONDecoder().decode(TrackInfo.self, from: encoded).payload
            XCTAssertEqual(again.title, original.payload.title)
            XCTAssertEqual(again.isPlaying, original.payload.isPlaying)
            XCTAssertEqual(again.PID, original.payload.PID)
            XCTAssertEqual(again.applicationName, original.payload.applicationName)
            XCTAssertEqual(again.artworkDataBase64, original.payload.artworkDataBase64)
            XCTAssertEqual(again.durationMicros, original.payload.durationMicros)
            XCTAssertEqual(again.shuffleMode, original.payload.shuffleMode)
            XCTAssertEqual(again.repeatMode, original.payload.repeatMode)
        }
    }

    func testUniqueIdentifierJoinsTitleArtistAlbum() throws {
        XCTAssertEqual(try decode(WireFixtures.playing).uniqueIdentifier,
                       "Fixture Tone-mediaremote-adapter-Recorded Fixtures")
        XCTAssertEqual(try decode(WireFixtures.modesOff).uniqueIdentifier, "Modes--")
    }

    // MARK: - currentElapsedTime

    func testElapsedTimeIsFrozenWhenPaused() throws {
        let payload = try decode(WireFixtures.paused)
        let elapsed = try XCTUnwrap(WireFixtures.payload(WireFixtures.paused)["elapsedTimeMicros"] as? Double)
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
