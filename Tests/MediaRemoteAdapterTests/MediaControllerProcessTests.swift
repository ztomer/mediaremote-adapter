import Foundation
import XCTest
@testable import MediaRemoteAdapter

/// `MediaController` against a REAL child process: `/usr/bin/perl` running a fixture in place of
/// `run.pl` (see `FixtureProcess`). Covers the spawn, the pipes, EOF, the command path and the
/// listener's lifecycle - everything the stream tests deliberately skip.
final class MediaControllerProcessTests: XCTestCase {

    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    // MARK: - getTrackInfo

    private struct Fetched {
        let info: TrackInfo?
        let calls: Int
        let fixture: FixtureProcess
    }

    private func fetch(_ lines: [String]) throws -> Fetched {
        let fixture = try FixtureProcess()
        try fixture.setOutput(lines)
        let controller = fixture.controller()
        let calls = Box(0)
        let result = Box<TrackInfo?>(nil)
        controller.getTrackInfo { info in
            calls.value += 1
            result.value = info
        }
        fixture.waitUntil("getTrackInfo completion") { calls.value > 0 }
        // Anything delivered twice would show up now.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        return Fetched(info: result.value, calls: calls.value, fixture: fixture)
    }

    func testGetTrackInfoDeliversThePlayingLineOnce() throws {
        let got = try fetch([WireFixtures.playing])
        XCTAssertEqual(got.info?.payload.title, "Fixture Tone")
        let recordedPID = (WireFixtures.payload(WireFixtures.playing)["PID"] as? String).flatMap { Int32($0) }
        XCTAssertNotNil(recordedPID)
        XCTAssertEqual(got.info?.payload.PID, recordedPID)
        XCTAssertEqual(got.calls, 1)
        XCTAssertEqual(got.fixture.logLines, ["argv get"])
    }

    func testGetTrackInfoDeliversNilForNoPlayer() throws {
        let got = try fetch([WireFixtures.noPlayer])
        XCTAssertNil(got.info)
        XCTAssertEqual(got.calls, 1)
    }

    func testGetTrackInfoDeliversNilForAMalformedLine() throws {
        let got = try fetch([WireFixtures.truncated])
        XCTAssertNil(got.info)
        XCTAssertEqual(got.calls, 1)
    }

    func testGetTrackInfoSkipsBlankLinesAndTakesTheFirstRealOne() throws {
        let got = try fetch(["", WireFixtures.paused, WireFixtures.playing])
        XCTAssertEqual(got.info?.payload.isPlaying, false, "the FIRST non-empty line wins")
        XCTAssertEqual(got.calls, 1)
    }

    func testGetTrackInfoDeliversNilExactlyOnceWhenTheChildPrintsNothing() throws {
        let fixture = try FixtureProcess()
        let controller = fixture.controller()
        let calls = Box(0)
        controller.getTrackInfo { _ in calls.value += 1 }
        fixture.waitUntil("EOF fallback") { calls.value > 0 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(calls.value, 1)
    }

    func testGetTrackInfoWithAMissingScriptStillCompletes() throws {
        let fixture = try FixtureProcess()
        let controller = MediaController(scriptPath: fixture.directory.appendingPathComponent("absent.pl").path,
                                         libraryPath: fixture.logPath)
        let calls = Box(0)
        controller.getTrackInfo { _ in calls.value += 1 }
        fixture.waitUntil("completion for a script that fails to run") { calls.value > 0 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(calls.value, 1)
    }

    // MARK: - commands

    func testEveryPlaybackCommandReachesThePerlScriptWithItsArguments() throws {
        let fixture = try FixtureProcess()
        let controller = fixture.controller()
        let table: [(String, () -> Void)] = [
            ("argv play", controller.play),
            ("argv pause", controller.pause),
            ("argv toggle_play_pause", controller.togglePlayPause),
            ("argv next_track", controller.nextTrack),
            ("argv previous_track", controller.previousTrack),
            ("argv stop", controller.stop),
            ("argv set_time 12.5", { controller.setTime(seconds: 12.5) }),
            ("argv toggle_shuffle", controller.toggleShuffle),
            ("argv toggle_repeat", controller.toggleRepeat),
            ("argv start_forward_seek", controller.startForwardSeek),
            ("argv end_forward_seek", controller.endForwardSeek),
            ("argv start_backward_seek", controller.startBackwardSeek),
            ("argv end_backward_seek", controller.endBackwardSeek),
            ("argv go_back_fifteen_seconds", controller.goBackFifteenSeconds),
            ("argv skip_fifteen_seconds", controller.skipFifteenSeconds),
            ("argv like_track", controller.likeTrack),
            ("argv ban_track", controller.banTrack),
            ("argv add_to_wish_list", controller.addToWishList),
            ("argv remove_from_wish_list", controller.removeFromWishList),
            ("argv set_shuffle_mode 2", { controller.setShuffleMode(.albums) }),
            ("argv set_repeat_mode 1", { controller.setRepeatMode(.one) })
        ]
        for (_, send) in table { send() }
        fixture.waitUntil("all \(table.count) commands run") { fixture.logLines.count >= table.count }
        XCTAssertEqual(fixture.logLines, table.map(\.0), "commands run in order, one child each")
    }

    // MARK: - the listener

    private func startListener(lines: [String], hold: Bool, record: Box<[String?]>) throws
        -> (FixtureProcess, MediaController) {
        let fixture = try FixtureProcess()
        try fixture.setOutput(lines)
        if hold { try fixture.holdLoopOpen() }
        let controller = fixture.controller()
        controller.onTrackInfoReceived = { record.value.append($0?.payload.title) }
        controller.startListening()
        return (fixture, controller)
    }

    func testListenerStreamsLinesAndTakesCommandsOnStdinWhileAlive() throws {
        let record = Box<[String?]>([])
        let (fixture, controller) = try startListener(
            lines: [WireFixtures.playing, WireFixtures.noPlayer, WireFixtures.paused], hold: true, record: record)
        defer { controller.stopListening() }
        fixture.waitUntil("three events") { record.value.count >= 3 }
        XCTAssertEqual(record.value, ["Fixture Tone", nil, "Fixture Tone"])

        controller.startListening() // already listening: must not spawn a second child
        controller.togglePlayPause()
        controller.setTime(seconds: 3)
        fixture.waitUntil("commands written to the live listener") { fixture.logLines.count >= 3 }
        XCTAssertEqual(fixture.logLines, ["argv loop", "stdin toggle_play_pause", "stdin set_time 3.0"],
                       "one child, commands over its stdin, no per-command spawn")
    }

    func testListenerExitAfterEventsReportsTermination() throws {
        let record = Box<[String?]>([])
        let (fixture, controller) = try startListener(lines: [WireFixtures.playing], hold: false, record: record)
        let terminated = Box(0)
        controller.onListenerTerminated = { terminated.value += 1 }
        fixture.waitUntil("termination callback") { terminated.value > 0 }
        XCTAssertEqual(record.value, ["Fixture Tone"])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(terminated.value, 1)

        controller.startListening() // the slot is free again after termination
        fixture.waitUntil("a second listener spawn") { fixture.logLines.filter { $0 == "argv loop" }.count == 2 }
        controller.stopListening()
    }

    func testListenerExitWithoutEventsIsNotReported() throws {
        let record = Box<[String?]>([])
        let (fixture, controller) = try startListener(lines: [], hold: false, record: record)
        let terminated = Box(0)
        controller.onListenerTerminated = { terminated.value += 1 }
        fixture.waitUntil("the child ran") { fixture.logLines.contains("argv loop") }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(terminated.value, 0, "a listener that never produced an event is a startup failure, not a death")
    }

    func testListenerIsRestartedAfterTheEventThreshold() throws {
        let record = Box<[String?]>([])
        let (fixture, controller) = try startListener(
            lines: Array(repeating: WireFixtures.playing, count: 100), hold: true, record: record)
        defer { controller.stopListening() }
        fixture.waitUntil("the listener respawned after 100 events", timeout: 20) {
            fixture.logLines.filter { $0 == "argv loop" }.count >= 2
        }
    }
}
