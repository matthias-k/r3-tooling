#!/usr/bin/env bash
# bootstrap.sh — clone r3-tooling into a single canonical location and run its installer.
#
# Only needs git. Intended to be curl'd (once the repo is public):
#   curl -fsSL <raw-url>/bootstrap.sh | bash
# or downloaded and run. It asks for the toolchain directory, clones
# r3-tooling into <toolchain-root>/r3-tooling, and hands off to that clone's
# install.sh (passing --toolchain-root through). Any extra flags are forwarded to
# install.sh, e.g.:  bash bootstrap.sh --toolchain-root ~/rt --no-slurm --yes
set -euo pipefail

TOOLCHAIN_ROOT=""
BRANCH="main"
R3TOOLING_REMOTE="https://github.com/matthias-k/r3-tooling.git"   # public; override with --r3-tooling-remote
ASSUME_YES=0
FORWARD=()

while [ $# -gt 0 ]; do
  case "$1" in
    --toolchain-root) TOOLCHAIN_ROOT="${2:?--toolchain-root needs a value}"; shift 2;;
    --branch) BRANCH="${2:?--branch needs a value}"; shift 2;;
    --r3-tooling-remote) R3TOOLING_REMOTE="${2:?--r3-tooling-remote needs a value}"; shift 2;;
    --yes|-y) ASSUME_YES=1; FORWARD+=("$1"); shift;;   # forward --yes to install.sh too
    -h|--help)
      sed -n '2,13p' "$0"; exit 0;;
    *) FORWARD+=("$1"); shift;;                          # forward everything else
  esac
done

command -v git >/dev/null 2>&1 || { echo "ERROR: git is required" >&2; exit 1; }

# Ask for the toolchain directory unless it was given or we're non-interactive.
if [ -z "$TOOLCHAIN_ROOT" ]; then
  default="$HOME/r3-toolchain"
  if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
    read -r -p "Toolchain directory (holds the toolchain clones + venv) [$default]: " ans || true
    TOOLCHAIN_ROOT="${ans:-$default}"
  else
    TOOLCHAIN_ROOT="$default"
  fi
fi
TOOLCHAIN_ROOT="${TOOLCHAIN_ROOT/#\~/$HOME}"   # expand a leading ~

canon="$TOOLCHAIN_ROOT/r3-tooling"
if [ -d "$canon/.git" ]; then
  echo "==> updating r3-tooling at $canon"
  if [ -z "$(cd "$canon" && git status --porcelain)" ]; then
    git -C "$canon" pull --ff-only || echo "warn: could not fast-forward $canon (using as-is)"
  else
    echo "warn: $canon has local changes; using as-is"
  fi
else
  echo "==> cloning r3-tooling ($BRANCH) -> $canon"
  mkdir -p "$TOOLCHAIN_ROOT"
  git clone --branch "$BRANCH" "$R3TOOLING_REMOTE" "$canon"
fi

echo "==> running installer"
exec "$canon/install.sh" --toolchain-root "$TOOLCHAIN_ROOT" ${FORWARD[@]+"${FORWARD[@]}"}
