import Foundation

/// Lines as the vendored core prints them. `stream` (with the listener's flags, `CoreCLI.stream`):
/// one JSON document per line, `{"type":"data","diff":false,"payload":{...}}`, the payload EMPTY
/// for "nothing playing". `get --micros`: the payload object itself, or `null`.
///
/// Provenance. The data lines are RECORDED, byte for byte, from the vendored core on macOS 27
/// (`tools/record_fixtures.sh`, 2026-10-24), playing `tools/fixture-player`: a silent player with
/// its own synthetic track, recorded once as an app bundle and once as a bare binary, through the
/// package's own `run.pl` and dylib. Re-record with that script; lines are found by what they say,
/// not by position, so a re-recording with new timestamps and PIDs still serves. What the
/// recordings show:
///   - key order is the dictionary's, not fixed;
///   - each state change usually arrives TWICE: first with `artworkMimeType` set and the
///     `artworkData` key absent, then again with the data;
///   - the first line of a stream is the empty payload (the core prints it until the player's
///     process, playing state and title have all arrived), and so is the line after the player
///     exits;
///   - a player without a bundle identity OMITS `bundleIdentifier` but still has its
///     `processIdentifier`;
///   - neither player reports a shuffle or repeat mode (the keys are absent).
/// `legacy-run-pl-loop.jsonl` is the OLD `run.pl loop`'s recording (ejbills's shim, 2026-10-24),
/// kept verbatim: the decoder still reads that spelling.
///
/// Still transcribed, each because a capture cannot produce it:
///   - `getNoPlayer` (`null`): this Mac always has another, paused player that becomes the
///     fallback when the fixture player exits, so `get` returns that player (never recorded);
///     `null` is the core's documented literal, and the stream's empty payload IS recorded;
///   - `modesReported`/`modesOff`: no player here reports a mode, the fixture player included
///     (MediaPlayer's current shuffle/repeat types do not reach Now Playing), so the decoding is
///     held to MediaRemote's numbering, which `commands.tsv` records live in the other direction;
///   - the malformed lines: rejects by definition, no healthy core prints them.
enum WireFixtures {

    // MARK: - recorded sessions

    /// The fixture player as an app bundle: every key present.
    static let bundledSession = load("stream-bundled-player", "jsonl")
    /// The same script from a bare binary: no `bundleIdentifier` key.
    static let bareSession = load("stream-bare-player", "jsonl")
    /// The old run.pl's spelling of the same session.
    static let legacySession = load("legacy-run-pl-loop", "jsonl")

    /// "Nothing playing": the stream's empty payload, as recorded.
    static let noPlayer: String = {
        guard let line = bundledSession.first(where: { payload($0).isEmpty }) else {
            fatalError("no recorded empty payload: re-record")
        }
        return line
    }()

    /// Playing, artwork delivered.
    static let playing = find(in: bundledSession, title: "Fixture Tone", playing: true, artwork: true)
    /// The same report a moment earlier: playing, mime type set, artwork data not yet sent.
    static let artworkPending = find(in: bundledSession, title: "Fixture Tone", playing: true, artwork: false)
    /// Paused, artwork delivered.
    static let paused = find(in: bundledSession, title: "Fixture Tone", playing: false, artwork: true)
    /// The track change: a new title, its artwork not yet sent.
    static let secondTrackPending = find(in: bundledSession, title: "Second Tone", playing: true, artwork: false,
                                         album: "Recorded Fixtures")
    /// The new track with its artwork.
    static let secondTrack = find(in: bundledSession, title: "Second Tone", playing: true, artwork: true)
    /// The player removed the artwork and the album.
    static let artworkRemoved = find(in: bundledSession, title: "Second Tone", playing: true, artwork: false, album: "")
    /// A player with no bundle identity, artwork delivered.
    static let barePlaying = find(in: bareSession, title: "Fixture Tone", playing: true, artwork: true)

    /// `get --micros` while the bundled player played: the payload object, no envelope.
    static let getPlaying = load("get-bundled-player", "json")[0]

    /// The old run.pl's playing line with its artwork (`isPlaying`, `artworkDataBase64`, a string
    /// `PID`, `applicationName`).
    static let legacyPlaying: String = {
        guard let line = legacySession.first(where: {
            payload($0)["isPlaying"] as? Bool == true && payload($0)["artworkDataBase64"] is String
        }) else { fatalError("no legacy playing line") }
        return line
    }()

    /// What the player RECEIVED for each command argv, recorded live: argv -> events.
    static let commandsReceived: [String: [String]] = {
        var table: [String: [String]] = [:]
        for row in load("commands", "tsv") where !row.hasPrefix("#") {
            let columns = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let events = columns.count > 1 ? columns[1] : ""
            table[columns[0]] = events.isEmpty ? [] : events.components(separatedBy: ";")
        }
        return table
    }()

    /// The payload of a stream line (or a `get` line), read by `JSONSerialization`: the oracle the
    /// decoder is checked against.
    static func payload(_ line: String) -> [String: Any] {
        guard let doc = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            fatalError("not a recorded data line: \(line.prefix(80))")
        }
        if doc["type"] == nil { return doc }
        guard let payload = doc["payload"] as? [String: Any] else {
            fatalError("not a recorded data line: \(line.prefix(80))")
        }
        return payload
    }

    /// A recorded stream line with payload fields replaced (NSNull removes a key): for a case the
    /// recording holds only half of.
    static func edited(_ line: String, _ changes: [String: Any]) -> String {
        var payload = payload(line)
        for (key, value) in changes {
            payload[key] = value is NSNull ? nil : value
        }
        let doc: [String: Any] = ["type": "data", "diff": false, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: doc),
              let text = String(bytes: data, encoding: .utf8) else {
            fatalError("could not re-serialize an edited line")
        }
        return text
    }

    private static func load(_ name: String, _ type: String) -> [String] {
        guard let url = Bundle.module.url(forResource: name, withExtension: type, subdirectory: "Fixtures"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("recorded fixture \(name).\(type) is missing: run tools/record_fixtures.sh")
        }
        return text.split(separator: "\n").map(String.init)
    }

    private static func find(in session: [String], title: String, playing: Bool, artwork: Bool,
                             album: String? = nil) -> String {
        let match = session.first { line in
            let fields = payload(line)
            return fields["title"] as? String == title
                && fields["playing"] as? Bool == playing
                && (fields["artworkData"] is String) == artwork
                && (album == nil || fields["album"] as? String == album)
        }
        guard let match else {
            fatalError("no recorded line: \(title) playing=\(playing) artwork=\(artwork): re-record")
        }
        return match
    }

    // MARK: - transcribed (see the provenance note above for why each one is)

    static let getNoPlayer = "null"

    private static func line(_ payload: String) -> String {
        "{\"type\":\"data\",\"diff\":false,\"payload\":{\(payload)}}"
    }

    /// Shuffle and repeat reported in MediaRemote's numbering: songs (3) and all (3), then off (1).
    static let modesReported = line("\"title\":\"Modes\",\"shuffleMode\":3,\"repeatMode\":3,\"playing\":true")
    static let modesOff = line("\"title\":\"Modes\",\"shuffleMode\":1,\"repeatMode\":1,\"playing\":false")
    /// The albums/one pair, and a 0, which MediaRemote does not use for a mode.
    static let modesMiddle = line("\"title\":\"Modes\",\"shuffleMode\":2,\"repeatMode\":2,\"playing\":true")
    static let modesZero = line("\"title\":\"Modes\",\"shuffleMode\":0,\"repeatMode\":0,\"playing\":true")

    /// A diff line: the listener asks for --no-diff, so one arriving means the CLI changed.
    static let diffLine = "{\"type\":\"data\",\"diff\":true,\"payload\":{\"playing\":false}}"
    /// A line type the core never printed.
    static let unknownType = "{\"type\":\"error\",\"diff\":false,\"payload\":{\"title\":\"X\"}}"
    /// Truncated mid-document, as a killed child leaves it.
    static let truncated = "{\"type\":\"data\",\"diff\":false,\"payload\":{\"title\":"
    /// Valid JSON, wrong type for a number field.
    static let wrongType = line("\"title\":\"X\",\"durationMicros\":\"soon\"")
    /// Valid JSON with no `payload`.
    static let noPayload = "{\"type\":\"data\",\"diff\":false}"
    static let notJSON = "perl: warning: Setting locale failed."
}
