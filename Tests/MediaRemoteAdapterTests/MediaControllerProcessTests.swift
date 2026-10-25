import Foundation
import XCTest
@testable import MediaRemoteAdapter

/// `MediaController` against a REAL child process: `/usr/bin/perl` running a fixture in place of
/// `run.pl` (see `FixtureProcess`). Covers the spawn, the argv, the pipes, EOF, the command path
/// and the listener's lifecycle - everything the stream tests deliberately skip.
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

    func testGetTrackInfoDeliversTheRecordedPayloadOnce() throws {
        let got = try fetch([WireFixtures.getPlaying])
        XCTAssertEqual(got.info?.payload.title, "Fixture Tone")
        let recordedPID = (WireFixtures.payload(WireFixtures.getPlaying)["processIdentifier"] as? Int).map { pid_t($0) }
        XCTAssertNotNil(recordedPID)
        XCTAssertEqual(got.info?.payload.PID, recordedPID)
        XCTAssertEqual(got.calls, 1)
        XCTAssertEqual(got.fixture.logLines, ["argv get --micros"])
    }

    func testGetTrackInfoDeliversNilForNoPlayer() throws {
        let got = try fetch([WireFixtures.getNoPlayer])
        XCTAssertNil(got.info)
        XCTAssertEqual(got.calls, 1)
    }

    func testGetTrackInfoDeliversNilForAMalformedLine() throws {
        let got = try fetch([WireFixtures.truncated])
        XCTAssertNil(got.info)
        XCTAssertEqual(got.calls, 1)
    }

    func testGetTrackInfoSkipsBlankLinesAndTakesTheFirstRealOne() throws {
        let paused = WireFixtures.getPlaying
            .replacingOccurrences(of: "\"playing\":true", with: "\"playing\":false")
        XCTAssertNotEqual(paused, WireFixtures.getPlaying)
        let got = try fetch(["", paused, WireFixtures.getPlaying])
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

    /// Every public command, the argv it runs (one child each, in call order). What each argv makes
    /// a real player receive is `CommandFixtureTests`'s half.
    static func commandTable(_ controller: MediaController) -> [(String, () -> Void)] {
        [
            ("send 0", controller.play),
            ("send 1", controller.pause),
            ("send 2", controller.togglePlayPause),
            ("send 4", controller.nextTrack),
            ("send 5", controller.previousTrack),
            ("send 3", controller.stop),
            ("seek 12500000", { controller.setTime(seconds: 12.5) }),
            ("seek 0", { controller.setTime(seconds: -3) }),
            ("send 6", controller.toggleShuffle),
            ("send 7", controller.toggleRepeat),
            ("send 8", controller.startForwardSeek),
            ("send 9", controller.endForwardSeek),
            ("send 10", controller.startBackwardSeek),
            ("send 11", controller.endBackwardSeek),
            ("send 12", controller.goBackFifteenSeconds),
            ("send 13", controller.skipFifteenSeconds),
            ("shuffle 1", { controller.setShuffleMode(.off) }),
            ("shuffle 2", { controller.setShuffleMode(.albums) }),
            ("shuffle 3", { controller.setShuffleMode(.songs) }),
            ("repeat 1", { controller.setRepeatMode(.off) }),
            ("repeat 2", { controller.setRepeatMode(.one) }),
            ("repeat 3", { controller.setRepeatMode(.all) })
        ]
    }

    func testEveryPlaybackCommandRunsTheCoreWithItsArguments() throws {
        let fixture = try FixtureProcess()
        let controller = fixture.controller()
        let table = Self.commandTable(controller)
        for (_, send) in table { send() }
        // A position that is no position sends nothing.
        controller.setTime(seconds: .nan)
        controller.setTime(seconds: .infinity)
        fixture.waitUntil("all \(table.count) commands run") { fixture.logLines.count >= table.count }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(fixture.logLines, table.map { "argv " + $0.0 }, "commands run in order, one child each")
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

    private static let streamArgv = "argv " + CoreCLI.stream.joined(separator: " ")

    func testListenerStreamsLinesAndCommandsRunBesideIt() throws {
        let record = Box<[String?]>([])
        let (fixture, controller) = try startListener(
            lines: [WireFixtures.playing, WireFixtures.noPlayer, WireFixtures.paused], hold: true, record: record)
        defer { controller.stopListening() }
        fixture.waitUntil("three events") { record.value.count >= 3 }
        XCTAssertEqual(record.value, ["Fixture Tone", nil, "Fixture Tone"])
        XCTAssertEqual(Self.streamArgv, "argv stream --micros --no-diff --debounce=100 --exit-with-parent")

        controller.startListening() // already listening: must not spawn a second child
        controller.togglePlayPause()
        controller.setTime(seconds: 3)
        fixture.waitUntil("two command children") { fixture.logLines.count >= 4 }
        XCTAssertEqual(fixture.logLines, [Self.streamArgv, "stdin eof", "argv send 2", "argv seek 3000000"],
                       "one listener, given no stdin; each command its own child (the core's stream reads none)")
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
        fixture.waitUntil("a second listener spawn") { fixture.logLines.filter { $0 == Self.streamArgv }.count == 2 }
        controller.stopListening()
    }

    func testListenerExitWithoutEventsIsNotReported() throws {
        let record = Box<[String?]>([])
        let (fixture, controller) = try startListener(lines: [], hold: false, record: record)
        let terminated = Box(0)
        controller.onListenerTerminated = { terminated.value += 1 }
        fixture.waitUntil("the child ran") { fixture.logLines.contains(Self.streamArgv) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(terminated.value, 0, "a listener that never produced an event is a startup failure, not a death")
    }

    func testListenerIsRestartedAfterTheEventThreshold() throws {
        let record = Box<[String?]>([])
        let (fixture, controller) = try startListener(
            lines: Array(repeating: WireFixtures.playing, count: 100), hold: true, record: record)
        defer { controller.stopListening() }
        fixture.waitUntil("the listener respawned after 100 events", timeout: 20) {
            fixture.logLines.filter { $0 == Self.streamArgv }.count >= 2
        }
    }
}
