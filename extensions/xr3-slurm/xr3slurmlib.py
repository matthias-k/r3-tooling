"""Pure SLURM string/parse helpers for xr3-slurm.

Stdlib only (no r3/executor) so it is unit-testable in base Python.
The xr3-slurm CLI does all I/O; this module does all parsing/formatting.
"""
from __future__ import annotations

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
    """First `N.M` step id from `sacct -j <id>` output (was sattachx's awk).

    Matches numeric steps only (`.0`, `.1`, ...), skipping pseudo-steps like
    `.batch` and `.extern` -- sattach must attach to the real srun compute
    step, never the batch/extern steps.
    """
    for line in sacct_output.split("\n"):
        parts = line.split()
        first = parts[0] if parts else ""
        if re.match(r"^[0-9]+\.[0-9]+", first):
            return first
    return None


def parse_running_step(sacct_p_output: str) -> Optional[int]:
    """Step number from the last row of `sacct -j <id> -P`, or None.

    Mirrors sattachx_wait.get_job_state: split last line on '|', take field 0,
    and if it is `<jobid>.<step>` return int(step) else None.
    """
    lines = [line for line in sacct_p_output.strip().split("\n") if line.strip()]
    if not lines:
        return None
    step_id = lines[-1].split("|")[0]
    if "." not in step_id:
        return None
    try:
        return int(step_id.split(".", 1)[1])
    except ValueError:
        return None
