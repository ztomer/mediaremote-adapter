import AppKit
import AVFoundation
import MediaPlayer

// A silent, scripted Now Playing session for recording the vendored core's real wire output
// (tools/record_fixtures.sh). It plays a generated silent WAV at volume 0, publishes its track
// through MPNowPlayingInfoCenter and runs one of two scripts:
//
//   FixturePlayer [--log PATH] [--commands] [WAV]
//
//   (default)   the stream script: playing with artwork, paused, playing, a track change, the
//               artwork and album removed, exit. Built twice by the recorder: as an app bundle and
//               as a bare binary (no bundle identity).
//   --commands  the command script: hold one track for 40 s with shuffle and repeat reported, and
//               append every remote command it RECEIVES to the --log file, one line each, so the
//               recorder can pair what it sent with what arrived.
//
// The remote command targets are not decoration: without a registered command the process is
// never made the now-playing app and the core reports nothing.

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}
func flag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}
let logPath = option("--log")
let commandScript = flag("--commands")
let audioURL = arguments.first.map { URL(fileURLWithPath: $0) }
    ?? Bundle.main.url(forResource: "silence", withExtension: "wav")
guard let audioURL, let player = try? AVAudioPlayer(contentsOf: audioURL) else {
    FileHandle.standardError.write(Data("fixture-player: no silent WAV to play\n".utf8))
    exit(2)
}
player.volume = 0
player.play()

func log(_ line: String) {
    guard let logPath else { return }
    let data = Data((line + "\n").utf8)
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: data)
    }
}

let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
    NSColor.systemTeal.setFill()
    rect.fill()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    return true
}
let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
let center = MPNowPlayingInfoCenter.default()
let commands = MPRemoteCommandCenter.shared()

final class Track {
    var title = "Fixture Tone"
    var album = "Recorded Fixtures"
    var withArtwork = true
    var rate = 1.0
}
let track = Track()

func publish() {
    var info: [String: Any] = [
        MPMediaItemPropertyTitle: track.title,
        MPMediaItemPropertyArtist: "mediaremote-adapter",
        MPMediaItemPropertyAlbumTitle: track.album,
        MPMediaItemPropertyPlaybackDuration: player.duration,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
        MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? track.rate : 0.0
    ]
    if track.withArtwork { info[MPMediaItemPropertyArtwork] = artwork }
    center.nowPlayingInfo = info
    center.playbackState = player.isPlaying ? .playing : .paused
}

func received(_ name: String, _ detail: String = "") -> MPRemoteCommandHandlerStatus {
    log(detail.isEmpty ? name : "\(name) \(detail)")
    return .success
}

commands.playCommand.addTarget { _ in
    player.play()
    publish()
    return received("play")
}
commands.pauseCommand.addTarget { _ in
    player.pause()
    publish()
    return received("pause")
}

if commandScript {
    commands.togglePlayPauseCommand.addTarget { _ in received("togglePlayPause") }
    commands.stopCommand.addTarget { _ in received("stop") }
    commands.nextTrackCommand.addTarget { _ in received("nextTrack") }
    commands.previousTrackCommand.addTarget { _ in received("previousTrack") }
    commands.seekForwardCommand.addTarget { event in
        received("seekForward", "\((event as? MPSeekCommandEvent)?.type == .beginSeeking ? "begin" : "end")")
    }
    commands.seekBackwardCommand.addTarget { event in
        received("seekBackward", "\((event as? MPSeekCommandEvent)?.type == .beginSeeking ? "begin" : "end")")
    }
    commands.skipForwardCommand.preferredIntervals = [15]
    commands.skipForwardCommand.addTarget { event in
        received("skipForward", "\(Int((event as? MPSkipIntervalCommandEvent)?.interval ?? -1))")
    }
    commands.skipBackwardCommand.preferredIntervals = [15]
    commands.skipBackwardCommand.addTarget { event in
        received("skipBackward", "\(Int((event as? MPSkipIntervalCommandEvent)?.interval ?? -1))")
    }
    commands.changePlaybackPositionCommand.addTarget { event in
        let time = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? -1
        return received("changePlaybackPosition", String(format: "%.3f", time))
    }
    commands.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1, 2]
    commands.changePlaybackRateCommand.addTarget { event in
        received("changePlaybackRate", "\((event as? MPChangePlaybackRateCommandEvent)?.playbackRate ?? -1)")
    }
    // MPShuffleType and MPRepeatType, by name, so the log reads without the enum's numbering.
    let shuffleNames: [MPShuffleType: String] = [.off: "off", .items: "items", .collections: "collections"]
    let repeatNames: [MPRepeatType: String] = [.off: "off", .one: "one", .all: "all"]
    commands.changeShuffleModeCommand.currentShuffleType = .items
    commands.changeShuffleModeCommand.addTarget { event in
        let type = (event as? MPChangeShuffleModeCommandEvent)?.shuffleType
        return received("changeShuffleMode", type.flatMap { shuffleNames[$0] } ?? "?")
    }
    commands.changeRepeatModeCommand.currentRepeatType = .all
    commands.changeRepeatModeCommand.addTarget { event in
        let type = (event as? MPChangeRepeatModeCommandEvent)?.repeatType
        return received("changeRepeatMode", type.flatMap { repeatNames[$0] } ?? "?")
    }
    commands.likeCommand.addTarget { _ in received("like") }
    commands.dislikeCommand.addTarget { _ in received("dislike") }
    commands.bookmarkCommand.addTarget { _ in received("bookmark") }
}
publish()

let script: [(TimeInterval, () -> Void)] = commandScript
    ? [(40, { exit(0) })]
    : [
        (4, { player.pause(); publish() }),
        (6, { player.play(); publish() }),
        (8, { track.title = "Second Tone"; publish() }),
        (11, { track.withArtwork = false; track.album = ""; publish() }),
        (14, { exit(0) })
    ]
for (delay, step) in script {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step)
}
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
