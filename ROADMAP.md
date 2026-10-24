# mediaremote-adapter (ztomer fork) roadmap

The ONE forward-looking plan for this fork (house rule #16). The fork exists for one consumer:
ZoneWM. The fork line is `main`; ZoneWM pins `branch: "main"` at `ab2eba8`
(`ZoneWM/Package.swift:100`, `Package.resolved`, ZoneWM `be486e80`). Never rewrite `main`'s
history: a pinned revision must stay reachable on the remote. Closed work is in git history; the
2026-10-12 consolidation record is `git show 66441aa:ROADMAP.md` ("Sources consolidated").

## Context (measured 2026-10-24)

- **Upstream has not moved.** `ejbills/mediaremote-adapter` HEAD is still `5b6afde` (last push
  2026-07-31), no tags or releases. Open upstream PRs: #7 (ours, `swift6-macos13`) and #8 (a
  third party's BSD-3-Clause LICENSE). No other fork is further along on Swift 6 (survey
  2026-10-12, 17 forks).
- **Branches** (M0.2 closed 2026-10-24, remote operations, no commit): `main` is the default
  branch of `ztomer/mediaremote-adapter` and the fork line; `swift6-macos13` is the head of PR #7;
  `master` mirrors upstream. `origin/test` and local `fork` are deleted. (`git branch -a` also lists
  `upstream/test`: that is upstream's own branch, not ours.)
- **Gate:** goh 0.27.0 stock hooks. `tools/gate.sh --full` is GREEN at `e01a226`: structural +
  SwiftLint `--strict` against the shrink-only `.swiftlint-baseline.json` (17 left, all in
  upstream-owned code) + cold build/test with warnings as errors + coverage (package floor 39,
  `MediaRemoteAdapter` target floor 90, `coverage-floors.json`) + `tools/repo_gates.sh` (no
  `unsafeFlags`; the shim compiled under ARC, read from the real compile line and object code).
  `Sources/CIMediaRemote/MediaRemoteAdapter.m` (578 lines, upstream-owned) is excluded from the
  500-line cap and held to 578 by `.line-baseline`.
- 37 tests. Coverage of the Swift target reads 94.0%; the ObjC shim is 0 of 725 lines in
  `MediaRemoteAdapter.m` because it drives the private framework and cannot run headless.

## Rulings

- The floor follows the ZoneWM root package (`7e6aef7`, 2026-09-14). The floor raise is FORK-ONLY.
- Not Rust: private ObjC shim, `../RUSTIFICATION_ROADMAP.md` §6.
- **2026-10-12, PR #7: "split, see if there's an updated upstream".** Keep upstreaming. PR #7 carries
  only what upstream can accept (Swift 6 + macOS 13 floor + the CPU spin fix). The floor raise and
  everything fork-only live on `main`.
- A commit pushed to `swift6-macos13` is published into upstream PR #7. Fork-only work goes to `main`.
- `swift6-macos13` may be rewritten (force-with-lease) only while `main` contains every commit a
  consumer pins. Never leave a pinned revision unreachable on the remote. ZoneWM pins
  `branch: "main"` (`ZoneWM/Package.swift:100`); never rewrite `main`'s history.

## Closed 2026-10-24 (phases 1 and 2)

M0.2 branch topology (remote operations). M1.1 no `unsafeFlags`, M1.2 tools 6.4, M1.5 no
`.swift-version` (swiftly's Swift 6.4.0 builds and tests `main` green): `87fc0d8`. M1.3 decoding
tests + coverage floors: `d64ef36`. M1.4 LICENSE + README: `e01a226`.

## Open

- **M1.6 remainder: the lint baseline.** 17 entries are left, all in upstream code: `MediaController.swift` (13)
  and `TrackInfo.swift` (4). Fork-authored entries on `main` are fixed; the same
  fixes (`Package.swift` trailing comma/newline/whitespace, `PipeReaderTests`) have NOT been mirrored
  onto `swift6-macos13`, because a commit there is published into upstream PR #7. Mirror them with the
  next real change to that branch, or decide to leave PR #7 alone. The upstream-owned entries wait for
  upstream or for the fork to stop merging it.
- **M1.1 upstream offer.** Dropping `unsafeFlags` is upstreamable: offer it on PR #7 or a follow-up
  PR (owner's call; it changes the PR upstream reviews).
- **Recorded fixtures.** `WireFixtures.noPlayer` was recorded live; the data lines are transcribed
  from the serializer because no player can be driven headless. Replace them with recordings when a
  real `run.pl loop` capture is taken (`perl run.pl <dylib> loop` with Music playing).
- **LICENSE holders.** The fork line reads `2026, ztomer`; ejbills's Swift package carries no licence
  of its own until PR #8 (or an equivalent) merges. See owner decisions.
