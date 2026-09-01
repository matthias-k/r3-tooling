# xr3 Extraction — Phase 2 (Externalize config) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace xr3's hardcoded personal assumptions — the 8-path pathmap list, the `bug/` blocker prefix, WIP-blocking, and the `IGNORED_*` dev-checkout skips — with a YAML config file, so a colleague can use xr3 by writing their own config, and pathmap commands fail with a clear, actionable message when unconfigured.

**Architecture:** A new **importable** pure-logic module `extensions/xr3/xr3config.py` (config loading + working-dir→r3-path resolution + defaults + a `PathmapError`) holds the new logic; it depends only on `pyyaml`, so it is unit-tested with `pytest` in the base Python (no `r3`/`executor` needed). The `xr3` script imports it and routes `_get_path` through it — a **single choke point**, so translating `PathmapError → click.ClickException` there gives graceful, traceback-free gating for *every* pathmap command at once. `check` and `dev-checkout` read blocker-tags / WIP / ignored-deps from config. Behavior preservation is proven by the existing golden harness, run with a config containing the real roots (config-driven pathmap must reproduce the old hardcoded output byte-for-byte).

**Tech Stack:** Python, Click, PyYAML, pytest.

**Spec:** `docs/specs/2026-08-22-xr3-extraction-design.md` §5 (config decisions), §6 (blockers/origin), §8 (`IGNORED_*` → config), §11 phase 2. Builds on branch `xr3-extraction` (Phases 0–1 already committed there).

---

## Config format decision (flag for plan review)

The spec left "exact path/format a planning detail." This plan chooses **YAML** at **`~/.config/xr3.yaml`**, overridable via **`$XR3_CONFIG`**:
- YAML (not TOML): matches the r3 ecosystem (`r3.yaml`, `metadata.yaml`) and `pyyaml` is already an xr3 dependency — no new dep.
- Per-user `~/.config/xr3.yaml`: pathmap roots are per-machine and SLURM settings (Phase 4) are per-cluster/user.
- `$XR3_CONFIG` override: lets tests and the golden run point at a fixture without touching the user's real config.

If you'd prefer TOML or a different location, say so before implementation — it's a one-place change here.

**Schema (Phase 2 subset; SLURM keys arrive in Phase 4):**
```yaml
pathmap:
  roots:
    - path: /abs/project/root            # working dirs under here map to r3 paths
    - path: /abs/other/root
      prefix: some-prefix                # optional: prepend this to the r3 path
blockers:
  tags: ["bug/"]                          # tag prefixes that block check / dev-checkout
  block_on_wip: true                      # non-empty metadata.WIP fails `check`
dev_checkout:
  ignored_destinations: []                # dep destinations to skip on dev-checkout
  ignored_repositories: []                # git dep repos to skip on dev-checkout
```
Missing config file → all defaults (empty `roots` → pathmap commands gate with an actionable error).

---

## Prerequisites

- Branch `xr3-extraction` is checked out in `/mnt/lustre/work/bethge/mkuemmerer31/projects/research/tools/r3-tooling` (`$REPO`).
- **Two interpreters:**
  - `xr3config` unit tests need only `pyyaml` → run with **base python** (`python -m pytest`, pytest 9.x present).
  - Running `xr3` itself (smoke/golden) needs the `r3_lustre` env. Export:
    ```bash
    export R3_REPOSITORY=/mnt/lustre/work/bethge/mkuemmerer31/r3_repo
    export XR3="env PYTHONPATH=/mnt/lustre/work/bethge/mkuemmerer31/r3 /mnt/lustre/work/bethge/mkuemmerer31/miniconda3/envs/r3_lustre/bin/python $REPO/extensions/xr3/xr3"
    export XR3_JOBDIR=/mnt/lustre/work/bethge/mkuemmerer31/projects/research/research/experiments/2026-08-04_DAEMONS-in-pysaliency
    export XR3_PATH_GLOB='research/experiments/2026-08-04_DAEMONS-in-pysaliency*'
    ```
  - **From Task 2.4 onward**, also export `XR3_CONFIG` pointing at the dev fixture with the real roots (created in Task 2.3): `export XR3_CONFIG=$REPO/dev/xr3.config.local.yaml`. Without it, pathmap commands will (correctly) gate and the golden will differ.
- **Transient Lustre note:** a run may fail with `Input/output error` — retry once or twice.
- The golden **baseline** (`dev/golden/baseline/`) from Phase 0 is the equivalence target; do NOT re-capture it. Config-driven pathmap with the real roots must reproduce it.

---

## File Structure (this plan's scope)

- Create: `extensions/xr3/xr3config.py` — config loading + pathmap resolution (pure; only stdlib + pyyaml).
- Create: `extensions/xr3/tests/test_xr3config.py` — unit tests (self-contained; inserts its own sys.path).
- Create: `extensions/xr3/xr3.example.yaml` — documented example config (committed; the sharing artifact — schema + placeholder paths).
- Create: `dev/xr3.config.local.yaml` — the author's REAL roots, used via `$XR3_CONFIG` for the golden run (gitignored).
- Modify: `extensions/xr3/xr3` — import `xr3config`; rewire `_get_path` through it with gating; wire `check`/`dev-checkout` blockers, WIP, and ignored-deps from config; remove the `IGNORED_*` module constants.

`HEADNODES` and all SLURM code are untouched (Phase 4).

---

## Task 2.1: TDD `xr3config.load_config` + defaults/merge

**Files:**
- Create: `extensions/xr3/xr3config.py`
- Create: `extensions/xr3/tests/test_xr3config.py`

- [ ] **Step 1: Write the failing tests**

Create `extensions/xr3/tests/test_xr3config.py`:
```python
import sys
from pathlib import Path

# Make `import xr3config` work regardless of pytest's rootdir.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
import xr3config


def test_load_config_missing_returns_defaults(tmp_path):
    cfg = xr3config.load_config(str(tmp_path / "nope.yaml"))
    assert cfg["blockers"]["tags"] == ["bug/"]
    assert cfg["blockers"]["block_on_wip"] is True
    assert cfg["pathmap"]["roots"] == []
    assert cfg["dev_checkout"]["ignored_destinations"] == []
    assert cfg["dev_checkout"]["ignored_repositories"] == []


def test_load_config_merges_over_defaults(tmp_path):
    p = tmp_path / "xr3.yaml"
    p.write_text(
        "blockers:\n"
        "  tags: ['bug/', 'wip/']\n"
        "pathmap:\n"
        "  roots:\n"
        "    - path: /a/b\n"
    )
    cfg = xr3config.load_config(str(p))
    assert cfg["blockers"]["tags"] == ["bug/", "wip/"]
    # deep-merge keeps sibling defaults not present in the file:
    assert cfg["blockers"]["block_on_wip"] is True
    assert cfg["pathmap"]["roots"] == [{"path": "/a/b"}]


def test_load_config_env_override(tmp_path, monkeypatch):
    p = tmp_path / "env.yaml"
    p.write_text("blockers:\n  block_on_wip: false\n")
    monkeypatch.setenv("XR3_CONFIG", str(p))
    cfg = xr3config.load_config()  # no explicit path -> uses $XR3_CONFIG
    assert cfg["blockers"]["block_on_wip"] is False


def test_load_config_non_mapping_raises(tmp_path):
    p = tmp_path / "bad.yaml"
    p.write_text("- just\n- a\n- list\n")
    with pytest.raises(ValueError):
        xr3config.load_config(str(p))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd $REPO && python -m pytest extensions/xr3/tests/test_xr3config.py -v`
Expected: collection/import error or failures — `xr3config` doesn't exist yet.

- [ ] **Step 3: Implement `xr3config.py` (load_config + helpers)**

Create `extensions/xr3/xr3config.py`:
```python
"""Configuration + working-dir->r3-path mapping for xr3.

Pure logic (stdlib + pyyaml only) so it is unit-testable without r3/executor.
The xr3 CLI imports load_config() and resolve_job_path() from here.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Optional

import yaml

DEFAULT_CONFIG_PATH = Path.home() / ".config" / "xr3.yaml"

DEFAULTS = {
    "pathmap": {"roots": []},
    "blockers": {"tags": ["bug/"], "block_on_wip": True},
    "dev_checkout": {"ignored_destinations": [], "ignored_repositories": []},
}


class PathmapError(Exception):
    """Raised when a working directory cannot be mapped to an r3 path."""


def config_path(explicit: Optional[str] = None) -> Path:
    """Resolve the config location: explicit arg > $XR3_CONFIG > default."""
    if explicit is not None:
        return Path(explicit)
    env = os.environ.get("XR3_CONFIG")
    if env:
        return Path(env)
    return DEFAULT_CONFIG_PATH


def _deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge `override` into a copy of `base` (dict values only)."""
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_config(path: Optional[str] = None) -> dict:
    """Load config merged over DEFAULTS. Missing file -> DEFAULTS."""
    cfg_path = config_path(path)
    if not cfg_path.is_file():
        return _deep_merge(DEFAULTS, {})
    with open(cfg_path) as f:
        loaded = yaml.safe_load(f) or {}
    if not isinstance(loaded, dict):
        raise ValueError(
            f"xr3 config at {cfg_path} must be a mapping, "
            f"got {type(loaded).__name__}"
        )
    return _deep_merge(DEFAULTS, loaded)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python -m pytest extensions/xr3/tests/test_xr3config.py -v`
Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add extensions/xr3/xr3config.py extensions/xr3/tests/test_xr3config.py
git commit -m "feat(xr3): xr3config.load_config with defaults + deep-merge

Pure module (stdlib + pyyaml), unit-tested. Config location:
\$XR3_CONFIG or ~/.config/xr3.yaml; missing file -> defaults."
```

## Task 2.2: TDD `xr3config.resolve_job_path` (pathmap + prefix + error)

**Files:**
- Modify: `extensions/xr3/xr3config.py` (add `resolve_job_path`)
- Modify: `extensions/xr3/tests/test_xr3config.py` (add tests)

- [ ] **Step 1: Write the failing tests** (append to `test_xr3config.py`)

```python
def test_resolve_job_path_basic(tmp_path):
    root = tmp_path / "proj"
    (root / "exp" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(root)}]}}
    assert xr3config.resolve_job_path(root / "exp" / "v1", cfg) == "exp/v1"


def test_resolve_job_path_prefix(tmp_path):
    root = tmp_path / "tasks"
    (root / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(root), "prefix": "combined"}]}}
    assert xr3config.resolve_job_path(root / "job", cfg) == "combined/job"


def test_resolve_job_path_longest_root_wins(tmp_path):
    outer = tmp_path / "o"
    inner = outer / "i"
    (inner / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(outer)}, {"path": str(inner)}]}}
    # inner is more specific -> path relative to inner
    assert xr3config.resolve_job_path(inner / "job", cfg) == "job"


def test_resolve_job_path_no_match_raises(tmp_path):
    (tmp_path / "elsewhere" / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(tmp_path / "other")}]}}
    with pytest.raises(xr3config.PathmapError) as excinfo:
        xr3config.resolve_job_path(tmp_path / "elsewhere" / "job", cfg)
    assert "pathmap" in str(excinfo.value).lower()


def test_resolve_job_path_no_roots_raises(tmp_path):
    with pytest.raises(xr3config.PathmapError):
        xr3config.resolve_job_path(tmp_path / "job", {"pathmap": {"roots": []}})
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `python -m pytest extensions/xr3/tests/test_xr3config.py -v`
Expected: the 5 new tests fail (`resolve_job_path` undefined); the 4 from Task 2.1 still pass.

- [ ] **Step 3: Implement `resolve_job_path`** (append to `xr3config.py`)

```python
def resolve_job_path(fs_path, config: dict) -> str:
    """Map a working-directory path to its r3 logical path.

    Finds the configured `pathmap.roots` entry containing `fs_path` (the most
    specific / longest root wins), returns the path relative to that root, and
    applies the entry's optional `prefix`. Raises PathmapError with an
    actionable message if no configured root matches.
    """
    resolved = Path(fs_path).resolve()
    roots = (config.get("pathmap") or {}).get("roots") or []

    matches = []
    for entry in roots:
        root = Path(entry["path"]).resolve()
        if resolved == root or root in resolved.parents:
            matches.append((root, entry))

    if not matches:
        cfg = config_path()
        configured = [str(e["path"]) for e in roots] or "none"
        raise PathmapError(
            f"No pathmap root matches {resolved}.\n"
            f"Add its project root under `pathmap.roots` in {cfg} "
            f"(see CONTRACT.md). Configured roots: {configured}."
        )

    root, entry = max(matches, key=lambda m: len(str(m[0])))
    rel = resolved.relative_to(root)
    prefix = entry.get("prefix")
    if prefix:
        rel = Path(prefix) / rel
    return str(rel)
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `python -m pytest extensions/xr3/tests/test_xr3config.py -v`
Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
git add extensions/xr3/xr3config.py extensions/xr3/tests/test_xr3config.py
git commit -m "feat(xr3): xr3config.resolve_job_path (pathmap from config)

Longest-root-wins, optional per-root prefix, PathmapError with an
actionable message when no root matches. Replaces the hardcoded
_get_path list (wired in a later task)."
```

## Task 2.3: Example config + dev fixture with the real roots

**Files:**
- Create: `extensions/xr3/xr3.example.yaml` (committed template)
- Create: `dev/xr3.config.local.yaml` (gitignored; real roots for the golden run)
- Modify: `dev/.gitignore` (ignore the local config)

- [ ] **Step 1: Write the committed example template**

Create `extensions/xr3/xr3.example.yaml`:
```yaml
# xr3 configuration — copy to ~/.config/xr3.yaml (or point $XR3_CONFIG at it)
# and edit for your machine. See CONTRACT.md for what xr3 assumes about jobs.

pathmap:
  # Working directories under these roots map to r3 logical paths by stripping
  # the root prefix. `history`, `diff`, and `check`'s path asserts need this.
  roots:
    - path: /abs/path/to/your/project
    # - path: /abs/path/to/another/project
    #   prefix: some-prefix        # optional: prepend to the derived r3 path

blockers:
  tags: ["bug/"]        # tag prefixes that block `check` and `dev-checkout`
  block_on_wip: true    # a non-empty metadata.WIP fails `check`

dev_checkout:
  ignored_destinations: []    # dep destinations to skip when checking out
  ignored_repositories: []    # git dep repos to skip when checking out
```

- [ ] **Step 2: Write the dev fixture with the REAL roots** (reproduces the old `_get_path` exactly)

Create `dev/xr3.config.local.yaml`:
```yaml
# Real roots for behavior-preservation golden runs (gitignored). Mirrors the
# original hardcoded _get_path list, including the combined-gaze prefix on the
# LUSTRE gaze-combined-datasets/tasks root only (matching original behavior).
pathmap:
  roots:
    - path: /mnt/qb/home/bethge/mkuemmerer31/projects/gaze-combined-datasets/tasks
    - path: /mnt/qb/home/bethge/mkuemmerer31/projects/deepgaze-vs-scenewalk
    - path: /mnt/lustre/work/bethge/mkuemmerer31/projects/gaze-combined-datasets/tasks
      prefix: combined-gaze-datasets
    - path: /mnt/lustre/work/bethge/mkuemmerer31/projects/deepgaze-vs-scenewalk
    - path: /mnt/lustre/work/bethge/mkuemmerer31/projects/gold-standard
    - path: /mnt/lustre/work/bethge/mkuemmerer31/projects/saliency-benchmarking
    - path: /mnt/lustre/work/bethge/mkuemmerer31/projects/Jannis-OneBench
    - path: /mnt/lustre/work/bethge/mkuemmerer31/projects/research
```

- [ ] **Step 3: Gitignore the local config** — append to `dev/.gitignore`:

```
xr3.config.local.yaml
```

- [ ] **Step 4: Verify the example parses and the fixture reproduces the current mapping**

Run (base python is fine — this only imports `xr3config`):
```bash
cd $REPO
python -c "import sys; sys.path.insert(0,'extensions/xr3'); import xr3config as c; \
print(c.load_config('extensions/xr3/xr3.example.yaml')['blockers']); \
cfg=c.load_config('dev/xr3.config.local.yaml'); \
print(c.resolve_job_path('$XR3_JOBDIR', cfg))"
```
Expected: prints the blockers dict, then `research/experiments/2026-08-04_DAEMONS-in-pysaliency` (the same logical path the old `_get_path` produced — confirm it matches `metadata.path` of that job).

- [ ] **Step 5: Commit**

```bash
git add extensions/xr3/xr3.example.yaml dev/.gitignore
git commit -m "docs(xr3): example config template + gitignore local golden config

xr3.example.yaml is the copy-and-edit template for colleagues. The real
roots live in dev/xr3.config.local.yaml (gitignored) for golden runs."
```

## Task 2.4: Rewire `_get_path` through config, with graceful gating

**Files:**
- Modify: `extensions/xr3/xr3` (add imports; replace `_get_path`)

- [ ] **Step 1: Add imports** near the top of `extensions/xr3/xr3` (after the existing `import` block, e.g. after `from tqdm import tqdm`):

```python
import functools
import xr3config
```

- [ ] **Step 2: Replace the body of `_get_path`** (currently lines ~314–338 — the function with the hardcoded `task_root_directories` list). Replace the ENTIRE function with:

```python
@functools.lru_cache(maxsize=1)
def _config():
    return xr3config.load_config()


def _get_path(path: Path) -> str:
    """Map a working-directory path to its r3 logical path (from config)."""
    try:
        return xr3config.resolve_job_path(Path(path), _config())
    except xr3config.PathmapError as e:
        raise click.ClickException(str(e))
```

- [ ] **Step 3: Parse + import check**

Run:
```bash
cd extensions/xr3
python -c "import ast; ast.parse(open('xr3').read())" && echo "parse OK"
grep -n "task_root_directories" xr3 || echo "hardcoded list gone"
```
Expected: `parse OK`, `hardcoded list gone`.

- [ ] **Step 4: Golden — with the real-roots config, behavior is byte-identical**

Run (ensure `XR3_CONFIG` points at the dev fixture):
```bash
cd $REPO
export XR3_CONFIG=$REPO/dev/xr3.config.local.yaml
dev/xr3_golden.sh check
```
Expected: `ALL DATA COMMANDS IDENTICAL`. (The pathmap-driven `history`/`check` now come from config but resolve to the same logical path, so output is unchanged.) If any data command differs, STOP and report BLOCKED with the diff.

- [ ] **Step 5: Gating smoke — no config / unmatched path gives an actionable error, not a traceback**

Run:
```bash
cd $REPO
# Point XR3_CONFIG at an empty config so no roots match:
printf 'pathmap:\n  roots: []\n' > /tmp/xr3_empty.yaml
XR3_CONFIG=/tmp/xr3_empty.yaml $XR3 history --latest "$XR3_JOBDIR" 2>&1 | tee /tmp/xr3_gate.txt
grep -qi "No pathmap root matches" /tmp/xr3_gate.txt && echo "GATED cleanly"
grep -qi "Traceback" /tmp/xr3_gate.txt && echo "TRACEBACK LEAKED (BAD)" || echo "no traceback"
```
Expected: output contains `Error: No pathmap root matches …` (Click formats `ClickException` as `Error: …`), prints `GATED cleanly` and `no traceback`. Restore `XR3_CONFIG` to the dev fixture afterward.

- [ ] **Step 6: Commit**

```bash
git add extensions/xr3/xr3
git commit -m "refactor(xr3): pathmap from config, with graceful gating

_get_path now resolves via xr3config.resolve_job_path over config roots
(kills the hardcoded 8-path list). PathmapError -> click.ClickException
gives one actionable, traceback-free error for all pathmap commands.
Golden byte-identical with the real-roots config."
```

## Task 2.5: Blockers, WIP, and ignored-deps from config; remove `IGNORED_*` constants

**Files:**
- Modify: `extensions/xr3/xr3` (`_check_job` blocker + WIP; `dev_checkout` blocker + ignored-deps; remove `IGNORED_*` module constants)

- [ ] **Step 1: Wire `check`'s blocker tags** — in `_check_job`, replace the dependency bug-tag test (currently `if tag.startswith("bug/"):`, ~line 402) with:

```python
                if any(tag.startswith(p) for p in _config()["blockers"]["tags"]):
```

- [ ] **Step 2: Gate `check`'s WIP block on config** — replace the WIP block (currently `wip_items = job.metadata.get("WIP", [])` then `if wip_items:`, ~lines 435–440) with:

```python
    wip_items = job.metadata.get("WIP", [])
    if wip_items and _config()["blockers"]["block_on_wip"]:
        print(f"Job has {len(wip_items)} WIP items:")
        for item in wip_items:
            print(f" - {item}")
        correct = False
```

- [ ] **Step 3: Wire `dev-checkout`'s blocker tags** — replace its bug-tag list comprehension (currently `bug_tags = [tag for tag in tags if tag.startswith("bug/")]`, ~line 1303) with:

```python
            bug_tags = [tag for tag in tags if any(tag.startswith(p) for p in _config()["blockers"]["tags"])]
```

- [ ] **Step 4: Wire `dev-checkout`'s ignored-deps from config** — replace the two `IGNORED_*` references (~lines 1314 and 1318):

Replace `if str(dependency.destination) in IGNORED_DESTINATIONS:` with:
```python
        if str(dependency.destination) in _config()["dev_checkout"]["ignored_destinations"]:
```
Replace `... dependency.repository in IGNORED_REPOSITORIES) ...` with:
```python
        if isinstance(dependency, r3.GitDependency) and dependency.repository in _config()["dev_checkout"]["ignored_repositories"]:  # noqa: E501
```

- [ ] **Step 5: Remove the dead module constants** — delete the `IGNORED_DESTINATIONS = [ … ]` and `IGNORED_REPOSITORIES = [ … ]` blocks near the top (~lines 22–28). Leave `HEADNODES` untouched.

- [ ] **Step 6: Parse + no-orphan check**

Run:
```bash
cd extensions/xr3
python -c "import ast; ast.parse(open('xr3').read())" && echo "parse OK"
grep -n "IGNORED_DESTINATIONS\|IGNORED_REPOSITORIES" xr3 || echo "constants gone"
grep -n 'startswith("bug/")' xr3 || echo "no hardcoded bug/ left"
```
Expected: `parse OK`, `constants gone`, `no hardcoded bug/ left`.

- [ ] **Step 7: Golden — default config reproduces old behavior**

Run (with `XR3_CONFIG=$REPO/dev/xr3.config.local.yaml`; the fixture omits `blockers`/`dev_checkout`, so defaults apply → `["bug/"]`, WIP on, empty ignores = old behavior):
```bash
cd $REPO
dev/xr3_golden.sh check
```
Expected: `ALL DATA COMMANDS IDENTICAL`. (The `check` golden on the DAEMONS job — no bug deps, no WIP — still prints `All good.`) If any data command differs, STOP and report BLOCKED.

- [ ] **Step 8: Behavioral check — a custom blocker tag config is honored**

This proves config is actually read (not just defaults). Run a tiny unit-level check via the config accessor (no bugged r3 job needed):
```bash
cd $REPO
printf 'blockers:\n  tags: ["bug/", "flaky/"]\n' > /tmp/xr3_blockers.yaml
python -c "import sys; sys.path.insert(0,'extensions/xr3'); import xr3config as c; \
cfg=c.load_config('/tmp/xr3_blockers.yaml'); \
assert cfg['blockers']['tags']==['bug/','flaky/'], cfg['blockers']; \
assert any('flaky/x'.startswith(p) for p in cfg['blockers']['tags']); \
print('blocker-tag config honored')"
```
Expected: prints `blocker-tag config honored`.

- [ ] **Step 9: Commit**

```bash
git add extensions/xr3/xr3
git commit -m "refactor(xr3): blockers/WIP/ignored-deps from config

check + dev-checkout read blocker tag prefixes and WIP-blocking from
config['blockers']; dev-checkout ignored destinations/repositories from
config['dev_checkout']. Removed the empty IGNORED_* module constants.
Defaults reproduce prior behavior; golden byte-identical."
```

---

## Phase 2 exit check

- [ ] **Unit tests green:** `cd $REPO && python -m pytest extensions/xr3/tests/ -v` → 9 passed.
- [ ] **Golden regression (real-roots config):** `XR3_CONFIG=$REPO/dev/xr3.config.local.yaml dev/xr3_golden.sh check` → `ALL DATA COMMANDS IDENTICAL`.
- [ ] **Gating works:** an empty-roots config makes pathmap commands print `Error: No pathmap root matches …` with no traceback (Task 2.4 Step 5).
- [ ] **No hardcoded assumptions remain:** `grep -nE 'task_root_directories|IGNORED_DESTINATIONS|IGNORED_REPOSITORIES|startswith\("bug/"\)' extensions/xr3/xr3` → no hits.
- [ ] **Commits read cleanly:** `git log --oneline` shows the five Task-2 commits (2 feat for xr3config, 1 example/fixture, 2 refactor for the rewire).

## Next plans (not in this document)

- **Phase 3 — Module split** (`core`/`pathmap`/`diff`/`config`/`cli`): `xr3config.py` becomes the package's `config.py`/`pathmap.py`; `diff` made pathmap-independent; `commit` drops `--submit`; `history` gains `--id`.
- **Phase 4 — Extract `xr3-slurm`** (submit/status/watch), absorb `sattachx`, own sbatch options, `[slurm]` config section, clean up the deferred `if False:` block.
- **Phase 5 — Move `run_job_locally`**; **Phase 6 — Docs** (`CONTRACT.md`, tool READMEs, signposts, `projects/CLAUDE.md`, `RESEARCH_WORKFLOW.md`).
