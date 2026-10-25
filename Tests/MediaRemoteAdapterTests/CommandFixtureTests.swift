import Foundation
import XCTest
@testable import MediaRemoteAdapter

/// What each public command makes a REAL player receive, end to end: the argv the controller
/// runs (`MediaControllerProcessTests.commandTable`) looked up in Fixtures/commands.tsv, which
/// tools/record_fixtures.sh recorded by sending that argv through the vendored core to
/// tools/fixture-player and logging the MediaPlayer remote command that arrived.
///
/// This is the test the old shim never had: it passed `setShuffleMode(.songs)`'s raw value (1)
/// straight to MediaRemote, which reads 1 as "off".
final class CommandFixtureTests: XCTestCase {

    /// The MediaPlayer command each public method means. Empty: the fixture player received
    /// nothing (recorded; see the notes on the table).
    private static let expected: [String: [String]] = [
        "send 0": ["play"],
        "send 1": ["pause"],
        "send 2": ["togglePlayPause"],
        "send 3": ["stop"],
        "send 4": ["nextTrack"],
        "send 5": ["previousTrack"],
        "send 8": ["seekForward begin"],
        "send 9": ["seekForward end"],
        "send 10": ["seekBackward begin"],
        "send 11": ["seekBackward end"],
        "seek 12500000": ["changePlaybackPosition 12.500"],
        "seek 0": ["changePlaybackPosition 0.000"],
        "shuffle 1": ["changeShuffleMode off"],
        "shuffle 2": ["changeShuffleMode collections"],
        "shuffle 3": ["changeShuffleMode items"],
        "repeat 1": ["changeRepeatMode off"],
        "repeat 2": ["changeRepeatMode one"],
        "repeat 3": ["changeRepeatMode all"],
        // MediaRemote delivers no MediaPlayer event for these to a player that registered every
        // MPRemoteCommandCenter target (recorded 2026-10-24, macOS 27): toggle shuffle/repeat have
        // no MediaPlayer command, and the 15 s skips did not reach skipForward/skipBackward. They
        // are the same MRCommand ids the old shim sent; a player MediaRemote talks to natively may
        // still act on them.
        "send 6": [],
        "send 7": [],
        "send 12": [],
        "send 13": []
    ]

    func testEveryPublicCommandWasRecordedAgainstARealPlayer() throws {
        let fixture = try FixtureProcess()
        let argvs = MediaControllerProcessTests.commandTable(fixture.controller()).map(\.0)
        XCTAssertEqual(Set(argvs), Set(Self.expected.keys), "a command without a recorded expectation")
        for argv in argvs {
            let received = try XCTUnwrap(WireFixtures.commandsReceived[argv], "\(argv) was not recorded: re-record")
            XCTAssertEqual(received, Self.expected[argv], argv)
        }
    }

    func testShuffleAndRepeatModesReachThePlayerAsTheirNames() {
        let shuffle: [TrackInfo.ShuffleMode: String] = [.off: "off", .albums: "collections", .songs: "items"]
        for (mode, name) in shuffle {
            let argv = CoreCLI.shuffle(mode).joined(separator: " ")
            XCTAssertEqual(WireFixtures.commandsReceived[argv], ["changeShuffleMode \(name)"], "\(mode)")
        }
        let repeats: [TrackInfo.RepeatMode: String] = [.off: "off", .one: "one", .all: "all"]
        for (mode, name) in repeats {
            let argv = CoreCLI.repeat(mode).joined(separator: " ")
            XCTAssertEqual(WireFixtures.commandsReceived[argv], ["changeRepeatMode \(name)"], "\(mode)")
        }
    }
}
