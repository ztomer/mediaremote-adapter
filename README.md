# MediaRemoteAdapter

A Swift package for macOS that reads Now Playing and controls media playback through the private
`MediaRemote.framework`.

## This fork

This repository, `ztomer/mediaremote-adapter`, is the Swift package over
[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)'s core. It exists for
one consumer: **ZoneWM**, a macOS window manager that reads Now Playing through this package.
ZoneWM pins this fork's `main` branch, so `main` is the fork line and its history is never
rewritten.

- **The core is ungive's**, vendored at a pinned commit under
  [`Vendor/ungive-mediaremote-adapter`](Vendor/ungive-mediaremote-adapter/VENDORED.md): the
  Objective-C adapter and the Perl script that runs it in the system perl (which macOS lets use
  MediaRemote; an app is not). [`VENDORED.md`](Vendor/ungive-mediaremote-adapter/VENDORED.md)
  names the commit, the licence and every local patch, and the pre-push gate proves the tree is
  exactly upstream plus those patches. It is built by SwiftPM, mapped from ungive's CMake.
- **The Swift layer is this fork's**, from [ejbills/mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter)
  (whose own Objective-C copy of the core it replaces): `MediaController`, `TrackInfo` and the
  commands, over ungive's `stream`, `get`, `send`, `seek`, `shuffle` and `repeat`. It carries the
  pipe reader that cannot spin a core (`PipeReader`), every cross-queue field under one lock (run
  under ThreadSanitizer by the gate), and `artworkMimeType` read from the artwork's bytes.
- Swift 6 language mode, and a macOS 27 deployment floor (it follows ZoneWM's own floor).
- The tests replay the core's output as recorded live on a Mac playing a silent fixture player
  (`tools/record_fixtures.sh`), including what each command made that player receive.

The plan is in [ROADMAP.md](ROADMAP.md).

## Installation

Add `MediaRemoteAdapter` to your project using Swift Package Manager.

1. In Xcode: **File > Add Packages...**
2. Enter: `https://github.com/ztomer/mediaremote-adapter.git` and pick the `main` branch (this fork; the upstream package is `https://github.com/ejbills/mediaremote-adapter.git`).
3. Add `MediaRemoteAdapter` to your target.

### Embedding the Framework

After adding the package, ensure the framework is correctly embedded:

1. Select your project, then your main application target.
2. Go to the **General** tab.
3. In **"Frameworks, Libraries, and Embedded Content"**, set `MediaRemoteAdapter.framework` to **"Embed & Sign"**.

## Usage

```swift
import MediaRemoteAdapter

class YourAppController {
    let mediaController = MediaController()

    init() {
        // Handle incoming track data (nil when no media player is active)
        mediaController.onTrackInfoReceived = { trackInfo in
            guard let trackInfo = trackInfo else {
                print("No media playing")
                return
            }
            print("Now Playing: \(trackInfo.payload.title ?? "N/A")")

            // Get real-time playback position on demand
            if let position = trackInfo.payload.currentElapsedTime {
                print("Position: \(position)s")
            }
        }

        // Handle listener termination
        mediaController.onListenerTerminated = {
            print("Listener terminated")
        }
    }

    func start() {
        mediaController.startListening()
    }

    // Playback controls
    func play() { mediaController.play() }
    func pause() { mediaController.pause() }
    func togglePlayPause() { mediaController.togglePlayPause() }
    func nextTrack() { mediaController.nextTrack() }
    func previousTrack() { mediaController.previousTrack() }
    func stop() { mediaController.stop() }
    func seek(to seconds: Double) { mediaController.setTime(seconds: seconds) }

    // Shuffle and repeat
    func setShuffle(_ mode: TrackInfo.ShuffleMode) { mediaController.setShuffleMode(mode) }
    func setRepeat(_ mode: TrackInfo.RepeatMode) { mediaController.setRepeatMode(mode) }
    func toggleShuffle() { mediaController.toggleShuffle() }
    func toggleRepeat() { mediaController.toggleRepeat() }

    // Seeking
    func skipFifteenSeconds() { mediaController.skipFifteenSeconds() }
    func goBackFifteenSeconds() { mediaController.goBackFifteenSeconds() }
    func startForwardSeek() { mediaController.startForwardSeek() }
    func endForwardSeek() { mediaController.endForwardSeek() }
    func startBackwardSeek() { mediaController.startBackwardSeek() }
    func endBackwardSeek() { mediaController.endBackwardSeek() }

}
```

### One-Shot Track Info

Get current track info without starting a listener:

```swift
mediaController.getTrackInfo { trackInfo in
    guard let trackInfo = trackInfo else { return }
    print("Currently playing: \(trackInfo.payload.title ?? "Unknown")")
}
```

## API

### Callbacks

| Callback | Description |
|----------|-------------|
| `onTrackInfoReceived: ((TrackInfo?) -> Void)?` | Called with track info, or `nil` when no media is playing |
| `onDecodingError: ((Error, Data) -> Void)?` | JSON decode errors |
| `onListenerTerminated: (() -> Void)?` | Listener process terminated |

### Methods

| Method | Description |
|--------|-------------|
| `startListening()` | Start background listener |
| `stopListening()` | Stop listener |
| `getTrackInfo(_:)` | One-shot track info fetch |
| `play()`, `pause()`, `togglePlayPause()` | Playback control |
| `nextTrack()`, `previousTrack()`, `stop()` | Track navigation |
| `setTime(seconds:)` | Seek to position |
| `setShuffleMode(_:)` | Set shuffle (`.off`, `.songs`, `.albums`) |
| `setRepeatMode(_:)` | Set repeat (`.off`, `.one`, `.all`) |
| `toggleShuffle()` | Cycle through shuffle modes |
| `toggleRepeat()` | Cycle through repeat modes |
| `skipFifteenSeconds()` | Skip forward 15 seconds |
| `goBackFifteenSeconds()` | Skip back 15 seconds |
| `startForwardSeek()`, `endForwardSeek()` | Continuous forward seek (hold/release) |
| `startBackwardSeek()`, `endBackwardSeek()` | Continuous backward seek (hold/release) |

Each command runs the core once (`run.pl <image> send|seek|shuffle|repeat ...`). What each one
made a real player receive is recorded in `Tests/MediaRemoteAdapterTests/Fixtures/commands.tsv`:
`toggleShuffle()`, `toggleRepeat()` and the fifteen-second skips reached no MediaPlayer target of
the fixture player. The like/ban/wish-list commands are gone (none reached a player, one arrived as
"next track"), and ungive's `speed` is not exposed (the player received rate 1.0 for any value);
see `Vendor/ungive-mediaremote-adapter/VENDORED.md`.

### TrackInfo.Payload

| Property | Type | Description |
|----------|------|-------------|
| `title`, `artist`, `album`, `applicationName`, `bundleIdentifier` | `String?` | |
| `isPlaying` | `Bool?` | |
| `durationMicros`, `elapsedTimeMicros`, `timestampEpochMicros` | `Double?` | |
| `playbackRate` | `Double?` | 1.0 = playing, 0.0 = paused |
| `currentElapsedTime` | `TimeInterval?` | **Computed** - real-time position in seconds |
| `artwork` | `NSImage?` | Decoded once from base64 data at init |
| `artworkMimeType` | `String?` | The type the artwork's BYTES say (JPEG, PNG, GIF, TIFF, WebP, HEIC, AVIF, BMP); the player's label only for other bytes |
| `PID` | `pid_t?` | |
| `shuffleMode` | `ShuffleMode?` | MediaRemote numbers modes from 1; the enums' raw values are MediaPlayer's (from 0) |
| `repeatMode` | `RepeatMode?` | |
| `applicationName` | `String?` | The player's name, looked up from its process (the core reports the PID) |

> **Playback position:** `elapsedTimeMicros` is a snapshot from the last state change. Use `currentElapsedTime` to compute an accurate position on demand -- it interpolates from the snapshot using `timestampEpochMicros` and `playbackRate`.

## License

BSD 3-Clause. See [LICENSE](LICENSE); the vendored core keeps ungive's own
[LICENSE](Vendor/ungive-mediaremote-adapter/LICENSE).

## Acknowledgements

The core, and the technique of reaching MediaRemote through the system perl, are
[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)'s (Jonas van den Berg
and contributors). The Swift package began as [ejbills/mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter).
