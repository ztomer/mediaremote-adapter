#!/usr/bin/env bash
# Per-repo gate entry point. Declares which toolchains this repo contains and
# delegates; it holds no gate logic of its own.
#   --staged : pre-commit scope (fast) — layer 1 only
#   --full   : pre-push scope — every layer
set -euo pipefail
GOH="${GOH_DIR:-${GOH:-$HOME/Projects/gates_of_heck}}"

# Informational flags never reach the gates below.
case "${1:-}" in
  -h|--help)
    echo "usage: gate.sh [--staged | --full | --doctor [repo] | --help]"
    exit 0 ;;
  --doctor)  exec bash "$GOH/gates/doctor.sh" "${2:-$PWD}" ;;
esac

"$GOH/gates/structural.sh" "$@"

# The cheap half of a language gate runs at COMMIT time on the staged files
# (rule 14: a commit gate weaker than the push gate lets you commit red and
# find out at push). Uncomment for the languages this repo contains:
#   "$GOH/gates/py_staged.sh"  .

case "${1:-}" in
  --full)
    # Add per-language layers for what this repo actually contains:
    #   "$GOH/gates/rust_gate.sh"  .
    #   "$GOH/gates/py_gate.sh"    .
    "$GOH/gates/swift_gate.sh" .
    # Layer 3 (genuinely local checks): the manifest carries no unsafeFlags and the ObjC shim
    # really compiled under ARC. Reads the build the swift gate just made.
    ./tools/repo_gates.sh
    ;;
esac
