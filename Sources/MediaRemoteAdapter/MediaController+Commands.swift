import Foundation

/// The playback commands. Each is one word on `run.pl`'s command line: over the live listener's
/// stdin when there is one, else a one-shot child (`MediaController.sendCommand`).
extension MediaController {

    public func play() { sendCommand(["play"]) }

    public func pause() { sendCommand(["pause"]) }

    public func togglePlayPause() { sendCommand(["toggle_play_pause"]) }

    public func nextTrack() { sendCommand(["next_track"]) }

    public func previousTrack() { sendCommand(["previous_track"]) }

    public func stop() { sendCommand(["stop"]) }

    public func setTime(seconds: Double) { sendCommand(["set_time", String(seconds)]) }

    public func toggleShuffle() { sendCommand(["toggle_shuffle"]) }

    public func toggleRepeat() { sendCommand(["toggle_repeat"]) }

    public func startForwardSeek() { sendCommand(["start_forward_seek"]) }

    public func endForwardSeek() { sendCommand(["end_forward_seek"]) }

    public func startBackwardSeek() { sendCommand(["start_backward_seek"]) }

    public func endBackwardSeek() { sendCommand(["end_backward_seek"]) }

    public func goBackFifteenSeconds() { sendCommand(["go_back_fifteen_seconds"]) }

    public func skipFifteenSeconds() { sendCommand(["skip_fifteen_seconds"]) }

    public func likeTrack() { sendCommand(["like_track"]) }

    public func banTrack() { sendCommand(["ban_track"]) }

    public func addToWishList() { sendCommand(["add_to_wish_list"]) }

    public func removeFromWishList() { sendCommand(["remove_from_wish_list"]) }

    public func setShuffleMode(_ mode: TrackInfo.ShuffleMode) {
        sendCommand(["set_shuffle_mode", String(mode.rawValue)])
    }

    public func setRepeatMode(_ mode: TrackInfo.RepeatMode) {
        sendCommand(["set_repeat_mode", String(mode.rawValue)])
    }
}
