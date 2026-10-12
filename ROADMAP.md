# mediaremote-adapter (ztomer fork) roadmap

The ONE forward-looking plan for this fork (house rule #16). The fork exists for one consumer:
ZoneWM. The fork line is `main`; ZoneWM still pins `branch: "swift6-macos13"` at `d77d96c`
(`ZoneWM/Package.swift:93`, `Package.resolved`) until M0.2 lands there. `d77d96c` stays reachable
because `main` contains it.

## Context (measured 2026-10-12)

- **Upstream has not moved.** `ejbills/mediaremote-adapter` master is still `5b6afde` (last push
  2026-07-31). It has no tags or releases and absorbed nothing from PR #7, so nothing was rebased.
  Open upstream PRs: #7 (ours) and #8 (a third party's BSD-3-Clause LICENSE).
- **No other fork is further along on Swift 6.** Of 17 forks, only `MxIris-LyricsX-Project` has
  diverged substantially (20 ahead / 29 behind, tools 6.2 but Swift 5 language mode, macOS 11,
  OpenSoftLinking refactor), and it is a different direction rather than a superset. Every other
  active fork is on tools 5.5 / macOS 10.15. `dizzysound:lossless-switcher` independently fixed
  the same EOF pipe spin as `d77d96c` (one commit, 2026-09-29), which corroborates the bug class.
- **Branches after the split:**
  - `main` (fork line): `5b6afde` + `931e3a0` Swift 6 + `7e6aef7` macOS 27 floor + `d77d96c` CPU
    spin fix (with `.swift-version` = `xcode`) + this plan + the house gates.
  - `swift6-macos13` (head of upstream PR #7, macOS 13 floor): `5b6afde` + `5f36e22` Swift 6 +
    `8e40638` CPU spin fix. `5f36e22`/`8e40638` are the same changes as `931e3a0`/`d77d96c`, without
    the floor raise and without `.swift-version`. Verified there: clean build at
    `-target arm64-apple-macos13.0`, 0 warnings, `swift test` 2/2.
  - Remote-only `origin/master` (== upstream master) and `origin/test` (`199bc29`, an ancestor of
    upstream master). Local `fork` (`90ac259`) is superseded by `main`.
- **Gate installed** (`gates_of_heck/install.sh`, Swift layer, `GOH_SWIFT_MODE=spm`). Pre-push runs
  structural + cold `swift build --build-tests -warnings-as-errors` + `swift test`; proven red on a
  broken `PipeReaderTests` assertion and on a new lint violation. SwiftLint `--strict` runs against
  `.swiftlint-baseline.json`, a shrink-only ratchet seeded with the 29 violations present at install
  (most in upstream-owned `MediaController.swift`/`TrackInfo.swift`).
  `Sources/CIMediaRemote/MediaRemoteAdapter.m` (578 lines, upstream-owned) is excluded from the
  500-line cap in `.gatesrc`, with the reason, and held to a shrink-only ceiling of 578 in
  `.line-baseline` (proven red at 577). No coverage floor yet.
- `MediaController` (437 lines), `TrackInfo` decoding, the ObjC shim and `run.pl` have no tests.

## Rulings

- The floor follows the ZoneWM root package (`7e6aef7`, 2026-09-14). The floor raise is FORK-ONLY.
- Not Rust: private ObjC shim, `../RUSTIFICATION_ROADMAP.md` §6.
- **2026-10-12, PR #7: "split, see if there's an updated upstream".** Keep upstreaming. PR #7 carries
  only what upstream can accept (Swift 6 + macOS 13 floor + the CPU spin fix). The floor raise,
  `.swift-version` and everything fork-only live on `main`. Upstream had not moved, so no rebase.
- A commit pushed to `swift6-macos13` is published into upstream PR #7. Fork-only work goes to `main`.
- `swift6-macos13` may be rewritten (force-with-lease) only after `main` is pushed and contains every
  commit a consumer pins. Never leave a pinned revision unreachable on the remote.

## Phase 0: branch topology and a gate

- **M0.1 Decide upstreaming.** DONE 2026-10-12: split (ruling above). PR #7's file list has no
  `.macOS("27.0")` and no `.swift-version`.
- **M0.2 One fork trunk.** `main` exists and is pushed (DONE). Remaining:
  - ZoneWM (owned by the ZoneWM session, not edited from here): `Package.swift:93` →
    `branch: "main"`; replace the stale "macOS 13 floor ... upstream PR #7" comment at lines 90-92;
    `swift package resolve` so `Package.resolved` pins `main` at its head. Until then ZoneWM's
    resolved `swift6-macos13@d77d96c` still builds (reachable through `main`), but any
    `swift package update` there would move it to the macOS 13 PR line.
  - Make `main` the default branch on `ztomer/mediaremote-adapter` (it is `master`).
  - Delete `origin/test` and local `fork`. Proof: `git branch -a` shows only `main`,
    `swift6-macos13` and the upstream mirror `master`.
- **M0.3 Install the house gates.** DONE 2026-10-12 (see Context). Follow-up: set
  `GOH_SWIFT_COV_MIN` once M1.3 gives the decoding path tests.

## Phase 1: hardening (M)

- **M1.1 Drop `unsafeFlags`.** `Package.swift` passes `-fobjc-arc` and `-framework Foundation/AppKit`
  as unsafe flags. Use `linkerSettings: [.linkedFramework(...)]`, and confirm SwiftPM's default ARC
  for ObjC with `swift build -v | grep -c fobjc-arc`. Proof: build green and no `unsafeFlags`
  in the manifest. Risk: the ARC default must be confirmed on the real build line, not assumed.
  Upstreamable: offer it on PR #7 or a follow-up PR.
- **M1.2 Tools version 6.4** to match the toolchain (cutting-edge rule). Proof: manifest
  header reads 6.4 and the build stays green.
- **M1.3 Decoding tests.** Replay recorded `run.pl` JSON lines (playing, paused, no player,
  artwork, malformed) through `MediaController`/`TrackInfo`. Proof: each fixture asserts its
  payload, and a malformed line reaches `onDecodingError` rather than crashing.
- **M1.4 LICENSE + README.** Add BSD-3-Clause (as upstream PR #8 does). The README's install URL
  names upstream: state that this is the ZoneWM fork and why. Proof: `LICENSE` exists, and the
  README names `ztomer/mediaremote-adapter` and the consumer.
- **M1.5 Re-check `.swift-version`.** It pins `xcode` because swiftly's toolchain could not target
  the macOS 27 SDK (2026-09-22). swiftly's `swift` is now 6.4 with target `arm64-apple-macosx27.0`.
  Build `main` with swiftly's toolchain; if it is green, delete `.swift-version`. Proof: build
  green without it.
- **M1.6 Shrink the lint baseline.** Fix the fork-authored entries (`Package.swift`,
  `PipeReaderTests.swift`) on the PR branch and `main` alike, then re-record. Upstream-owned entries
  wait for upstream or for the fork to stop merging it.

## Sources consolidated (2026-10-12)

- Claude CLI / desktop, opencode, Antigravity, Gemini CLI: no session for this repo. The live
  ZoneWM desktop session `local_5940e87a…` only imports it, so it is not this repo's.
- Upstream PRs #7 and #8: carried as M0.1 and M1.4. Upstream survey and fork network: Context.
- `../RUSTIFICATION_ROADMAP.md` §6: "not Rust" ruling, carried.
- `../ROADMAP-consolidated.md`: no entry.
- Branches: `origin/test` is an ancestor of upstream master, so it is deleted in M0.2. No worktrees.
