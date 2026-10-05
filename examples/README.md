# examples

Copy-and-adapt starting points for the pieces the
[`RESEARCH_WORKFLOW.md`](../RESEARCH_WORKFLOW.md) describes. These are examples to
learn from and lift, not a library to depend on — keep them **generic and
cluster-agnostic** (no personal paths, no project-specific dependencies, no
hard-coded SLURM partitions). The workflow doc remains the source of truth;
examples just save you retyping.

## Available

- **[`report/`](report/)** — the house report scaffold: `report.qmd` + `styles.css`
  with the standard section layout (`tl;dr` → Introduction / Method / Results /
  Discussion / Follow up ideas / Appendix). See [`report/README.md`](report/README.md).

## To come

Real but currently project-coupled; to be genericized as they're needed (mostly
workshop-driven):

- **Singularity container job** — a minimal container-backed compute job (the
  `run_inner.sh` `run_in_container` pattern) plus an example container build script.
- **venv environment job** — a venv-based environment provider r3 job, for running
  off-cluster / on a laptop without Singularity (the off-cluster environment swap).
- **`setup_jobs.py` / `auto_submit.py`** — the `template_job/` + `tasks/` matrix
  fan-out helpers for grids / ablations / sweeps, repointed at `xr3` / `xr3-slurm`
  (they currently call the obsolete monolith).
