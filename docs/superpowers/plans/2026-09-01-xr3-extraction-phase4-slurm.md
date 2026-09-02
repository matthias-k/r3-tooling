# xr3-slurm Extraction (Phase 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract all SLURM code out of the `xr3` monolith into a self-contained sibling tool `extensions/xr3-slurm/`, absorbing the `sattachx`/`sattachx_wait` helpers, config-driving the galvani-specific assumptions, and merging `submit query`+`submit jobs` into one `submit`.

**Architecture:** A thin CLI script `extensions/xr3-slurm/xr3-slurm` (imports r3/executor) orchestrates I/O around a pure, stdlib-only `xr3slurmlib.py` (unit-tested in base Python, like `xr3config`/`xr3pathmap`). SLURM assumptions (headnodes, submit host, node excludes, partition/mem defaults) move into a new `slurm:` section of the shared `~/.config/xr3.yaml`, loaded via the existing `xr3config` module (imported from the sibling `../xr3` dir). `xr3-slurm` is built and verified alongside the untouched `xr3`; only the final task deletes the SLURM code from `xr3`, gated by the golden harness proving `xr3`'s kept commands are byte-identical.

**Tech Stack:** Python 3, Click, `executor` (`ExternalCommand`/`RemoteCommand`/`execute`), r3, pyyaml, pytest.

## Design decisions (settled)

1. **Suite, not monolith.** `xr3-slurm` is a sibling script. It reuses `xr3config` (the suite-wide config loader) via a `sys.path` insert of `../xr3`; it does NOT import from the `xr3` CLI script. The tiny `_build_query` helper is **copied** into `xr3-slurm` (a ~20-line pure function — duplication is more honest than coupling to a CLI script's internals).
2. **Pure/impure seam.** All string/parse logic (sbatch command construction, sbatch-option parsing, done-marker interpretation, sattach step parsing) lives in `xr3slurmlib.py` (stdlib only) and is unit-tested in base Python. The CLI does only I/O (r3 queries, `execute`/SSH, the poll loops). This is how a phase with no live `sbatch` still gets real test coverage.
3. **Merged `submit` — local-vs-SSH reconciliation (BEHAVIOR CHANGE, deliberate).** Today `submit query` submits **locally** (`cluster=None`) and `submit jobs` submits **over SSH** (`cluster="galvani"`). The merged `submit` defaults to **SSH-to-headnode** via `slurm.submit_host` (default `"galvani"`), because `sbatch` requires a submission host and that matches the more-used `submit jobs` path. To submit locally (when already on the headnode), pass `--cluster ''` (or set `slurm.submit_host: null`). This is a conscious unification, not a silent pick.
4. **`watch` primitive = a SLURM job name/id** (positional), served by the absorbed `sattachx_wait` logic (which natively accepts a name or numeric id). It composes with `xr3 history --latest --id .`. An optional `--tag/-t` family mode keeps the old r3-query selection loop. The latent typo bug `'newest-running_job'` (underscore) is FIXED to `newest-running-job`.
5. **Absorb `sattachx`+`sattachx_wait`** fully into `xr3-slurm` (via `xr3slurmlib` for the pure parts), removing the external-script dependency AND the hardcoded `#!/home/.../miniconda3/bin/python` shebang and the hardcoded `/home/bethge/mkuemmerer31/.local/bin/sattachx_wait` path.
6. **Config-drive galvani specifics:** `slurm.headnodes` (status/watch squeue polling), `slurm.submit_host` (sbatch SSH target), `slurm.exclude_nodes` (was hardcoded `galvani-cn221,galvani-cn240`), `slurm.partition`/`slurm.mem` (defaults). `xr3-slurm` reads only `slurm:`; `xr3` reads only its own sections.
7. **`done`-marker convention** (write `output/done` with body `restart`/`failed`/other) is assumed by submit (idempotency/restart) and status. Documented in Phase 6; here it is centralized in `xr3slurmlib.parse_done_state`.
8. **Clean up the dead `if False:` block** in `_submit_job` (collapse to the live line) as part of the sattach rewrite.

## File Structure

- **Create** `extensions/xr3-slurm/xr3-slurm` — the CLI (imports r3/executor/click; `sys.path`-imports `xr3config`; commands `submit`, `status`, `watch`).
- **Create** `extensions/xr3-slurm/xr3slurmlib.py` — pure, stdlib-only parse/build helpers.
- **Create** `extensions/xr3-slurm/tests/test_xr3slurmlib.py` — base-Python pytest.
- **Modify** `extensions/xr3/xr3config.py` — add `slurm` to `DEFAULTS` (this is the suite-wide loader).
- **Modify** `extensions/xr3/xr3.example.yaml` — add a documented `slurm:` section.
- **Modify** `dev/xr3.config.local.yaml` — add real galvani `slurm:` values (gitignored; preserves the old hardcoded excludes).
- **Modify** `extensions/xr3/xr3` — (final task) delete all SLURM code + now-unused imports.

Verification env (from the handoff — export before any `xr3`/`xr3-slurm` run):
```bash
export R3_REPOSITORY=/mnt/lustre/work/bethge/mkuemmerer31/r3_repo
export XR3="env PYTHONPATH=/mnt/lustre/work/bethge/mkuemmerer31/r3 /mnt/lustre/work/bethge/mkuemmerer31/miniconda3/envs/r3_lustre/bin/python $(git -C . rev-parse --show-toplevel)/extensions/xr3/xr3"
export XR3_SLURM="env PYTHONPATH=/mnt/lustre/work/bethge/mkuemmerer31/r3 /mnt/lustre/work/bethge/mkuemmerer31/miniconda3/envs/r3_lustre/bin/python $(git -C . rev-parse --show-toplevel)/extensions/xr3-slurm/xr3-slurm"
export XR3_JOBDIR=/mnt/lustre/work/bethge/mkuemmerer31/projects/research/research/experiments/2026-08-04_DAEMONS-in-pysaliency
export XR3_PATH_GLOB='research/experiments/2026-08-04_DAEMONS-in-pysaliency*'
export XR3_CONFIG=$(git -C . rev-parse --show-toplevel)/dev/xr3.config.local.yaml
```
- Pure unit tests run in **base Python**: `python -m pytest extensions/xr3-slurm/tests/`.
- Transient Lustre `Input/output error` → retry once or twice (not a code bug).

---

### Task 1: Scaffold `xr3-slurm` + `slurm` config section

**Files:**
- Modify: `extensions/xr3/xr3config.py` (DEFAULTS)
- Modify: `extensions/xr3/xr3.example.yaml`
- Modify: `dev/xr3.config.local.yaml`
- Create: `extensions/xr3-slurm/xr3-slurm`
- Create: `extensions/xr3-slurm/xr3slurmlib.py` (empty placeholder for Task 2)

- [ ] **Step 1: Add `slurm` defaults to the shared config loader**

In `extensions/xr3/xr3config.py`, update the module docstring's first line and `DEFAULTS`:

```python
"""Configuration loading for the xr3 tool suite (xr3 + xr3-slurm).

Pure logic (stdlib + pyyaml only) so it is unit-testable without r3/executor.
Each tool reads only its own section(s). See xr3pathmap for the
working-dir->r3-path mapping.
"""
```

```python
DEFAULTS = {
    "pathmap": {"roots": []},
    "blockers": {"tags": ["bug/"], "block_on_wip": True},
    "dev_checkout": {"ignored_destinations": [], "ignored_repositories": []},
    "slurm": {
        "headnodes": ["galvani"],   # squeue/sacct polling targets (status, watch --tag)
        "submit_host": "galvani",   # sbatch SSH target; null/"" => submit locally
        "exclude_nodes": [],        # sbatch --exclude nodes (empty => no --exclude)
        "partition": None,          # default sbatch --partition (null => omit)
        "mem": None,                # default sbatch --mem (null => omit)
    },
}
```

- [ ] **Step 2: Verify the config module still loads and merges**

Run: `python -c "import sys; sys.path.insert(0,'extensions/xr3'); import xr3config; c=xr3config.load_config('/dev/null'); print(c['slurm'])"`
Expected: `{'headnodes': ['galvani'], 'submit_host': 'galvani', 'exclude_nodes': [], 'partition': None, 'mem': None}`

- [ ] **Step 3: Run the existing config unit tests (must stay green)**

Run: `python -m pytest extensions/xr3/tests/test_xr3config.py -q`
Expected: PASS (4 passed). If a test asserts the exact `DEFAULTS` dict, update it to include the new `slurm` key.

- [ ] **Step 4: Document the section in the example config**

Append to `extensions/xr3/xr3.example.yaml`:

```yaml

slurm:                     # read only by xr3-slurm (MLCloud / galvani; ports to other SLURM)
  headnodes: ["galvani"]   # hosts to SSH for squeue/sacct (status, watch --tag)
  submit_host: galvani     # host to SSH for sbatch; set null (or pass --cluster "") to submit locally
  exclude_nodes: []        # e.g. ["galvani-cn221", "galvani-cn240"]
  partition: null          # default --partition
  mem: null                # default --mem
```

- [ ] **Step 5: Add real galvani values to the dev fixture (preserves old hardcoded behavior)**

Append to `dev/xr3.config.local.yaml`:

```yaml

slurm:
  headnodes: ["galvani"]
  submit_host: galvani
  exclude_nodes: ["galvani-cn221", "galvani-cn240"]
  partition: null
  mem: null
```

- [ ] **Step 6: Create the empty pure lib placeholder**

Create `extensions/xr3-slurm/xr3slurmlib.py`:

```python
"""Pure SLURM string/parse helpers for xr3-slurm.

Stdlib only (no r3/executor) so it is unit-testable in base Python.
The xr3-slurm CLI does all I/O; this module does all parsing/formatting.
"""
from __future__ import annotations
```

- [ ] **Step 7: Create the CLI skeleton**

Create `extensions/xr3-slurm/xr3-slurm` (no `.py` extension, matches `xr3`):

```python
import functools
import json
import os
import re
import sys
import time
import uuid
from collections import Counter
from datetime import datetime
from pathlib import Path
from time import sleep
from typing import List, Optional

import click
import r3
from executor import ExternalCommand, ExternalCommandFailed, execute
from executor.ssh.client import RemoteCommand
from tqdm import tqdm

# xr3-slurm reuses the suite-wide config loader that lives in the sibling xr3 dir.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "xr3"))
import xr3config

import xr3slurmlib


@functools.lru_cache(maxsize=1)
def _config() -> dict:
    return xr3config.load_config()


def _slurm_config() -> dict:
    return _config()["slurm"]


def _build_query(tags, queries) -> dict:
    """Build a Mongo-style query dict from tag/query CLI options.

    Copied (intentionally) from xr3 so xr3-slurm stays self-contained.
    - tags -> {"tags": {"$all": [...]}} (omitted if empty)
    - queries: JSON fragments; bare `key: value` is wrapped in {...} and merged.
    """
    query: dict = {}
    if tags:
        query["tags"] = {"$all": list(tags)}
    for q in queries:
        if not q.startswith("{"):
            q = f"{{{q}}}"
        query_data = json.loads(q)
        if not isinstance(query_data, dict):
            raise ValueError(f"Query must be a JSON object, got {query_data}")
        query.update(query_data)
    return query


@click.group()
def cli():
    pass


if __name__ == "__main__":
    cli()
```

- [ ] **Step 8: Make it executable and smoke-test `--help`**

Run:
```bash
chmod +x extensions/xr3-slurm/xr3-slurm
eval "$XR3_SLURM --help"
```
Expected: Click usage banner listing the (currently empty) command group, no traceback.

- [ ] **Step 9: Commit**

```bash
git add extensions/xr3/xr3config.py extensions/xr3/xr3.example.yaml dev/xr3.config.local.yaml extensions/xr3-slurm/xr3-slurm extensions/xr3-slurm/xr3slurmlib.py
git commit -m "feat(xr3-slurm): scaffold sibling tool + slurm config section"
```

---

### Task 2: Pure `xr3slurmlib` helpers (TDD)

**Files:**
- Create: `extensions/xr3-slurm/tests/test_xr3slurmlib.py`
- Modify: `extensions/xr3-slurm/xr3slurmlib.py`

- [ ] **Step 1: Write the failing tests**

Create `extensions/xr3-slurm/tests/test_xr3slurmlib.py`:

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import xr3slurmlib as lib


def test_parse_done_state():
    assert lib.parse_done_state("restart\n") == "restart"
    assert lib.parse_done_state("  failed ") == "failed"
    assert lib.parse_done_state("completed\n") == "done"
    assert lib.parse_done_state("") == "done"


def test_is_array_job():
    assert lib.is_array_job("#SBATCH --array=0-9\n#SBATCH --mem=4G\n") is True
    assert lib.is_array_job("#SBATCH --mem=4G\n#!/bin/bash\n") is False
    # leading whitespace before #SBATCH is not a directive (sbatch ignores it)
    assert lib.is_array_job("   #SBATCH --array=0-9\n") is False


def test_build_sbatch_command_scalar():
    cmd = lib.build_sbatch_command(
        script_path="/jobs/ID/run.sh",
        job_dir="/jobs/ID",
        full_id="ID",
        is_array=False,
        exclude_nodes=["cn221", "cn240"],
        partition=None,
        mem=None,
    )
    assert cmd == (
        "sbatch --job-name=ID --comment=/jobs/ID --chdir=/jobs/ID "
        "--output=/jobs/ID/output/slurm_%J.log --error=/jobs/ID/output/slurm_%J.log "
        "--exclude=cn221,cn240 /jobs/ID/run.sh"
    )


def test_build_sbatch_command_array_and_opts():
    cmd = lib.build_sbatch_command(
        script_path="/jobs/ID/run.sh",
        job_dir="/jobs/ID",
        full_id="ID",
        is_array=True,
        exclude_nodes=[],
        partition="a100",
        mem="16G",
    )
    assert "--output=/jobs/ID/output/slurm_%A_%a.log" in cmd
    assert "--exclude" not in cmd          # empty list => omitted
    assert "--partition=a100" in cmd
    assert "--mem=16G" in cmd


def test_parse_sattach_step():
    sacct = "12345         node   ...\n12345.batch   node   ...\n12345.0       node   ...\n"
    assert lib.parse_sattach_step(sacct) == "12345.batch"   # first N.M line
    assert lib.parse_sattach_step("12345  node\n") is None   # no step line


def test_parse_running_step():
    # sacct -j ID -P last row's step id -> integer step number (or None)
    assert lib.parse_running_step("JobID|...\n12345|...\n12345.0|...\n") == 0
    assert lib.parse_running_step("JobID|...\n12345|...\n12345.batch|...\n") is None
    assert lib.parse_running_step("JobID|...\n12345|...\n") is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m pytest extensions/xr3-slurm/tests/test_xr3slurmlib.py -q`
Expected: FAIL (AttributeError: module has no attribute 'parse_done_state' ...).

- [ ] **Step 3: Implement the pure helpers**

Append to `extensions/xr3-slurm/xr3slurmlib.py`:

```python
import re
from typing import List, Optional


def parse_done_state(done_file_text: str) -> str:
    """Classify an `output/done` marker body: 'restart' | 'failed' | 'done'."""
    body = done_file_text.strip()
    if body == "restart":
        return "restart"
    if body == "failed":
        return "failed"
    return "done"


def is_array_job(script_content: str) -> bool:
    """True if any line is a `#SBATCH --array...` directive (no leading whitespace)."""
    for line in script_content.split("\n"):
        if line.startswith("#SBATCH"):
            opt = line[len("#SBATCH"):].strip()
            if opt.startswith("--array"):
                return True
    return False


def build_sbatch_command(
    script_path: str,
    job_dir: str,
    full_id: str,
    is_array: bool,
    exclude_nodes: List[str],
    partition: Optional[str],
    mem: Optional[str],
) -> str:
    """Construct the `sbatch ...` command string. Pure: no filesystem access."""
    log = f"{job_dir}/output/" + ("slurm_%A_%a.log" if is_array else "slurm_%J.log")
    options = {
        "--job-name": full_id,
        "--comment": job_dir,
        "--chdir": job_dir,
        "--output": log,
        "--error": log,
    }
    if exclude_nodes:
        options["--exclude"] = ",".join(exclude_nodes)
    if partition:
        options["--partition"] = partition
    if mem:
        options["--mem"] = mem
    options_str = " ".join(f"{k}={v}" for k, v in options.items())
    return f"sbatch {options_str} {script_path}"


def parse_sattach_step(sacct_output: str) -> Optional[str]:
    """First `N.M` step id from `sacct -j <id>` output (was sattachx's awk)."""
    for line in sacct_output.split("\n"):
        first = line.split()[0] if line.split() else ""
        if re.match(r"^[0-9]+\.[0-9]+", first):
            return first
    return None


def parse_running_step(sacct_p_output: str) -> Optional[int]:
    """Step number from the last row of `sacct -j <id> -P`, or None.

    Mirrors sattachx_wait.get_job_state: split last line on '|', take field 0,
    and if it is `<jobid>.<step>` return int(step) else None.
    """
    lines = [l for l in sacct_p_output.strip().split("\n") if l.strip()]
    if not lines:
        return None
    step_id = lines[-1].split("|")[0]
    if "." not in step_id:
        return None
    try:
        return int(step_id.split(".", 1)[1])
    except ValueError:
        return None
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python -m pytest extensions/xr3-slurm/tests/test_xr3slurmlib.py -q`
Expected: PASS (6 passed).

- [ ] **Step 5: Commit**

```bash
git add extensions/xr3-slurm/xr3slurmlib.py extensions/xr3-slurm/tests/test_xr3slurmlib.py
git commit -m "feat(xr3-slurm): pure sbatch/sattach parse+build helpers with tests"
```

---

### Task 3: Absorb `sattachx` + `sattachx_wait` into the CLI

**Files:**
- Modify: `extensions/xr3-slurm/xr3-slurm`

Replaces the external `/home/.../sattachx_wait` script and its `#!/home/.../miniconda3/bin/python` shebang with internal functions built on `execute` + `xr3slurmlib`. `cluster=None` means run locally (attach where you are), matching today's watch/observe attach behavior.

- [ ] **Step 1: Add the attach helpers to the CLI**

Insert into `extensions/xr3-slurm/xr3-slurm` (before the `cli` group):

```python
def _run(cluster: Optional[str], command: str, **kwargs):
    """RemoteCommand if a cluster host is given, else a local ExternalCommand."""
    if cluster:
        return RemoteCommand(cluster, command, **kwargs)
    return ExternalCommand(command, **kwargs)


def _capture(cluster: Optional[str], command: str) -> str:
    cmd = _run(cluster, command, capture=True)
    cmd.start()
    return cmd.output


def _get_job_id(job_name: str, cluster: Optional[str]) -> str:
    """Newest/highest-priority slurm job id for a job name (was sattachx_wait)."""
    output = _capture(
        cluster,
        f"squeue --me --sort=-t,-M,-p --format=%i --noheader --name={job_name}",
    )
    return output.strip().split("\n")[0]


def _get_job_state(job_id: str, cluster: Optional[str]) -> str:
    """'RUNNING.<step>' when a step exists, else the raw squeue state."""
    state = _capture(
        cluster, f'squeue --jobs={job_id} --noheader --format="%T"'
    ).strip()
    if state == "RUNNING":
        sacct = _capture(cluster, f"sacct -j {job_id} -P")
        return f"RUNNING.{xr3slurmlib.parse_running_step(sacct)}"
    return state


def _sattach(job_id: str, cluster: Optional[str]) -> None:
    """Attach to the running step of a job id (was the sattachx bash script)."""
    sacct = _capture(cluster, f"sacct -j {job_id}")
    step = xr3slurmlib.parse_sattach_step(sacct)
    if step is None:
        print(f"No step to attach for job {job_id}")
        return
    print(f"attaching to {step}")
    time.sleep(1)
    _run(cluster, f"sattach {step}").start()


def _sattach_wait(job_name_or_id: str, cluster: Optional[str] = None) -> None:
    """Poll a job (by numeric id or name) and attach once a step is RUNNING.

    Absorbs sattachx_wait: if given a name, resolve the id and keep re-resolving
    when the queued job changes; attach via _sattach when a step appears.
    """
    try:
        int(job_name_or_id)
        job_name = None
        job_id = job_name_or_id
    except ValueError:
        job_name = job_name_or_id
        job_id = _get_job_id(job_name, cluster)

    job_state = None
    last_state_change = datetime.utcnow()
    while True:
        new_state = _get_job_state(job_id, cluster) if job_id else ""
        if new_state != job_state:
            if job_state is not None:
                print()
            if job_id:
                print(f"job {job_id} is {new_state}", end="", flush=True)
                if job_name is None and new_state == "":
                    print("\nJob not existing anymore, quitting")
                    return
            else:
                print(f"Waiting for job {job_name} to appear", end="", flush=True)
            job_state = new_state
            last_state_change = datetime.utcnow()
        else:
            elapsed = str(datetime.utcnow() - last_state_change).split(".", 1)[0]
            if job_id:
                print(f"\rjob {job_id} is {new_state} since {elapsed}", end="", flush=True)
            else:
                print(f"\rWaiting for job {job_name} to appear since {elapsed}", end="", flush=True)

        if job_state.startswith("RUNNING"):
            _, step_no = job_state.split(".")
            if step_no != "None":
                _sattach(job_id, cluster)
        elif job_name is not None or not job_id:
            new_job_id = _get_job_id(job_name, cluster)
            if new_job_id != job_id:
                print(f"\nswitching to monitoring job {new_job_id}")
                job_id = new_job_id
                job_state = None

        sleep(10)
```

- [ ] **Step 2: Byte-compile smoke (no live SLURM)**

Run: `eval "$XR3_SLURM --help"`
Expected: usage banner, no import/syntax error (proves the new functions parse and `xr3slurmlib` imports).

- [ ] **Step 3: Commit**

```bash
git add extensions/xr3-slurm/xr3-slurm
git commit -m "feat(xr3-slurm): absorb sattachx/sattachx_wait as internal attach helpers"
```

---

### Task 4: `submit` command (merged query+jobs)

**Files:**
- Modify: `extensions/xr3-slurm/xr3-slurm`

- [ ] **Step 1: Add the core `_submit_job` (config-driven, `if False:` removed)**

Insert into `extensions/xr3-slurm/xr3-slurm`:

```python
def _submit_job(
    path: Path,
    cluster: Optional[str],
    dry: bool = False,
    check_existing_jobs: bool = False,
    observe: bool = False,
    restart_failed: bool = False,
    verbose: int = 0,
) -> bool:
    path = path.absolute()
    done_file = path / "output" / "done"

    if done_file.is_file():
        done_state = xr3slurmlib.parse_done_state(done_file.read_text())
        if done_state == "restart":
            if verbose >= 3:
                print("restart requested")
        elif done_state == "failed" and restart_failed:
            if verbose >= 2:
                print("restarting failed job")
            if not dry:
                done_file.write_text("restart\n")
        else:
            return False

    script = path / "run.sh"
    if not script.exists():
        raise click.ClickException("No run script.")

    full_id = path.name
    try:
        uuid.UUID(full_id)
    except ValueError:
        raise click.ClickException("Job directory is not a valid UUID.")

    if check_existing_jobs:
        squeue_output = _capture(cluster, f"squeue --noheader --name={full_id}")
        if squeue_output.strip():
            if verbose >= 3:
                print(f"Job is already in queue:\n{squeue_output}")
            return False

    slurm_cfg = _slurm_config()
    command = xr3slurmlib.build_sbatch_command(
        script_path=str(script),
        job_dir=str(path),
        full_id=full_id,
        is_array=xr3slurmlib.is_array_job(script.read_text()),
        exclude_nodes=slurm_cfg["exclude_nodes"],
        partition=slurm_cfg["partition"],
        mem=slurm_cfg["mem"],
    )

    if dry:
        if verbose >= 1:
            print(f"Would submit job {full_id}:")
        print(command)
        return True

    os.makedirs(path / "output", exist_ok=True)
    cmd = _run(cluster, command, capture=True)
    print(command)
    cmd.start()
    output = cmd.output
    print(output)

    if observe:
        match = re.match(r"^Submitted batch job (.*)$", output)
        if not match:
            print("Observing failed: Unable to get job id from job.")
        else:
            job_id = match.group(1)
            print("Sleeping for 5s before attaching...")
            time.sleep(5)
            _sattach_wait(job_id, cluster=None)
    return True
```

- [ ] **Step 2: Add the merged `submit` command**

Insert into `extensions/xr3-slurm/xr3-slurm`:

```python
@cli.command()
@click.argument("job_ids", type=click.UUID, nargs=-1)
@click.option("--tag", "-t", "tags", multiple=True, type=str,
              help="Select jobs by tag ($all). Combine with JOB_IDS or --query.")
@click.option("--query", "-q", "queries", type=str, multiple=True,
              help="JSON query fragment to select jobs. Repeatable.")
@click.option("--dry/--no-dry", default=False)
@click.option("--check-existing-jobs/--no-check-existing-jobs", default=False,
              help="Skip jobs already in the queue.")
@click.option("-r", "--restart-failed/--no-restart-failed", default=False)
@click.option("--cluster", "-c", default=None,
              help='sbatch host. Default: slurm.submit_host. Pass "" to submit locally.')
@click.option("-o", "--observe/--no-observe", default=False,
              help="Attach to the job after submitting (single job only).")
def submit(job_ids, tags, queries, dry, check_existing_jobs, restart_failed, cluster, observe):
    """Submit jobs to SLURM, selected by JOB_IDS and/or --tag/--query."""
    if cluster is None:
        cluster = _slurm_config()["submit_host"]
    if not cluster:            # "" or null => submit locally
        cluster = None

    repository = r3.Repository(os.environ["R3_REPOSITORY"])
    paths = []

    for job_id in job_ids:
        paths.append(repository.path / "jobs" / str(job_id))

    if tags or queries:
        query = _build_query(tags, queries)
        print(f"Selecting jobs with query:\n{json.dumps(query, indent=2)}")
        found = repository.find(query=query)
        for job in found:
            print(f"  {job.id}: {job.metadata.get('tags', ['no tags'])[0]}")
            paths.append(Path(job.path))

    if not paths:
        raise click.ClickException("No jobs selected (give JOB_IDS, --tag, or --query).")
    if observe and len(paths) > 1:
        raise click.ClickException("Can't observe more than one job at once.")

    for path in paths:
        _submit_job(
            Path(path), cluster=cluster, dry=dry,
            check_existing_jobs=check_existing_jobs,
            restart_failed=restart_failed, observe=observe,
        )
```

- [ ] **Step 3: Characterize the constructed command with `--dry`**

Run:
```bash
eval "$XR3_SLURM submit $(basename $(ls -d $R3_REPOSITORY/jobs/* | head -1)) --dry"
```
Expected: prints a `sbatch --job-name=<uuid> --comment=... --chdir=... --output=.../output/slurm_%J.log --error=... --exclude=galvani-cn221,galvani-cn240 .../run.sh` line (or, if that job has `output/done` without `restart`, nothing — try another job id or one without a done marker). No SSH occurs on `--dry`.

- [ ] **Step 4: Verify tag selection resolves (dry)**

Run: `eval "$XR3_SLURM submit --tag mkuemmerer31 --dry --no-check-existing-jobs" 2>&1 | head -20`
Expected: prints the query JSON and a list of matched `uuid: tag` lines, then dry `sbatch` lines (or skips for done jobs). No traceback.

- [ ] **Step 5: Commit**

```bash
git add extensions/xr3-slurm/xr3-slurm
git commit -m "feat(xr3-slurm): merged submit (job-ids + tag/query), config-driven sbatch"
```

---

### Task 5: `status` command

**Files:**
- Modify: `extensions/xr3-slurm/xr3-slurm`

- [ ] **Step 1: Add the squeue-scan helper + `status`**

Insert into `extensions/xr3-slurm/xr3-slurm`:

```python
def _running_jobs_by_name() -> dict:
    """{job_name: (slurm_id, state)} across all configured headnodes."""
    running = {}
    for cluster in _slurm_config()["headnodes"]:
        output = _capture(cluster, "squeue --me --noheader --format='%j|%i|%T'")
        for line in output.split("\n"):
            if not line.strip():
                continue
            job_name, job_id, job_state = line.split("|")
            running[job_name] = (job_id, job_state)
    return running


def _remove_common_prefix(strings: List[str]) -> List[str]:
    """Trim the shared leading prefix from all strings (for compact display)."""
    if not strings:
        return strings
    i = 0
    for i in range(len(strings[0])):
        if not all(s.startswith(strings[0][:i]) for s in strings):
            break
    return [s[i - 1:] for s in strings]


@cli.command()
@click.option("--summary/--no-summary", default=True)
@click.option("--details/--no-details", default=True)
@click.argument("tags", nargs=-1)
def status(summary, details, tags):
    """Show done/running status for jobs whose tags match the given globs."""
    repository = r3.Repository(os.environ["R3_REPOSITORY"])
    query = {"$and": [{"tags": {"$glob": tag}} for tag in tags]}
    jobs = repository.find(query=query)

    if not jobs:
        print("No jobs found.")
        return

    running = _running_jobs_by_name()

    def check_job_status(job):
        done_file = job.path / "output" / "done"
        state = ""
        if done_file.is_file():
            classified = xr3slurmlib.parse_done_state(done_file.read_text())
            state = classified  # 'restart' | 'failed' | 'done'
        cluster_job_id, cluster_state = running.get(job.id, (None, None))
        return state, cluster_job_id, cluster_state

    job_names = _remove_common_prefix([job.metadata["tags"][0] for job in jobs])
    data = []
    for job, job_name in zip(tqdm(jobs, delay=10), job_names):
        state, cluster_job_id, cluster_state = check_job_status(job)
        data.append({
            "job_name": job_name, "job_state": state,
            "cluster_job_id": cluster_job_id, "cluster_state": cluster_state,
        })

    if summary:
        summary_states = []
        for item in data:
            parts = [item[k] for k in ("job_state", "cluster_state") if item[k]]
            summary_states.append("-".join(parts))
        for key, value in Counter(summary_states).items():
            print(f"{key}: {value}")

    if details:
        for item in sorted(data, key=lambda i: i["job_name"]):
            jid = item["cluster_job_id"] or ""
            cstate = item["cluster_state"] or ""
            print(f"{item['job_name']}: {item['job_state']} {jid} {cstate}")
```

- [ ] **Step 2: Smoke-test (SSHes to headnode — expect real output or a clean SSH message)**

Run: `eval "$XR3_SLURM status 'research/experiments/2026-08-04_DAEMONS-in-pysaliency*'" 2>&1 | head -20`
Expected: either a summary/details listing, or `No jobs found.`; no Python traceback. (SSH to galvani may print its own status; that's fine.)

- [ ] **Step 3: Commit**

```bash
git add extensions/xr3-slurm/xr3-slurm
git commit -m "feat(xr3-slurm): status command with config-driven headnodes"
```

---

### Task 6: `watch` command (job-name/id primitive + `--tag` mode)

**Files:**
- Modify: `extensions/xr3-slurm/xr3-slurm`

- [ ] **Step 1: Add the job-lookup helper, the tag-mode loop, and `watch`**

Insert into `extensions/xr3-slurm/xr3-slurm`:

```python
def _find_slurm_job(job_name: str):
    """Return (cluster, slurm_id) for the first headnode with this job name."""
    for cluster in _slurm_config()["headnodes"]:
        output = _capture(
            cluster, f"squeue --me --noheader --format=%i --name={job_name}"
        )
        if output.strip():
            return cluster, output.strip()
    return None, None


def _all_slurm_jobs():
    """List of (cluster, job_name, slurm_id, state) across all headnodes."""
    jobs = []
    for cluster in _slurm_config()["headnodes"]:
        output = _capture(cluster, "squeue --me --noheader --format='%j|%i|%T'")
        for line in output.split("\n"):
            if not line.strip():
                continue
            job_name, job_id, job_state = line.split("|")
            jobs.append((cluster, job_name, job_id, job_state))
    return jobs


def _watch_by_tag(tags, selection: str) -> None:
    repository = r3.Repository(os.environ["R3_REPOSITORY"])
    last_state = None
    last_state_change = datetime.now()
    while True:
        jobs = repository.find(query={"tags": {"$all": list(tags)}})
        if not jobs:
            if last_state != "no_jobs_found":
                last_state = "no_jobs_found"
                last_state_change = datetime.now()
            print(f"No jobs found for {datetime.now() - last_state_change}\r", end="", flush=True)
            sleep(10)
            continue

        print(f"found {len(jobs)} matching r3 jobs")
        if selection == "oldest":
            job = jobs[0]
        elif selection == "newest":
            job = jobs[-1]
        elif selection in ("oldest-running-job", "newest-running-job"):
            cluster_jobs = sorted(_all_slurm_jobs(), key=lambda x: int(x[2]))
            if selection == "newest-running-job":
                cluster_jobs = list(reversed(cluster_jobs))
            by_id = {job.id: job for job in jobs}
            matching = [e for e in cluster_jobs if e[1] in by_id]
            print(f"found ({len(matching)}) jobs in clusters")
            running = [e for e in matching if e[-1] == "RUNNING"]
            print(f"found ({len(running)}) running jobs in clusters")
            if not running:
                sleep(10)
                continue
            job = by_id[running[0][1]]
        else:
            raise click.ClickException("Invalid selection.")

        print(f"Attaching to job {job.id}...")
        for tag in job.metadata["tags"]:
            print(f"- {tag}")
        sleep(5)
        cluster, slurm_id = _find_slurm_job(job.id)
        if cluster is None:
            if last_state != "job_not_in_queue":
                last_state = "job_not_in_queue"
                last_state_change = datetime.now()
            print(f"Job not found in queue for {datetime.now() - last_state_change}\r", end="", flush=True)
            sleep(10)
            continue
        if last_state != "jobs_in_queue":
            last_state = "jobs_in_queue"
            last_state_change = datetime.now()

        print(f"Attaching to job {slurm_id} on {cluster}...")
        try:
            _sattach_wait(slurm_id, cluster=None)
        except ExternalCommandFailed:
            print("sattach failed")
        sleep(10)


@cli.command()
@click.argument("job_name_or_id", required=False)
@click.option("--tag", "-t", "tags", multiple=True, type=str,
              help="Watch by r3 tag ($all) instead of a job name/id.")
@click.option("--newest", "selection", flag_value="newest", default=True)
@click.option("--oldest", "selection", flag_value="oldest")
@click.option("--oldest-running-job", "selection", flag_value="oldest-running-job")
@click.option("--newest-running-job", "selection", flag_value="newest-running-job")
def watch(job_name_or_id, tags, selection):
    """Attach to a SLURM job by name/id, or by r3 --tag selection.

    Compose with xr3: `xr3-slurm watch $(xr3 history --latest --id .)`.
    """
    if job_name_or_id and tags:
        raise click.ClickException("Give either a job name/id or --tag, not both.")
    if job_name_or_id:
        _sattach_wait(job_name_or_id, cluster=None)
    elif tags:
        _watch_by_tag(tags, selection)
    else:
        raise click.ClickException("Give a job name/id or --tag.")
```

- [ ] **Step 2: Verify argument validation (no live SLURM needed)**

Run:
```bash
eval "$XR3_SLURM watch --help"
eval "$XR3_SLURM watch somename --tag x" 2>&1 | tail -2
eval "$XR3_SLURM watch" 2>&1 | tail -2
```
Expected: help shows the positional arg + `--tag`/selection flags; the second prints `Error: Give either a job name/id or --tag, not both.`; the third prints `Error: Give a job name/id or --tag.`

- [ ] **Step 3: Commit**

```bash
git add extensions/xr3-slurm/xr3-slurm
git commit -m "feat(xr3-slurm): watch by job-name/id primitive + optional --tag mode (typo fixed)"
```

---

### Task 7: Delete SLURM code from `xr3` + import cleanup (golden-gated)

**Files:**
- Modify: `extensions/xr3/xr3`

- [ ] **Step 1: Capture the pre-deletion golden baseline is already fixed**

The golden baseline (`dev/golden/baseline/`) was captured at Phase 0 and must NOT be re-captured. Proceed to deletion.

- [ ] **Step 2: Delete the SLURM code from `extensions/xr3/xr3`**

Remove these definitions entirely (identify by name; line numbers approximate):
- `HEADNODES` constant (~line 26)
- the `submit` group + `submit_query` + `submit_jobs` (~1452–1495)
- `_submit_job` (~1499, including the dead `if False:` block)
- `check_for_slurm_job` (~1602)
- `get_all_slurm_jobs` (~1613)
- `watch` + `_watch` (~1628–1714)
- `status` (~1717)
- `make_external_command` (~1821)

Leave everything else (`_check_git_*`, `diff`, `files`, `find`, `history`, `check`, `commit`, `dev-checkout`, `dev-cleanup`, `git-check`, `_build_query`, and the `if __name__` block) untouched.

- [ ] **Step 3: Remove now-unused imports from `extensions/xr3/xr3`**

Edit the import block:
- Line 1: `from collections import Counter` → **delete** (Counter only used by `status`).
- Line 8: `import time` → **delete** (only `time.sleep` in `_submit_job`).
- Line 13: `from time import sleep` → **delete** (only used by `_watch`).
- Line 18: `from executor import ExternalCommandFailed, execute, ExternalCommand` → change to `from executor import ExternalCommandFailed, execute` (`ExternalCommand` was SLURM-only).
- Line 19: `from executor.ssh.client import RemoteCommand` → **delete** (SLURM-only).
- Line 20: `from tqdm import tqdm` → **delete** (only used by `status`).

Keep: `json`, `os`, `re`, `shutil`, `sys`, `datetime`, typing, `uuid`, `Path`, `yaml`, `click`, `r3`, `ExternalCommandFailed`, `execute`, `functools`, `xr3config`, `xr3pathmap`.

- [ ] **Step 4: Verify `xr3` still imports and lists only its kept commands**

Run: `eval "$XR3 --help"`
Expected: usage banner with NO `submit`/`status`/`watch` commands; no `NameError`/`ImportError`. (If an `ImportError` for a removed name appears, a kept function still references it — re-check Step 3.)

- [ ] **Step 5: Run the xr3 golden harness — the hard gate**

Run: `eval "XR3=\"$XR3\" bash dev/xr3_golden.sh check"`
Expected: `ALL DATA COMMANDS IDENTICAL`. The informational `help.txt` diff will additionally show `submit`/`status`/`watch` removed — expected. If any data-command diff appears, a kept command was disturbed — revert and narrow the deletion.

- [ ] **Step 6: Run the xr3 pure unit tests (must stay green)**

Run: `python -m pytest extensions/xr3/tests/ -q`
Expected: PASS (10 passed).

- [ ] **Step 7: Confirm xr3-slurm still stands alone**

Run:
```bash
eval "$XR3_SLURM --help"
python -m pytest extensions/xr3-slurm/tests/ -q
```
Expected: `submit`/`status`/`watch` listed; `6 passed`.

- [ ] **Step 8: Commit**

```bash
git add extensions/xr3/xr3
git commit -m "refactor(xr3): remove SLURM code (extracted to xr3-slurm) + unused imports"
```

---

### Task 8: Retire the raw-material sattach sources

**Files:**
- Delete: `raw-material/sattachx`, `raw-material/sattachx_wait`

- [ ] **Step 1: Confirm they are fully absorbed**

Their logic now lives in `xr3slurmlib.parse_sattach_step`/`parse_running_step` + the CLI `_sattach`/`_sattach_wait`/`_get_job_*`. Remove the staged copies.

Run: `git rm raw-material/sattachx raw-material/sattachx_wait`

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: drop raw-material sattach sources (absorbed into xr3-slurm)"
```

---

## Self-Review notes

- **Spec coverage:** submit-merge (§3, Task 4), watch primitive+tag mode+typo fix (§4, Task 6), sattach absorption + shebang removal (§5, Tasks 2–3), config-driven galvani specifics (§6, Task 1), done-marker centralization (§7, Task 2), `if False:` cleanup (§8, Task 4), golden-gated deletion (Task 7). All covered.
- **Out of scope (Phase 4):** `watch --path` glob (roadmap), SSH-minimization / read-only-local-squeue (spec §10 roadmap), moving `run_job_locally` (Phase 5), the CONTRACT.md/docs (Phase 6). Not implemented here.
- **Type consistency:** `_run`/`_capture`/`_sattach`/`_sattach_wait`/`_get_job_id`/`_get_job_state`/`_find_slurm_job`/`_all_slurm_jobs`/`_running_jobs_by_name`/`_submit_job` signatures are used consistently across tasks; `xr3slurmlib` function names match between tests (Task 2) and callers (Tasks 3–5).
- **Verification honesty:** no live `sbatch`/`sattach` runs in tests; behavior is pinned by (a) pure unit tests on the constructible parts, (b) `--dry` characterization of the submit command string, (c) `--help`/validation smoke, (d) the xr3 golden proving the *kept* tool is byte-identical.
