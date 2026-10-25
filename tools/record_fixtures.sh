#!/usr/bin/env bash
# Record the wire fixtures from a LIVE `run.pl loop` on this Mac (2026-10-24).
#
# The tests' data lines are real captures, not transcriptions: this builds the shim dylib, starts
# `perl run.pl <dylib> loop`, plays tools/fixture-player (silent, volume 0, its own synthetic track)
# once as an app bundle and once as a bare binary, and keeps ONLY the lines whose artist is
# `mediaremote-adapter`. Any other player on the Mac (the owner's music) is dropped, never written:
# the fixtures are committed to a public repo.
#
#   tools/record_fixtures.sh            record into Tests/MediaRemoteAdapterTests/Fixtures/
#
# Needs a logged-in GUI session (Now Playing is per-user). Takes about 40 seconds.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
GOH="${GOH_DIR:-${GOH:-$HOME/Projects/gates_of_heck}}"
# shellcheck disable=SC1091
. "$GOH/tui/lib.sh"

OUT="$ROOT/Tests/MediaRemoteAdapterTests/Fixtures"
RUN_PL="$ROOT/Sources/MediaRemoteAdapter/Resources/run.pl"
WORK="$(mktemp -d -t mra-record)"
listener=""
cleanup() {
    if [ -n "$listener" ]; then kill "$listener" 2>/dev/null || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

section "mediaremote-adapter: record wire fixtures"

info "building the shim dylib"
(cd "$ROOT" && swift build >/dev/null)
DYLIB="$(cd "$ROOT" && swift build --show-bin-path)/libMediaRemoteAdapter.dylib"
[ -f "$DYLIB" ] || die "no dylib at $DYLIB"

info "building the fixture player"
python3 -I - "$WORK/silence.wav" <<'PY'
import sys, wave
w = wave.open(sys.argv[1], "wb")
w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000)
w.writeframes(b"\x00\x00" * 8000 * 120)
w.close()
PY
APP="$WORK/FixturePlayer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$WORK/silence.wav" "$APP/Contents/Resources/"
cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ztomer.mediaremote-adapter.fixture-player</string>
<key>CFBundleName</key><string>Fixture Player</string>
<key>CFBundleExecutable</key><string>FixturePlayer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -O "$HERE/fixture-player/FixturePlayer.swift" -o "$APP/Contents/MacOS/FixturePlayer"
codesign -s - --force "$APP" >/dev/null 2>&1
cp "$APP/Contents/MacOS/FixturePlayer" "$WORK/fixture-player-bare"

# One listener per session; its stdin is held open (EOF does not end `loop`, but a closed stdin is
# not the production shape either) and it is killed on the way out.
record() { # <raw-out> <command...>
    local raw="$1"; shift
    mkfifo "$WORK/stdin"
    perl "$RUN_PL" "$DYLIB" loop <"$WORK/stdin" >"$raw" 2>"$raw.err" &
    listener=$!
    exec 3>"$WORK/stdin"
    sleep 3
    "$@"
    sleep 3
    kill "$listener" 2>/dev/null || true
    wait "$listener" 2>/dev/null || true
    listener=""
    exec 3>&-
    rm -f "$WORK/stdin"
}

info "session 1: the fixture player as an app bundle"
record "$WORK/bundled.raw" open -W -n "$APP"
info "session 2: the fixture player as a bare binary (no bundle identity)"
record "$WORK/bare.raw" "$WORK/fixture-player-bare" "$WORK/silence.wav"

# Keep the fixture player's lines VERBATIM (bytes as run.pl printed them, key order and `\/`
# escapes included); the filter only reads them.
keep() { # <raw> <out> <min-lines>
    python3 -I - "$1" "$2" "$3" <<'PY'
import json, sys
raw, out, need = sys.argv[1], sys.argv[2], int(sys.argv[3])
kept = []
with open(raw, "rb") as fh:
    for line in fh:
        line = line.rstrip(b"\n")
        try:
            doc = json.loads(line)
        except ValueError:
            continue
        if isinstance(doc, dict) and doc.get("payload", {}).get("artist") == "mediaremote-adapter":
            kept.append(line)
if len(kept) < need:
    sys.exit(f"{raw}: {len(kept)} fixture-player lines, need {need}: was it made the now-playing app?")
with open(out, "wb") as fh:
    fh.write(b"\n".join(kept) + b"\n")
print(len(kept))
PY
}
mkdir -p "$OUT"
n="$(keep "$WORK/bundled.raw" "$OUT/loop-bundled-player.jsonl" 5)" || die "session 1 recorded too little"
ok "loop-bundled-player.jsonl: $n lines"
n="$(keep "$WORK/bare.raw" "$OUT/loop-bare-player.jsonl" 3)" || die "session 2 recorded too little"
ok "loop-bare-player.jsonl: $n lines"
