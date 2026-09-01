# xr3 Extraction — Phase 3 (lean: history --id, commit drops --submit, pathmap module) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three low-risk, high-value changes: add `history --id` (unblocks Phase 4's composition), drop `commit`'s SLURM tie (`--submit`/`--observe`), and split the pathmap logic into its own module `xr3pathmap.py` (with the error-message tidy the Phase 2 review flagged).

**Architecture:** This is the "lean Phase 3" — the heavy internal file-split (a `diff.py`, `core`/`cli` separation) is **deferred** until after Phase 4 extracts `xr3-slurm` (which removes ~400 lines and is the higher-value structural change; splitting first would move some code twice). Here we only carve `pathmap` out of `xr3config` — a small, clean, unit-tested move — and make two small command changes. The golden harness proves the pathmap move is behavior-preserving; `xr3pathmap` is pure (pathlib only) and unit-tested.

**Tech Stack:** Python, Click, PyYAML, pytest.

**Spec:** `docs/specs/2026-08-22-xr3-extraction-design.md` §6 (`history --id`, `commit` drops `--submit`), §11 phase 3 (module split — partial here, by design). Builds on branch `xr3-extraction` (Phases 0–2 committed).

---

## Prerequisites

- Branch `xr3-extraction` in `/mnt/lustre/work/bethge/mkuemmerer31/projects/research/tools/r3-tooling` (`$REPO`).
- **Interpreters:** `xr3pathmap` unit tests need only stdlib → **base python** (`python -m pytest`). Running `xr3` (smoke/golden) needs the `r3_lustre` env + config. Export:
  ```bash
  export R3_REPOSITORY=/mnt/lustre/work/bethge/mkuemmerer31/r3_repo
  export XR3="env PYTHONPATH=/mnt/lustre/work/bethge/mkuemmerer31/r3 /mnt/lustre/work/bethge/mkuemmerer31/miniconda3/envs/r3_lustre/bin/python $REPO/extensions/xr3/xr3"
  export XR3_JOBDIR=/mnt/lustre/work/bethge/mkuemmerer31/projects/research/research/experiments/2026-08-04_DAEMONS-in-pysaliency
  export XR3_PATH_GLOB='research/experiments/2026-08-04_DAEMONS-in-pysaliency*'
  export XR3_CONFIG=$REPO/dev/xr3.config.local.yaml
  ```
- **Transient Lustre note:** a run may fail with `Input/output error` — retry once or twice.
- The known committed job id for `$XR3_JOBDIR` is `c47aba9d-b2d9-443a-b939-9c377365300f` (its single version) — used to verify `history --id`.

---

## File Structure (this plan's scope)

- Modify: `extensions/xr3/xr3` — add `history --id`; remove `commit`'s `--submit`/`--observe`; import `xr3pathmap` and route `_get_path` through it.
- Create: `extensions/xr3/xr3pathmap.py` — `PathmapError` + `resolve_job_path` (moved out of `xr3config.py`, made standalone, with a `config_source` error param).
- Modify: `extensions/xr3/xr3config.py` — remove `PathmapError` + `resolve_job_path` (now in `xr3pathmap`).
- Create: `extensions/xr3/tests/test_xr3pathmap.py` — the pathmap tests (moved from `test_xr3config.py`) + a `config_source` test.
- Modify: `extensions/xr3/tests/test_xr3config.py` — remove the pathmap tests (keep the 4 `load_config` tests).

---

## Task 3.1: `history --id` (print only the job id)

**Files:**
- Modify: `extensions/xr3/xr3` (the `history` command, ~lines 207–230)

- [ ] **Step 1: Add the `--id` option** — insert after the `--long/--short` option line (currently line 211, `@click.option("--long/--short", "-l", default=False)`):

```python
@click.option("--id", "id_only", is_flag=True, default=False,
              help="Print only the job id (one per line) — composes into xr3-slurm.")
```

- [ ] **Step 2: Update the signature and body** — replace the `def history(...)` signature and body (currently lines 218–230) with:

```python
def history(latest: bool, long: bool, id_only: bool, path: Path, repository_path: Path) -> None:
    results = _history(latest, path, repository_path)
    if id_only:
        for job in results:
            print(job.id)
        return
    # history is scoped to a single metadata.path, so print it once as a header
    # (in --long) rather than repeating it on every row like `find` does.
    if long and results:
        print(results[0].metadata.get("path", ""))
    for job in results:
        if long:
            datetime_str = job.timestamp.strftime(r"%Y-%m-%d %H:%M:%S")
            tags = " ".join(f"#{tag}" for tag in job.metadata.get("tags", []))
            print(f"  {job.id} | {datetime_str} | {tags}")
        else:
            print(job.path)
```

- [ ] **Step 3: Parse check**

Run: `cd extensions/xr3 && python -c "import ast; ast.parse(open('xr3').read())" && echo "parse OK"`
Expected: `parse OK`.

- [ ] **Step 4: Behavioral check — `--id` prints the bare UUID**

Run (from `$REPO`, env exported incl. `XR3_CONFIG`):
```bash
$XR3 history --latest --id "$XR3_JOBDIR"
```
Expected: prints exactly `c47aba9d-b2d9-443a-b939-9c377365300f` (the job's id) and nothing else.

- [ ] **Step 5: Golden — default `history` output unchanged**

Run: `cd $REPO && dev/xr3_golden.sh check`
Expected: `ALL DATA COMMANDS IDENTICAL` (the golden uses `history --long`, which is untouched).

- [ ] **Step 6: Commit**

```bash
git add extensions/xr3/xr3
git commit -m "feat(xr3): history --id prints only the job id

Composes into xr3-slurm: e.g. submit \$(xr3 history --latest --id .).
Default history output unchanged (golden identical)."
```

## Task 3.2: `commit` drops `--submit`/`--observe`

Removes `commit`'s only SLURM tie. Submission becomes composed (Phase 4's `xr3-slurm submit`). `_submit_job` stays — it's still used by `submit jobs`/`submit query`.

**Files:**
- Modify: `extensions/xr3/xr3` (the `commit` command, ~lines 1187–1251)

- [ ] **Step 1: Remove the two options** — delete these two decorator lines (currently 1191–1192):

```python
@click.option('-s', '--submit/--no-submit', default=False)
@click.option('-o', '--observe/--no-observe', default=False, help="Attach to job after submission.")
```

- [ ] **Step 2: Update the signature** — replace (currently line 1200):

```python
def commit(remove_previous, copy_previous_output, exclude_done, submit: bool, observe: bool, check: bool, path, repository_path):
```
with:
```python
def commit(remove_previous, copy_previous_output, exclude_done, check: bool, path, repository_path):
```

- [ ] **Step 3: Remove the trailing submit block** — delete these three lines (currently 1249–1251, the last lines of `commit`):

```python
    if submit:
        print("Submitting job")
        _submit_job(job.path, dry=False, check_existing_jobs=False, restart_failed=False, observe=observe, cluster='galvani')
```

- [ ] **Step 4: Parse + `_submit_job` still present**

Run:
```bash
cd extensions/xr3
python -c "import ast; ast.parse(open('xr3').read())" && echo "parse OK"
grep -n "def _submit_job" xr3 && echo "_submit_job kept"
grep -n "submit: bool\|observe: bool\|--submit/--no-submit" xr3 || echo "commit submit tie gone"
```
Expected: `parse OK`, `_submit_job kept`, `commit submit tie gone`.

- [ ] **Step 5: Smoke — `commit --help` no longer offers `--submit`/`--observe`; `submit jobs` still works**

Run (from `$REPO`):
```bash
$XR3 commit --help 2>&1 | grep -qi -- '--submit' && echo "SUBMIT STILL ON COMMIT (BAD)" || echo "commit --submit gone"
$XR3 commit --help 2>&1 | grep -q -- '--remove-previous' && echo "commit other opts intact"
$XR3 submit jobs --help >/dev/null 2>&1 && echo "submit jobs still OK"
```
Expected: `commit --submit gone`, `commit other opts intact`, `submit jobs still OK`.

- [ ] **Step 6: Golden** (unaffected — golden doesn't run `commit`)

Run: `cd $REPO && dev/xr3_golden.sh check`
Expected: `ALL DATA COMMANDS IDENTICAL`.

- [ ] **Step 7: Commit**

```bash
git add extensions/xr3/xr3
git commit -m "refactor(xr3): commit drops --submit/--observe (SLURM decouple)

Submission is composed now (xr3-slurm submit, Phase 4). _submit_job
stays for submit jobs/query. commit's other options unchanged."
```

## Task 3.3: Split `pathmap` into `xr3pathmap.py` (+ error-source tidy)

Moves `PathmapError` + `resolve_job_path` out of `xr3config.py` into a standalone `xr3pathmap.py`, and threads the real config path into the "no pathmap root" error (the Phase 2 review's advisory).

**Files:**
- Create: `extensions/xr3/xr3pathmap.py`
- Modify: `extensions/xr3/xr3config.py` (remove the moved symbols)
- Create: `extensions/xr3/tests/test_xr3pathmap.py`
- Modify: `extensions/xr3/tests/test_xr3config.py` (drop the moved tests)
- Modify: `extensions/xr3/xr3` (import `xr3pathmap`; route `_get_path` through it)

- [ ] **Step 1: Create `extensions/xr3/xr3pathmap.py`** (standalone; `config_source` param for the error):

```python
"""Working-directory -> r3 logical-path mapping for xr3.

Pure logic (pathlib only) so it is unit-testable without r3/executor/pyyaml.
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional


class PathmapError(Exception):
    """Raised when a working directory cannot be mapped to an r3 path."""


def resolve_job_path(fs_path, config: dict, config_source: Optional[str] = None) -> str:
    """Map a working-directory path to its r3 logical path.

    Finds the `config['pathmap']['roots']` entry containing `fs_path` (the most
    specific / longest root wins), returns the path relative to that root, and
    applies the entry's optional `prefix`. Raises PathmapError with an
    actionable message (naming `config_source`, if given) when no root matches.
    """
    resolved = Path(fs_path).resolve()
    roots = (config.get("pathmap") or {}).get("roots") or []

    matches = []
    for entry in roots:
        root = Path(entry["path"]).resolve()
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
    prefix = entry.get("prefix")
    if prefix:
        rel = Path(prefix) / rel
    return str(rel)
```

- [ ] **Step 2: Remove the moved symbols from `xr3config.py`** — delete the `class PathmapError(Exception): ...` block and the entire `def resolve_job_path(...)` function from `extensions/xr3/xr3config.py`. Keep `DEFAULT_CONFIG_PATH`, `DEFAULTS`, `config_path`, `_deep_merge`, `load_config` (and its imports `os`, `Path`, `Optional`, `yaml`).

Verify:
```bash
cd extensions/xr3
grep -n "resolve_job_path\|PathmapError" xr3config.py || echo "moved out of xr3config"
python -c "import ast; ast.parse(open('xr3config.py').read())" && echo "config parse OK"
python -c "import ast; ast.parse(open('xr3pathmap.py').read())" && echo "pathmap parse OK"
```
Expected: `moved out of xr3config`, both `parse OK`.

- [ ] **Step 3: Create `extensions/xr3/tests/test_xr3pathmap.py`** (the 5 moved tests + a `config_source` test):

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
import xr3pathmap


def test_resolve_job_path_basic(tmp_path):
    root = tmp_path / "proj"
    (root / "exp" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(root)}]}}
    assert xr3pathmap.resolve_job_path(root / "exp" / "v1", cfg) == "exp/v1"


def test_resolve_job_path_prefix(tmp_path):
    root = tmp_path / "tasks"
    (root / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(root), "prefix": "combined"}]}}
    assert xr3pathmap.resolve_job_path(root / "job", cfg) == "combined/job"


def test_resolve_job_path_longest_root_wins(tmp_path):
    outer = tmp_path / "o"
    inner = outer / "i"
    (inner / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(outer)}, {"path": str(inner)}]}}
    assert xr3pathmap.resolve_job_path(inner / "job", cfg) == "job"


def test_resolve_job_path_no_match_raises(tmp_path):
    (tmp_path / "elsewhere" / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(tmp_path / "other")}]}}
    with pytest.raises(xr3pathmap.PathmapError) as excinfo:
        xr3pathmap.resolve_job_path(tmp_path / "elsewhere" / "job", cfg)
    assert "pathmap" in str(excinfo.value).lower()


def test_resolve_job_path_no_roots_raises(tmp_path):
    with pytest.raises(xr3pathmap.PathmapError):
        xr3pathmap.resolve_job_path(tmp_path / "job", {"pathmap": {"roots": []}})


def test_resolve_job_path_error_names_config_source(tmp_path):
    with pytest.raises(xr3pathmap.PathmapError) as excinfo:
        xr3pathmap.resolve_job_path(
            tmp_path / "job", {"pathmap": {"roots": []}}, config_source="/my/cfg.yaml"
        )
    assert "/my/cfg.yaml" in str(excinfo.value)
```

- [ ] **Step 4: Remove the moved tests from `test_xr3config.py`** — delete the five `test_resolve_job_path_*` functions from `extensions/xr3/tests/test_xr3config.py`. Keep the four `test_load_config_*` tests. (Leave its `import xr3config` — still used.)

- [ ] **Step 5: Run the unit tests**

Run: `cd $REPO && python -m pytest extensions/xr3/tests/ -v`
Expected: **10 passed** (4 in `test_xr3config.py`, 6 in `test_xr3pathmap.py`).

- [ ] **Step 6: Rewire the `xr3` script** — (a) add `import xr3pathmap` next to `import xr3config` (near the top). (b) Replace the `_get_path` function body with the `xr3pathmap` call + config source:

```python
def _get_path(path: Path) -> str:
    """Map a working-directory path to its r3 logical path (from config)."""
    try:
        return xr3pathmap.resolve_job_path(
            Path(path), _config(), config_source=str(xr3config.config_path())
        )
    except xr3pathmap.PathmapError as e:
        raise click.ClickException(str(e))
```
(Leave `_config()` and the `import xr3config` as-is.)

- [ ] **Step 7: Parse + golden + gating**

Run:
```bash
cd extensions/xr3
python -c "import ast; ast.parse(open('xr3').read())" && echo "parse OK"
grep -n "xr3config.resolve_job_path\|xr3config.PathmapError" xr3 || echo "no stale xr3config pathmap refs"
cd $REPO && dev/xr3_golden.sh check
```
Expected: `parse OK`, `no stale xr3config pathmap refs`, `ALL DATA COMMANDS IDENTICAL`.

Gating now names the real config file:
```bash
printf 'pathmap:\n  roots: []\n' > /tmp/xr3_empty.yaml
XR3_CONFIG=/tmp/xr3_empty.yaml $XR3 history --latest "$XR3_JOBDIR" 2>&1 | tee /tmp/g.txt
grep -qi "No pathmap root matches" /tmp/g.txt && grep -q "/tmp/xr3_empty.yaml" /tmp/g.txt && echo "GATED, names config file"
grep -qi Traceback /tmp/g.txt && echo "TRACEBACK (BAD)" || echo "no traceback"
```
Expected: `GATED, names config file` (the message now shows `/tmp/xr3_empty.yaml`, thanks to `config_source`) and `no traceback`.

- [ ] **Step 8: Commit**

```bash
git add extensions/xr3/xr3pathmap.py extensions/xr3/xr3config.py extensions/xr3/xr3 \
        extensions/xr3/tests/test_xr3pathmap.py extensions/xr3/tests/test_xr3config.py
git commit -m "refactor(xr3): split pathmap into xr3pathmap.py

Moves resolve_job_path + PathmapError out of xr3config into a standalone
pure module; threads the real config path into the no-root error
(config_source). Tests split accordingly (10 passing). Golden identical."
```

---

## Phase 3 exit check

- [ ] **Unit tests:** `cd $REPO && python -m pytest extensions/xr3/tests/ -q` → 10 passed.
- [ ] **Golden:** `dev/xr3_golden.sh check` → `ALL DATA COMMANDS IDENTICAL`.
- [ ] **`history --id`:** `$XR3 history --latest --id "$XR3_JOBDIR"` → the bare UUID.
- [ ] **`commit` decoupled:** `$XR3 commit --help` shows no `--submit`/`--observe`; `_submit_job` still in the file (for `submit jobs`/`query`).
- [ ] **Gating names the config file** (Task 3.3 Step 7).
- [ ] **Commits:** three (`feat history --id`, `refactor commit decouple`, `refactor pathmap split`).

## Next plans (not in this document)

- **Phase 4 — Extract `xr3-slurm`** (submit/status/watch → separate tool): absorb `sattachx`/`sattachx_wait`, own the sbatch options (`--job-name`/`--output`/`--chdir`/excludes), preserve the `submit` per-invocation flags + reconcile local-vs-SSH, add the `[slurm]` config section, and clean up the deferred `if False:` block. Removes ~400 lines from the main file.
- **Phase 5 — Move `run_job_locally`** into final place; **decide** whether a further internal split (`diff.py`, `core`/`cli`) is worth it on the smaller remaining file.
- **Phase 6 — Docs** (`CONTRACT.md`, tool READMEs, signposts, `projects/CLAUDE.md`, `RESEARCH_WORKFLOW.md`).
