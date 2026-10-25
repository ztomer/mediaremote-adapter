import AppKit
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

        return copy(artworkDataBase64: previous.payload.artworkDataBase64,
                    artworkMimeType: previous.payload.artworkMimeType,
                    artwork: previous.payload.artwork)
    }

    /// The core reports the player's process and bundle identifier but not its display name, which
    /// the old run.pl did: `name` (a lookup by PID) fills it in. A payload that already has a name,
    /// or has no PID, is returned unchanged.
    func namingApplication(with name: (pid_t) -> String?) -> TrackInfo {
        guard payload.applicationName == nil, let pid = payload.PID, let resolved = name(pid) else {
            return self
        }
        return copy(applicationName: resolved)
    }

    /// This report with some fields replaced; every other field is kept.
    private func copy(applicationName: String? = nil, artworkDataBase64: String? = nil,
                      artworkMimeType: String? = nil, artwork: NSImage? = nil) -> TrackInfo {
        let current = payload
        let artworkReplaced = artworkDataBase64 != nil
        return TrackInfo(payload: TrackInfo.Payload(
            title: current.title,
            artist: current.artist,
            album: current.album,
            isPlaying: current.isPlaying,
            durationMicros: current.durationMicros,
            elapsedTimeMicros: current.elapsedTimeMicros,
            applicationName: applicationName ?? current.applicationName,
            bundleIdentifier: current.bundleIdentifier,
            artworkDataBase64: artworkReplaced ? artworkDataBase64 : current.artworkDataBase64,
            artworkMimeType: artworkReplaced ? artworkMimeType : current.artworkMimeType,
            timestampEpochMicros: current.timestampEpochMicros,
            PID: current.PID,
            shuffleMode: current.shuffleMode,
            repeatMode: current.repeatMode,
            playbackRate: current.playbackRate,
            artwork: artworkReplaced ? artwork : current.artwork
        ))
    }

    private static func isSameTrack(_ lhs: Payload, _ rhs: Payload) -> Bool {
        guard lhs.title == rhs.title, lhs.artist == rhs.artist else { return false }
        let lhsAlbum = lhs.album ?? ""
        let rhsAlbum = rhs.album ?? ""
        return lhsAlbum == rhsAlbum || lhsAlbum.isEmpty || rhsAlbum.isEmpty
    }
}
