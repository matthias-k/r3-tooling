#!/usr/bin/env python3
"""Submit grid cells to SLURM up to a concurrency cap, resumably.

The point of this script (vs. a one-shot `sbatch` loop) is to stay under the cluster's submit
limit (e.g. AssocMaxSubmitJobLimit): it counts what's already queued/running and what's already
finished (per-batch `output/done_batch_*` markers), then submits only enough missing work to fill
the free slots. Re-run it until everything is done — each run makes progress and nothing is
double-submitted.

Array cells declare TOTAL_BATCH_COUNT; each batch writes its own done marker, so a resumed run
submits only the missing batches of each cell.

Usage:
  python auto_submit.py --status          # show done / remaining per cell
  python auto_submit.py --dry-run         # show what WOULD be submitted
  python auto_submit.py --max-jobs 100    # submit up to 100 concurrent, then stop
"""
import argparse
import os
import subprocess
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
TASKS = HERE / "tasks"
DEFAULT_MAX_JOBS = 100


def main_tag_of(cell: Path) -> str:
    return yaml.safe_load((cell / "metadata.yaml").read_text())["tags"][0]


def committed_job_dir(main_tag: str):
    """The committed r3 job dir for a cell, or None if it isn't committed yet."""
    jid = subprocess.run(
        ["r3", "find", f"--tag={main_tag}", "--latest"], capture_output=True, text=True
    ).stdout.strip()
    if not jid:
        return None
    return Path(os.environ["R3_REPOSITORY"]) / "jobs" / jid


def total_batches(job_dir: Path) -> int:
    """Read TOTAL_BATCH_COUNT from the cell's run.sh (1 = single-task cell)."""
    for line in (job_dir / "run.sh").read_text().splitlines():
        s = line.strip()
        if s.startswith("TOTAL_BATCH_COUNT=") and "PLACEHOLDER" not in s:
            val = s.split("=", 1)[1].strip()
            return int(val) if val else 1
    return 1


def remaining_batches(job_dir: Path, n: int) -> list:
    """Batches with no output/done_batch_<i> marker yet (n == 1 → the single task)."""
    out = job_dir / "output"
    done = {int(p.name.rsplit("_", 1)[1]) for p in out.glob("done_batch_*")}
    if n == 1:
        return [] if (out / "done").exists() else [0]
    return [i for i in range(n) if i not in done]


# --- the two scheduler-specific pieces: adapt to your cluster -----------------
def free_slots(max_jobs: int) -> int:
    """How many more jobs we may have queued/running at once."""
    out = subprocess.run(
        ["squeue", "-h", "-u", os.environ["USER"], "-o", "%i"], capture_output=True, text=True
    ).stdout
    active = len([line for line in out.splitlines() if line.strip()])
    return max(0, max_jobs - active)


def submit(job_dir: Path, batches: list) -> None:
    """Submit the given batch indices of a cell as a SLURM array."""
    array = ",".join(str(b) for b in batches)
    subprocess.run(["xr3-slurm", "submit", job_dir.name, "--array", array], check=True)
# -----------------------------------------------------------------------------


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--status", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--max-jobs", type=int, default=DEFAULT_MAX_JOBS)
    args = ap.parse_args()

    slots = free_slots(args.max_jobs)
    print(f"free slots: {slots}")

    for cell in sorted(p.parent for p in TASKS.glob("*/*/metadata.yaml")):
        rel = cell.relative_to(HERE)
        job_dir = committed_job_dir(main_tag_of(cell))
        if job_dir is None:
            print(f"not committed: {rel} (run setup_tasks.py --commit)")
            continue

        n = total_batches(job_dir)
        todo = remaining_batches(job_dir, n)
        if not todo:
            print(f"done: {rel}")
            continue
        if args.status:
            print(f"remaining {len(todo)}/{n}: {rel}")
            continue

        take = todo[:slots]
        if not take:
            print("slot cap reached; re-run later to continue")
            break
        print(f"submit {len(take)} batch(es) of {rel}: {take}")
        if not args.dry_run:
            submit(job_dir, take)
            slots -= len(take)


if __name__ == "__main__":
    main()
