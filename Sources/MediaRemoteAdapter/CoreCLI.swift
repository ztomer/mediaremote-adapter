import Foundation

/// The vendored core's command line and wire format, in ONE place: ungive/mediaremote-adapter's
/// `bin/mediaremote-adapter.pl` (shipped here as `run.pl`) and its README's "Usage". Everything
/// `MediaController` spawns is built here and everything it reads is decoded here.
///
/// argv is `run.pl <image> <function> [params|options]`, where `<image>` is the Mach-O image the
/// core is linked into (vendored patch 0003 lets the script load an image as well as a
/// `.framework` directory).
enum CoreCLI {

    /// The listener. `--micros`: the times arrive as the Payload's `*Micros` fields.
    /// `--no-diff`: every line is a whole payload, so no line depends on one before it (a restart
    /// or a dropped line cannot leave a stale field behind). `--debounce=100`: the 100 ms the old
    /// `run.pl loop` waited after a change notification before reading. `--exit-with-parent`
    /// (vendored patch 0004): the listener ends with this process, however this process ends.
    static let stream = ["stream", "--micros", "--no-diff", "--debounce=100", "--exit-with-parent"]

    /// A one-shot read: the payload itself (no envelope), or `null` when nothing is playing.
    static let get = ["get", "--micros"]

    /// ungive's `MRACommand` (include/MediaRemoteAdapter.h): the ids `send` accepts.
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
        case toggleShuffle = 6
        case toggleRepeat = 7
        case startForwardSeek = 8
        case endForwardSeek = 9
        case startBackwardSeek = 10
        case endBackwardSeek = 11
        case goBackFifteenSeconds = 12
        case skipFifteenSeconds = 13
    }

    static func send(_ command: Command) -> [String] {
        ["send", String(command.rawValue)]
    }

    /// `seek` takes whole microseconds and refuses a negative position; a position before the
    /// start is the start. A non-finite position is no position: nil, nothing is sent.
    static func seek(seconds: Double) -> [String]? {
        guard seconds.isFinite else { return nil }
        let micros = (max(0, seconds) * 1_000_000).rounded()
        guard micros < Double(Int64.max) else { return nil }
        return ["seek", String(Int64(micros))]
    }

    static func shuffle(_ mode: TrackInfo.ShuffleMode) -> [String] {
        ["shuffle", String(mode.wireValue)]
    }

    static func `repeat`(_ mode: TrackInfo.RepeatMode) -> [String] {
        ["repeat", String(mode.wireValue)]
    }

    // MARK: - the wire

    /// One `stream` line: `{"type":"data","diff":false,"payload":{...}}`. An EMPTY payload is the
    /// core's "nothing is playing" (it prints one whenever a player lacks the mandatory keys:
    /// a process, a playing state, a title) and decodes to nil.
    static func decodeStreamLine(_ line: Data) throws -> TrackInfo? {
        try JSONDecoder().decode(StreamLine.self, from: line).trackInfo
    }

    /// `get`'s one line: the payload object, or `null`.
    static func decodeGet(_ line: Data) throws -> TrackInfo? {
        if line == Data("null".utf8) { return nil }
        return try JSONDecoder().decode(GetLine.self, from: line).trackInfo
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct StreamLine: Decodable {
        let trackInfo: TrackInfo?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: StreamLineKeys.self)
            if let type = try container.decodeIfPresent(String.self, forKey: .type), type != "data" {
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: container, debugDescription: "unknown line type '\(type)'")
            }
            // The listener runs with --no-diff. A diff line carries only what changed, so reading it
            // as a whole payload would drop every unchanged field: refuse it, loudly.
            if try container.decodeIfPresent(Bool.self, forKey: .diff) == true {
                throw DecodingError.dataCorruptedError(
                    forKey: .diff, in: container,
                    debugDescription: "a diff line, but the listener asked for --no-diff: the core's CLI changed")
            }
            let keys = try container.nestedContainer(keyedBy: AnyKey.self, forKey: .payload).allKeys
            trackInfo = keys.isEmpty
                ? nil
                : TrackInfo(payload: try container.decode(TrackInfo.Payload.self, forKey: .payload))
        }
    }

    private struct GetLine: Decodable {
        let trackInfo: TrackInfo?

        init(from decoder: Decoder) throws {
            let keys = try decoder.container(keyedBy: AnyKey.self).allKeys
            trackInfo = keys.isEmpty ? nil : TrackInfo(payload: try TrackInfo.Payload(from: decoder))
        }
    }
}

private enum StreamLineKeys: String, CodingKey { case type, diff, payload }
