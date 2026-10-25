# mediaremote-adapter (ztomer fork) roadmap

The ONE forward-looking plan for this fork (house rule #16). The fork exists for one consumer:
ZoneWM. The fork line is `main`; ZoneWM pins `branch: "main"` (`ZoneWM/Package.swift:100`,
`Package.resolved`). Never rewrite `main`'s history: a pinned revision must stay reachable on the
remote. Closed work is in git history; the 2026-10-12 consolidation record is
`git show 66441aa:ROADMAP.md`, the ejbills-era plan `git show 008b68d:ROADMAP.md`.

## Context (measured 2026-10-24)

- **The core is ungive's.** `Vendor/ungive-mediaremote-adapter` is
  [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) at `0e82bf1`
  (master, 2026-10-17) plus four local patches, all listed in its
  [VENDORED.md](Vendor/ungive-mediaremote-adapter/VENDORED.md): 0001 is ungive's open PR #38
  (stream ordering), 0002 no load-time side effects in a host app, 0003 the script loads an image
  path, 0004 `stream --exit-with-parent`. The Swift layer (MediaController, TrackInfo, PipeReader,
  the commands) is the fork's, from ejbills's package; ejbills's diverged ObjC copy of the core is
  gone.
- **Upstreams.** ungive is maintained (seek/speed #34, fractional rates #31, artworkMimeType with
  artworkData #36, `--no-artwork` #29, `--allow-missing-title` #40, missing PID #16, since April).
  `ejbills/mediaremote-adapter` HEAD is still `5b6afde` (2026-07-31); its open PRs are #7 (ours,
  `swift6-macos13`) and #8 (a third party's LICENSE). Owner ruling: nothing is posted upstream.
- **Branches.** `main` is the default branch and the fork line; `swift6-macos13` is the head of
  ejbills PR #7; `master` mirrors ejbills.
- **Gate:** goh 0.27.0 stock hooks. `tools/gate.sh --full` is GREEN at the vendoring commits:
  structural (with `GOH_EXCLUDE='^Vendor/'`) + SwiftLint `--strict` against the shrink-only
  `.swiftlint-baseline.json` (8 left, all in ejbills-era Swift) + cold build/test with warnings
  as errors + coverage (package floor 26, `MediaRemoteAdapter` target floor 90, reads 94.0) +
  `tools/repo_gates.sh`: no `unsafeFlags`; the core compiled under ARC (compile line and object
  code); the core's load-time initializers only in an allowlist; `tools/check_vendored.sh` (the
  tree is upstream plus the listed patches, run.pl is the vendored script); the suite under TSan.
- 55 tests. Fixtures are live captures of the vendored core against `tools/fixture-player`
  (`tools/record_fixtures.sh`), including `commands.tsv`: what every command argv made the player
  receive.

## Rulings

- **2026-10-24, the core:** "Yes: vendor ungive's current adapter as the fork's core, keep our
  Swift layer on top, apply PR #38's ordering locally, re-record the fixtures, and release for
  ZoneWM. Don't post anything upstream."
- The floor follows the ZoneWM root package (`7e6aef7`, 2026-09-14), fork-only.
- Not Rust: private ObjC core, `../RUSTIFICATION_ROADMAP.md` §6.
- A commit pushed to `swift6-macos13` is published into ejbills PR #7. Fork-only work goes to
  `main`. `swift6-macos13` may be rewritten (force-with-lease) only while `main` contains every
  commit a consumer pins.
- Releases are tags on `main` (`v0.1.0` is the first: the Swift package over ungive's core).

## Open

- **Re-vendor when ungive moves.** Bump: export the new commit's files, re-record
  `upstream.sha256`, re-apply the patches (drop 0001 when PR #38 merges), re-run
  `tools/record_fixtures.sh` and the gate. `tools/check_vendored.sh` refuses a half-done bump.
- **ungive's `speed` does nothing on macOS 27.** The fixture player received playback rate 1.0 for
  every value, with the function pointer declared int, float or double. Not exposed. Next: find
  the real signature/semantics (it may take an MRPlaybackSpeed enum), then expose it.
- **Toggle shuffle/repeat and the 15-second skips reach no MediaPlayer target** of the fixture
  player (`commands.tsv`). Same MRCommand ids as before; unknown whether a native MediaRemote
  player acts on them. Next: record them against Music.app before deciding whether they stay.
- **Shuffle/repeat reporting is transcribed.** No player here reports a mode in Now Playing, the
  fixture player included. A capture from a player that does (Music.app) would replace
  `modesReported`.
- **ZoneWM's licence inventory is stale** (ZoneWM's lane, not edited here): `ZTUI/LicenseTexts.swift`
  lists Cykey's `MediaRemote.h` as shipped inside this package and links ejbills; the package now
  ships ungive's core (BSD-3, Jonas van den Berg) and no Cykey header.
- **ejbills PR #7 offers (owner's call, nothing posted).** `upstream-patches/swift6-macos13-0001-listener-race.patch`
  (the stateLock fix for PR #7's head) and dropping `unsafeFlags` (M1.1) are still unoffered.
  `main` no longer shares its core with ejbills, so PR #7 is the only thing left that tracks them.
  Delete the patch file once offered or declined.
- **The lint baseline:** 8 entries, all in ejbills-era Swift (`MediaController.swift`,
  `TrackInfo.swift`); `main` no longer merges ejbills, so they can be fixed here.
