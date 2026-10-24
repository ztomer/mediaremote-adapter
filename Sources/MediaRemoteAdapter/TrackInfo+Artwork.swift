import Foundation

extension TrackInfo {

    /// A player often re-reports the track it is already playing with the artwork not yet
    /// re-fetched. Keep the artwork we have rather than flash to none: when `self` is the SAME track
    /// as `previous` and carries LESS artwork, it is returned with `previous`'s artwork; otherwise
    /// unchanged.
    func preservingArtwork(from previous: TrackInfo?) -> TrackInfo {
        guard let previous,
              Self.isSameTrack(previous.payload, payload) else {
            return self
        }

        let previousLen = previous.payload.artworkDataBase64?.count ?? 0
        let incomingLen = payload.artworkDataBase64?.count ?? 0
        guard incomingLen < previousLen else {
            return self
        }

        let current = payload
        let merged = TrackInfo.Payload(
            title: current.title,
            artist: current.artist,
            album: current.album,
            isPlaying: current.isPlaying,
            durationMicros: current.durationMicros,
            elapsedTimeMicros: current.elapsedTimeMicros,
            applicationName: current.applicationName,
            bundleIdentifier: current.bundleIdentifier,
            artworkDataBase64: previous.payload.artworkDataBase64,
            artworkMimeType: previous.payload.artworkMimeType,
            timestampEpochMicros: current.timestampEpochMicros,
            PID: current.PID,
            shuffleMode: current.shuffleMode,
            repeatMode: current.repeatMode,
            playbackRate: current.playbackRate,
            artwork: previous.payload.artwork
        )
        return TrackInfo(payload: merged)
    }

    private static func isSameTrack(_ lhs: Payload, _ rhs: Payload) -> Bool {
        guard lhs.title == rhs.title, lhs.artist == rhs.artist else { return false }
        let lhsAlbum = lhs.album ?? ""
        let rhsAlbum = rhs.album ?? ""
        return lhsAlbum == rhsAlbum || lhsAlbum.isEmpty || rhsAlbum.isEmpty
    }
}
