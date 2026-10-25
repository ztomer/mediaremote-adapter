# Vendored: ungive/mediaremote-adapter

The package's core: the Objective-C adapter and the Perl script that loads it into the system perl
(which macOS lets use MediaRemote), as maintained upstream.

| | |
|---|---|
| Source | <https://github.com/ungive/mediaremote-adapter> (branch `master`) |
| Commit | `0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd` (2026-10-17, "Sort projects alphabetically") |
| License | BSD 3-Clause, Copyright (c) 2025 Jonas van den Berg and contributors: [LICENSE](LICENSE), unmodified |
| Vendored | 2026-10-24 |

## What is here

Upstream's `LICENSE`, `README.md`, `CMakeLists.txt`, `include/`, `src/` and `bin/`, byte for byte at
that commit, then the patches below. Left out: `.vscode/`, `scripts/` (developer tooling),
`Makefile`, and the dotfiles (`.clang-format`, `.cmake-format`, `.perltidyrc`, `.gitignore`,
`.gitmodules`, which is empty). `upstream.sha256` records every vendored file as upstream has it;
`tools/check_vendored.sh` (run by the pre-push gate) reverse-applies the patches and checks the
result against it, so an edit here that is not a listed patch is red.

## How it is built

SwiftPM, mapped from `CMakeLists.txt` without changing a source (`Package.swift`):

- target `MediaRemoteAdapterCore`: CMake's `ADAPTER_SOURCES` (`src/adapter`, `src/private`,
  `src/utility`), public headers `include/`, private include root `src` (`headerSearchPath`),
  linked against Foundation, AppKit and UniformTypeIdentifiers. Not built: `src/test/` (CMake's
  separate `MediaRemoteAdapterTestClient`, which only the `test` function uses).
- `bin/mediaremote-adapter.pl` ships as the Swift target's resource `run.pl` (the name consumers'
  availability probes look for), a byte copy held equal by `tools/check_vendored.sh`.
- CMake's `-fobjc-arc` is clang's default for these targets (`tools/repo_gates.sh` reads it off the
  real compile line); its `-fvisibility=default` is SwiftPM's default.

The core is linked into the package's own image (the Swift layer's dylib or framework), which is
what the script loads: `MediaController` finds that image from a core symbol's address and passes
its path. So, unlike upstream's, this build of the core is also loaded into every host app. That
is what patches 0002 and 0003 are for.

## Local patches

Applied in order. Each is a `git apply`-able file; regenerate one by diffing the tree before and
after it.

1. [`patches/0001-stream-observers-before-initial-fetch-ungive-pr-38.patch`](patches/0001-stream-observers-before-initial-fetch-ungive-pr-38.patch):
   `stream` installs its notification observers and registers for MediaRemote's notifications
   BEFORE the initial fetch, and dispatches that fetch onto the serial queue, so its replies are
   ordered against startup notifications. Upstream's open pull request
   [ungive/mediaremote-adapter#38](https://github.com/ungive/mediaremote-adapter/pull/38) by
   Matthew Giles (mgxv), head `bf8bf81`, applied verbatim (the file is the PR's own patch). It
   resolves upstream's own FIXME at the old `requestAll()`. Drop it when #38 merges.
2. [`patches/0002-no-load-time-side-effects-in-a-host-process.patch`](patches/0002-no-load-time-side-effects-in-a-host-process.patch):
   the two load-time constructors with process-wide effects run at first use instead. `globals.m`
   loaded MediaRemote and called `exit(1)` if it could not (now a `dispatch_once` behind accessor
   functions; `globals.h` keeps the `g_mediaRemote`/`g_serialdispatchQueue` names as macros, so no
   other file changes). `stream.m` installed SIGINT/SIGTERM handlers that stop the loading
   thread's run loop (now installed when `adapter_stream` starts). Upstream loads the framework
   only into perl, where load time and first use coincide; here it is also linked into the host
   app, where they would have meant a SIGTERM that no longer quits the app and a fatal path
   reachable from dyld. Proof: `CoreLoadTests` (signal dispositions, red before) and
   `tools/repo_gates.sh` (only the allowlisted objects carry a load-time initializer).
3. [`patches/0003-perl-loads-an-image-path-as-well-as-a-framework.patch`](patches/0003-perl-loads-an-image-path-as-well-as-a-framework.patch):
   the script's `FRAMEWORK_PATH` may also be the Mach-O image the adapter is linked into. A
   SwiftPM build produces `libMediaRemoteAdapter.dylib` (or a test bundle), not a `.framework`
   directory; a framework path works as before.
4. [`patches/0004-stream-exit-with-parent.patch`](patches/0004-stream-exit-with-parent.patch):
   `stream --exit-with-parent` watches the parent process (a `DISPATCH_SOURCE_TYPE_PROC` exit
   source) and ends the stream when it exits. Without it, a host that crashed or was killed left
   the stream running until its next write failed, which with nothing playing may be never
   (measured: the orphan was still alive with the parent gone; with the option it exited). Opt-in,
   so upstream's CLI behaves as before. The old ejbills shim had the same guard (a parent PID poll).

## Findings not patched

- `speed N` does not set the speed on macOS 27: the fixture player received a playback rate of 1.0
  for every N tried (0, 1, 2, 3, 4, 10), and still did with `MRMediaRemoteSetPlaybackSpeed`
  declared as taking a float or a double. The Swift layer does not expose it.
- `send` refuses the like/ban/wish-list MRCommand ids (upstream's TODO). Probed with them allowed:
  none reached the player's like, dislike or bookmark target, and 0x6D arrived as "next track". The
  Swift layer dropped those four commands.
- The artwork MIME type is passed through as MediaRemote gives it (#36 carries it along with the
  data, it does not check it): `image/jpeg` over TIFF bytes was seen live. The Swift layer reads
  the type from the bytes (`ArtworkType`).
