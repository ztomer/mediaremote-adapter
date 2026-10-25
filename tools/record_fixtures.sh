#!/usr/bin/env bash
# Record the wire fixtures LIVE from the vendored core (ungive/mediaremote-adapter, Vendor/) on this
# Mac, through the same script and image the package ships (run.pl + libMediaRemoteAdapter.dylib).
#
# The tests' data lines are real captures, not transcriptions: this builds the package, plays
# tools/fixture-player (silent, volume 0, its own synthetic track) and records three sessions:
#   1. `stream` (the listener's exact flags, read from Sources/MediaRemoteAdapter/CoreCLI.swift)
#      with the player as an app bundle, then `get` while it plays;
#   2. the same `stream` with the player as a bare binary (no bundle identity);
#   3. every command argv the package sends, each paired with what the player RECEIVED.
# Only the fixture player's lines are kept (artist `mediaremote-adapter`), plus the core's empty
# "nothing playing" payload, which names no one. Any other player on the Mac (the owner's music) is
# dropped, never written: the fixtures are committed to a public repo.
#
#   tools/record_fixtures.sh            record into Tests/MediaRemoteAdapterTests/Fixtures/
#
# Needs a logged-in GUI session (Now Playing is per-user). Takes about a minute and a half.
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
player=""
cleanup() {
    if [ -n "$listener" ]; then kill "$listener" 2>/dev/null || true; fi
    if [ -n "$player" ]; then kill "$player" 2>/dev/null || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

section "mediaremote-adapter: record wire fixtures"

# The listener's flags are the package's, not a copy: read from the one place that defines them.
mapfile -t STREAM_ARGS < <(python3 -I - "$ROOT/Sources/MediaRemoteAdapter/CoreCLI.swift" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'static let stream = \[(.*?)\]', src)
if not m:
    sys.exit("CoreCLI.stream not found")
for arg in re.findall(r'"([^"]*)"', m.group(1)):
    print(arg)
PY
)
[ "${#STREAM_ARGS[@]}" -gt 0 ] || die "could not read CoreCLI.stream"
info "listener argv: ${STREAM_ARGS[*]}"

info "building the package"
(cd "$ROOT" && swift build >/dev/null)
DYLIB="$(cd "$ROOT" && swift build --show-bin-path)/libMediaRemoteAdapter.dylib"
[ -f "$DYLIB" ] || die "no dylib at $DYLIB"
run_core() { perl "$RUN_PL" "$DYLIB" "$@"; }

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
BARE="$WORK/fixture-player-bare"
cp "$APP/Contents/MacOS/FixturePlayer" "$BARE"

# One listener per session, started before the player and stopped after it (SIGTERM: the core's
# own clean exit).
record() { # <raw-out> <command...>
    local raw="$1"; shift
    run_core "${STREAM_ARGS[@]}" </dev/null >"$raw" 2>"$raw.err" &
    listener=$!
    sleep 3
    "$@"
    sleep 3
    kill "$listener" 2>/dev/null || true
    wait "$listener" 2>/dev/null || true
    listener=""
}

info "session 1: the fixture player as an app bundle (stream, then get)"
bundled_with_get() {
    open -W -n "$APP" &
    local opener=$!
    sleep 2
    run_core get --micros >"$WORK/get.raw" 2>"$WORK/get.err" || true
    wait "$opener"
}
record "$WORK/bundled.raw" bundled_with_get
info "session 2: the fixture player as a bare binary (no bundle identity)"
record "$WORK/bare.raw" "$BARE" "$WORK/silence.wav"

info "session 3: every command, and what the player received"
COMMANDS=(
    "send 0" "send 1" "send 2" "send 3" "send 4" "send 5" "send 6" "send 7" "send 8" "send 9"
    "send 10" "send 11" "send 12" "send 13" "seek 12500000" "seek 0"
    "shuffle 1" "shuffle 2" "shuffle 3" "repeat 1" "repeat 2" "repeat 3"
)
"$BARE" --commands --log "$WORK/received.log" "$WORK/silence.wav" &
player=$!
sleep 3
for argv in "${COMMANDS[@]}"; do
    echo "--> $argv" >>"$WORK/received.log"
    # shellcheck disable=SC2086 # argv is the command and its parameter, split on purpose
    run_core $argv >/dev/null 2>>"$WORK/commands.err" || echo "--x $argv" >>"$WORK/received.log"
    sleep 0.4
done
sleep 1
kill "$player" 2>/dev/null || true
wait "$player" 2>/dev/null || true
player=""

# Keep the fixture player's lines VERBATIM (bytes as the core printed them, key order and `\/`
# escapes included); the filter only reads them.
keep() { # <raw> <out> <min-lines> <stream|get>
    python3 -I - "$@" <<'PY'
import json, sys
raw, out, need, kind = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
kept = []
with open(raw, "rb") as fh:
    for line in fh:
        line = line.rstrip(b"\n")
        try:
            doc = json.loads(line)
        except ValueError:
            continue
        payload = doc.get("payload") if kind == "stream" and isinstance(doc, dict) else doc
        if not isinstance(payload, dict):
            continue
        # The core's "nothing playing" names no player; everything else must be ours.
        if payload == {} or payload.get("artist") == "mediaremote-adapter":
            if not kept or kept[-1] != line or payload != {}:
                kept.append(line)
if sum(1 for line in kept if line.find(b'"artist"') >= 0) < need:
    sys.exit(f"{raw}: fewer than {need} fixture-player lines: was it made the now-playing app?")
# A stream session must hold every state the tests look up. Another player on the Mac can take
# Now Playing over mid-script (a paused one becomes the fallback the moment ours pauses), and its
# lines are dropped above: such a session is incomplete, so it is refused rather than committed.
if kind == "stream":
    def has(title, playing=None, art=None, album=None):
        for line in kept:
            p = json.loads(line)["payload"]
            if p.get("title") == title and (playing is None or p.get("playing") == playing) \
                    and (art is None or ("artworkData" in p) == art) \
                    and (album is None or p.get("album") == album):
                return True
        return False
    wanted = [("Fixture Tone", True, True, None), ("Fixture Tone", True, False, None),
              ("Fixture Tone", False, True, None), ("Second Tone", True, False, "Recorded Fixtures"),
              ("Second Tone", True, True, None), ("Second Tone", True, False, "")]
    missing = [w for w in wanted if not has(*w)]
    if missing or kept[0] != b'{"type":"data","diff":false,"payload":{}}':
        sys.exit(f"{raw}: another player interrupted the script (missing {missing}); re-record")
with open(out, "wb") as fh:
    fh.write(b"\n".join(kept) + b"\n")
print(len(kept))
PY
}
mkdir -p "$OUT"
n="$(keep "$WORK/bundled.raw" "$OUT/stream-bundled-player.jsonl" 5 stream)" || die "session 1 recorded too little"
ok "stream-bundled-player.jsonl: $n lines"
n="$(keep "$WORK/bare.raw" "$OUT/stream-bare-player.jsonl" 3 stream)" || die "session 2 recorded too little"
ok "stream-bare-player.jsonl: $n lines"
n="$(keep "$WORK/get.raw" "$OUT/get-bundled-player.json" 1 get)" || die "get recorded nothing of the fixture player"
ok "get-bundled-player.json: $n line"

# commands.tsv: <argv> TAB <what the player received, ';'-joined, empty for nothing>.
python3 -I - "$WORK/received.log" "$OUT/commands.tsv" <<'PY'
import sys
rows, current = [], None
for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    if line.startswith("--> "):
        current = [line[4:], []]
        rows.append(current)
    elif line.startswith("--x "):
        current[1].append("REFUSED")
    elif current is not None and line:
        current[1].append(line)
with open(sys.argv[2], "w") as fh:
    fh.write("# argv\treceived by tools/fixture-player (';'-joined; empty: nothing arrived)\n")
    for argv, got in rows:
        fh.write(f"{argv}\t{';'.join(got)}\n")
PY
ok "commands.tsv: ${#COMMANDS[@]} commands"
rm -f "$OUT/loop-bundled-player.jsonl" "$OUT/loop-bare-player.jsonl"
