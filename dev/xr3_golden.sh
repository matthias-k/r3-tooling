#!/bin/bash
# Golden characterization harness for the xr3 extraction.
# Captures the output of KEPT, read-only, deterministic commands so that
# deletion-only refactors can be proven behavior-preserving.
#
# Usage:
#   dev/xr3_golden.sh baseline   # capture into golden/baseline/
#   dev/xr3_golden.sh current    # capture into golden/current/
#   dev/xr3_golden.sh check      # capture current + diff against baseline
#
# Requires env: R3_REPOSITORY, XR3_JOBDIR, XR3_PATH_GLOB
set -euo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
XR3="${XR3:-python $REPO/extensions/xr3/xr3}"
MODE="${1:-check}"

: "${R3_REPOSITORY:?set R3_REPOSITORY}"
: "${XR3_JOBDIR:?set XR3_JOBDIR (a working dir with committed history)}"
: "${XR3_PATH_GLOB:?set XR3_PATH_GLOB (a find --path glob)}"

capture() {
  local out="$1"; mkdir -p "$out"
  # Kept, read-only, deterministic commands. --no-check-git avoids git-state variance.
  $XR3 files "$XR3_JOBDIR"                         > "$out/files.txt"        2>&1 || true
  $XR3 history --long "$XR3_JOBDIR"                > "$out/history.txt"      2>&1 || true
  $XR3 find -p "$XR3_PATH_GLOB" --long             > "$out/find.txt"         2>&1 || true
  $XR3 check "$XR3_JOBDIR" --no-check-git          > "$out/check.txt"        2>&1 || true
  # Command-tree record (help WILL change as commands are pruned — recorded, not strict-diffed).
  $XR3 --help                                      > "$out/help.txt"         2>&1 || true
}

case "$MODE" in
  baseline) capture "$REPO/dev/golden/baseline"; echo "baseline captured" ;;
  current)  capture "$REPO/dev/golden/current";  echo "current captured" ;;
  check)
    capture "$REPO/dev/golden/current"
    echo "=== strict diff (expect EMPTY for data commands) ==="
    rc=0
    for f in files.txt history.txt find.txt check.txt; do
      if ! diff -u "$REPO/dev/golden/baseline/$f" "$REPO/dev/golden/current/$f"; then
        echo "!! DIFF in $f"; rc=1
      fi
    done
    [ $rc -eq 0 ] && echo "ALL DATA COMMANDS IDENTICAL"
    echo "=== help.txt diff (informational — pruned commands expected to disappear) ==="
    diff -u "$REPO/dev/golden/baseline/help.txt" "$REPO/dev/golden/current/help.txt" || true
    exit $rc ;;
  *) echo "usage: $0 {baseline|current|check}"; exit 2 ;;
esac
