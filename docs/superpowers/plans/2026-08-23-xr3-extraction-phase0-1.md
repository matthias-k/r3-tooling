# xr3 Extraction — Phase 0 (baseline) + Phase 1 (prune) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get `xr3` and `run_job_locally` verbatim into `r3-tooling/extensions/`, then remove all dead code and superseded commands — with every removal proven behavior-preserving against a golden baseline.

**Architecture:** This is a *relocation + deletion* increment, not new-feature work. So the discipline is **characterize-then-verify-unchanged**, not red-green TDD: capture a golden baseline of the kept read-only commands right after the verbatim copy, then re-run it after each deletion and assert byte-identical output. Deletions are content-anchored (by symbol/definition) and done **bottom-of-file first** so line numbers above stay stable within a task. Genuinely new logic (config parsing, pathmap-from-config) arrives in the *next* plan and gets real TDD there.

**Tech Stack:** Python 3 + Click CLI (single file), `r3` package, `executor`, `pyyaml`, `tqdm`; git; bash for the golden harness.

**Spec:** `docs/specs/2026-08-22-xr3-extraction-design.md` (Phases 0–1 of §11).

---

## Prerequisites (read once)

- **Repo:** all work happens in `tools/r3-tooling` (a git repo), on `main` — this repo's established convention (specs + skill work commit to `main`). Paths below are relative to the `r3-tooling` root unless absolute.
- **Source of truth:** the current script lives at `../scripts/xr3` and `../scripts/run_job_locally` (i.e. `research/tools/scripts/`). The `sattachx`/`sattachx_wait` copies are already staged in `tmp/`.
- **Running `xr3` needs the `r3_lustre` env** — the base Python lacks `r3`/`executor`. `xr3` has no shebang; the working invocation (from the `xr3()` bash function in `~/.bashrc`) is the `r3_lustre` conda Python with `PYTHONPATH` pointed at the `r3` source. Export it as `XR3` so the harness and smoke steps use it:
  ```bash
  export R3_REPOSITORY=/mnt/lustre/work/bethge/mkuemmerer31/r3_repo
  export XR3="env PYTHONPATH=/mnt/lustre/work/bethge/mkuemmerer31/r3 \
    /mnt/lustre/work/bethge/mkuemmerer31/miniconda3/envs/r3_lustre/bin/python \
    $(git -C . rev-parse --show-toplevel)/extensions/xr3/xr3"
  ```
  Every `python extensions/xr3/xr3 …` in the smoke steps below should instead be run as `$XR3 …` (the plan's smoke commands are written with `python extensions/xr3/xr3` for readability — substitute `$XR3`). The golden harness reads `$XR3` directly.
- **Characterization target** (verified to have committed history; `files`=7 lines, `history`=1 version, `find`=this job's versions, `check`=`All good.`). The `find` glob is scoped to the one job so the baseline is deterministic (not repo-wide, which would drift if any job is committed mid-refactor):
  ```bash
  export XR3_JOBDIR=/mnt/lustre/work/bethge/mkuemmerer31/projects/research/research/experiments/2026-08-04_DAEMONS-in-pysaliency
  export XR3_PATH_GLOB='research/experiments/2026-08-04_DAEMONS-in-pysaliency*'
  ```

---

## File Structure (this plan's scope)

- Create: `extensions/xr3/xr3` — the CLI, copied verbatim from `../scripts/xr3` (Phase 0), then edited down (Phase 1).
- Create: `extensions/scripts/run_job_locally` — copied verbatim from `../scripts/run_job_locally`.
- Move: `tmp/sattachx`, `tmp/sattachx_wait` → `raw-material/sattachx`, `raw-material/sattachx_wait` (absorption source for a later plan).
- Create: `dev/xr3_golden.sh` — the golden characterization harness (dev-only; not shipped/imported by the tools).
- Create (gitignored): `dev/golden/baseline/`, `dev/golden/current/` — captured command outputs.

No module split happens here — `extensions/xr3/xr3` stays a single file through Phase 1. The `xr3/` subdir is created now so the split in the next plan is an in-place carve.

---

## Phase 0 — Baseline

### Task 0.1: Copy `xr3` + `run_job_locally` verbatim into `extensions/`

**Files:**
- Create: `extensions/xr3/xr3`
- Create: `extensions/scripts/run_job_locally`

- [ ] **Step 1: Create target dirs and copy verbatim**

```bash
cd "$(git -C . rev-parse --show-toplevel)"   # r3-tooling root
mkdir -p extensions/xr3 extensions/scripts
cp ../scripts/xr3 extensions/xr3/xr3
cp ../scripts/run_job_locally extensions/scripts/run_job_locally
chmod +x extensions/scripts/run_job_locally    # was executable; xr3 keeps its mode too
```

- [ ] **Step 2: Verify the copies are byte-identical to the source**

Run:
```bash
diff ../scripts/xr3 extensions/xr3/xr3 && diff ../scripts/run_job_locally extensions/scripts/run_job_locally && echo "IDENTICAL"
```
Expected: prints `IDENTICAL`, no diff output.

- [ ] **Step 3: Commit the verbatim baseline**

```bash
git add extensions/xr3/xr3 extensions/scripts/run_job_locally
git commit -m "chore(xr3): vendor xr3 + run_job_locally verbatim (baseline)

Verbatim copy from research/tools/scripts/ so all later cleanup is a
reviewable diff inside r3-tooling. No changes to content."
```
Expected: one commit, 2 files added.

### Task 0.2: Move `sattachx` sources into `raw-material/`

**Files:**
- Move: `tmp/sattachx` → `raw-material/sattachx`
- Move: `tmp/sattachx_wait` → `raw-material/sattachx_wait`

- [ ] **Step 1: Move with git**

```bash
git mv tmp/sattachx raw-material/sattachx 2>/dev/null || { mv tmp/sattachx raw-material/sattachx; git add raw-material/sattachx; }
git mv tmp/sattachx_wait raw-material/sattachx_wait 2>/dev/null || { mv tmp/sattachx_wait raw-material/sattachx_wait; git add raw-material/sattachx_wait; }
rmdir tmp 2>/dev/null || true
```
(The `||` fallbacks handle the case where `tmp/` files are untracked — `git mv` fails on untracked, so we plain-move and `git add`.)

- [ ] **Step 2: Verify placement**

Run: `ls raw-material/sattachx raw-material/sattachx_wait && test ! -d tmp && echo OK`
Expected: both files listed, `tmp/` gone, prints `OK`.

- [ ] **Step 3: Commit**

```bash
git add -A raw-material tmp
git commit -m "chore(xr3): stage sattachx/sattachx_wait as raw-material

Absorption source for xr3-slurm watch (a later plan). Not wired in yet."
```

### Task 0.3: Build the golden characterization harness and capture the baseline

**Files:**
- Create: `dev/xr3_golden.sh`
- Create: `dev/.gitignore`

- [ ] **Step 1: Write the harness**

Create `dev/xr3_golden.sh`:
```bash
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
```

- [ ] **Step 2: Gitignore the captured outputs**

Create `dev/.gitignore`:
```
golden/
```

- [ ] **Step 3: Make executable and capture the baseline NOW (against the verbatim copy)**

Run:
```bash
chmod +x dev/xr3_golden.sh
dev/xr3_golden.sh baseline
ls dev/golden/baseline/
```
Expected: prints `baseline captured`; directory contains `files.txt history.txt find.txt check.txt help.txt`. Open `history.txt` and `find.txt` and confirm they contain real rows (not an error/empty) — if empty, your `XR3_JOBDIR`/`XR3_PATH_GLOB` are wrong; fix and re-capture before proceeding.

- [ ] **Step 4: Commit the harness**

```bash
git add dev/xr3_golden.sh dev/.gitignore
git commit -m "test(xr3): golden characterization harness for the extraction

Captures kept read-only commands (files/history/find/check) so deletion
refactors can be proven behavior-preserving. Outputs gitignored."
```

---

## Phase 1 — Remove dead code + prune superseded commands

**Discipline for every task below:** re-grep the anchors first (line numbers below are orientation from the baseline, which equals the current script); delete the named definitions **in full**, bottom-of-file first; then run the smoke + golden checks; then commit. All edits are in `extensions/xr3/xr3`.

### Task 1.1: Remove the `bugmark` feature

Removes the deprecated `bugmark` command and its three helpers (replaced by notebook-based bug marking). The bug-tag *checking* in `check`/`dev-checkout` is untouched.

**Files:**
- Modify: `extensions/xr3/xr3` (delete `bugmark` command + `_build_dependents_graph` + `_trace_bug_in_graph` + `_trace_bug`; orientation: the contiguous tail block ~lines 1992–2121, immediately before `def make_external_command`).

- [ ] **Step 1: Confirm anchors**

Run:
```bash
cd extensions/xr3
grep -n 'def bugmark\|def _build_dependents_graph\|def _trace_bug_in_graph\|def _trace_bug\|def make_external_command' xr3
```
Expected: five hits; `bugmark`'s decorators (`@cli.command()` / `@click.argument` / `@click.option`) sit just above `def bugmark`, and `def make_external_command` is the first definition *after* the block to delete.

- [ ] **Step 2: Delete the block**

Delete from the `@cli.command()` decorator that begins the `bugmark` command through the end of `_trace_bug` — i.e. everything from the bugmark decorator block up to (but not including) `def make_external_command`. Verify nothing else references the removed names:
```bash
grep -n 'bugmark\|_build_dependents_graph\|_trace_bug_in_graph\|_trace_bug' xr3 || echo "no references remain"
```
Expected: `no references remain`.

- [ ] **Step 3: Smoke — module still imports, command is gone, kept commands intact**

Run (from repo root):
```bash
python extensions/xr3/xr3 --help >/dev/null && echo "imports OK"
python extensions/xr3/xr3 bugmark --help 2>&1 | grep -qi 'no such command\|Error' && echo "bugmark gone"
python extensions/xr3/xr3 check --help >/dev/null && echo "check OK"
```
Expected: `imports OK`, `bugmark gone`, `check OK`.

- [ ] **Step 4: Golden — kept read-only commands unchanged**

Run: `dev/xr3_golden.sh check`
Expected: `ALL DATA COMMANDS IDENTICAL` (exit 0). The `help.txt` informational diff shows only `bugmark` removed.

- [ ] **Step 5: Commit**

```bash
git add extensions/xr3/xr3
git commit -m "refactor(xr3): remove deprecated bugmark command + helpers

Bug marking is done via notebooks now. Bug-tag CHECKING in check/
dev-checkout is unchanged. Golden data commands byte-identical."
```

### Task 1.2: Prune superseded submit/watch wrappers

Removes `submit auto` (superseded by `submit query`) and the `location` wrappers — `submit location` and the `slurm watch-location` group (replaced by shell composition). Their per-invocation flags migrate onto `submit`/`watch` in a later plan (xr3-slurm extraction); nothing here depends on them. `_submit_job` and `_watch` stay (still used by `submit jobs`/`submit query`/`commit --submit` and by `watch`, respectively).

**Files:**
- Modify: `extensions/xr3/xr3` (delete `submit_auto` ~1700–1760; `submit_location` command ~1554–1588; the `slurm` group + `watch_location` ~1486–1504).

- [ ] **Step 1: Confirm anchors and non-referencing**

Run:
```bash
cd extensions/xr3
grep -n "def submit_auto\|name='auto'\|def submit_location\|name='location'\|def slurm\|def watch_location\|def _submit_job\|def _watch\|def watch\b" xr3
grep -n '_submit_job\|_watch(' xr3   # confirm _submit_job/_watch have OTHER callers that remain
```
Expected: `_submit_job` is still called by `submit_jobs`, `submit_query`, and `commit`; `_watch` is still called by `watch`. Only the three wrappers get removed.

- [ ] **Step 2: Delete the three wrappers (bottom-first: submit_auto, then submit_location, then the slurm group)**

Delete `submit_auto` (its `@submit.command(name='auto')` decorators through end of function), `submit_location` (its `@submit.command(name='location'...)` decorators through end of function), and the entire `slurm` group block: the `@cli.group()` + `def slurm` and the `@slurm.command()` + `def watch_location`. Then confirm:
```bash
grep -n "name='auto'\|name='location'\|def slurm\|watch_location" xr3 || echo "wrappers gone"
python -c "import ast; ast.parse(open('xr3').read())" && echo "parse OK"
```
Expected: `wrappers gone`, `parse OK`.

- [ ] **Step 3: Smoke — remaining submit tree intact, removed ones gone**

Run (from repo root):
```bash
python extensions/xr3/xr3 submit --help 2>&1 | grep -qi 'jobs' && echo "submit jobs kept"
python extensions/xr3/xr3 submit --help 2>&1 | grep -qi 'auto' && echo "AUTO STILL PRESENT (BAD)" || echo "submit auto gone"
python extensions/xr3/xr3 submit location --help 2>&1 | grep -qi 'no such command\|Error' && echo "submit location gone"
python extensions/xr3/xr3 slurm --help 2>&1 | grep -qi 'no such command\|Error' && echo "slurm group gone"
python extensions/xr3/xr3 watch --help >/dev/null && echo "watch (top-level) kept"
```
Expected: `submit jobs kept`, `submit auto gone`, `submit location gone`, `slurm group gone`, `watch (top-level) kept`.

- [ ] **Step 4: Golden — kept read-only commands unchanged**

Run: `dev/xr3_golden.sh check`
Expected: `ALL DATA COMMANDS IDENTICAL`.

- [ ] **Step 5: Commit**

```bash
git add extensions/xr3/xr3
git commit -m "refactor(xr3): prune submit auto + location wrappers

submit auto is superseded by submit query; submit location and slurm
watch-location are replaced by composition (xr3-slurm submit/watch
\$(xr3 history --latest --id .)). _submit_job/_watch retained for their
remaining callers. Golden data commands byte-identical."
```

### Task 1.3: Remove dead code and the now-dead `joblib` import

Removes symbols confirmed unreferenced: `_get_origin`, the `FORBIDDEN_TAG_PREFIXES` constant, the commented-out dead blocks, and the `joblib` import (whose only use was the commented `_history` block).

**Files:**
- Modify: `extensions/xr3/xr3` (delete `from joblib import Parallel, delayed` line 17; `FORBIDDEN_TAG_PREFIXES` ~31–33; `_get_origin` ~300–302; commented blocks: `_history` parallel ~317–323, commented `--nodelist`/`--exclude` sbatch options ~1653–1659 (keep the LIVE `"--exclude": "galvani-cn221,galvani-cn240"`), `status` per-cluster loop ~1928–1937).

> **Deferred to Phase 4:** the `if False:` block in `_submit_job` (~1691) is NOT removed here — it's an `if False: … else: <live code>`, so cleaning it means collapsing the `else` and dedenting the live line (not a pure deletion). That whole sattach section is rewritten when `sattachx` is absorbed in Phase 4, so it's handled there.

- [ ] **Step 1: Confirm each anchor is truly unreferenced**

Run:
```bash
cd extensions/xr3
grep -n 'FORBIDDEN_TAG_PREFIXES' xr3          # expect ONLY the definition
grep -n '_get_origin' xr3                     # expect ONLY the def + commented usage
grep -n 'joblib\|Parallel\|delayed' xr3       # expect import + commented usage only
```
Expected: none of these appear in live (non-comment) code except their own definitions/imports.

- [ ] **Step 2: Delete the dead symbols and comment blocks (bottom-first)**

Delete, from bottom of file up: the `status` per-cluster commented loop, the commented sbatch `--nodelist`/`--exclude` option lines (keeping the LIVE `"--exclude": "galvani-cn221,galvani-cn240"`), the commented parallel block in `_history`, `_get_origin`, `FORBIDDEN_TAG_PREFIXES`, and finally the `from joblib import Parallel, delayed` import. (The `if False:` block is deferred to Phase 4 — see note above.) Then:
```bash
python -c "import ast; ast.parse(open('xr3').read())" && echo "parse OK"
grep -n 'joblib\|FORBIDDEN_TAG_PREFIXES\|_get_origin' xr3 || echo "all gone"
```
Expected: `parse OK`, `all gone`.

- [ ] **Step 3: Smoke — imports fine without joblib, all kept commands help**

Run (from repo root):
```bash
python extensions/xr3/xr3 --help >/dev/null && echo "imports OK (no joblib)"
for c in find files history diff check commit dev-checkout dev-cleanup git-check submit watch status; do
  python extensions/xr3/xr3 $c --help >/dev/null 2>&1 && echo "  $c OK" || echo "  $c FAIL"
done
```
Expected: `imports OK (no joblib)` and every listed command prints `OK`.

- [ ] **Step 4: Golden — kept read-only commands unchanged**

Run: `dev/xr3_golden.sh check`
Expected: `ALL DATA COMMANDS IDENTICAL`.

- [ ] **Step 5: Commit**

```bash
git add extensions/xr3/xr3
git commit -m "refactor(xr3): drop dead code (_get_origin, FORBIDDEN_TAG_PREFIXES,
commented blocks) and now-unused joblib import

All confirmed unreferenced. FORBIDDEN_TAG_PREFIXES returns as
config-driven blocker tags in the next (config) plan. Golden data
commands byte-identical."
```

---

## Phase 1 exit check

- [ ] **Full regression pass**

Run: `dev/xr3_golden.sh check`
Expected: `ALL DATA COMMANDS IDENTICAL`. Review the `help.txt` informational diff and confirm the ONLY command-tree changes vs baseline are the intended removals: `bugmark`, `submit auto`, `submit location`, the `slurm` group.

- [ ] **Confirm the git history reads as intended**

Run: `git log --oneline -8`
Expected (newest first): the three Phase-1 refactor commits, the harness commit, the sattachx move, the verbatim baseline. Each Phase-1 diff should be pure deletion.

---

## Next plans (not in this document)

Written against the real post-Phase-1 state:
- **Phase 2 — Externalize config** (`config.py`, pathmap-from-config incl. the `combined-gaze-datasets` per-root prefix, configurable blocker tags for BOTH `check` and `dev-checkout`, `IGNORED_*` → config, graceful gating). *This is where real TDD begins* — the new pure-logic modules get unit tests.
- **Phase 3 — Module split** (`core`/`pathmap`/`diff`/`config`/`cli`), `diff` made pathmap-independent, `commit` drops `--submit`, `history` gains `--id`.
- **Phase 4 — Extract `xr3-slurm`** (submit/status/watch), absorb `sattachx`, own the sbatch options, preserve the `submit` per-invocation flags + reconcile local-vs-SSH.
- **Phase 5 — Move `run_job_locally`** (already vendored here; final placement/wiring).
- **Phase 6 — Docs** (`CONTRACT.md`, tool READMEs, signposts, `projects/CLAUDE.md`, `RESEARCH_WORKFLOW.md`).
