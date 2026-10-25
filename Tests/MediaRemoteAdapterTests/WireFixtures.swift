import Foundation

/// Lines as `run.pl` prints them: one JSON document per line, `{"type":"data","diff":false,
/// "payload":{...}}`, plus the bare token `NIL` for "no player".
///
/// Provenance. The data lines are RECORDED, byte for byte, from a live `run.pl loop` on macOS 27
/// (`tools/record_fixtures.sh`, 2026-10-24), playing `tools/fixture-player`: a silent player with
/// its own synthetic track, recorded once as an app bundle and once as a bare binary. Re-record
/// with that script; the lines here are found by what they say, not by position, so a re-recording
/// with new timestamps and PIDs still serves. What the recordings taught that the earlier hand
/// transcription had wrong:
///   - key order is the dictionary's, not fixed;
///   - each state change arrives TWICE: first with `artworkMimeType` set and `artworkDataBase64`
///     null, then again with the data (the artwork-downgrade path is the common case, not an edge);
///   - a player without a bundle identity OMITS `bundleIdentifier`, `applicationName` and `PID`
///     (absent, not null);
///   - `shuffleMode` and `repeatMode` are null for every player on this Mac.
/// `noPlayer` was recorded live too (`run.pl get` with nothing playing, 2026-10-24).
///
/// Still transcribed, each because a capture cannot produce it:
///   - `modesReported`: no player here reports a shuffle or repeat mode (the fixture player, and the
///     third-party player present while recording, both send null), so the enum decoding is held
///     to the serializer's shape by hand;
///   - `sparse`: a numeric `PID` and an integer `isPlaying`. The shim always prints `PID` as a
///     string and `isPlaying` as a bool, so no capture holds them; the decoder accepts them anyway;
///   - the malformed lines: rejects by definition, no healthy `run.pl` prints them.
enum WireFixtures {
    static let noPlayer = "NIL"

    // MARK: - recorded sessions

    /// The fixture player as an app bundle: every key present.
    static let bundledSession = load("loop-bundled-player")
    /// The same script from a bare binary: no `bundleIdentifier`/`applicationName`/`PID` keys.
    static let bareSession = load("loop-bare-player")

    /// Playing, artwork delivered.
    static let playing = find(in: bundledSession, title: "Fixture Tone", playing: true, artwork: true)
    /// The same report a moment earlier: playing, mime type set, artwork data not yet sent.
    static let artworkPending = find(in: bundledSession, title: "Fixture Tone", playing: true, artwork: false)
    /// Paused, artwork delivered.
    static let paused = find(in: bundledSession, title: "Fixture Tone", playing: false, artwork: true)
    /// Paused, re-reported without its artwork: the same track as `playing`.
    static let pausedArtworkPending = find(in: bundledSession, title: "Fixture Tone", playing: false, artwork: false)
    /// The track change: a new title, its artwork not yet sent.
    static let secondTrackPending = find(in: bundledSession, title: "Second Tone", playing: true, artwork: false,
                                         album: "Recorded Fixtures")
    /// The new track with its artwork.
    static let secondTrack = find(in: bundledSession, title: "Second Tone", playing: true, artwork: true)
    /// The player removed the artwork and the album.
    static let artworkRemoved = find(in: bundledSession, title: "Second Tone", playing: true, artwork: false, album: "")
    /// A player with no bundle identity, artwork delivered.
    static let barePlaying = find(in: bareSession, title: "Fixture Tone", playing: true, artwork: true)

    /// The payload of a line, read by `JSONSerialization`: the oracle the decoder is checked against.
    static func payload(_ line: String) -> [String: Any] {
        guard let doc = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let payload = doc["payload"] as? [String: Any] else {
            fatalError("not a recorded data line: \(line.prefix(80))")
        }
        return payload
    }

    /// A recorded line with payload fields replaced: for a case the recording holds only half of.
    static func edited(_ line: String, _ changes: [String: Any]) -> String {
        var payload = payload(line)
        for (key, value) in changes { payload[key] = value }
        let doc: [String: Any] = ["type": "data", "diff": false, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: doc),
              let text = String(bytes: data, encoding: .utf8) else {
            fatalError("could not re-serialize an edited line")
        }
        return text
    }

    private static func load(_ name: String) -> [String] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("recorded fixture \(name).jsonl is missing: run tools/record_fixtures.sh")
        }
        return text.split(separator: "\n").map(String.init)
    }

    private static func find(in session: [String], title: String, playing: Bool, artwork: Bool,
                             album: String? = nil) -> String {
        let match = session.first { line in
            let fields = payload(line)
            return fields["title"] as? String == title
                && fields["isPlaying"] as? Bool == playing
                && (fields["artworkDataBase64"] is String) == artwork
                && (album == nil || fields["album"] as? String == album)
        }
        guard let match else {
            fatalError("no recorded line: \(title) playing=\(playing) artwork=\(artwork): re-record")
        }
        return match
    }

    // MARK: - transcribed (see the provenance note above for why each one is)

    private static func line(_ payload: String) -> String {
        "{\"type\":\"data\",\"diff\":false,\"payload\":{\(payload)}}"
    }

    /// Shuffle and repeat reported (no player on this Mac does): songs/all, then off/off.
    static let modesReported = line("\"title\":\"Modes\",\"shuffleMode\":1,\"repeatMode\":2,\"isPlaying\":true")
    static let modesOff = line("\"title\":\"Modes\",\"shuffleMode\":0,\"repeatMode\":0,\"isPlaying\":false")

    /// Only a title and the player flag, the flag and PID as numbers.
    static let sparse = line("\"title\":\"Podcast\",\"isPlaying\":1,\"PID\":4321")

    /// Truncated mid-document, as a killed child leaves it.
    static let truncated = "{\"type\":\"data\",\"diff\":false,\"payload\":{\"title\":"
    /// Valid JSON, wrong type for a number field.
    static let wrongType = line("\"title\":\"X\",\"durationMicros\":\"soon\"")
    /// Valid JSON with no `payload`.
    static let noPayload = "{\"type\":\"data\",\"diff\":false}"
    static let notJSON = "perl: warning: Setting locale failed."
}
