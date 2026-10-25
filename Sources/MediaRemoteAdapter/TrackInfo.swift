import AppKit
import Foundation

public struct TrackInfo: Codable, Sendable {
    public let payload: Payload

    public init(payload: Payload) {
        self.payload = payload
    }

    public enum ShuffleMode: Int, Codable, Sendable {
        case off = 0
        case songs = 1
        case albums = 2
    }

    public enum RepeatMode: Int, Codable, Sendable {
        case off = 0
        case one = 1
        case all = 2
    }

    public struct Payload: Codable, Sendable {
        public let title: String?
        public let artist: String?
        public let album: String?
        public let isPlaying: Bool?
        public let durationMicros: Double?
        public let elapsedTimeMicros: Double?
        public let applicationName: String?
        public let bundleIdentifier: String?
        public let artworkDataBase64: String?
        public let artworkMimeType: String?
        public let timestampEpochMicros: Double?
        public let PID: pid_t?
        public let shuffleMode: ShuffleMode?
        public let repeatMode: RepeatMode?
        public let playbackRate: Double?

        public let artwork: NSImage?

        public var uniqueIdentifier: String {
            return "\(title ?? "")-\(artist ?? "")-\(album ?? "")"
        }

        public var currentElapsedTime: TimeInterval? {
            guard let elapsedMicros = elapsedTimeMicros,
                  let timestampMicros = timestampEpochMicros else {
                return nil
            }

            let elapsedSeconds = elapsedMicros / 1_000_000

            if isPlaying != true {
                return elapsedSeconds
            }

            let timestampSeconds = timestampMicros / 1_000_000
            let rate = playbackRate ?? 0.0

            let now = Date().timeIntervalSince1970
            let timeSinceUpdate = now - timestampSeconds

            return elapsedSeconds + (timeSinceUpdate * rate)
        }

        /// The keys this payload is read from and written as: ungive's core (`stream`/`get` with
        /// `--micros`) first, then the old `run.pl` spelling of the same field, which is still
        /// READ so a payload stored by an older version decodes. `applicationName` exists only in
        /// the old spelling: the core reports a process, and `MediaController` names it.
        enum CodingKeys: String, CodingKey {
            case title, artist, album, durationMicros, elapsedTimeMicros, applicationName, bundleIdentifier
            case artworkMimeType, timestampEpochMicros, shuffleMode, repeatMode, playbackRate
            case playing, artworkData, processIdentifier
            // The old run.pl spellings of `playing`, `artworkData` and `processIdentifier`.
            case isPlaying, artworkDataBase64, PID
        }

        public init(
            title: String? = nil,
            artist: String? = nil,
            album: String? = nil,
            isPlaying: Bool? = nil,
            durationMicros: Double? = nil,
            elapsedTimeMicros: Double? = nil,
            applicationName: String? = nil,
            bundleIdentifier: String? = nil,
            artworkDataBase64: String? = nil,
            artworkMimeType: String? = nil,
            timestampEpochMicros: Double? = nil,
            PID: pid_t? = nil,
            shuffleMode: ShuffleMode? = nil,
            repeatMode: RepeatMode? = nil,
            playbackRate: Double? = nil,
            artwork: NSImage? = nil
        ) {
            self.title = title
            self.artist = artist
            self.album = album
            self.isPlaying = isPlaying
            self.durationMicros = durationMicros
            self.elapsedTimeMicros = elapsedTimeMicros
            self.applicationName = applicationName
            self.bundleIdentifier = bundleIdentifier
            self.artworkDataBase64 = artworkDataBase64
            self.artworkMimeType = artworkMimeType
            self.timestampEpochMicros = timestampEpochMicros
            self.PID = PID
            self.shuffleMode = shuffleMode
            self.repeatMode = repeatMode
            self.playbackRate = playbackRate
            self.artwork = artwork
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.title = try container.decodeIfPresent(String.self, forKey: .title)
            self.artist = try container.decodeIfPresent(String.self, forKey: .artist)
            self.album = try container.decodeIfPresent(String.self, forKey: .album)
            self.durationMicros = try container.decodeIfPresent(Double.self, forKey: .durationMicros)
            self.elapsedTimeMicros = try container.decodeIfPresent(Double.self, forKey: .elapsedTimeMicros)
            self.applicationName = try container.decodeIfPresent(String.self, forKey: .applicationName)
            self.bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
            self.artworkDataBase64 = try container.decodeIfPresent(String.self, forKey: .artworkData)
                ?? container.decodeIfPresent(String.self, forKey: .artworkDataBase64)
            self.timestampEpochMicros = try container.decodeIfPresent(Double.self, forKey: .timestampEpochMicros)
            self.PID = Self.decodePID(container, .processIdentifier) ?? Self.decodePID(container, .PID)

            // The wire numbers are MediaRemote's, not the enums' raw values (`wireValue`). An
            // unknown number is no mode, never a failed line.
            self.shuffleMode = (try? container.decodeIfPresent(Int.self, forKey: .shuffleMode)).flatMap {
                $0.flatMap(ShuffleMode.init(wireValue:))
            }
            self.repeatMode = (try? container.decodeIfPresent(Int.self, forKey: .repeatMode)).flatMap {
                $0.flatMap(RepeatMode.init(wireValue:))
            }
            self.playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate)
            self.isPlaying = Self.decodeFlag(container, .playing) ?? Self.decodeFlag(container, .isPlaying)

            let artworkData = self.artworkDataBase64.flatMap { Data(base64Encoded: $0) }
            self.artworkMimeType = try container.decodeIfPresent(String.self, forKey: .artworkMimeType)
            self.artwork = artworkData.flatMap(NSImage.init(data:))
        }

        /// Writes the core's spelling, so what is encoded decodes to the same payload.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(artist, forKey: .artist)
            try container.encodeIfPresent(album, forKey: .album)
            try container.encodeIfPresent(isPlaying, forKey: .playing)
            try container.encodeIfPresent(durationMicros, forKey: .durationMicros)
            try container.encodeIfPresent(elapsedTimeMicros, forKey: .elapsedTimeMicros)
            try container.encodeIfPresent(applicationName, forKey: .applicationName)
            try container.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
            try container.encodeIfPresent(artworkDataBase64, forKey: .artworkData)
            try container.encodeIfPresent(artworkMimeType, forKey: .artworkMimeType)
            try container.encodeIfPresent(timestampEpochMicros, forKey: .timestampEpochMicros)
            try container.encodeIfPresent(PID, forKey: .processIdentifier)
            try container.encodeIfPresent(shuffleMode?.wireValue, forKey: .shuffleMode)
            try container.encodeIfPresent(repeatMode?.wireValue, forKey: .repeatMode)
            try container.encodeIfPresent(playbackRate, forKey: .playbackRate)
        }

        /// A PID as a number (the core) or a decimal string (the old run.pl).
        private static func decodePID(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> pid_t? {
            if let number = try? container.decodeIfPresent(Int32.self, forKey: key) {
                return number
            }
            if let text = try? container.decodeIfPresent(String.self, forKey: key) {
                return Int32(text)
            }
            return nil
        }

        /// A playing flag as a bool, or as 0/1.
        private static func decodeFlag(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Bool? {
            if let flag = try? container.decodeIfPresent(Bool.self, forKey: key) {
                return flag
            }
            if let number = try? container.decodeIfPresent(Int.self, forKey: key) {
                return number == 1
            }
            return nil
        }
    }
}

/// MediaRemote numbers its modes from 1 (ungive's `MRAShuffleMode`/`MRARepeatMode`, which `shuffle`
/// and `repeat` take, and which the payload reports). The enums' raw values are a different,
/// public numbering (MediaPlayer's `MPShuffleType`/`MPRepeatType`, from 0) and stay as they are;
/// the two meet only here.
extension TrackInfo.ShuffleMode {
    var wireValue: Int {
        switch self {
        case .off: 1
        case .albums: 2
        case .songs: 3
        }
    }

    init?(wireValue: Int) {
        switch wireValue {
        case 1: self = .off
        case 2: self = .albums
        case 3: self = .songs
        default: return nil
        }
    }
}

extension TrackInfo.RepeatMode {
    var wireValue: Int {
        switch self {
        case .off: 1
        case .one: 2
        case .all: 3
        }
    }

    init?(wireValue: Int) {
        switch wireValue {
        case 1: self = .off
        case 2: self = .one
        case 3: self = .all
        default: return nil
        }
    }
}
