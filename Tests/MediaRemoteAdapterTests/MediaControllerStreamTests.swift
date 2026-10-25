import Foundation
import XCTest
@testable import MediaRemoteAdapter

/// The listener's wire protocol, replayed into `MediaController.ingest` exactly as the pipe reader
/// would deliver it: arbitrary chunks, several lines per chunk, a line split across chunks.
final class MediaControllerStreamTests: XCTestCase {

    private enum Event: Equatable {
        case track(String?)       // title, nil for the NIL "no player" report
        case decodingError(String) // the raw line the decoder rejected
    }

    private final class Recorder {
        var events: [Event] = []
        var tracks: [TrackInfo] = []
    }

    private func controller() -> (MediaController, Recorder) {
        let controller = MediaController()
        let recorder = Recorder()
        controller.onTrackInfoReceived = { info in
            recorder.events.append(.track(info?.payload.title))
            if let info { recorder.tracks.append(info) }
        }
        controller.onDecodingError = { _, data in
            recorder.events.append(.decodingError(String(bytes: data, encoding: .utf8) ?? "<binary>"))
        }
        return (controller, recorder)
    }

    /// Callbacks hop to the main queue; drain it before looking.
    private func settle() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    private func feed(_ controller: MediaController, _ text: String) {
        controller.ingest(Data(text.utf8))
    }

    func testPlayingThenPausedThenNoPlayerArriveInOrder() {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.playing + "\n" + WireFixtures.paused + "\n" + WireFixtures.noPlayer + "\n")
        settle()
        XCTAssertEqual(recorder.events, [.track("Fixture Tone"), .track("Fixture Tone"), .track(nil)])
        XCTAssertEqual(recorder.tracks.map(\.payload.isPlaying), [true, false])
    }

    func testALineSplitAcrossChunksIsDeliveredOnceWhenComplete() {
        let (controller, recorder) = controller()
        let line = WireFixtures.playing + "\n"
        let cut = line.index(line.startIndex, offsetBy: line.count / 2)
        feed(controller, String(line[..<cut]))
        settle()
        XCTAssertEqual(recorder.events, [], "half a line is not an event")
        feed(controller, String(line[cut...]))
        settle()
        XCTAssertEqual(recorder.events, [.track("Fixture Tone")])
    }

    func testByteAtATimeDeliveryStillYieldsEachLine() {
        let (controller, recorder) = controller()
        for byte in Data((WireFixtures.noPlayer + "\n" + WireFixtures.paused + "\n").utf8) {
            controller.ingest(Data([byte]))
        }
        settle()
        XCTAssertEqual(recorder.events, [.track(nil), .track("Fixture Tone")])
    }

    func testBlankLinesAreIgnored() {
        let (controller, recorder) = controller()
        feed(controller, "\n\n" + WireFixtures.playing + "\n\n")
        settle()
        XCTAssertEqual(recorder.events, [.track("Fixture Tone")])
    }

    func testMalformedLinesReachOnDecodingErrorWithTheirBytesAndDoNotStopTheStream() {
        let (controller, recorder) = controller()
        let lines = [WireFixtures.truncated, WireFixtures.wrongType, WireFixtures.noPayload, WireFixtures.notJSON]
        feed(controller, lines.joined(separator: "\n") + "\n" + WireFixtures.playing + "\n")
        settle()
        XCTAssertEqual(recorder.events, lines.map(Event.decodingError) + [.track("Fixture Tone")])
    }

    func testAPartialTrailingLineWaitsInTheBufferUntilItsNewline() {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.noPlayer + "\n" + "{\"payload\":")
        settle()
        XCTAssertEqual(recorder.events, [.track(nil)])
        feed(controller, "{\"title\":\"Late\"}}\n")
        settle()
        XCTAssertEqual(recorder.events, [.track(nil), .track("Late")])
    }

    // MARK: - artwork downgrade (the recorded sequences)

    private func artwork(_ line: String) -> String? {
        WireFixtures.payload(line)["artworkDataBase64"] as? String
    }

    func testTheWholeRecordedSessionStreamsWithoutADecodingError() {
        for session in [WireFixtures.bundledSession, WireFixtures.bareSession] {
            let (controller, recorder) = controller()
            feed(controller, session.joined(separator: "\n") + "\n")
            settle()
            XCTAssertEqual(recorder.events.count, session.count)
            XCTAssertFalse(recorder.events.contains { if case .decodingError = $0 { true } else { false } })
            let second = recorder.tracks.filter { $0.payload.title == "Second Tone" }
            XCTAssertNil(second.first?.payload.artwork, "the new track does not inherit the old art")
            XCTAssertTrue(second.contains { $0.payload.artwork != nil }, "its own art arrives on a later report")
        }
    }

    func testArtworkIsKeptWhenTheSameTrackReportsItAgainWithoutArtwork() throws {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.playing + "\n" + WireFixtures.pausedArtworkPending + "\n")
        settle()
        let second = try XCTUnwrap(recorder.tracks.last)
        XCTAssertEqual(second.payload.artworkDataBase64, artwork(WireFixtures.playing))
        XCTAssertEqual(second.payload.artworkMimeType, "image/jpeg")
        XCTAssertNotNil(second.payload.artwork)
        XCTAssertEqual(second.payload.isPlaying, false, "everything but the artwork is the NEW report")
        XCTAssertEqual(second.payload.elapsedTimeMicros,
                       WireFixtures.payload(WireFixtures.pausedArtworkPending)["elapsedTimeMicros"] as? Double)
    }

    func testArtworkIsDroppedWhenTheTrackChanges() throws {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.playing + "\n" + WireFixtures.secondTrackPending + "\n")
        settle()
        let second = try XCTUnwrap(recorder.tracks.last)
        XCTAssertEqual(second.payload.title, "Second Tone")
        XCTAssertNil(second.payload.artworkDataBase64, "a different track must not inherit the old art")
    }

    func testArtworkSurvivesWhenOneSideLeavesTheAlbumEmpty() throws {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.secondTrack + "\n" + WireFixtures.artworkRemoved + "\n")
        settle()
        XCTAssertEqual(try XCTUnwrap(recorder.tracks.last).payload.artworkDataBase64, artwork(WireFixtures.secondTrack))
    }

    func testArtworkIsDroppedWhenBothAlbumsAreSetAndDiffer() throws {
        // The recording never changes a set album to another set album: the second report is the
        // recorded pending line with its album edited.
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.playing + "\n"
             + WireFixtures.edited(WireFixtures.pausedArtworkPending, ["album": "Live"]) + "\n")
        settle()
        XCTAssertNil(try XCTUnwrap(recorder.tracks.last).payload.artworkDataBase64)
    }

    func testTheArtworkThatArrivesAfterItsMimeTypeIsDelivered() throws {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.artworkPending + "\n" + WireFixtures.playing + "\n")
        settle()
        XCTAssertEqual(try XCTUnwrap(recorder.tracks.last).payload.artworkDataBase64, artwork(WireFixtures.playing))
    }
}
