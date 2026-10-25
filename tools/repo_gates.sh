#!/usr/bin/env bash
# Layer 3 (repo-specific): the two things the swift gate cannot see about the ObjC shim.
#   1. The manifest passes the compiler and linker nothing unsafe. `unsafeFlags` makes the package
#      unusable as a dependency of anything that is not a root package, and every flag it carried
#      (-fobjc-arc, -framework X) has a safe spelling.
#   2. The shim REALLY compiled under ARC. Dropping `-fobjc-arc` from the manifest is only safe if
#      the toolchain's default supplies it, and a default is an assumption until the real build
#      line says so: both the compile line SwiftPM handed clang and the object code it produced
#      are read here. Needs the build the swift gate just made (.build is not touched).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOH="${GOH_DIR:-${GOH:-$HOME/Projects/gates_of_heck}}"
# shellcheck disable=SC1091
. "$GOH/tui/lib.sh"

ROOT="${MRA_ROOT:-$HERE/..}"
fail=0

section "mediaremote-adapter: manifest and ARC"

if grep -n 'unsafeFlags' "$ROOT/Package.swift"; then
    err "Package.swift uses unsafeFlags: use cSettings/linkerSettings/linkedFramework"
    fail=1
else
    ok "Package.swift: no unsafeFlags"
fi

# The compile line: SwiftPM/xcbuild writes the shared clang arguments of the shim's target to a
# *-common-args.resp beside its objects. Debug and release both count.
mapfile -t resps < <(find "$ROOT/.build" -path '*CIMediaRemote-t.build*' -name '*-common-args.resp' 2>/dev/null)
if [ "${#resps[@]}" -eq 0 ]; then
    err "no CIMediaRemote compile line under .build: the swift gate's build is missing, so ARC is unproven"
    fail=1
fi
for resp in "${resps[@]}"; do
    args="$(tr ' ' '\n' <"$resp")"
    if grep -qx -- '-fno-objc-arc' <<<"$args"; then
        err "compile line disables ARC: $resp"
        fail=1
    elif grep -qx -- '-fobjc-arc' <<<"$args"; then
        ok "compile line carries -fobjc-arc ($(basename "$(dirname "$resp")"))"
    else
        err "compile line has no -fobjc-arc: $resp"
        fail=1
    fi
done

# The object code: ARC inserts calls to objc_release/objc_retain*/objc_storeStrong; a manual
# retain/release build of this file (blocks, an autorelease pool, collections) has none.
mapfile -t objs < <(find "$ROOT/.build" -path '*CIMediaRemote-t.build*' -name 'MediaRemoteAdapter.o' 2>/dev/null)
if [ "${#objs[@]}" -eq 0 ]; then
    err "no MediaRemoteAdapter.o under .build: ARC is unproven"
    fail=1
fi
for obj in "${objs[@]}"; do
    undefined="$(nm -u "$obj")"
    if grep -Eq '_objc_(release|retain|storeStrong|autoreleaseReturnValue|retainAutoreleasedReturnValue)' <<<"$undefined"; then
        ok "object code uses ARC runtime calls ($(basename "$(dirname "$(dirname "$(dirname "$obj")")")"))"
    else
        err "object code makes no ARC runtime calls: $obj"
        fail=1
    fi
done

# 3. The tests under ThreadSanitizer. MediaController moves state between the main queue, its pipe
#    reader's queue and its command queue; a plain test run passes over a data race that only TSan
#    sees (eventCount was read on main while the reader wrote it under the lock: 2026-10-24).
#    Its own scratch path, so the instrumented build never replaces the one checked above.
section "mediaremote-adapter: ThreadSanitizer"
if [ "${MRA_SKIP_TSAN:-0}" = "1" ]; then
    err "MRA_SKIP_TSAN=1: the race check did not run"
    fail=1
else
    tsan_log="$(mktemp -t mra-tsan)"
    if (cd "$ROOT" && swift test --sanitize=thread --scratch-path "$ROOT/.build/tsan") >"$tsan_log" 2>&1 \
        && ! grep -aq 'WARNING: ThreadSanitizer' "$tsan_log"; then
        ok "swift test --sanitize=thread: no races"
    else
        grep -a -A3 -E 'WARNING: ThreadSanitizer|SUMMARY: ThreadSanitizer|error:' "$tsan_log" | head -60 >&2 || true
        err "ThreadSanitizer run failed or reported a race (full log: $tsan_log)"
        fail=1
    fi
fi

exit "$fail"
