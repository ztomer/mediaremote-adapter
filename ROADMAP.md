# mediaremote-adapter (ztomer fork) roadmap

The ONE forward-looking plan for this fork (house rule #16). The fork exists for one consumer:
ZoneWM, which pins `branch: "swift6-macos13"` (`ZoneWM/Package.swift:93`, resolved at `d77d96c`).

## Context (measured 2026-10-12)

- Upstream `ejbills/mediaremote-adapter` master is `5b6afde`. This fork carries 3 commits on top
  (`git cherry origin/master swift6-macos13`, all `+`). `931e3a0` is the Swift 6 strict-concurrency
  migration. `7e6aef7` raises the floor to macOS 27, following ZoneWM. `d77d96c` fixes a 100% CPU
  spin: pipe readers now drain and detach at EOF.
- Upstream PR #7 (`ztomer:swift6-macos13`, open since 2026-08-22) is titled "macOS 13 floor". It is
  the consumer's pin branch, so it now carries the macOS 27 floor too, which a general-purpose
  upstream will not take. Upstream PR #8 (a third party's) adds the missing LICENSE (BSD-3-Clause).
- `swift build`: clean, 0 warnings (Swift 6.4, arm64-apple-macosx27). `swift test`: 2 XCTests pass
  (`PipeReaderTests`). `MediaController` (437 lines), `TrackInfo` decoding, the ObjC shim (769
  lines) and `run.pl` have no tests.
- **No gate.** No `.githooks`, no `tools/gate.sh`, `core.hooksPath` unset. Nothing structural runs here.
- Branches: local `swift6-macos13` == `origin/swift6-macos13`. Remote-only `origin/master`
  (== upstream master) and `origin/test` (`199bc29`, an ancestor of upstream master).

## Rulings

- The floor follows the ZoneWM root package (`7e6aef7`, 2026-09-14).
- Not Rust: private ObjC shim, `../RUSTIFICATION_ROADMAP.md` §6.
- This plan lives on the local branch `fork`, NOT on `swift6-macos13`. That branch is the head of
  upstream PR #7, so a commit pushed there is published into someone else's PR.

## Phase 0: branch topology and a gate (S, one session; needs one user decision)

- **M0.1 Decide upstreaming (user).** Either (a) keep upstreaming: cut `upstream/swift6` from
  upstream master with `931e3a0` + `d77d96c` only, repoint PR #7 at it, and keep the floor raise
  fork-only; or (b) stop upstreaming: close PR #7 and treat this fork as ZoneWM-owned. Proof:
  PR #7's file list contains no `.macOS("27.0")`, or PR #7 is closed.
- **M0.2 One fork trunk.** Rename the consumer pin from `swift6-macos13` (its name says 13, its
  floor is 27) to `main`, carry the `fork` branch's ROADMAP onto it, repoint
  `ZoneWM/Package.swift:93`, and correct ZoneWM's stale "macOS 13 floor" comment in the same
  ZoneWM commit. Delete `origin/test`. Proof: `swift package resolve` in ZoneWM pins `main`, and
  `git branch -a` shows only `main` and the upstream-PR branch. Depends on M0.1.
- **M0.3 Install the house gates.** Run `gates_of_heck/install.sh` and enable the Swift layer
  (`GOH_SWIFT_MODE=spm`). Proof: the pre-push gate runs `swift build` + `swift test` and goes red
  on a deliberately broken test.

## Phase 1: hardening (M)

- **M1.1 Drop `unsafeFlags`.** `Package.swift` passes `-fobjc-arc` and `-framework Foundation/AppKit`
  as unsafe flags. Use `linkerSettings: [.linkedFramework(...)]`, and confirm SwiftPM's default ARC
  for ObjC with `swift build -v | grep -c fobjc-arc`. Proof: build green and no `unsafeFlags`
  in the manifest. Risk: the ARC default must be confirmed on the real build line, not assumed.
- **M1.2 Tools version 6.4** to match the toolchain (cutting-edge rule). Proof: manifest
  header reads 6.4 and the build stays green.
- **M1.3 Decoding tests.** Replay recorded `run.pl` JSON lines (playing, paused, no player,
  artwork, malformed) through `MediaController`/`TrackInfo`. Proof: each fixture asserts its
  payload, and a malformed line reaches `onDecodingError` rather than crashing.
- **M1.4 LICENSE + README.** Add BSD-3-Clause (as upstream PR #8 does). The README's install URL
  names upstream: state that this is the ZoneWM fork and why. Proof: `LICENSE` exists, and the
  README names `ztomer/mediaremote-adapter` and the consumer.

## Sources consolidated (2026-10-12)

- Claude CLI / desktop, opencode, Antigravity, Gemini CLI: no session for this repo. The live
  ZoneWM desktop session `local_5940e87a…` only imports it, so it is not this repo's.
- Upstream PRs #7 and #8: carried as M0.1 and M1.4.
- `../RUSTIFICATION_ROADMAP.md` §6: "not Rust" ruling, carried.
- `../ROADMAP-consolidated.md`: no entry.
- Branches: `origin/test` is an ancestor of upstream master, so it is deleted in M0.2. No worktrees.
