import Foundation

/// The playback commands. Each runs the core once (`CoreCLI`): `send <MRACommand>` for the
/// transport, `seek`, `shuffle` and `repeat` for the rest. What each one makes a player receive is
/// recorded live in Fixtures/commands.tsv and held by `CommandFixtureTests`.
///
/// Not here, on purpose (measured 2026-10-24 against tools/fixture-player, macOS 27): the old
/// like/ban/add-to-wish-list/remove-from-wish-list commands (MRCommand 0x6A-0x6D). None reached
/// the player's like, dislike or bookmark target, and 0x6D arrived as "next track"; ungive's
/// core refuses them for the same reason. And ungive's `speed`: the player received rate 1.0
/// whatever speed was sent.
extension MediaController {

    public func play() { send(.play) }

    public func pause() { send(.pause) }

    public func togglePlayPause() { send(.togglePlayPause) }

    public func nextTrack() { send(.nextTrack) }

    public func previousTrack() { send(.previousTrack) }

    public func stop() { send(.stop) }

    /// Seeks to `seconds` (whole microseconds on the wire; a negative position is the start).
    public func setTime(seconds: Double) {
        guard let arguments = CoreCLI.seek(seconds: seconds) else { return }
        sendCommand(arguments)
    }

    public func toggleShuffle() { send(.toggleShuffle) }

    public func toggleRepeat() { send(.toggleRepeat) }

    public func startForwardSeek() { send(.startForwardSeek) }

    public func endForwardSeek() { send(.endForwardSeek) }

    public func startBackwardSeek() { send(.startBackwardSeek) }

    public func endBackwardSeek() { send(.endBackwardSeek) }

    public func goBackFifteenSeconds() { send(.goBackFifteenSeconds) }

    public func skipFifteenSeconds() { send(.skipFifteenSeconds) }

    public func setShuffleMode(_ mode: TrackInfo.ShuffleMode) {
        sendCommand(CoreCLI.shuffle(mode))
    }

    public func setRepeatMode(_ mode: TrackInfo.RepeatMode) {
        sendCommand(CoreCLI.repeat(mode))
    }

    private func send(_ command: CoreCLI.Command) {
        sendCommand(CoreCLI.send(command))
    }
}
