# compute-job — a minimal compute-job skeleton

The smallest **compute** job: read a config, read its dependencies, write results to `output/`.
Copy it as the starting point for an experiment's `compute/` job.

## Files
- `run.sh` — the portable runner (works under SLURM and on a laptop; verbatim the doc's
  template). You rarely edit it beyond the `#SBATCH` header.
- `run_inner.sh` — the logic entrypoint: picks the environment's interpreter and runs `run.py`.
- `run.py` — your computation. The stub reads `config.yaml` and writes `output/results.json`.
- `config.yaml` — knobs, pulled out of the code and committed.
- `r3.yaml` — what this job reads: an **environment** and a **dataset**, each by `path`.
- `metadata.yaml` — editable labels; `tags[0]` is the primary version tag, `path` is the name
  other jobs depend on.
- `SPEC.md` — scope the work before coding (SPEC → PLAN → implement).

## Use
Replace the `PROJECT` / `DATASET` / `DATE_SLUG` / `USER` / `CLUSTER` placeholders, point `r3.yaml`
at a real environment + dataset, then `xr3 check .` and `xr3 commit .`. Run with
`run_job_locally <committed-dir>` (laptop) or `xr3-slurm submit <id>` (SLURM).

## Why this example is deliberately thin
Given only `RESEARCH_WORKFLOW.md`, a fresh session reproduces this skeleton closely — the doc is
the source of truth for the shape. This example exists to save retyping, not to re-teach the doc;
keeping it minimal is what stops the two from drifting.
