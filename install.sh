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
CLONE_PROTO="https"
R3_REMOTE=""                # default derived from proto
FOREMAN_REMOTE=""           # default derived from proto
R3_REF="main"
FOREMAN_REF="main"          # foreman-ai-builder-camp's default branch mirrors upstream dev; r3 tracks main
SLURM_HEADNODES=()
SLURM_SUBMIT_HOST=""
NO_SLURM=0
INSTALL_SKILL="prompt"      # prompt | yes | no (resolved to yes/no in interactive_config)
SKILL_TARGET="all"          # all | claude | codex
IMPORT_CONTEXT="prompt"     # prompt | yes | no — add the workflow @import to a CLAUDE.md
CONTEXT_CLAUDE_MD="$HOME/.claude/CLAUDE.md"   # target for the @import (--import-context)
INSTALL_FEEDBACK="prompt"   # prompt | yes | no — install the r3-feedback observer (opt-out; default on)
ASSUME_YES=0
INTERACTIVE=0               # resolved in main(): 1 = prompt on a tty, 0 = --yes/non-interactive
DRY_RUN=0
NO_UPDATE=0
NO_RELOCATE="${R3_NO_RELOCATE:-0}"   # 1 = run this clone in place, don't relocate
BUILD_FRONTEND=1            # set to 0 by preflight if npm is unavailable (foreman UI stays unstyled)

# track which promptable settings were given explicitly, so we don't re-ask them
CLONE_PROTO_SET=0; TOOLCHAIN_ROOT_SET=0; BIN_DIR_SET=0
PROJECTS_DIR_SET=0; R3_REPO_SET=0; CONFIG_PATH_SET=0

EXIT_CODE=0                 # phases set this to 1 on non-fatal errors (e.g. skipped repo)

usage() {
  sed -n '2,4p' "$0"
  cat <<'EOF'

Usage: ./install.sh [flags]

Prompts for the settings below on a terminal (press Enter to accept each
[default]) — including when piped, e.g. `curl … | bash`, since prompts read from
/dev/tty. --yes runs unattended (defaults/flags, no prompts). With no terminal and
no --yes the installer errors rather than silently taking defaults.

Layout:
  --toolchain-root DIR   (default ~/r3-toolchain) clones + venv live here
  --venv DIR             (default <toolchain-root>/.venv)
  --python VER           (default 3.12; must satisfy r3 >=3.9,<3.13)
  --bin-dir DIR          (default ~/bin, or $LUSTREWORK/bin if present)
  --config PATH          (default ~/.config/xr3.yaml)
  --projects-dir DIR     (default ~/projects) base root written into pathmap
  --r3-repo DIR          (default ~/r3_repo) R3_REPOSITORY

Sources:
  --clone-proto ssh|https        (default https)
  --r3-remote URL / --foreman-remote URL
  --r3-ref REF / --foreman-ref REF   (defaults: r3 main, foreman main)

SLURM:
  --slurm-headnode HOST   (repeatable)   --slurm-submit-host HOST   --no-slurm

Skill:
  --install-skill / --no-install-skill   --skill-target all|claude|codex
  --feedback / --no-feedback             r3-feedback observer (local-only; opt-out, default on)

Agent context (point agents at RESEARCH_WORKFLOW.md — CLAUDE.md @import / AGENTS.md pointer):
  --import-context / --no-import-context   --context-claude-md PATH  (default ~/.claude/CLAUDE.md)

Modes:
  --yes         accept defaults, no prompts
  --dry-run     print actions, change nothing
  --no-update   on re-run, skip git pulls (only re-ensure env/wrappers/config)
  --no-relocate run THIS clone in place; don't relocate to <toolchain-root>/r3-tooling
  -h, --help

By default the installer works from a single canonical clone at
<toolchain-root>/r3-tooling: if launched from another clone it ensures that one
exists and re-runs from it, so wrappers/skill/update.sh all point at one place.
EOF
}

# ---- output + run helpers ----
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mERROR\033[0m %s\n' "$*" >&2; }

# have_tty: true if a controlling terminal is available to prompt on — works even
# when stdin is a pipe (e.g. `curl … | bash`).
have_tty() { { : < /dev/tty; } 2>/dev/null; }

# run CMD...: execute, or just print under --dry-run.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi
}

# prompt VAR "question" "default": ask on the terminal, or use the default when
# non-interactive (--yes). INTERACTIVE is resolved once in main().
prompt() {
  local __var="$1" __q="$2" __def="$3" __ans
  if [ "$INTERACTIVE" -eq 0 ]; then printf -v "$__var" '%s' "$__def"; return; fi
  read -r -p "$__q [$__def]: " __ans < /dev/tty || true
  printf -v "$__var" '%s' "${__ans:-$__def}"
}

# reqval "$@": ensure the current flag ($1) has a value ($2) following it.
reqval() { [ "$#" -ge 2 ] || { err "missing value for $1"; exit 2; }; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --toolchain-root) reqval "$@"; TOOLCHAIN_ROOT="$2"; TOOLCHAIN_ROOT_SET=1; shift 2;;
      --venv) reqval "$@"; VENV_DIR="$2"; shift 2;;
      --python) reqval "$@"; PYTHON_VERSION="$2"; shift 2;;
      --bin-dir) reqval "$@"; BIN_DIR="$2"; BIN_DIR_SET=1; shift 2;;
      --config) reqval "$@"; CONFIG_PATH="$2"; CONFIG_PATH_SET=1; shift 2;;
      --projects-dir) reqval "$@"; PROJECTS_DIR="$2"; PROJECTS_DIR_SET=1; shift 2;;
      --r3-repo) reqval "$@"; R3_REPO="$2"; R3_REPO_SET=1; shift 2;;
      --clone-proto) reqval "$@"; CLONE_PROTO="$2"; CLONE_PROTO_SET=1; shift 2;;
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
      --import-context) IMPORT_CONTEXT="yes"; shift;;
      --no-import-context) IMPORT_CONTEXT="no"; shift;;
      --context-claude-md) reqval "$@"; CONTEXT_CLAUDE_MD="$2"; shift 2;;
      --feedback) INSTALL_FEEDBACK="yes"; shift;;
      --no-feedback) INSTALL_FEEDBACK="no"; shift;;
      --yes|-y) ASSUME_YES=1; shift;;
      --dry-run) DRY_RUN=1; shift;;
      --no-update) NO_UPDATE=1; shift;;
      --no-relocate) NO_RELOCATE=1; shift;;
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
  if [ "$INTERACTIVE" -eq 1 ]; then
    info "Configure the install (press Enter to accept each [default]):"
  fi
  # A setting given explicitly on the command line is not re-asked.
  [ "$CLONE_PROTO_SET" -eq 1 ]    || prompt CLONE_PROTO    "  git clone protocol (ssh/https)" "$CLONE_PROTO"
  [ "$TOOLCHAIN_ROOT_SET" -eq 1 ] || prompt TOOLCHAIN_ROOT "  toolchain root (r3+foreman clones and the venv live here)" "$TOOLCHAIN_ROOT"
  [ "$BIN_DIR_SET" -eq 1 ]        || prompt BIN_DIR        "  bin dir for wrappers (must be on PATH)" "${BIN_DIR:-$(_default_bindir)}"
  [ "$PROJECTS_DIR_SET" -eq 1 ]   || prompt PROJECTS_DIR   "  projects dir (written as the pathmap base root)" "$PROJECTS_DIR"
  [ "$R3_REPO_SET" -eq 1 ]        || prompt R3_REPO        "  R3_REPOSITORY (job repository) location" "$R3_REPO"
  [ "$CONFIG_PATH_SET" -eq 1 ]    || prompt CONFIG_PATH    "  xr3 config file path" "$CONFIG_PATH"
  # SLURM: ask only when not already decided by flags, and only interactively.
  if [ "$INTERACTIVE" -eq 1 ] && [ "$NO_SLURM" -eq 0 ] && [ "${#SLURM_HEADNODES[@]}" -eq 0 ]; then
    local hn=""; read -r -p "  SLURM head node for xr3-slurm (blank = no SLURM): " hn < /dev/tty || true
    if [ -n "$hn" ]; then SLURM_HEADNODES=("$hn"); else NO_SLURM=1; fi
  fi
  # Skill decision (resolve "prompt" -> yes/no now, so it happens before any relocate).
  if [ "$INSTALL_SKILL" = "prompt" ]; then
    if [ "$INTERACTIVE" -eq 1 ]; then
      local a=""; read -r -p "  install the r3 agent skill for claude/codex? (yes/no) [yes]: " a < /dev/tty || true
      case "${a:-yes}" in y|Y|yes|YES) INSTALL_SKILL=yes;; *) INSTALL_SKILL=no;; esac
    else
      INSTALL_SKILL=yes
    fi
  fi
  # Context-import decision (resolve "prompt" -> yes/no now, before any relocate).
  # Non-interactive default is "no": phase_agent_context still prints the import line,
  # but doesn't edit a CLAUDE.md unless the user explicitly asked (--import-context).
  if [ "$IMPORT_CONTEXT" = "prompt" ]; then
    if [ "$INTERACTIVE" -eq 1 ]; then
      local c=""; read -r -p "  add the research-workflow context import to a CLAUDE.md? (yes/no) [yes]: " c < /dev/tty || true
      case "${c:-yes}" in y|Y|yes|YES) IMPORT_CONTEXT=yes;; *) IMPORT_CONTEXT=no;; esac
      [ "$IMPORT_CONTEXT" = "yes" ] && prompt CONTEXT_CLAUDE_MD "    target CLAUDE.md" "$CONTEXT_CLAUDE_MD"
    else
      IMPORT_CONTEXT=no
    fi
  fi
  # Feedback-observer decision (resolve "prompt" -> yes/no now; opt-out, default yes).
  if [ "$INSTALL_FEEDBACK" = "prompt" ]; then
    if [ "$INTERACTIVE" -eq 1 ]; then
      local fb=""; read -r -p "  install the r3-feedback observer? (local-only notes you can choose to share) (yes/no) [yes]: " fb < /dev/tty || true
      case "${fb:-yes}" in y|Y|yes|YES) INSTALL_FEEDBACK=yes;; *) INSTALL_FEEDBACK=no;; esac
    else
      INSTALL_FEEDBACK=yes
    fi
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
    # foreman's upstream (mtangemann) is private; foreman-ai-builder-camp is a PUBLIC
    # mirror of its dev branch so colleagues can install without access. Override with --foreman-remote.
    [ "$CLONE_PROTO" = "https" ] && FOREMAN_REMOTE="https://$host/matthias-k/foreman-ai-builder-camp.git" || FOREMAN_REMOTE="git@$host:matthias-k/foreman-ai-builder-camp.git"
  fi
}

# ---- phase stubs (replaced by later tasks) ----
phase_preflight() {
  info "preflight: checking prerequisites"
  local missing=0
  local tools="git"
  [ "$CLONE_PROTO" = "ssh" ] && tools="git ssh"
  for tool in $tools; do
    command -v "$tool" >/dev/null 2>&1 || { err "missing required tool: $tool"; missing=1; }
  done
  [ "$missing" -eq 1 ] && { err "install the missing tools and re-run"; exit 1; }

  if [ "$CLONE_PROTO" = "ssh" ]; then
    # ssh -T git@github.com exits 1 on success (no shell); grep for the greeting.
    if ssh -T -o BatchMode=yes -o ConnectTimeout=8 git@github.com 2>&1 | grep -qi "successfully authenticated"; then
      info "github ssh access ok"
    else
      warn "github ssh auth not confirmed; private repo clones may fail."
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

  # node/npm build foreman's web UI stylesheet (Tailwind -> static/output.css, which is
  # gitignored, so a fresh clone has none). Without it foreman runs but renders unstyled.
  # We don't auto-install node (unlike uv): it's a heavier toolchain and often user-managed
  # (nvm) on HPC. Missing npm -> make the user confirm skipping, defaulting to abort.
  if command -v npm >/dev/null 2>&1; then
    info "npm: $(command -v npm) ($(npm -v 2>/dev/null))"
  else
    BUILD_FRONTEND=0
    warn "npm not found — cannot build foreman's web UI stylesheet (static/output.css)."
    warn "foreman will still run, but its pages render UNSTYLED until the CSS is built."
    warn "install Node.js/npm (e.g. via nvm: https://github.com/nvm-sh/nvm) and re-run to fix."
    if [ "$INTERACTIVE" -eq 0 ]; then
      warn "continuing without the foreman frontend build (--yes); re-run once npm is available."
    else
      local ans=""; read -r -p "Continue without building foreman's UI styling? (yes = skip, no = abort to install npm first) [no]: " ans < /dev/tty || true
      case "${ans:-no}" in y|Y|yes|YES) warn "skipping foreman frontend build at your request.";; *) err "aborted — install npm, then re-run install.sh."; exit 1;; esac
    fi
  fi
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
# phase_foreman_frontend: build foreman's web UI (npm deps + Tailwind CSS). Mirrors
# foreman's own Makefile `install` target so the two don't drift. output.css is gitignored,
# so this must run on every fresh install for the UI to be styled.
phase_foreman_frontend() {
  local static_dir="$TOOLCHAIN_ROOT/foreman/foreman/static"
  if [ "$BUILD_FRONTEND" -eq 0 ]; then
    info "foreman frontend: skipped (npm unavailable); UI stays unstyled until built"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] cd %s && npm install && npx tailwindcss -i input.css -o output.css\n' "$static_dir"
    return
  fi
  if [ ! -d "$static_dir" ]; then
    warn "foreman frontend: $static_dir not found (foreman clone missing?); skipping"
    EXIT_CODE=1; return
  fi
  info "foreman frontend: npm install + Tailwind build ($static_dir)"
  run bash -c "cd \"$static_dir\" && npm install" \
    || { err "foreman frontend: npm install failed in $static_dir"; EXIT_CODE=1; return; }
  run bash -c "cd \"$static_dir\" && npx tailwindcss -i input.css -o output.css" \
    || { err "foreman frontend: Tailwind CSS build failed in $static_dir"; EXIT_CODE=1; return; }
  info "foreman frontend built: $static_dir/output.css"
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
# link_agent_skill ROOT SKILLS_DIR SRC NAME: symlink a skill dir into an agent's skills dir.
# Skips when the agent isn't installed (ROOT absent); otherwise creates SKILLS_DIR if needed, so
# the link lands even on an agent that hasn't populated its skills dir yet. Both Claude Code
# (~/.claude/skills) and Codex (~/.codex/skills) load Anthropic-format SKILL.md skills this way.
link_agent_skill() {
  local root="$1" sdir="$2" src="$3" name="$4"
  [ -d "$root" ] || { info "skill: $root absent (agent not installed); skipping $name"; return; }
  run mkdir -p "$sdir" || { warn "skill: cannot create $sdir; skipping $name"; return; }
  if [ -e "$sdir/$name" ] && [ ! -L "$sdir/$name" ]; then
    warn "skill: $sdir/$name exists and is not a symlink; skipping"; return
  fi
  run ln -sfn "$src" "$sdir/$name" && info "skill linked -> $sdir/$name" \
    || warn "could not link $name into $sdir"
}
phase_skill() {
  # INSTALL_SKILL is resolved to yes/no in interactive_config (or by a flag).
  [ "$INSTALL_SKILL" = "yes" ] || { info "skill install: skipped"; return; }
  local src="$REPO_DIR/skills/r3"
  case "$SKILL_TARGET" in
    claude) link_agent_skill "$HOME/.claude" "$HOME/.claude/skills" "$src" r3;;
    codex)  link_agent_skill "$HOME/.codex"  "$HOME/.codex/skills"  "$src" r3;;
    all|*)  link_agent_skill "$HOME/.claude" "$HOME/.claude/skills" "$src" r3
            link_agent_skill "$HOME/.codex"  "$HOME/.codex/skills"  "$src" r3;;
  esac
}
# phase_agent_context: point agents at the workflow. Always prints the @import line; wires it in
# only when opted in (interactive yes, or --import-context). Claude: an @import in the configured
# CLAUDE.md. Codex: AGENTS.md is the global-guidance analog but doesn't do @-imports, so we write a
# prose pointer by path. Each is written per --skill-target, and Codex only when ~/.codex exists.
phase_agent_context() {
  local ctx="$REPO_DIR/agent-context.md" line
  line="@$ctx"
  printf '\n'
  info "Agent discovery — add this to a CLAUDE.md (Claude) / AGENTS.md (Codex) so sessions auto-follow the workflow:"
  printf '  %s\n' "$line"
  info "(in ~/.claude/CLAUDE.md the @import loads with no approval prompt; a project CLAUDE.md prompts once — check with /context)"
  [ "$IMPORT_CONTEXT" = "yes" ] || return 0   # print-only; explicit 0 so set -e doesn't abort main

  # Claude Code: @import into the configured CLAUDE.md.
  if [ "$SKILL_TARGET" = "all" ] || [ "$SKILL_TARGET" = "claude" ]; then
    local target="${CONTEXT_CLAUDE_MD/#\~/$HOME}"
    if [ "$DRY_RUN" -eq 1 ]; then
      info "(dry-run) would add the workflow import to $target"
    elif [ -f "$target" ] && grep -qF "agent-context.md" "$target" 2>/dev/null; then
      info "context import already present in $target; leaving it"
    elif mkdir -p "$(dirname "$target")" 2>/dev/null \
         && printf '\n# r3 research workflow — maintained in r3-tooling\n%s\n' "$line" >> "$target"; then
      info "added the context import to $target"
    else
      warn "could not write $target"
    fi
  fi

  # Codex: AGENTS.md (global guidance). Prose pointer by path; only if Codex is installed.
  if { [ "$SKILL_TARGET" = "all" ] || [ "$SKILL_TARGET" = "codex" ]; } && [ -d "$HOME/.codex" ]; then
    local agents_md="$HOME/.codex/AGENTS.md"
    if [ "$DRY_RUN" -eq 1 ]; then
      info "(dry-run) would add the workflow pointer to $agents_md"
    elif [ -f "$agents_md" ] && grep -qF "agent-context.md" "$agents_md" 2>/dev/null; then
      info "context pointer already present in $agents_md; leaving it"
    elif printf '\n# r3 research workflow — maintained in r3-tooling\nBefore computational research work, read and follow the r3 research workflow: %s (and the RESEARCH_WORKFLOW.md it points to).\n' "$ctx" >> "$agents_md"; then
      info "added the workflow pointer to $agents_md"
    else
      warn "could not write $agents_md"
    fi
  fi
}
# phase_feedback: install the r3-feedback observer (opt-out, default on). Two parts:
#   presence   — symlink feedback/skill into each selected agent's skills dir (native discovery);
#   activation — a session-start pointer in each agent's always-loaded guidance file
#                (CLAUDE.md for Claude, AGENTS.md for Codex). Activation is load-bearing: a passive
#                observer isn't triggered by prompt-matching, so the pointer — which references the
#                SKILL.md by path — is what actually runs it, even where the skills subsystem is off.
phase_feedback() {
  [ "$INSTALL_FEEDBACK" = "yes" ] || { info "r3-feedback observer: skipped"; return 0; }
  local src="$REPO_DIR/feedback/skill" skillmd="$REPO_DIR/feedback/skill/SKILL.md"
  [ -f "$skillmd" ] || { warn "r3-feedback: $skillmd missing; skipping"; return 0; }

  local act="At the START of every session, read and follow the r3-feedback observer skill at ${skillmd}: silently watch for friction / corrections / steering with the r3 toolchain and append observations to its local log. Observe in the background only — never interrupt or override the user's task, and explicit user instructions always take precedence."

  # activation: idempotently append a session-start block to an agent guidance file.
  _fb_activate() { # GUIDANCE_FILE
    local f="$1"
    if [ "$DRY_RUN" -eq 1 ]; then info "(dry-run) would add the r3-feedback activation to $f"; return 0; fi
    if [ -f "$f" ] && grep -qF "r3-feedback observer skill" "$f" 2>/dev/null; then
      info "r3-feedback activation already present in $f; leaving it"; return 0
    fi
    mkdir -p "$(dirname "$f")" 2>/dev/null || { warn "r3-feedback: cannot create dir for $f"; return 0; }
    if printf '\n# r3-feedback observer — maintained in r3-tooling (delete this block to disable)\n%s\n' "$act" >> "$f"; then
      info "r3-feedback activation added to $f"
    else
      warn "r3-feedback: could not write $f"
    fi
  }

  case "$SKILL_TARGET" in
    claude)
      link_agent_skill "$HOME/.claude" "$HOME/.claude/skills" "$src" r3-feedback
      _fb_activate "$HOME/.claude/CLAUDE.md"
      ;;
    codex)
      link_agent_skill "$HOME/.codex" "$HOME/.codex/skills" "$src" r3-feedback
      if [ -d "$HOME/.codex" ]; then _fb_activate "$HOME/.codex/AGENTS.md"; else info "r3-feedback: ~/.codex absent; skipping Codex activation"; fi
      ;;
    all|*)
      link_agent_skill "$HOME/.claude" "$HOME/.claude/skills" "$src" r3-feedback
      link_agent_skill "$HOME/.codex"  "$HOME/.codex/skills"  "$src" r3-feedback
      _fb_activate "$HOME/.claude/CLAUDE.md"
      if [ -d "$HOME/.codex" ]; then _fb_activate "$HOME/.codex/AGENTS.md"; else info "r3-feedback: ~/.codex absent; skipping Codex activation"; fi
      ;;
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
    # foreman UI stylesheet: warn (don't fail) if it wasn't built — foreman still runs.
    local css="$TOOLCHAIN_ROOT/foreman/foreman/static/output.css"
    if [ "$BUILD_FRONTEND" -eq 1 ]; then
      [ -s "$css" ] && info "foreman stylesheet present: $css" \
        || warn "foreman stylesheet missing ($css); UI will be unstyled. Re-run install, or 'make install' in the foreman clone."
    fi
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
  case "$INSTALL_SKILL" in
    yes) f+="$(printf ' --install-skill --skill-target %q' "$SKILL_TARGET")";;
    no)  f+=" --no-install-skill";;
  esac
  case "$IMPORT_CONTEXT" in
    yes) f+="$(printf ' --import-context --context-claude-md %q' "$CONTEXT_CLAUDE_MD")";;
    no)  f+=" --no-import-context";;
  esac
  case "$INSTALL_FEEDBACK" in
    yes) f+=" --feedback";;
    no)  f+=" --no-feedback";;
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

# relocate_if_needed: ensure we run from the single canonical clone at
# <toolchain-root>/r3-tooling. If launched from another clone, create/refresh the
# canonical one and re-exec it non-interactively with the settings just gathered —
# so wrappers, the skill symlink and update.sh all reference one stable location.
relocate_if_needed() {
  [ "$NO_RELOCATE" = "1" ] && return
  local canon="$TOOLCHAIN_ROOT/r3-tooling"
  local canon_abs; canon_abs="$(cd "$canon" 2>/dev/null && pwd || echo "$canon")"
  [ "$REPO_DIR" = "$canon_abs" ] && return   # already canonical

  info "canonical r3-tooling clone: $canon"
  if [ "$DRY_RUN" -eq 1 ]; then
    info "(dry-run) would ensure that clone and re-run from it; previewing in place"
    return
  fi
  if [ ! -d "$canon/.git" ]; then
    local origin branch
    origin="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
    branch="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
    [ -n "$origin" ] || { err "cannot determine r3-tooling origin to create the canonical clone at $canon"; exit 1; }
    mkdir -p "$TOOLCHAIN_ROOT" || { err "cannot create toolchain root $TOOLCHAIN_ROOT"; exit 1; }
    info "cloning r3-tooling ($branch) -> $canon"
    git clone --branch "$branch" "$origin" "$canon" || { err "failed to clone canonical r3-tooling from $origin"; exit 1; }
  elif [ -z "$(cd "$canon" && git status --porcelain)" ]; then
    git -C "$canon" pull --ff-only || warn "could not fast-forward $canon; using it as-is"
  else
    warn "$canon has local changes; using it as-is"
  fi
  info "re-running the installer from the canonical clone"
  local flags; flags="$(_update_flags)"
  # $flags is %q-quoted content we generated; eval re-parses it safely.
  eval "exec env R3_NO_RELOCATE=1 $(printf '%q' "$canon/install.sh") $flags"
}

main() {
  parse_args "$@"
  # Resolve interactivity once: prompt on the terminal, or use defaults under --yes.
  # No terminal and no --yes is an error — accepting all defaults must be deliberate.
  if [ "$ASSUME_YES" -eq 1 ]; then
    INTERACTIVE=0
  elif have_tty; then
    INTERACTIVE=1
  else
    err "no terminal available for prompts; re-run in a terminal, or pass --yes to accept defaults/flags."
    exit 2
  fi
  interactive_config
  resolve_defaults
  info "r3 toolchain installer (dry-run=$DRY_RUN)"
  info "toolchain-root=$TOOLCHAIN_ROOT venv=$VENV_DIR bin=$BIN_DIR config=$CONFIG_PATH"
  local slurm_desc="none"
  [ "$NO_SLURM" -eq 1 ] || slurm_desc="${SLURM_HEADNODES[*]:-<empty>}"
  info "projects=$PROJECTS_DIR r3-repo=$R3_REPO clone-proto=$CLONE_PROTO slurm=$slurm_desc"
  if [ "$INTERACTIVE" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    local go=""; read -r -p "Proceed with these settings? [yes]: " go < /dev/tty || true
    case "${go:-yes}" in y|Y|yes|YES) ;; *) info "aborted."; exit 0;; esac
  fi
  relocate_if_needed
  phase_preflight
  phase_clones
  phase_venv
  phase_foreman_frontend
  phase_wrappers
  phase_config
  phase_skill
  phase_verify
  phase_agent_context
  phase_feedback
  print_update_command
  [ "$EXIT_CODE" -eq 0 ] && info "done." || warn "finished with errors (see above)."
  exit "$EXIT_CODE"
}

main "$@"
