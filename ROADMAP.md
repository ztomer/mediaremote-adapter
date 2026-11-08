# mediaremote-adapter (ztomer fork) roadmap

The ONE forward-looking plan for this fork (house rule #16). The fork exists for one consumer:
ZoneWM, which pins this package at `exact: "0.1.0"` (`ZoneWM/Package.swift:98`, `Package.resolved`:
revision `7a9b48e`). The fork line is `main`; never rewrite `main`'s history: a pinned revision must
stay reachable on the remote. Finished work is in git history only.

## Context (measured 2026-11-08)

- **The core is ungive's.** `Vendor/ungive-mediaremote-adapter` is
  [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) at `0e82bf1`
  plus four local patches, all listed in its [VENDORED.md](Vendor/ungive-mediaremote-adapter/VENDORED.md):
  0001 is ungive's open PR #38 (stream ordering), 0002 no load-time side effects in a host app,
  0003 the script loads an image path, 0004 `stream --exit-with-parent`. The Swift layer
  (MediaController, TrackInfo, PipeReader, the commands) is the fork's, from ejbills's package.
- **Branches.** `main` is the fork line (HEAD `68d056a` = `origin/main`); `swift6-macos13` is the
  head of ejbills PR #7; `master` mirrors ejbills.
- **Gate.** `tools/gate.sh --full`: structural (with `GOH_EXCLUDE='^Vendor/'`) + SwiftLint
  `--strict` against the shrink-only `.swiftlint-baseline.json` (8 entries) + cold build/test with
  warnings as errors + coverage (`MediaRemoteAdapter` target floor 90 in `coverage-floors.json`) +
  `tools/repo_gates.sh` (no `unsafeFlags`; core compiled under ARC; load-time initializers
  allowlisted; `tools/check_vendored.sh`; the suite under TSan).
- 55 tests. Fixtures are live captures of the vendored core against `tools/fixture-player`
  (`tools/record_fixtures.sh`), including `commands.tsv`: what every command argv made the player
  receive.

## Rulings in force

- **2026-10-24 (R3.16), the core:** "Yes: vendor ungive's current adapter as the fork's core, keep
  our Swift layer on top, apply PR #38's ordering locally, re-record the fixtures, and release for
  ZoneWM. Don't post anything upstream."
- **2026-10-31 (OW.43), the listener-race patch:** decline. Nothing is offered to ejbills PR #7.
  Supersedes the earlier "owner's call" on offering it and on offering the `unsafeFlags` removal.
- **2026-10-31 (OW.41), the licence:** "Don't change the copyright." The LICENSE line stays as is;
  ejbills is not asked to license their package.
- Releases are tags on `main` (`v0.1.0` is the first). The macOS floor follows the ZoneWM root
  package, fork-only.
- Not Rust: the core is private-framework ObjC (owner ruling, 2026-10-12 plan; its reference file
  no longer exists).
- A commit pushed to `swift6-macos13` is published into ejbills PR #7. Fork-only work goes to
  `main`. `swift6-macos13` may be rewritten (force-with-lease) only while `main` contains every
  commit a consumer pins.
- Fixtures are committed to a public repo: a capture from any real player (Music.app) is recorded
  with a synthetic track only and stripped of every other player's lines, as
  `tools/record_fixtures.sh` does for the fixture player.

## Phase 1: local cleanup (no external dependency, immediate value)

- **MR.1 Delete the declined patch file.** `upstream-patches/swift6-macos13-0001-listener-race.patch`
  is the only content of `upstream-patches/`; OW.43 declined it and nothing else references it.
  Delete the directory. Done when: `upstream-patches/` is gone and `tools/gate.sh --full` is green.
- **MR.2 Empty the lint baseline.** 8 entries, all in ejbills-era Swift: `MediaController.swift`
  (large tuple on `runPerlCommand`, three line lengths, `getTrackInfo` body length, two
  `"\n".data(using:)` conversions) and `TrackInfo.swift` (nested `CodingKeys`). `main` no longer
  merges ejbills, so fix them here. Done when: `.swiftlint-baseline.json` holds 0 entries (or is
  removed with the gate's baseline step) and `tools/gate.sh --full` is green with the 55 tests
  unchanged.

## Phase 2: evidence from a real player (the fixture player cannot answer these)

- **MR.3 ungive's `speed` does nothing on macOS 27.** The fixture player received playback rate
  1.0 for every value, with the function pointer declared int, float or double. Not exposed. Next:
  find the real signature/semantics (it may take an MRPlaybackSpeed enum). Done when: either a
  `commands.tsv` row from `tools/record_fixtures.sh` shows the player received a non-1.0 rate for
  a `speed` argv and a test pins that argv-to-rate pair, then the Swift API exposes it; or the
  finding that no signature carries it is written into `Vendor/.../VENDORED.md` and the API stays
  without `speed`.
- **MR.4 Toggle shuffle/repeat and the 15-second skips reach no MediaPlayer target** of the
  fixture player (`commands.tsv`). Same MRCommand ids as before; unknown whether a native
  MediaRemote player acts on them. Done when: a Music.app capture (synthetic track, see Rulings)
  shows each of them acted on and the commands stay with a test, or they are removed from the
  public API with the suite green.
- **MR.5 Shuffle/repeat reporting is transcribed.** No player here reports a mode in Now Playing,
  the fixture player included; `modesReported` (`Tests/.../WireFixtures.swift:155`) is a
  hand-written line. Done when: a capture from a player that reports a mode replaces it and
  `TrackInfoDecodingTests` passes on the captured line under `tools/gate.sh --full`. Shares the
  Music.app recording with MR.4.

## Phase 3: on trigger (ungive moves, or PR #38 merges)

- **MR.6 Re-vendor when ungive moves.** Export the new commit's files, re-record
  `upstream.sha256`, re-apply the patches (drop 0001 when PR #38 merges), re-run
  `tools/record_fixtures.sh`. Done when: `tools/check_vendored.sh` and `tools/gate.sh --full` are
  green at the new commit and VENDORED.md names it; `tools/check_vendored.sh` refuses a half-done
  bump.
