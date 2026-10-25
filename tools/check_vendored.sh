#!/usr/bin/env bash
# The vendored core is ungive/mediaremote-adapter at ONE commit plus the patches listed in
# Vendor/ungive-mediaremote-adapter/patches, and nothing else. Proved, not promised:
#   1. a copy of the tree with every patch reverse-applied (last first) is byte-identical to the
#      upstream files recorded in upstream.sha256, and holds no file that is not one of them;
#   2. every patch file is named in VENDORED.md, and VENDORED.md names no patch that is absent;
#   3. the package's resource run.pl IS the vendored script (consumers look the helper up as
#      run.pl, so the script ships under that name; a byte copy, held equal here).
# An edit to a vendored file that is not a listed patch, an unlisted patch, or a drifted run.pl is
# red. Usage: tools/check_vendored.sh [repo-root]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOH="${GOH_DIR:-${GOH:-$HOME/Projects/gates_of_heck}}"
# shellcheck disable=SC1091
. "$GOH/tui/lib.sh"

ROOT="$(cd "${1:-$HERE/..}" && pwd)"
VENDOR="$ROOT/Vendor/ungive-mediaremote-adapter"
FORK_FILES='^(VENDORED\.md|upstream\.sha256|patches/.*)$'
fail=0

section "mediaremote-adapter: vendored core"

work="$(mktemp -d -t mra-vendored)"
trap 'rm -rf "$work"' EXIT
(cd "$VENDOR" && find . -type f | sed 's|^\./||' | grep -Ev "$FORK_FILES" | sort) >"$work/files"
mkdir "$work/tree"
(cd "$VENDOR" && tar -cf - -T "$work/files") | (cd "$work/tree" && tar -xf -)

mapfile -t patches < <(cd "$VENDOR/patches" && find . -name '*.patch' | sed 's|^\./||' | sort -r)
[ "${#patches[@]}" -gt 0 ] || { err "no patches under $VENDOR/patches"; exit 1; }
for patch in "${patches[@]}"; do
    if ! (cd "$work/tree" && git apply --reverse "$VENDOR/patches/$patch" 2>"$work/apply.err"); then
        err "patch $patch does not reverse-apply: the tree is not upstream plus the listed patches"
        sed 's/^/    /' "$work/apply.err" >&2
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    grep -v '^#' "$VENDOR/upstream.sha256" | awk '{print $2}' | sort >"$work/expected"
    if ! diff -u "$work/expected" "$work/files" >"$work/set.diff"; then
        err "vendored file set differs from upstream's (+ a file upstream does not have, - one removed):"
        sed 's/^/    /' "$work/set.diff" >&2
        fail=1
    elif ! (cd "$work/tree" && grep -v '^#' "$VENDOR/upstream.sha256" | shasum -a 256 -c --quiet) 2>&1; then
        err "a vendored file differs from upstream by more than the listed patches"
        fail=1
    else
        ok "tree = upstream $(grep -o '[0-9a-f]\{40\}' "$VENDOR/upstream.sha256" | head -1 | cut -c1-12) + ${#patches[@]} listed patches"
    fi
fi

for patch in "${patches[@]}"; do
    grep -qF "patches/$patch" "$VENDOR/VENDORED.md" || { err "patch $patch is not listed in VENDORED.md"; fail=1; }
done
while read -r named; do
    [ -f "$VENDOR/$named" ] || { err "VENDORED.md lists $named, which does not exist"; fail=1; }
done < <(grep -o 'patches/[0-9A-Za-z._-]*\.patch' "$VENDOR/VENDORED.md" | sort -u)
[ "$fail" -ne 0 ] || ok "VENDORED.md lists exactly the patches present"

if cmp -s "$VENDOR/bin/mediaremote-adapter.pl" "$ROOT/Sources/MediaRemoteAdapter/Resources/run.pl"; then
    ok "Resources/run.pl is the vendored bin/mediaremote-adapter.pl"
else
    err "Resources/run.pl differs from Vendor/ungive-mediaremote-adapter/bin/mediaremote-adapter.pl: copy it"
    fail=1
fi

exit "$fail"
