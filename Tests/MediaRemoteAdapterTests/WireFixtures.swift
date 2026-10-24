import Foundation

/// Lines as `run.pl` prints them, one JSON document per line (`serializeData` in
/// `MediaRemoteAdapter.m`: `{"type":"data","diff":false,"payload":{...}}`, every key present, `null`
/// for a missing value, `PID` a decimal STRING, `isPlaying` a JSON bool, `/` escaped as `\/` by
/// NSJSONSerialization) plus the bare token `NIL` for "no player".
///
/// Provenance: `noPlayer` was recorded live on macOS 27 (`perl run.pl <dylib> get` with nothing
/// playing, 2026-10-24). A player cannot be driven headless here, so the data lines are transcribed
/// from the shim's serializer by hand, key for key; they are the shapes the decoder is held to.
enum WireFixtures {
    static let noPlayer = "NIL"

    /// `payload` body, with the app identity and a one-second-old timestamp left to the caller.
    private static func line(_ payload: String) -> String {
        "{\"type\":\"data\",\"diff\":false,\"payload\":{\(payload)}}"
    }

    static let playing = line("""
    "title":"Weightless","artist":"Marconi Union","album":"Weightless",\
    "durationMicros":480000000,"elapsedTimeMicros":12345678,"timestampEpochMicros":1792800000000000,\
    "artworkMimeType":null,"artworkDataBase64":null,"shuffleMode":1,"repeatMode":2,"playbackRate":1,\
    "isPlaying":true,"bundleIdentifier":"com.apple.Music","applicationName":"Music","PID":"1234"
    """)

    static let paused = line("""
    "title":"Weightless","artist":"Marconi Union","album":"Weightless",\
    "durationMicros":480000000,"elapsedTimeMicros":99000000,"timestampEpochMicros":1792800000000000,\
    "artworkMimeType":null,"artworkDataBase64":null,"shuffleMode":0,"repeatMode":0,"playbackRate":0,\
    "isPlaying":false,"bundleIdentifier":"com.apple.Music","applicationName":"Music","PID":"1234"
    """)

    /// A 2x2 PNG whose base64 contains `//`, escaped on the wire as `\/\/`.
    static let artworkBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEElEQVR4nGNg+P//PxjDGABlrAv1EPkwzAAAAABJRU5ErkJggg=="

    static func withArtwork(title: String = "Weightless", album: String = "Weightless") -> String {
        let escaped = artworkBase64.replacingOccurrences(of: "/", with: "\\/")
        return line("""
        "title":"\(title)","artist":"Marconi Union","album":"\(album)",\
        "durationMicros":480000000,"elapsedTimeMicros":1000000,"timestampEpochMicros":1792800000000000,\
        "artworkMimeType":"image\\/png","artworkDataBase64":"\(escaped)","shuffleMode":0,"repeatMode":0,\
        "playbackRate":1,"isPlaying":true,"bundleIdentifier":"com.spotify.client",\
        "applicationName":"Spotify","PID":"777"
        """)
    }

    /// The same track a moment later, the artwork not yet re-fetched: every field present, art null.
    static func artworkDropped(title: String = "Weightless", album: String = "Weightless") -> String {
        line("""
        "title":"\(title)","artist":"Marconi Union","album":"\(album)",\
        "durationMicros":480000000,"elapsedTimeMicros":2000000,"timestampEpochMicros":1792800001000000,\
        "artworkMimeType":null,"artworkDataBase64":null,"shuffleMode":0,"repeatMode":0,\
        "playbackRate":1,"isPlaying":true,"bundleIdentifier":"com.spotify.client",\
        "applicationName":"Spotify","PID":"777"
        """)
    }

    /// Only a title and the player flag: the app did not report the rest.
    static let sparse = line("\"title\":\"Podcast\",\"isPlaying\":1,\"PID\":4321")

    // MARK: - lines the decoder must reject

    /// Truncated mid-document, as a killed child leaves it.
    static let truncated = "{\"type\":\"data\",\"diff\":false,\"payload\":{\"title\":"
    /// Valid JSON, wrong type for a number field.
    static let wrongType = line("\"title\":\"X\",\"durationMicros\":\"soon\"")
    /// Valid JSON with no `payload`.
    static let noPayload = "{\"type\":\"data\",\"diff\":false}"
    static let notJSON = "perl: warning: Setting locale failed."
}
