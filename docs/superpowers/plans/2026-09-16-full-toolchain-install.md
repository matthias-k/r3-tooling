# Full r3-toolchain Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a one-command installer + full-toolchain setup guide for r3 + xr3/xr3-slurm + foreman, plus the small `xr3` pathmap change (base roots + `~`/env expansion) that makes a portable default config expressible.

**Architecture:** Three coupled parts. (A) A pure-Python change to `xr3pathmap.resolve_job_path` (base-root semantics, tilde/env expansion, `.`-edge error), TDD. (B) A single idempotent `install.sh` (bash, prompts+flags, re-run = update) that stands up a shared `uv` venv with `r3`/`foreman` editable-installed, generates PATH wrappers, writes an `xr3.yaml` with a base root, optionally installs the `r3` skill for claude/codex, and prints a copy-paste remote-foreman launcher. (C) A rewrite of `SETUP.md` into a full-toolchain guide plus README/ROADMAP pointers.

**Tech Stack:** Python 3.12 (r3 requires `>=3.9,<3.13`), `uv` (venv + pip), bash, `pytest` for the pathmap tests, git.

**Working location:** All paths are relative to the `r3-tooling` repo root: `/mnt/lustre/work/bethge/mkuemmerer31/projects/research/tools/r3-tooling`. Run git commands from there.

**Spec:** `docs/specs/2026-09-16-full-toolchain-install-design.md`.

---

## File Structure

**Part A — pathmap change**
- Modify: `extensions/xr3/xr3pathmap.py` — add tilde/env expansion + `.`-edge error to `resolve_job_path`.
- Modify: `extensions/xr3/tests/test_xr3pathmap.py` — new tests for base roots, expansion, `.`-edge.
- Modify: `extensions/xr3/xr3.example.yaml` — document base roots.
- Modify: `extensions/CONTRACT.md` — document base roots + expansion in the pathmap section.

**Part B — installer**
- Create: `install.sh` (repo root) — the whole installer, one file, function-per-phase.

**Part C — docs**
- Rewrite: `SETUP.md` — full-toolchain guide.
- Modify: `README.md`, `ROADMAP.md` — repoint setup links; mark installer done.

The installer is one file (a shell script is naturally a single unit; phases are functions). The pathmap change stays in the existing `xr3pathmap.py` — no new module.

---

## PART A — xr3 pathmap base roots

### Task A1: Base-root support in `resolve_job_path`

**Files:**
- Modify: `extensions/xr3/xr3pathmap.py`
- Test: `extensions/xr3/tests/test_xr3pathmap.py`

- [ ] **Step 1: Write the failing tests**

Append to `extensions/xr3/tests/test_xr3pathmap.py`:

```python
def test_base_root_no_prefix_has_no_leading_slash(tmp_path):
    # A prefix-less "base root": subpath maps directly, first dir is first segment.
    root = tmp_path / "projects"
    (root / "research" / "exp" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(root)}]}}
    result = xr3pathmap.resolve_job_path(root / "research" / "exp" / "v1", cfg)
    assert result == "research/exp/v1"
    assert not result.startswith("/")


def test_multiple_base_roots_longest_match_wins(tmp_path):
    outer = tmp_path / "projects"
    inner = outer / "research"
    (inner / "exp" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(outer)}, {"path": str(inner)}]}}
    # inner is the longer match -> strips inner, not outer
    assert xr3pathmap.resolve_job_path(inner / "exp" / "v1", cfg) == "exp/v1"


def test_tilde_expansion_in_root(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    (tmp_path / "projects" / "research" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": "~/projects"}]}}
    assert xr3pathmap.resolve_job_path(
        tmp_path / "projects" / "research" / "v1", cfg
    ) == "research/v1"


def test_envvar_expansion_in_root(tmp_path, monkeypatch):
    monkeypatch.setenv("MYBASE", str(tmp_path / "projects"))
    (tmp_path / "projects" / "research" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": "$MYBASE"}]}}
    assert xr3pathmap.resolve_job_path(
        tmp_path / "projects" / "research" / "v1", cfg
    ) == "research/v1"


def test_job_dir_equals_root_raises(tmp_path):
    root = tmp_path / "projects"
    root.mkdir()
    cfg = {"pathmap": {"roots": [{"path": str(root)}]}}
    with pytest.raises(xr3pathmap.PathmapError) as excinfo:
        xr3pathmap.resolve_job_path(root, cfg)
    assert "pathmap root" in str(excinfo.value).lower()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd extensions/xr3 && python -m pytest tests/test_xr3pathmap.py -v`
Expected: the five new tests FAIL — `test_tilde_expansion_in_root`/`test_envvar_expansion_in_root` with a `PathmapError` ("No pathmap root matches"), `test_job_dir_equals_root_raises` because `.` is returned instead of raising. (The base-root/longest-match tests may already pass — that is fine, they pin behavior.)

- [ ] **Step 3: Implement the change**

In `extensions/xr3/xr3pathmap.py`, add `import os` under `from __future__ import annotations`, and replace the body of `resolve_job_path` (from `resolved = ...` to the end) with:

```python
    resolved = Path(fs_path).resolve()
    roots = (config.get("pathmap") or {}).get("roots") or []

    def _expand(p: str) -> Path:
        return Path(os.path.expanduser(os.path.expandvars(str(p)))).resolve()

    matches = []
    for entry in roots:
        root = _expand(entry["path"])
        if resolved == root or root in resolved.parents:
            matches.append((root, entry))

    if not matches:
        where = config_source or "your xr3 config"
        configured = [str(e["path"]) for e in roots] or "none"
        raise PathmapError(
            f"No pathmap root matches {resolved}.\n"
            f"Add its project root under `pathmap.roots` in {where} "
            f"(see CONTRACT.md). Configured roots: {configured}."
        )

    root, entry = max(matches, key=lambda m: len(str(m[0])))
    rel = resolved.relative_to(root)
    if str(rel) == ".":
        raise PathmapError(
            f"{resolved} is itself a pathmap root, not a job directory. "
            f"Run xr3 from inside a job directory beneath it."
        )
    prefix = entry.get("prefix")
    if prefix:
        rel = Path(prefix) / rel
    return str(rel)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd extensions/xr3 && python -m pytest tests/test_xr3pathmap.py -v`
Expected: all tests PASS (new five plus the pre-existing ones).

- [ ] **Step 5: Commit**

```bash
cd /mnt/lustre/work/bethge/mkuemmerer31/projects/research/tools/r3-tooling
git add extensions/xr3/xr3pathmap.py extensions/xr3/tests/test_xr3pathmap.py
git commit -m "feat(xr3): base-root pathmap support (~/env expansion, .-edge error)"
```

---

### Task A2: Document base roots in example config and CONTRACT

**Files:**
- Modify: `extensions/xr3/xr3.example.yaml`
- Modify: `extensions/CONTRACT.md`

- [ ] **Step 1: Update the example config**

Replace the `pathmap:` block in `extensions/xr3/xr3.example.yaml` (lines describing `roots`) with:

```yaml
pathmap:
  # Working directories under these roots map to r3 logical paths by stripping
  # the root prefix. `history`, `diff`, and `check`'s path asserts need this.
  # `~` and $VARS are expanded.
  roots:
    # A "base root" (no `prefix`): subpaths map directly, so the first
    # sub-directory becomes the first r3-path segment. One base root over your
    # projects dir covers every project under it; you can list several.
    - path: ~/projects
    # A named root with an explicit prefix prepended to the derived path:
    # - path: /abs/path/to/another/project
    #   prefix: some-prefix
```

- [ ] **Step 2: Update CONTRACT.md**

In `extensions/CONTRACT.md`, find the pathmap section and add a sentence documenting base roots and expansion. Run to locate it:

Run: `grep -n "pathmap\|prefix\|roots" extensions/CONTRACT.md`

Then, in that section, add:

```markdown
A `pathmap.roots` entry with no `prefix` is a **base root**: subpaths map directly
(the first sub-directory becomes the first r3-path segment), so a single base root over
your projects directory covers every project beneath it, and multiple base roots share
one path space. `~` and `$VARS` in `path` are expanded. Running xr3 in a directory that
*is* a root (no sub-path) is an error.
```

- [ ] **Step 3: Verify docs render sanely**

Run: `grep -n "base root" extensions/CONTRACT.md extensions/xr3/xr3.example.yaml`
Expected: matches in both files.

- [ ] **Step 4: Commit**

```bash
git add extensions/xr3/xr3.example.yaml extensions/CONTRACT.md
git commit -m "docs(xr3): document base roots + ~/env expansion in pathmap"
```

---

## PART B — install.sh

The installer is built as one file. Task B1 lays down the scaffold with **stub** phase functions so the script always parses and runs in `--dry-run`; Tasks B2–B8 replace one stub each with its real implementation. Verify every task with `bash -n install.sh` (syntax) plus a targeted `--dry-run` run.

### Task B1: Scaffold — args, defaults, helpers, stub phases

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Create `install.sh` with the full scaffold**

Create `install.sh` (repo root):

```bash
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
SKILL_TARGET="all"          # all | claude | codex
ASSUME_YES=0
DRY_RUN=0
NO_UPDATE=0

EXIT_CODE=0                 # phases set this to 1 on non-fatal errors (e.g. skipped repo)

usage() {
  sed -n '2,4p' "$0"
  cat <<'EOF'

Usage: ./install.sh [flags]

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

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --toolchain-root) TOOLCHAIN_ROOT="$2"; shift 2;;
      --venv) VENV_DIR="$2"; shift 2;;
      --python) PYTHON_VERSION="$2"; shift 2;;
      --bin-dir) BIN_DIR="$2"; shift 2;;
      --config) CONFIG_PATH="$2"; shift 2;;
      --projects-dir) PROJECTS_DIR="$2"; shift 2;;
      --r3-repo) R3_REPO="$2"; shift 2;;
      --clone-proto) CLONE_PROTO="$2"; shift 2;;
      --r3-remote) R3_REMOTE="$2"; shift 2;;
      --foreman-remote) FOREMAN_REMOTE="$2"; shift 2;;
      --r3-ref) R3_REF="$2"; shift 2;;
      --foreman-ref) FOREMAN_REF="$2"; shift 2;;
      --slurm-headnode) SLURM_HEADNODES+=("$2"); shift 2;;
      --slurm-submit-host) SLURM_SUBMIT_HOST="$2"; shift 2;;
      --no-slurm) NO_SLURM=1; shift;;
      --install-skill) INSTALL_SKILL="yes"; shift;;
      --no-install-skill) INSTALL_SKILL="no"; shift;;
      --skill-target) SKILL_TARGET="$2"; shift 2;;
      --yes|-y) ASSUME_YES=1; shift;;
      --dry-run) DRY_RUN=1; shift;;
      --no-update) NO_UPDATE=1; shift;;
      -h|--help) usage; exit 0;;
      *) err "unknown flag: $1"; usage; exit 2;;
    esac
  done
}

resolve_defaults() {
  [ -n "$VENV_DIR" ] || VENV_DIR="$TOOLCHAIN_ROOT/.venv"
  if [ -z "$BIN_DIR" ]; then
    if [ -n "${LUSTREWORK:-}" ] && [ -d "${LUSTREWORK:-}/bin" ]; then BIN_DIR="$LUSTREWORK/bin"; else BIN_DIR="$HOME/bin"; fi
  fi
  local host="github.com"
  if [ -z "$R3_REMOTE" ]; then
    [ "$CLONE_PROTO" = "https" ] && R3_REMOTE="https://$host/mtangemann/r3.git" || R3_REMOTE="git@$host:mtangemann/r3.git"
  fi
  if [ -z "$FOREMAN_REMOTE" ]; then
    [ "$CLONE_PROTO" = "https" ] && FOREMAN_REMOTE="https://$host/mtangemann/foreman.git" || FOREMAN_REMOTE="git@$host:mtangemann/foreman.git"
  fi
}

# ---- phase stubs (replaced by Tasks B2-B8) ----
phase_preflight() { info "preflight (stub)"; }
phase_clones()    { info "clones (stub)"; }
phase_venv()      { info "venv (stub)"; }
phase_wrappers()  { info "wrappers (stub)"; }
phase_config()    { info "config (stub)"; }
phase_skill()     { info "skill (stub)"; }
phase_verify()    { info "verify (stub)"; }

main() {
  parse_args "$@"
  resolve_defaults
  info "r3 toolchain installer (dry-run=$DRY_RUN)"
  info "toolchain-root=$TOOLCHAIN_ROOT venv=$VENV_DIR bin=$BIN_DIR config=$CONFIG_PATH"
  phase_preflight
  phase_clones
  phase_venv
  phase_wrappers
  phase_config
  phase_skill
  phase_verify
  [ "$EXIT_CODE" -eq 0 ] && info "done." || warn "finished with errors (see above)."
  exit "$EXIT_CODE"
}

main "$@"
```

- [ ] **Step 2: Make it executable and syntax-check**

Run: `chmod +x install.sh && bash -n install.sh && ./install.sh --dry-run --yes`
Expected: prints the header/config lines and each `(stub)` phase line; exits 0; changes nothing.

- [ ] **Step 3: Check help and flag parsing**

Run: `./install.sh --help && ./install.sh --dry-run --yes --toolchain-root /tmp/tc --no-slurm --bin-dir /tmp/bin`
Expected: help text prints; second run shows `toolchain-root=/tmp/tc ... bin=/tmp/bin`.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat(install): install.sh scaffold (args, defaults, dry-run, stub phases)"
```

---

### Task B2: Preflight phase

**Files:**
- Modify: `install.sh` — replace `phase_preflight` stub.

- [ ] **Step 1: Replace the `phase_preflight` stub**

Replace the `phase_preflight() { ... }` line with:

```bash
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
```

- [ ] **Step 2: Syntax-check and dry-run**

Run: `bash -n install.sh && ./install.sh --dry-run --yes`
Expected: preflight prints tool checks and (if uv present) its path; no `(stub)` for preflight; still reaches later stubs; exits 0.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): preflight (git/ssh/uv checks, uv auto-install offer)"
```

---

### Task B3: Clones phase + update semantics

**Files:**
- Modify: `install.sh` — replace `phase_clones` stub; add `update_repo` helper.

- [ ] **Step 1: Replace the `phase_clones` stub and add the helper**

Replace `phase_clones() { ... }` with:

```bash
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
  run git -C "$dir" fetch --quiet origin
  # ff-only; diverged -> error, do not merge.
  if ! run git -C "$dir" pull --ff-only origin "$ref"; then
    err "$label could not fast-forward (diverged from origin/$ref); skipping. Resolve manually in $dir."
    EXIT_CODE=1
  fi
}

phase_clones() {
  info "clones: r3, foreman under $TOOLCHAIN_ROOT"
  run mkdir -p "$TOOLCHAIN_ROOT"
  clone_or_update "$TOOLCHAIN_ROOT/r3" "$R3_REMOTE" "$R3_REF" "r3"
  clone_or_update "$TOOLCHAIN_ROOT/foreman" "$FOREMAN_REMOTE" "$FOREMAN_REF" "foreman"
}
```

- [ ] **Step 2: Syntax-check and dry-run**

Run: `bash -n install.sh && ./install.sh --dry-run --yes --toolchain-root /tmp/tc-dry`
Expected: prints `[dry-run] mkdir -p /tmp/tc-dry`, then `[dry-run] git clone --branch main ... r3` and `... foreman`; no real clone happens.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): clone/ff-only-update phase (dirty/diverged -> skip+error)"
```

---

### Task B4: Venv + editable installs

**Files:**
- Modify: `install.sh` — replace `phase_venv` stub.

- [ ] **Step 1: Replace the `phase_venv` stub**

Replace `phase_venv() { ... }` with:

```bash
phase_venv() {
  info "venv: $VENV_DIR (python $PYTHON_VERSION)"
  [ -d "$VENV_DIR" ] || run uv venv --python "$PYTHON_VERSION" "$VENV_DIR"
  info "installing r3 + foreman (editable) + xr3 deps"
  run uv pip install --python "$VENV_DIR/bin/python" \
    -e "$TOOLCHAIN_ROOT/r3" -e "$TOOLCHAIN_ROOT/foreman"
  run uv pip install --python "$VENV_DIR/bin/python" click pyyaml executor tqdm
}
```

- [ ] **Step 2: Syntax-check and dry-run**

Run: `bash -n install.sh && ./install.sh --dry-run --yes --toolchain-root /tmp/tc --venv /tmp/tc/.venv`
Expected: prints `[dry-run] uv venv --python 3.12 /tmp/tc/.venv` and two `[dry-run] uv pip install ...` lines.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): uv venv + editable r3/foreman + xr3 deps"
```

---

### Task B5: Wrappers + PATH

**Files:**
- Modify: `install.sh` — replace `phase_wrappers` stub; add `write_wrapper` and `ensure_bashrc_block`.

- [ ] **Step 1: Replace the `phase_wrappers` stub and add helpers**

Replace `phase_wrappers() { ... }` with:

```bash
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
  run mkdir -p "$BIN_DIR"
  local py="$VENV_DIR/bin/python"
  write_wrapper r3        "exec \"$VENV_DIR/bin/r3\" \"\$@\""
  write_wrapper foreman   "exec \"$VENV_DIR/bin/foreman\" \"\$@\""
  write_wrapper xr3       "exec \"$py\" \"$REPO_DIR/extensions/xr3/xr3\" \"\$@\""
  write_wrapper xr3-slurm "exec \"$py\" \"$REPO_DIR/extensions/xr3-slurm/xr3-slurm\" \"\$@\""
  ensure_bashrc_block "r3-toolchain PATH" "export PATH=\"$BIN_DIR:\$PATH\""
  info "added $BIN_DIR to PATH in ~/.bashrc (run: source ~/.bashrc)"
}
```

- [ ] **Step 2: Syntax-check and real run into a temp bin (safe: only writes files + a bashrc block)**

Run: `bash -n install.sh && ./install.sh --dry-run --yes --bin-dir /tmp/tcbin --venv /tmp/tc/.venv`
Expected: `[dry-run] write wrapper /tmp/tcbin/r3` (and foreman/xr3/xr3-slurm), plus `[dry-run] ensure ~/.bashrc block "r3-toolchain PATH"`.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): generate r3/foreman/xr3/xr3-slurm wrappers + PATH block"
```

---

### Task B6: Config generation

**Files:**
- Modify: `install.sh` — replace `phase_config` stub.

- [ ] **Step 1: Replace the `phase_config` stub**

Replace `phase_config() { ... }` with:

```bash
phase_config() {
  info "config: $CONFIG_PATH"
  local abs_projects; abs_projects="$(cd "$PROJECTS_DIR" 2>/dev/null && pwd || echo "$PROJECTS_DIR")"
  # ensure R3_REPOSITORY dir + export.
  run mkdir -p "$R3_REPO"
  ensure_bashrc_block "r3-toolchain R3_REPOSITORY" "export R3_REPOSITORY=\"$R3_REPO\""

  if [ -f "$CONFIG_PATH" ]; then
    info "config exists; leaving it untouched (writing $CONFIG_PATH.new for reference)"
    local target="$CONFIG_PATH.new"
  else
    local target="$CONFIG_PATH"
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
  mkdir -p "$(dirname "$target")"
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
```

- [ ] **Step 2: Syntax-check and dry-run (both slurm variants)**

Run: `bash -n install.sh && ./install.sh --dry-run --yes --config /tmp/xr3.yaml --projects-dir "$HOME" --slurm-headnode galvani && ./install.sh --dry-run --yes --config /tmp/xr3.yaml --no-slurm`
Expected: first shows `write /tmp/xr3.yaml (base root: <home>; slurm: included)`; second shows `slurm: omitted`.

- [ ] **Step 3: Real config write + assert contents**

Run:
```bash
./install.sh --yes --config /tmp/xr3-real.yaml --projects-dir "$HOME" --no-slurm \
  --toolchain-root /tmp/skip --venv /tmp/skip/.venv --bin-dir /tmp/skipbin --no-update 2>/dev/null || true
grep -A3 "pathmap:" /tmp/xr3-real.yaml
```
Expected: a `roots:` list with `- path: <your home>`; no `slurm:` section. (Other phases may error on the throwaway dirs — that is fine; we are only asserting the config file here.)

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat(install): generate xr3.yaml (base root, slurm/--no-slurm, no-clobber)"
```

---

### Task B7: Skill install

**Files:**
- Modify: `install.sh` — replace `phase_skill` stub.

- [ ] **Step 1: Replace the `phase_skill` stub**

Replace `phase_skill() { ... }` with:

```bash
phase_skill() {
  local decision="$INSTALL_SKILL"
  if [ "$decision" = "prompt" ]; then
    local ans; prompt ans "Install the r3 agent skill (symlink into claude/codex)?" "yes"
    [ "$ans" = "yes" ] && decision="yes" || decision="no"
  fi
  [ "$decision" = "yes" ] || { info "skill install: skipped"; return; }

  local src="$REPO_DIR/skills/r3"
  link_skill() { # AGENT_DIR
    local d="$1"
    [ -d "$d" ] || { info "skill: $d absent, skipping"; return; }
    run ln -sfn "$src" "$d/r3"
    info "skill linked -> $d/r3"
  }
  case "$SKILL_TARGET" in
    claude) link_skill "$HOME/.claude/skills";;
    codex)  link_skill "$HOME/.codex/skills";;
    all|*)  link_skill "$HOME/.claude/skills"; link_skill "$HOME/.codex/skills";;
  esac
}
```

- [ ] **Step 2: Syntax-check and dry-run**

Run: `bash -n install.sh && ./install.sh --dry-run --yes --install-skill`
Expected: for each present agent dir, `[dry-run] ln -sfn <repo>/skills/r3 <dir>/r3`; absent dirs report "absent, skipping".

- [ ] **Step 3: Verify `--no-install-skill` and `--skill-target`**

Run: `./install.sh --dry-run --yes --no-install-skill && ./install.sh --dry-run --yes --install-skill --skill-target codex`
Expected: first prints "skill install: skipped"; second only touches `~/.codex/skills`.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat(install): optional r3 skill install for claude + codex"
```

---

### Task B8: Verify phase + remote-foreman launcher print

**Files:**
- Modify: `install.sh` — replace `phase_verify` stub.

- [ ] **Step 1: Replace the `phase_verify` stub**

Replace `phase_verify() { ... }` with:

```bash
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
    printf '  [dry-run] would run: which r3 xr3 xr3-slurm foreman; each --help\n'
  else
    export PATH="$BIN_DIR:$PATH"
    local ok=1
    for t in r3 xr3 xr3-slurm foreman; do
      if command -v "$t" >/dev/null 2>&1; then info "found $t -> $(command -v "$t")"; else err "missing on PATH: $t"; ok=0; fi
    done
    for t in xr3 xr3-slurm; do "$t" --help >/dev/null 2>&1 && info "$t --help ok" || { err "$t --help failed"; ok=0; }; done
    python3 -c "import subprocess,sys; sys.exit(subprocess.run(['xr3','--help'],stdout=subprocess.DEVNULL).returncode)" \
      && info "xr3 resolves from a subprocess" || { err "xr3 not resolvable from subprocess"; ok=0; }
    [ "$ok" -eq 1 ] || EXIT_CODE=1
  fi
  print_remote_foreman
  info "next: run 'source ~/.bashrc' to pick up PATH + R3_REPOSITORY"
}
```

- [ ] **Step 2: Syntax-check and dry-run**

Run: `bash -n install.sh && ./install.sh --dry-run --yes --slurm-headnode galvani`
Expected: verify dry-run line; then the remote-foreman block with `ssh -L 8080:localhost:8080 galvani ...`.

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): verify phase + copy-paste remote-foreman launcher"
```

---

### Task B9: End-to-end smoke test (real run) + update path

**Files:** none (verification only).

- [ ] **Step 1: Full real install into a throwaway toolchain root**

Run:
```bash
TMP=$(mktemp -d)
./install.sh --yes \
  --toolchain-root "$TMP/tc" --venv "$TMP/tc/.venv" --bin-dir "$TMP/bin" \
  --config "$TMP/xr3.yaml" --projects-dir "$HOME" --r3-repo "$TMP/r3repo" \
  --clone-proto https --no-slurm --no-install-skill
echo "exit=$?"
```
Expected: clones r3 (public https) + foreman (https; may fail if still private — note it), creates venv, installs, writes wrappers + config; exit 0 if both clones succeed. If foreman clone fails (private), expect a clear error and `exit=1` — re-run with `--clone-proto ssh` if you have access.

- [ ] **Step 2: Verify the installed tools work**

Run: `PATH="$TMP/bin:$PATH" xr3 --help && PATH="$TMP/bin:$PATH" r3 --help`
Expected: both print help.

- [ ] **Step 3: Exercise the update path (idempotent re-run + dirty-skip)**

Run:
```bash
# second run = update; should ff-only pull (no-op) and re-sync
./install.sh --yes --toolchain-root "$TMP/tc" --venv "$TMP/tc/.venv" --bin-dir "$TMP/bin" \
  --config "$TMP/xr3.yaml" --projects-dir "$HOME" --clone-proto https --no-slurm --no-install-skill
# now dirty a clone and confirm it is skipped with non-zero exit
touch "$TMP/tc/r3/DIRTY"
./install.sh --yes --toolchain-root "$TMP/tc" --venv "$TMP/tc/.venv" --bin-dir "$TMP/bin" \
  --config "$TMP/xr3.yaml" --projects-dir "$HOME" --clone-proto https --no-slurm --no-install-skill; echo "exit=$?"
```
Expected: first re-run exits 0 (config untouched → `$TMP/xr3.yaml.new` written); second run prints "r3 has local changes; skipping update" and `exit=1`.

- [ ] **Step 4: Clean up**

Run: `rm -rf "$TMP"`

- [ ] **Step 5: Commit (if any fixes were needed)**

```bash
git add -A && git commit -m "test(install): smoke + update-path fixes" || echo "no changes"
```

---

## PART C — docs

### Task C1: Rewrite SETUP.md as the full-toolchain guide

**Files:**
- Rewrite: `SETUP.md`

- [ ] **Step 1: Replace `SETUP.md` with the full-toolchain guide**

Overwrite `SETUP.md` with the following structure, filling each section from the spec §6 and the real `install.sh` flags (keep the existing "wrapper scripts, not shell functions" rationale and the `$LUSTREWORK/bin` cluster caveat verbatim from the current file):

```markdown
# SETUP — installing the full r3 toolchain

Get `r3`, `xr3`, `xr3-slurm`, and `foreman` working from everywhere — one venv, PATH
wrappers, one config. Two ways: the installer (quickest), or manual steps.

## 0. Quickstart — the installer

```bash
git clone <r3-tooling-url> r3-tooling && cd r3-tooling
./install.sh --yes                 # accept all defaults, no prompts
./install.sh --dry-run             # preview every action, change nothing
```

Run `./install.sh --help` for the full flag list. Every prompt has a matching flag, so a
saved fully-flagged command **re-runs as an updater** (it ff-only-pulls each repo, re-syncs
the editable installs, and refreshes wrappers). A clone with local changes or a diverged
branch is skipped with an error (never auto-merged). After a run: `source ~/.bashrc`.

Common flags: `--toolchain-root DIR` (default `~/r3-toolchain`), `--bin-dir DIR`
(default `~/bin`, or `$LUSTREWORK/bin` if present), `--projects-dir DIR` (default
`~/projects`, written as a pathmap base root), `--r3-repo DIR` (default `~/r3_repo`,
`R3_REPOSITORY`), `--slurm-headnode HOST` / `--no-slurm`, `--clone-proto ssh|https`,
`--install-skill`.

## 1. What gets installed

- a shared **uv venv** with `r3` and `foreman` **editable-installed** (+ xr3's deps);
- **wrapper scripts** on `PATH` (`r3`, `xr3`, `xr3-slurm`, `foreman`) that pin that venv;
- an **`~/.config/xr3.yaml`** with a base root over your projects dir (+ optional slurm);
- optionally the **`r3` agent skill** symlinked into `~/.claude/skills` / `~/.codex/skills`.

Clones live under the toolchain root: `<toolchain-root>/{r3,foreman}`; `r3-tooling` is the
repo you cloned to get here.

## 2. Manual setup

[Expand today's env + PATH-wrapper + config content to also cover cloning and editable-
installing r3 and foreman. Keep section 2's "Why not a ~/.bashrc function?" rationale and
the $LUSTREWORK/bin cluster caveat. r3 requires Python >=3.9,<3.13.]

## 3. Config (pathmap + slurm)

[The base-root explanation + `~`/env expansion; the slurm section vs --no-slurm. Point at
extensions/xr3/xr3.example.yaml and CONTRACT.md.]

## 4. Verify

which r3 xr3 xr3-slurm foreman   # -> your bin dir
xr3 --help ; xr3-slurm --help
python3 -c "import subprocess; subprocess.run(['xr3','--help'])"

## 5. What the tools assume about your jobs

See extensions/CONTRACT.md — the single source of truth.

## Remote foreman (optional)

Run foreman on the cluster and tunnel it to your laptop's browser; `install.sh` prints a
pre-filled `ssh -L ...` command at the end of a run.
```

Fill the `[...]` sections with real prose (do not leave brackets). Preserve the current
file's wrapper rationale and cluster caveat wording.

- [ ] **Step 2: Sanity-check links and structure**

Run: `grep -n "install.sh\|CONTRACT.md\|xr3.example.yaml\|LUSTREWORK/bin" SETUP.md`
Expected: the quickstart references `install.sh`; config section references the example + CONTRACT; the manual section keeps the `$LUSTREWORK/bin` caveat.

- [ ] **Step 3: Commit**

```bash
git add SETUP.md
git commit -m "docs: rewrite SETUP.md as full-toolchain guide (installer + manual)"
```

---

### Task C2: Repoint README/ROADMAP

**Files:**
- Modify: `README.md`, `ROADMAP.md`

- [ ] **Step 1: Update README setup pointer**

In `README.md`, find the SETUP reference:

Run: `grep -n "SETUP.md\|install" README.md`

Update the sentence that points at SETUP to mention the one-command installer, e.g. replace the "To install the CLI tools ... see SETUP.md" line with:

```markdown
To install the **full toolchain** (r3 + xr3/xr3-slurm + foreman) — one command or manual
steps — see **[`SETUP.md`](SETUP.md)** (`./install.sh --yes`).
```

- [ ] **Step 2: Mark the installer done in ROADMAP**

In `ROADMAP.md`, under `## Done`, add:

```markdown
- **Full-toolchain installer** — `install.sh` (uv venv, editable r3+foreman, PATH wrappers,
  base-root config, optional skill install; re-run = update) + `SETUP.md` rewrite + the
  `xr3` base-root pathmap change. See `docs/specs/2026-09-16-full-toolchain-install-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add README.md ROADMAP.md
git commit -m "docs: point README/ROADMAP at the full-toolchain installer"
```

---

## Self-Review notes (for the implementer)

- **Spec coverage:** Part A §4 → Tasks A1–A2; installer §5 (all flags, phases, update
  semantics, skill, remote-foreman) → Tasks B1–B9; SETUP rewrite §6 → C1; README/ROADMAP → C2.
- **Type/name consistency:** phase function names (`phase_preflight/clones/venv/wrappers/
  config/skill/verify`) are fixed in B1 and only *replaced* (not renamed) later; helpers
  `run`/`prompt`/`info`/`warn`/`err`/`ensure_bashrc_block`/`write_wrapper`/`clone_or_update`
  are referenced consistently.
- **Known soft spots to watch during execution:** `EXIT_CODE` propagation through the `run`
  wrapper in B3 (`run git ... pull --ff-only` inside `if !` — confirm the non-zero path
  actually sets `EXIT_CODE=1` on a diverged repo); the `SLURM_HEADNODES[@]` expansion under
  `set -u` when the array is empty (B6/B8 guard with `${arr[@]:-}` if needed); foreman clone
  requiring ssh while r3 is public. Fix inline if a dry-run or smoke run disagrees with the
  "Expected" lines.
```
