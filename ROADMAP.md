# mediaremote-adapter (ztomer fork) roadmap

The ONE forward-looking plan for this fork (house rule #16). The fork exists for one consumer:
ZoneWM. The fork line is `main`; ZoneWM pins `branch: "main"` at `ab2eba8`
(`ZoneWM/Package.swift:94`, `Package.resolved`, ZoneWM `be486e80`). Never rewrite `main`'s
history: a pinned revision must stay reachable on the remote. Closed work is in git history; the
2026-10-12 consolidation record is `git show 66441aa:ROADMAP.md` ("Sources consolidated").

## Context (measured 2026-10-14)

- **Upstream has not moved.** `ejbills/mediaremote-adapter` HEAD is still `5b6afde` (last push
  2026-07-31), no tags or releases. Open upstream PRs: #7 (ours, `swift6-macos13`) and #8 (a
  third party's BSD-3-Clause LICENSE). No other fork is further along on Swift 6 (survey
  2026-10-12, 17 forks).
- **Branches:** `main` (fork line: `5b6afde` + Swift 6 + macOS 27 floor + the CPU spin fix +
  `.swift-version` + the house gates + this plan); `swift6-macos13` (head of PR #7, macOS 13
  floor, the same code without the floor raise); remote-only `origin/master` (== upstream) and
  `origin/test` (an ancestor of upstream master); local `fork` (an ancestor of `main`).
- **Gate:** goh 0.27.0 stock hooks (`66441aa`). `tools/gate.sh --full` is GREEN at `66441aa`
  (40 s): structural + SwiftLint `--strict` against the shrink-only `.swiftlint-baseline.json`
  (29 at install, mostly upstream-owned) + cold build/test with warnings as errors.
  `Sources/CIMediaRemote/MediaRemoteAdapter.m` (578 lines, upstream-owned) is excluded from the
  500-line cap and held to 578 by `.line-baseline`. Scanner floors set (`f6d0631`); no coverage
  floor yet.
- `MediaController` (437 lines), `TrackInfo` decoding, the ObjC shim and `run.pl` have no tests.

## Rulings

- The floor follows the ZoneWM root package (`7e6aef7`, 2026-09-14). The floor raise is FORK-ONLY.
- Not Rust: private ObjC shim, `../RUSTIFICATION_ROADMAP.md` §6.
- **2026-10-12, PR #7: "split, see if there's an updated upstream".** Keep upstreaming. PR #7 carries
  only what upstream can accept (Swift 6 + macOS 13 floor + the CPU spin fix). The floor raise,
  `.swift-version` and everything fork-only live on `main`.
- A commit pushed to `swift6-macos13` is published into upstream PR #7. Fork-only work goes to `main`.
- `swift6-macos13` may be rewritten (force-with-lease) only while `main` contains every commit a
  consumer pins. Never leave a pinned revision unreachable on the remote.

## Phase 0: wire in goh 0.27.0 (closed)

- **G0.1 Set the scanner floors.** Closed `f6d0631`.
- **G0.2 Push.** Closed `f6d0631`.

## Phase 1: branch topology (size S)

- **M0.2 One fork trunk, remainder.** Make `main` the default branch on `ztomer/mediaremote-adapter`
  (it is still `master`, 2026-10-14). Delete `origin/test` and local `fork` (both are ancestors of
  a kept branch, verified 2026-10-14). *Accept:* `git branch -a` shows only `main`,
  `swift6-macos13` and the upstream mirror `master`; `gh repo view --json defaultBranchRef` reads
  `main`.

## Phase 2: hardening (M)

- **M1.1 Drop `unsafeFlags`.** `Package.swift:37-41` passes `-fobjc-arc` and `-framework
  Foundation/AppKit` as unsafe flags. Use `linkerSettings: [.linkedFramework(...)]`, and confirm
  SwiftPM's default ARC for ObjC with `swift build -v | grep -c fobjc-arc`. *Accept:* build green
  and no `unsafeFlags` in the manifest. Risk: the ARC default must be confirmed on the real build
  line, not assumed. Upstreamable: offer it on PR #7 or a follow-up PR.
- **M1.2 Tools version 6.4** to match the toolchain (cutting-edge rule; the manifest reads 6.3,
  `swift --version` is 6.4 on 2026-10-14). *Accept:* manifest header reads 6.4, build green.
- **M1.3 Decoding tests, then a coverage floor.** Replay recorded `run.pl` JSON lines (playing,
  paused, no player, artwork, malformed) through `MediaController`/`TrackInfo`. *Accept:* each
  fixture asserts its payload, a malformed line reaches `onDecodingError` rather than crashing,
  and `GOH_SWIFT_COV_MIN` is set (the swift gate's `⚠ no coverage floor` line is gone).
- **M1.4 LICENSE + README.** Add BSD-3-Clause (as upstream PR #8 does). The README's install URL
  names upstream: state that this is the ZoneWM fork and why. *Accept:* `LICENSE` exists, and the
  README names `ztomer/mediaremote-adapter` and the consumer.
- **M1.5 Re-check `.swift-version`.** It pins `xcode` because swiftly's toolchain could not target
  the macOS 27 SDK (2026-09-22). swiftly's `swift` is now 6.4 with target `arm64-apple-macosx27.0`.
  Build `main` with swiftly's toolchain; if green, delete `.swift-version`. *Accept:* build green
  without it.
- **M1.6 Shrink the lint baseline.** Fix the fork-authored entries (`Package.swift`,
  `PipeReaderTests.swift`) on the PR branch and `main` alike, then re-record. Upstream-owned entries
  wait for upstream or for the fork to stop merging it.
