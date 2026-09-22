#!/usr/bin/env bash
# install.sh — set up (or update) the full r3 toolchain: r3 + xr3/xr3-slurm + foreman.
# Idempotent: re-running updates in place. Every prompt has a matching flag; a fully
# flagged (or --yes) invocation runs with no prompts and doubles as the update command.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- defaults (overridable by flags) ----
TOOLCHAIN_ROOT="$HOME/r3-toolchain"
VENV_DIR=""                 # default: $TOOLCHAIN_ROOT/.venv (resolved after parsing)
PYTHON_VERSION="3.12"
BIN_DIR=""                  # default: ~/bin, or $LUSTREWORK/bin if it exists
CONFIG_PATH="$HOME/.config/xr3.yaml"
PROJECTS_DIR="$HOME/projects"
R3_REPO="$HOME/r3_repo"
CLONE_PROTO="ssh"
R3_REMOTE=""                # default derived from proto
FOREMAN_REMOTE=""           # default derived from proto
R3_REF="main"
FOREMAN_REF="main"
SLURM_HEADNODES=()
SLURM_SUBMIT_HOST=""
NO_SLURM=0
INSTALL_SKILL="prompt"      # prompt | yes | no
SKILL_DECISION=""           # resolved skill decision (set by phase_skill)
SKILL_TARGET="all"          # all | claude | codex
ASSUME_YES=0
DRY_RUN=0
NO_UPDATE=0

EXIT_CODE=0                 # phases set this to 1 on non-fatal errors (e.g. skipped repo)

usage() {
  sed -n '2,4p' "$0"
  cat <<'EOF'

Usage: ./install.sh [flags]

Run with no flags on a terminal to be prompted for the settings below (press
Enter to accept each default). --yes (or any non-interactive stdin) skips all
prompts and uses defaults/flags.

Layout:
  --toolchain-root DIR   (default ~/r3-toolchain) clones + venv live here
  --venv DIR             (default <toolchain-root>/.venv)
  --python VER           (default 3.12; must satisfy r3 >=3.9,<3.13)
  --bin-dir DIR          (default ~/bin, or $LUSTREWORK/bin if present)
  --config PATH          (default ~/.config/xr3.yaml)
  --projects-dir DIR     (default ~/projects) base root written into pathmap
  --r3-repo DIR          (default ~/r3_repo) R3_REPOSITORY

Sources:
  --clone-proto ssh|https        (default ssh)
  --r3-remote URL / --foreman-remote URL
  --r3-ref REF / --foreman-ref REF   (default main)

SLURM:
  --slurm-headnode HOST   (repeatable)   --slurm-submit-host HOST   --no-slurm

Skill:
  --install-skill / --no-install-skill   --skill-target all|claude|codex

Modes:
  --yes         accept defaults, no prompts
  --dry-run     print actions, change nothing
  --no-update   on re-run, skip git pulls (only re-ensure env/wrappers/config)
  -h, --help
EOF
}

# ---- output + run helpers ----
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mERROR\033[0m %s\n' "$*" >&2; }

# run CMD...: execute, or just print under --dry-run.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi
}

# prompt VAR "question" "default": set VAR from stdin unless --yes/non-interactive.
prompt() {
  local __var="$1" __q="$2" __def="$3" __ans
  if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then printf -v "$__var" '%s' "$__def"; return; fi
  read -r -p "$__q [$__def]: " __ans || true
  printf -v "$__var" '%s' "${__ans:-$__def}"
}

# reqval "$@": ensure the current flag ($1) has a value ($2) following it.
reqval() { [ "$#" -ge 2 ] || { err "missing value for $1"; exit 2; }; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --toolchain-root) reqval "$@"; TOOLCHAIN_ROOT="$2"; shift 2;;
      --venv) reqval "$@"; VENV_DIR="$2"; shift 2;;
      --python) reqval "$@"; PYTHON_VERSION="$2"; shift 2;;
      --bin-dir) reqval "$@"; BIN_DIR="$2"; shift 2;;
      --config) reqval "$@"; CONFIG_PATH="$2"; shift 2;;
      --projects-dir) reqval "$@"; PROJECTS_DIR="$2"; shift 2;;
      --r3-repo) reqval "$@"; R3_REPO="$2"; shift 2;;
      --clone-proto) reqval "$@"; CLONE_PROTO="$2"; shift 2;;
      --r3-remote) reqval "$@"; R3_REMOTE="$2"; shift 2;;
      --foreman-remote) reqval "$@"; FOREMAN_REMOTE="$2"; shift 2;;
      --r3-ref) reqval "$@"; R3_REF="$2"; shift 2;;
      --foreman-ref) reqval "$@"; FOREMAN_REF="$2"; shift 2;;
      --slurm-headnode) reqval "$@"; SLURM_HEADNODES+=("$2"); shift 2;;
      --slurm-submit-host) reqval "$@"; SLURM_SUBMIT_HOST="$2"; shift 2;;
      --no-slurm) NO_SLURM=1; shift;;
      --install-skill) INSTALL_SKILL="yes"; shift;;
      --no-install-skill) INSTALL_SKILL="no"; shift;;
      --skill-target) reqval "$@"; SKILL_TARGET="$2"; shift 2;;
      --yes|-y) ASSUME_YES=1; shift;;
      --dry-run) DRY_RUN=1; shift;;
      --no-update) NO_UPDATE=1; shift;;
      -h|--help) usage; exit 0;;
      *) err "unknown flag: $1"; usage; exit 2;;
    esac
  done
}

# _default_bindir: ~/bin, or $LUSTREWORK/bin if that shared dir exists.
_default_bindir() {
  if [ -n "${LUSTREWORK:-}" ] && [ -d "${LUSTREWORK:-}/bin" ]; then echo "$LUSTREWORK/bin"; else echo "$HOME/bin"; fi
}

# interactive_config: prompt for the main settings (Enter accepts each [default]).
# A no-op under --yes or a non-interactive stdin (prompt returns the default),
# so a fully-flagged or --yes run stays non-interactive.
interactive_config() {
  if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
    info "Configure the install (press Enter to accept each [default]):"
  fi
  prompt CLONE_PROTO    "  git clone protocol (ssh/https)" "$CLONE_PROTO"
  prompt TOOLCHAIN_ROOT "  toolchain root (r3+foreman clones and the venv live here)" "$TOOLCHAIN_ROOT"
  prompt BIN_DIR        "  bin dir for wrappers (must be on PATH)" "${BIN_DIR:-$(_default_bindir)}"
  prompt PROJECTS_DIR   "  projects dir (written as the pathmap base root)" "$PROJECTS_DIR"
  prompt R3_REPO        "  R3_REPOSITORY (job repository) location" "$R3_REPO"
  prompt CONFIG_PATH    "  xr3 config file path" "$CONFIG_PATH"
  # SLURM: ask only when not already decided by flags, and only interactively.
  if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ] && [ "$NO_SLURM" -eq 0 ] && [ "${#SLURM_HEADNODES[@]}" -eq 0 ]; then
    local hn=""; read -r -p "  SLURM head node for xr3-slurm (blank = no SLURM): " hn || true
    if [ -n "$hn" ]; then SLURM_HEADNODES=("$hn"); else NO_SLURM=1; fi
  fi
}

resolve_defaults() {
  case "$CLONE_PROTO" in ssh|https) ;; *) err "--clone-proto must be ssh or https (got: $CLONE_PROTO)"; exit 2;; esac
  case "$SKILL_TARGET" in all|claude|codex) ;; *) err "--skill-target must be all|claude|codex (got: $SKILL_TARGET)"; exit 2;; esac
  [ -n "$VENV_DIR" ] || VENV_DIR="$TOOLCHAIN_ROOT/.venv"
  [ -n "$BIN_DIR" ] || BIN_DIR="$(_default_bindir)"
  local host="github.com"
  if [ -z "$R3_REMOTE" ]; then
    [ "$CLONE_PROTO" = "https" ] && R3_REMOTE="https://$host/mtangemann/r3.git" || R3_REMOTE="git@$host:mtangemann/r3.git"
  fi
  if [ -z "$FOREMAN_REMOTE" ]; then
    [ "$CLONE_PROTO" = "https" ] && FOREMAN_REMOTE="https://$host/mtangemann/foreman.git" || FOREMAN_REMOTE="git@$host:mtangemann/foreman.git"
  fi
}

# ---- phase stubs (replaced by later tasks) ----
phase_preflight() {
  info "preflight: checking prerequisites"
  local missing=0
  for tool in git ssh; do
    command -v "$tool" >/dev/null 2>&1 || { err "missing required tool: $tool"; missing=1; }
  done
  [ "$missing" -eq 1 ] && { err "install the missing tools and re-run"; exit 1; }

  if [ "$CLONE_PROTO" = "ssh" ]; then
    # ssh -T git@github.com exits 1 on success (no shell); grep for the greeting.
    if ssh -T -o BatchMode=yes -o ConnectTimeout=8 git@github.com 2>&1 | grep -qi "successfully authenticated"; then
      info "github ssh access ok"
    else
      warn "github ssh auth not confirmed; foreman is private and its clone may fail."
      warn "use --clone-proto https for public repos, or set up an ssh key for github."
    fi
  fi

  if ! command -v uv >/dev/null 2>&1; then
    local do_install=0
    if [ "$ASSUME_YES" -eq 1 ]; then
      do_install=1
    else
      local ans; prompt ans "uv not found. Install it now via the official installer?" "yes"
      [ "$ans" = "yes" ] && do_install=1
    fi
    if [ "$do_install" -eq 1 ]; then
      info "installing uv"
      run bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
      export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    else
      err "uv is required; install from https://docs.astral.sh/uv/ and re-run"; exit 1
    fi
  fi
  [ "$DRY_RUN" -eq 1 ] || info "uv: $(command -v uv 2>/dev/null || echo 'will be installed')"
}
# clone_or_update DIR URL REF LABEL: clone if absent; else ff-only update (safe).
clone_or_update() {
  local dir="$1" url="$2" ref="$3" label="$4"
  if [ ! -d "$dir/.git" ]; then
    info "cloning $label -> $dir"
    run git clone --branch "$ref" "$url" "$dir" \
      || { err "clone of $label failed ($url)"; EXIT_CODE=1; return; }
    return
  fi
  if [ "$NO_UPDATE" -eq 1 ]; then info "$label present; --no-update, skipping pull"; return; fi
  info "updating $label ($dir)"
  # dirty tree? refuse to touch.
  if [ -n "$(cd "$dir" && git status --porcelain 2>/dev/null)" ]; then
    err "$label has local changes; skipping update. Resolve manually in $dir."
    EXIT_CODE=1; return
  fi
  run git -C "$dir" fetch --quiet origin \
    || { err "$label: fetch failed; skipping. Resolve manually in $dir."; EXIT_CODE=1; return; }
  # ff-only; diverged -> error, do not merge.
  if ! run git -C "$dir" pull --ff-only origin "$ref"; then
    err "$label could not fast-forward (diverged from origin/$ref); skipping. Resolve manually in $dir."
    EXIT_CODE=1
  fi
}

phase_clones() {
  info "clones: r3, foreman under $TOOLCHAIN_ROOT"
  run mkdir -p "$TOOLCHAIN_ROOT" \
    || { err "cannot create toolchain root $TOOLCHAIN_ROOT"; exit 1; }
  clone_or_update "$TOOLCHAIN_ROOT/r3" "$R3_REMOTE" "$R3_REF" "r3"
  clone_or_update "$TOOLCHAIN_ROOT/foreman" "$FOREMAN_REMOTE" "$FOREMAN_REF" "foreman"
}
phase_venv() {
  info "venv: $VENV_DIR (python $PYTHON_VERSION)"
  [ -d "$VENV_DIR" ] || run uv venv --python "$PYTHON_VERSION" "$VENV_DIR" \
    || { err "failed to create venv at $VENV_DIR"; exit 1; }
  info "installing r3 + foreman (editable) + xr3 deps"
  run uv pip install --python "$VENV_DIR/bin/python" \
    -e "$TOOLCHAIN_ROOT/r3" -e "$TOOLCHAIN_ROOT/foreman" \
    || { err "editable install of r3/foreman failed"; exit 1; }
  run uv pip install --python "$VENV_DIR/bin/python" click pyyaml executor tqdm \
    || { err "install of xr3 deps failed"; exit 1; }
}
# ensure_bashrc_block MARKER LINE...: idempotently maintain a marked block in ~/.bashrc.
ensure_bashrc_block() {
  local marker="$1"; shift
  local rc="$HOME/.bashrc" begin="# >>> $marker >>>" end="# <<< $marker <<<"
  local body; body="$(printf '%s\n' "$@")"
  if [ "$DRY_RUN" -eq 1 ]; then printf '  [dry-run] ensure ~/.bashrc block "%s"\n' "$marker"; return; fi
  touch "$rc"
  # strip an existing block, then append a fresh one.
  local tmp; tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0==b{skip=1} !skip{print} $0==e{skip=0}' "$rc" > "$tmp"
  { cat "$tmp"; printf '%s\n%s\n%s\n' "$begin" "$body" "$end"; } > "$rc"
  rm -f "$tmp"
}

# write_wrapper NAME BODY: write an executable wrapper into BIN_DIR.
write_wrapper() {
  local name="$1" body="$2" dest="$BIN_DIR/$1"
  if [ "$DRY_RUN" -eq 1 ]; then printf '  [dry-run] write wrapper %s\n' "$dest"; return; fi
  printf '#!/bin/bash\n# %s wrapper (generated by r3-tooling install.sh). See SETUP.md.\n%s\n' \
    "$name" "$body" > "$dest"
  chmod +x "$dest"
}

phase_wrappers() {
  info "wrappers -> $BIN_DIR"
  run mkdir -p "$BIN_DIR" \
    || { err "cannot create bin dir $BIN_DIR"; exit 1; }
  local py="$VENV_DIR/bin/python"
  write_wrapper r3        "exec \"$VENV_DIR/bin/r3\" \"\$@\""
  write_wrapper foreman   "exec \"$VENV_DIR/bin/foreman\" \"\$@\""
  write_wrapper xr3       "exec \"$py\" \"$REPO_DIR/extensions/xr3/xr3\" \"\$@\""
  write_wrapper xr3-slurm "exec \"$py\" \"$REPO_DIR/extensions/xr3-slurm/xr3-slurm\" \"\$@\""
  ensure_bashrc_block "r3-toolchain PATH" "export PATH=\"$BIN_DIR:\$PATH\""
  info "added $BIN_DIR to PATH in ~/.bashrc (run: source ~/.bashrc)"
}
phase_config() {
  info "config: $CONFIG_PATH"
  local abs_projects; abs_projects="$(cd "$PROJECTS_DIR" 2>/dev/null && pwd || realpath -m "$PROJECTS_DIR" 2>/dev/null || echo "$PROJECTS_DIR")"
  # initialize the R3_REPOSITORY. An empty dir is NOT a valid repo — r3 needs an
  # r3.yaml, created by `r3 init` (which refuses a pre-existing path).
  if [ -f "$R3_REPO/r3.yaml" ]; then
    info "R3_REPOSITORY already initialized: $R3_REPO"
  elif [ -e "$R3_REPO" ]; then
    if [ -d "$R3_REPO" ] && [ -z "$(ls -A "$R3_REPO" 2>/dev/null)" ]; then
      info "initializing empty R3_REPOSITORY: $R3_REPO"
      run rmdir "$R3_REPO" && run "$VENV_DIR/bin/r3" init "$R3_REPO" \
        || { err "failed to initialize r3 repository at $R3_REPO"; exit 1; }
    else
      err "$R3_REPO exists but is not an r3 repository (no r3.yaml) and is not empty;"
      err "refusing to touch it — remove it or pass a different --r3-repo."
      EXIT_CODE=1
    fi
  else
    info "initializing R3_REPOSITORY: $R3_REPO"
    run "$VENV_DIR/bin/r3" init "$R3_REPO" \
      || { err "failed to initialize r3 repository at $R3_REPO"; exit 1; }
  fi
  ensure_bashrc_block "r3-toolchain R3_REPOSITORY" "export R3_REPOSITORY=\"$R3_REPO\""

  local target
  if [ -f "$CONFIG_PATH" ]; then
    info "config exists; leaving it untouched (writing $CONFIG_PATH.new for reference)"
    target="$CONFIG_PATH.new"
  else
    target="$CONFIG_PATH"
  fi

  # build slurm section (or omit).
  local slurm_yaml=""
  if [ "$NO_SLURM" -eq 0 ]; then
    local heads="[]" submit="null"
    if [ "${#SLURM_HEADNODES[@]}" -gt 0 ]; then
      heads="[$(printf '"%s", ' "${SLURM_HEADNODES[@]}" | sed 's/, $//')]"
      submit="\"${SLURM_SUBMIT_HOST:-${SLURM_HEADNODES[0]}}\""
    fi
    slurm_yaml=$'\nslurm:\n  headnodes: '"$heads"$'\n  submit_host: '"$submit"$'\n  exclude_nodes: []\n  partition: null\n  mem: null'
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] write %s (base root: %s; slurm: %s)\n' "$target" "$abs_projects" \
      "$([ "$NO_SLURM" -eq 1 ] && echo omitted || echo included)"
    return
  fi
  mkdir -p "$(dirname "$target")" || { err "cannot create config dir for $target"; exit 1; }
  cat > "$target" <<EOF
# xr3 configuration (generated by r3-tooling install.sh). See extensions/CONTRACT.md.
pathmap:
  roots:
    - path: $abs_projects   # base root: subpaths map directly
blockers:
  tags: ["bug/"]
  block_on_wip: true
dev_checkout:
  ignored_destinations: []
  ignored_repositories: []$slurm_yaml
EOF
  info "wrote $target"
}
phase_skill() {
  SKILL_DECISION="$INSTALL_SKILL"
  if [ "$SKILL_DECISION" = "prompt" ]; then
    local ans; prompt ans "Install the r3 agent skill (symlink into claude/codex)?" "yes"
    [ "$ans" = "yes" ] && SKILL_DECISION="yes" || SKILL_DECISION="no"
  fi
  [ "$SKILL_DECISION" = "yes" ] || { info "skill install: skipped"; return; }

  local src="$REPO_DIR/skills/r3"
  link_skill() { # AGENT_DIR
    local d="$1"
    [ -d "$d" ] || { info "skill: $d absent, skipping"; return; }
    if [ -e "$d/r3" ] && [ ! -L "$d/r3" ]; then warn "skill: $d/r3 exists and is not a symlink; skipping"; return; fi
    run ln -sfn "$src" "$d/r3" || { warn "could not link skill into $d"; return; }
    info "skill linked -> $d/r3"
  }
  case "$SKILL_TARGET" in
    claude) link_skill "$HOME/.claude/skills";;
    codex)  link_skill "$HOME/.codex/skills";;
    all|*)  link_skill "$HOME/.claude/skills"; link_skill "$HOME/.codex/skills";;
  esac
}
print_remote_foreman() {
  local host="${SLURM_SUBMIT_HOST:-${SLURM_HEADNODES[0]:-<cluster-host>}}"
  cat <<EOF

--- remote-foreman launcher (copy to your LAPTOP; not installed here) ---
# Opens the cluster's foreman in your local browser via an SSH tunnel.
ssh -L 8080:localhost:8080 $host \\
  'R3_REPOSITORY="$R3_REPO" "$BIN_DIR/foreman" --port 8080'
# then browse: http://localhost:8080
------------------------------------------------------------------------
EOF
}

phase_verify() {
  info "verify"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] would run: <bin>/{r3,xr3,xr3-slurm,foreman} --help + a PATH subprocess check\n'
  else
    local ok=1
    # Check the wrappers we just wrote by ABSOLUTE PATH. Resolving bare names
    # here would hit any r3/xr3 shell functions in the caller's environment
    # (which can even `exec`, replacing this process mid-verify).
    for t in r3 xr3 xr3-slurm foreman; do
      if [ -x "$BIN_DIR/$t" ]; then info "found $t -> $BIN_DIR/$t"; else err "missing wrapper: $BIN_DIR/$t"; ok=0; fi
    done
    for t in xr3 xr3-slurm; do
      "$BIN_DIR/$t" --help >/dev/null 2>&1 && info "$t --help ok" || { err "$t --help failed"; ok=0; }
    done
    # subprocess resolution via PATH (execvp ignores shell functions/aliases):
    PATH="$BIN_DIR:$PATH" python3 -c "import subprocess,sys; sys.exit(subprocess.run(['xr3','--help'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode)" \
      && info "xr3 resolves from a subprocess" || { err "xr3 not resolvable from subprocess"; ok=0; }
    [ "$ok" -eq 1 ] || EXIT_CODE=1
  fi
  print_remote_foreman
  info "next: run 'source ~/.bashrc' to pick up PATH + R3_REPOSITORY"
}

# _update_flags: the flag string (after the install.sh path) reproducing this install.
_update_flags() {
  local f="--yes"
  f+="$(printf ' --toolchain-root %q --venv %q --python %q --bin-dir %q --config %q --projects-dir %q --r3-repo %q --clone-proto %q --r3-ref %q --foreman-ref %q' \
      "$TOOLCHAIN_ROOT" "$VENV_DIR" "$PYTHON_VERSION" "$BIN_DIR" "$CONFIG_PATH" "$PROJECTS_DIR" "$R3_REPO" "$CLONE_PROTO" "$R3_REF" "$FOREMAN_REF")"
  if [ "$NO_SLURM" -eq 1 ]; then
    f+=" --no-slurm"
  else
    local h
    for h in "${SLURM_HEADNODES[@]:-}"; do
      if [ -n "$h" ]; then f+="$(printf ' --slurm-headnode %q' "$h")"; fi
    done
    if [ -n "$SLURM_SUBMIT_HOST" ]; then f+="$(printf ' --slurm-submit-host %q' "$SLURM_SUBMIT_HOST")"; fi
  fi
  case "$SKILL_DECISION" in
    yes) f+="$(printf ' --install-skill --skill-target %q' "$SKILL_TARGET")";;
    no)  f+=" --no-install-skill";;
  esac
  printf '%s' "$f"
}

# print_update_command: print the exact no-prompt update command reproducing this
# install, and save it as <toolchain-root>/update.sh (which also refreshes the
# r3-tooling checkout first, since the installer won't self-update otherwise).
print_update_command() {
  local install_path="$REPO_DIR/install.sh" flags; flags="$(_update_flags)"
  printf '\n'
  info "To update later (no prompts), re-run this command:"
  printf '  %q %s\n' "$install_path" "$flags"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] would save %s/update.sh\n' "$TOOLCHAIN_ROOT"
    return
  fi
  local upd="$TOOLCHAIN_ROOT/update.sh"
  if { printf '#!/usr/bin/env bash\n'
       printf '# Auto-generated by r3-tooling install.sh — run to update the toolchain.\n'
       printf '# Regenerated on every install; to change settings, re-run install.sh directly.\n'
       printf 'set -euo pipefail\n'
       printf 'if [ -d %q/.git ]; then\n' "$REPO_DIR"
       printf '  git -C %q pull --ff-only || echo "warn: could not fast-forward %s (skipping its update)"\n' "$REPO_DIR" "$REPO_DIR"
       printf 'fi\n'
       printf 'exec %q %s\n' "$install_path" "$flags"
     } > "$upd"; then
    chmod +x "$upd" 2>/dev/null || true
    info "Saved update script: $upd  (run it any time to update)"
  else
    warn "could not write $upd"
  fi
}

main() {
  parse_args "$@"
  interactive_config
  resolve_defaults
  info "r3 toolchain installer (dry-run=$DRY_RUN)"
  info "toolchain-root=$TOOLCHAIN_ROOT venv=$VENV_DIR bin=$BIN_DIR config=$CONFIG_PATH"
  local slurm_desc="none"
  [ "$NO_SLURM" -eq 1 ] || slurm_desc="${SLURM_HEADNODES[*]:-<empty>}"
  info "projects=$PROJECTS_DIR r3-repo=$R3_REPO clone-proto=$CLONE_PROTO slurm=$slurm_desc"
  if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    local go=""; read -r -p "Proceed with these settings? [yes]: " go || true
    case "${go:-yes}" in y|Y|yes|YES) ;; *) info "aborted."; exit 0;; esac
  fi
  phase_preflight
  phase_clones
  phase_venv
  phase_wrappers
  phase_config
  phase_skill
  phase_verify
  print_update_command
  [ "$EXIT_CODE" -eq 0 ] && info "done." || warn "finished with errors (see above)."
  exit "$EXIT_CODE"
}

main "$@"
