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
        XCTAssertEqual(recorder.events, [.track("Weightless"), .track("Weightless"), .track(nil)])
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
        XCTAssertEqual(recorder.events, [.track("Weightless")])
    }

    func testByteAtATimeDeliveryStillYieldsEachLine() {
        let (controller, recorder) = controller()
        for byte in Data((WireFixtures.noPlayer + "\n" + WireFixtures.paused + "\n").utf8) {
            controller.ingest(Data([byte]))
        }
        settle()
        XCTAssertEqual(recorder.events, [.track(nil), .track("Weightless")])
    }

    func testBlankLinesAreIgnored() {
        let (controller, recorder) = controller()
        feed(controller, "\n\n" + WireFixtures.playing + "\n\n")
        settle()
        XCTAssertEqual(recorder.events, [.track("Weightless")])
    }

    func testMalformedLinesReachOnDecodingErrorWithTheirBytesAndDoNotStopTheStream() {
        let (controller, recorder) = controller()
        let lines = [WireFixtures.truncated, WireFixtures.wrongType, WireFixtures.noPayload, WireFixtures.notJSON]
        feed(controller, lines.joined(separator: "\n") + "\n" + WireFixtures.playing + "\n")
        settle()
        XCTAssertEqual(recorder.events, lines.map(Event.decodingError) + [.track("Weightless")])
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

    // MARK: - artwork downgrade

    func testArtworkIsKeptWhenTheSameTrackReportsItAgainWithoutArtwork() throws {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.withArtwork() + "\n" + WireFixtures.artworkDropped() + "\n")
        settle()
        let second = try XCTUnwrap(recorder.tracks.last)
        XCTAssertEqual(second.payload.artworkDataBase64, WireFixtures.artworkBase64)
        XCTAssertEqual(second.payload.artworkMimeType, "image/png")
        XCTAssertNotNil(second.payload.artwork)
        XCTAssertEqual(second.payload.elapsedTimeMicros, 2_000_000, "everything but the artwork is the NEW report")
    }

    func testArtworkIsDroppedWhenTheTrackChanges() throws {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.withArtwork() + "\n"
             + WireFixtures.artworkDropped(title: "Other", album: "Other") + "\n")
        settle()
        let second = try XCTUnwrap(recorder.tracks.last)
        XCTAssertEqual(second.payload.title, "Other")
        XCTAssertNil(second.payload.artworkDataBase64, "a different track must not inherit the old art")
    }

    func testArtworkSurvivesWhenOneSideLeavesTheAlbumEmpty() throws {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.withArtwork() + "\n" + WireFixtures.artworkDropped(album: "") + "\n")
        settle()
        XCTAssertNotNil(try XCTUnwrap(recorder.tracks.last).payload.artworkDataBase64)
    }

    func testArtworkIsDroppedWhenBothAlbumsAreSetAndDiffer() throws {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.withArtwork() + "\n" + WireFixtures.artworkDropped(album: "Live") + "\n")
        settle()
        XCTAssertNil(try XCTUnwrap(recorder.tracks.last).payload.artworkDataBase64)
    }

    func testALargerArtworkReplacesTheOldOne() throws {
        let (controller, recorder) = controller()
        feed(controller, WireFixtures.artworkDropped() + "\n" + WireFixtures.withArtwork() + "\n")
        settle()
        XCTAssertEqual(try XCTUnwrap(recorder.tracks.last).payload.artworkDataBase64, WireFixtures.artworkBase64)
    }
}
