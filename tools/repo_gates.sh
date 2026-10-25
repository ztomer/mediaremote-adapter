#!/usr/bin/env bash
# Layer 3 (repo-specific): what the swift gate cannot see about the vendored ObjC core.
#   1. The manifest passes the compiler and linker nothing unsafe. `unsafeFlags` makes the package
#      unusable as a dependency of anything that is not a root package, and every flag it carried
#      (-fobjc-arc, -framework X) has a safe spelling.
#   2. The core REALLY compiled under ARC. ungive's CMake passes `-fobjc-arc`; the manifest relies
#      on the toolchain's default instead, and a default is an assumption until the real build
#      line says so: both the compile line SwiftPM handed clang and the object code it produced
#      are read here. Needs the build the swift gate just made (.build is not touched).
#   3. The core carries no load-time initializer beyond an allowlist (vendored patch 0002): it is
#      linked into host apps, where a constructor runs inside the host at dyld time.
#   4. The vendored tree is upstream plus the listed patches (tools/check_vendored.sh).
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
mapfile -t resps < <(find "$ROOT/.build" -path '*MediaRemoteAdapterCore-t.build*' -name '*-common-args.resp' -not -path "$ROOT/.build/tsan/*" 2>/dev/null)
if [ "${#resps[@]}" -eq 0 ]; then
    err "no MediaRemoteAdapterCore compile line under .build: the swift gate's build is missing, so ARC is unproven"
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
# retain/release build of these files (blocks, collections, dictionaries) has none. stream.o is
# the largest user of all three.
mapfile -t objs < <(find "$ROOT/.build" -path '*MediaRemoteAdapterCore-t.build*' -name 'stream.o' -not -path "$ROOT/.build/tsan/*" 2>/dev/null)
if [ "${#objs[@]}" -eq 0 ]; then
    err "no stream.o under .build: ARC is unproven"
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

# Load-time initializers. Each object's __mod_init_func/__init_offsets entries (8 or 4 bytes each)
# against an allowlist of exactly what is reviewed: send/shuffle/repeat build their table of
# accepted values (static data), and stream registers its destructor (a no-op unless a stream ran
# in that process). Anything else is code that would run inside a host app at dyld time: red.
section "mediaremote-adapter: load-time initializers in the core"
declare -A allowed_inits=([send.o]=1 [shuffle.o]=1 [repeat.o]=1 [stream.o]=1)
mapfile -t core_objs < <(find "$ROOT/.build" -path '*MediaRemoteAdapterCore-t.build*' -name '*.o' -not -path "$ROOT/.build/tsan/*" 2>/dev/null | sort)
if [ "${#core_objs[@]}" -lt 15 ]; then
    err "found ${#core_objs[@]} core objects under .build, expected 15 (one per ADAPTER_SOURCES file): unproven"
    fail=1
fi
init_fail=0
for obj in "${core_objs[@]}"; do
    count=0
    while read -r sect size; do
        if [ "$sect" = "__mod_init_func" ]; then count=$((count + size / 8)); else count=$((count + size / 4)); fi
    done < <(otool -l "$obj" | awk '
        /sectname/ { name = $2 }
        /^ *size / && (name == "__mod_init_func" || name == "__init_offsets") { print name, $2 }' \
        | while read -r sect hex; do echo "$sect $((hex))"; done)
    want="${allowed_inits[$(basename "$obj")]:-0}"
    if [ "$count" -gt "$want" ]; then
        err "$(basename "$obj"): $count load-time initializer(s), $want allowed (it would run inside every host app)"
        init_fail=1
    fi
done
if [ "$init_fail" -eq 0 ] && [ "${#core_objs[@]}" -ge 15 ]; then
    ok "${#core_objs[@]} core objects: load-time initializers only in the allowlist"
fi
[ "$init_fail" -eq 0 ] || fail=1

"$HERE/check_vendored.sh" "$ROOT" || fail=1

# 5. The tests under ThreadSanitizer. MediaController moves state between the main queue, its pipe
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
