import AppKit
import AVFoundation
import MediaPlayer

// A silent, scripted Now Playing session for recording `run.pl loop`'s real wire output
// (tools/record_fixtures.sh). It plays a generated silent WAV at volume 0, publishes its track
// through MPNowPlayingInfoCenter and walks a fixed script: playing with artwork, paused, playing,
// a track change, the artwork and album removed, exit. Built twice by the recorder: as an app
// bundle (the wire then carries bundleIdentifier/applicationName/PID) and as a bare binary (those
// keys are then ABSENT from the payload, not null).
// The play/pause targets are not decoration: without a registered remote command the process is
// never made the now-playing app and the listener reports nothing.

let arguments = CommandLine.arguments
let audioURL = arguments.count > 1
    ? URL(fileURLWithPath: arguments[1])
    : Bundle.main.url(forResource: "silence", withExtension: "wav")
guard let audioURL, let player = try? AVAudioPlayer(contentsOf: audioURL) else {
    FileHandle.standardError.write(Data("fixture-player: no silent WAV to play\n".utf8))
    exit(2)
}
player.volume = 0
player.play()

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
}
let track = Track()

func publish() {
    var info: [String: Any] = [
        MPMediaItemPropertyTitle: track.title,
        MPMediaItemPropertyArtist: "mediaremote-adapter",
        MPMediaItemPropertyAlbumTitle: track.album,
        MPMediaItemPropertyPlaybackDuration: player.duration,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
        MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0
    ]
    if track.withArtwork { info[MPMediaItemPropertyArtwork] = artwork }
    center.nowPlayingInfo = info
    center.playbackState = player.isPlaying ? .playing : .paused
}

commands.playCommand.addTarget { _ in
    player.play()
    publish()
    return .success
}
commands.pauseCommand.addTarget { _ in
    player.pause()
    publish()
    return .success
}
publish()

let script: [(TimeInterval, () -> Void)] = [
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
