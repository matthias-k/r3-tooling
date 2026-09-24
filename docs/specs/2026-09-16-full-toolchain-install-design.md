# Full r3-toolchain install — design spec

- **Date:** 2026-09-16
- **Status:** approved design; ready for implementation plan
- **Repo:** `r3-tooling`
- **Related:** `SETUP.md` (superseded/rewritten by this), `extensions/xr3/xr3pathmap.py`,
  `extensions/xr3/xr3.example.yaml`, `extensions/CONTRACT.md`, `ROADMAP.md`

## 1. Motivation

Today `SETUP.md` documents only the `xr3`/`xr3-slurm` CLI setup and assumes `r3` and
`foreman` are already installed. A colleague standing up the toolchain from scratch has no
single document, and every step is manual. We want:

1. **One document** that covers the *entire* toolchain — `r3`, the `xr3`/`xr3-slurm`
   extensions, and `foreman` (the r3 web GUI) — from nothing to verified.
2. **One script** (`install.sh`) that performs that setup with sensible, overridable
   defaults, and that **doubles as an updater**: re-running it (ideally the same saved
   fully-flagged command) brings every tool up to date.
3. The **small `xr3` change** that makes a good, portable default config expressible: a
   *base root* (a `pathmap.roots` entry with no `prefix`) plus `~`/env-var expansion.

## 2. Scope

Three coupled deliverables, one spec:

- **Part A — `xr3` pathmap "base root" support** (§4): the code change.
- **Part B — `install.sh`** (§5): the automation.
- **Part C — `SETUP.md` rewrite** (§6): the full-toolchain guide.

Plus doc touch-ups: `extensions/xr3/xr3.example.yaml`, `extensions/CONTRACT.md`,
`README.md`/`ROADMAP.md` pointers.

### Non-goals

- No changes to `r3` core or `foreman` (the foreman `diskcache` dependency gap was already
  fixed upstream — plain `pip install -e foreman` now pulls it).
- No "unified path space with project tags" feature yet — noted as a future extension (§7).
- No Windows support; Linux/HPC + macOS shells only.
- The script does not install system-level prerequisites (a working `git`, `ssh`, and a
  shell); it *checks* for them and, for `uv`, offers to run the official installer.

## 3. Toolchain inventory (what "installed" means)

| Component | Source | Install form | Invoked as |
|---|---|---|---|
| `r3` | `mtangemann/r3` (public) | editable (`pip install -e`) into the venv | `r3` wrapper on `PATH` |
| `xr3` / `xr3-slurm` | this repo (`r3-tooling`) | run from checkout via wrappers | `xr3`, `xr3-slurm` wrappers |
| `foreman` | `mtangemann/foreman` (private for now) | editable into the venv | `foreman` wrapper |
| `r3` skill | this repo (`skills/r3/`) | symlink into agent skill dirs | (agent-facing) |

All Python tools share **one venv** with `r3` and `foreman` editable-installed plus xr3's
runtime deps (`click pyyaml executor tqdm`). Wrappers are tiny files on `PATH` that pin that
venv's interpreter — the existing rationale (functions are invisible to `execvp`/subprocess/
agents; a file on `PATH` is not) carries over unchanged from today's `SETUP.md`.

## 4. Part A — `xr3` pathmap "base root" support

### 4.1 Behavior

A `pathmap.roots` entry with no `prefix` (or `prefix: null`) is a **base root**: a working
directory under it maps to the path relative to that root, with the first sub-directory
becoming the first r3-path segment. Example: root `{path: /home/u/projects}` maps
`/home/u/projects/research/exp/v1` → `research/exp/v1`.

- **Multiple base roots are allowed.** They can share a unified path space; longest-match-
  wins is unchanged, so a specific deeper root still overrides a shallower base root.
- **`~` and `$VARS` are expanded** in each `path` before resolving. Today
  `Path("~/projects").resolve()` yields `<cwd>/~/projects` (silently wrong); we add
  `os.path.expanduser` + `os.path.expandvars` so a hand-edited config and the example file
  can use `~/projects`. (The install script still writes an absolute path.)
- **No leading slash** in the constructed r3 path (already true of `relative_to`; pinned by
  test).
- **`.`-edge errors clearly.** When the working directory *equals* a root, `relative_to`
  yields `.` — not a valid r3 path. Raise `PathmapError` with an actionable message
  ("<dir> is itself a pathmap root; run xr3 from inside a job directory beneath it")
  instead of emitting `.`.

### 4.2 Implementation

In `extensions/xr3/xr3pathmap.py`, `resolve_job_path`:

1. Expand each root path: `Path(os.path.expandvars(os.path.expanduser(entry["path"]))).resolve()`.
2. Existing match/longest-wins logic unchanged.
3. Compute `rel = resolved.relative_to(root)`; if `str(rel) == "."`, raise `PathmapError`
   (new `.`-edge message).
4. `prefix` handling unchanged (falsy/absent → skip).

"Base root" is not a new schema field — just the documented meaning of an entry without
`prefix`. `xr3config.py` DEFAULTS unchanged.

### 4.3 Tests (`extensions/xr3/tests/test_xr3pathmap.py`)

- base root (no prefix) → `research/exp/v1`, no leading slash;
- multiple base roots, longest-match wins;
- `~` expansion and `$VAR` expansion resolve to the intended root;
- job dir == root → raises `PathmapError` with the `.`-edge message;
- existing prefix/override tests still pass.

### 4.4 Docs

- `xr3.example.yaml`: show a base-root example (`- path: ~/projects`) with a comment that a
  prefix-less root maps subpaths directly and that multiple are allowed.
- `extensions/CONTRACT.md`: document base roots + `~`/env expansion in the pathmap section.

## 5. Part B — `install.sh`

Lives at the repo root. Interaction: **prompts + flags**, idempotent, re-run = update.
Every prompt has a 1:1 flag; a fully-flagged (or `--yes`) invocation runs with **zero
prompts**, so a saved command re-runs as an updater.

### 5.1 Defaults & flags

| Flag | Default | Meaning |
|---|---|---|
| `--toolchain-root DIR` | `~/r3-toolchain` | holds sibling clones `r3/`, `foreman/`, and the venv |
| `--venv DIR` | `<toolchain-root>/.venv` | shared uv venv |
| `--python VER` | `3.12` | venv Python (must satisfy r3's `>=3.9,<3.13`) |
| `--bin-dir DIR` | `~/bin`, or `$LUSTREWORK/bin` if that dir exists | where wrappers are written; ensured on `PATH` |
| `--config PATH` | `~/.config/xr3.yaml` | xr3 config location |
| `--projects-dir DIR` | `~/projects` | written as a base root in `pathmap.roots` (absolute) |
| `--r3-repo DIR` | `~/r3_repo` | `R3_REPOSITORY` (created if missing) |
| `--clone-proto ssh\|https` | `ssh` | how default remotes are formed |
| `--r3-remote URL` | `mtangemann/r3` via proto | r3 clone source |
| `--foreman-remote URL` | `mtangemann/foreman` via proto | foreman clone source |
| `--r3-ref REF` / `--foreman-ref REF` | `main` | branch/tag to track |
| `--slurm-headnode HOST` | (none) | repeatable; SSH targets for squeue/sacct |
| `--slurm-submit-host HOST` | first headnode | sbatch SSH target |
| `--no-slurm` | off | omit the `slurm:` config section entirely |
| `--install-skill` / `--no-install-skill` | prompt | symlink `skills/r3` into agent dirs |
| `--skill-target claude\|codex\|all` | `all` (present dirs only) | which agent skill dirs |
| `--yes` | off | accept all defaults; no prompts |
| `--dry-run` | off | print every action; change nothing |
| `--no-update` | off | on a re-run, re-ensure wrappers/config but skip `git pull` |

Flags override prompts; prompts show the default and accept it on empty input.

### 5.2 Phases

1. **Preflight.** Verify `git`, `ssh`; verify `ssh -T git@github.com` reachability when using
   ssh proto (clear message if foreman — still private — is inaccessible). Verify `uv`; if
   missing, offer to run the official installer (skip under `--yes` only if already present,
   else install non-interactively).
2. **Clones.** For `r3` and `foreman` under `<toolchain-root>`: clone if absent; if present,
   update per §5.3.
3. **Venv + installs.** `uv venv --python <ver> <venv>` (create if absent). `uv pip install
   -e <toolchain-root>/r3 -e <toolchain-root>/foreman` and `uv pip install click pyyaml
   executor tqdm` (re-running re-syncs; picks up dependency changes, e.g. foreman's
   `diskcache`).
4. **Wrappers.** (Re)generate `r3`, `xr3`, `xr3-slurm`, `foreman` in `--bin-dir`, each
   `exec <venv>/bin/python <target> "$@"` (`r3` → r3's `cli.py`; `xr3`/`xr3-slurm` → this
   repo's `extensions/.../` entry points; `foreman` → `-m foreman.app` or its console
   script). `chmod +x`. Ensure `--bin-dir` is on `PATH` via an idempotent marker block in
   `~/.bashrc`.
5. **Config.** If `--config` is absent, generate from `xr3.example.yaml` with: a base root
   `pathmap.roots: [{path: <abs projects-dir>}]`, and either the `slurm:` section
   (headnodes/submit host) or, under `--no-slurm`, that section omitted. Also ensure
   `R3_REPOSITORY` is exported (marker block in `~/.bashrc`) and the repo dir exists. If
   `--config` **exists, never clobber it** — leave it untouched and, if the template has
   gained keys, write `<config>.new` beside it and note the diff.
6. **Skill (optional).** For each present agent dir (`~/.claude/skills`, `~/.codex/skills`)
   per `--skill-target`: `ln -sfn <repo>/skills/r3 <dir>/r3`. Skip absent dirs with a note.
7. **Verify.** Run `which r3 xr3 xr3-slurm foreman`, each `--help`, and the
   subprocess-resolves check (`python3 -c "import subprocess; subprocess.run(['xr3','--help'])"`).
   Print a summary: what was installed vs updated vs skipped, and next steps (`source
   ~/.bashrc`; the `foreman` run line `R3_REPOSITORY=<repo> foreman`).

### 5.3 Update semantics (re-run safety)

Re-running is the update path (idempotent). For each managed clone (`r3`, `foreman`, and
`r3-tooling` itself when it is a normal clone):

- `git fetch` then **`git pull --ff-only`** on the tracked ref.
- **Dirty working tree or diverged branch → error for that repo, skip its pull, continue
  the others, exit non-zero at the end.** Never `merge`/`rebase`/`stash` automatically —
  so no merge conflict can occur; the user resolves manually. This is what protects an
  actively-developed `r3-tooling` clone (simply skipped with a note).
- Editable re-install and wrapper regeneration still run (safe/idempotent) so dependency
  and wrapper changes apply even when a pull was skipped.
- `--no-update` skips the `git pull` step entirely (only re-ensures env/wrappers/config).

`--dry-run` prints each action (clone/pull/venv/install/write/symlink) and mutates nothing.

### 5.4 Bootstrap note

The script ships **inside** `r3-tooling`, so the user clones `r3-tooling` first, then runs
`./install.sh`. (A one-line curl bootstrap is out of scope; the README documents the
two-step clone-then-run.)

## 6. Part C — `SETUP.md` rewrite

Restructure into a full-toolchain guide:

0. **Quickstart** — clone `r3-tooling`, run `./install.sh` (mention `--yes`, `--dry-run`,
   and that a saved flagged command re-runs as an updater).
1. **What gets installed** — the mental model from §3 (env → clones → editable installs →
   wrappers → config → foreman → skill) and the toolchain-root layout.
2. **Manual setup** — today's content, expanded to also cover installing `r3` and
   `foreman` (for people who prefer not to run the script). Keep the "wrapper scripts, not
   shell functions" rationale and the `$LUSTREWORK/bin` cluster caveat.
3. **Config** — the base-root/`pathmap` section, including `~`/env expansion and the
   slurm/`--no-slurm` choice.
4. **Verify** — the `which` + `--help` + subprocess checks.
5. **What the tools assume** — pointer to `extensions/CONTRACT.md` (unchanged).

`README.md`/`ROADMAP.md`: repoint the setup links; note the toolchain installer under Done.

## 7. Future extensions (out of scope here)

- **Unified path space with project tags** — instead of (or beside) per-project separation,
  optionally inject a project tag derived from the base-root subpath. Deferred until a
  concrete need; base roots already give a unified path space.
- **Making `foreman` / `r3-tooling` public** — pending discussion with upstream; once
  public, the ssh-access preflight for foreman relaxes to https by default.
- **curl one-line bootstrap** — if colleagues want zero manual clone step.
- **Remote-foreman launcher (print-only).** A *laptop-side* helper that SSHes to the HPC
  cluster, starts `foreman` there against the cluster's `R3_REPOSITORY`, and forwards the
  port to `localhost` so the user opens the GUI in their local browser. It runs on a
  different machine than the installer, so `install.sh` cannot install it — instead, at the
  end of a run it **generates and prints the script for copy-paste**, pre-filled with the
  values it already knows (submit/head host, `R3_REPOSITORY`, the `foreman` wrapper path or
  venv, and a default local↔remote port, all overridable). Shape: `ssh -L
  <lport>:localhost:<rport> <host> 'R3_REPOSITORY=<repo> <foreman> --port <rport>'` (or a
  small heredoc wrapper), then open `http://localhost:<lport>`. Deferred here; captured so
  it lands with (or just after) the installer.

## 8. Testing & verification

- Part A: unit tests (§4.3) — pure, fast, fit existing `extensions/xr3/tests/`.
- Part B: `--dry-run` output is the primary checkable surface; plus a real smoke run into a
  throwaway `--toolchain-root` (temp dir), then a second run to exercise the update path
  (including a deliberately dirtied clone → expect skip+non-zero exit).
- Part C: manual read-through; the quickstart command matches the script's actual flags.
