# grid-search — fan a template job out over a grid, submit it resumably

Two scripts around a `template_job/`:

- **`setup_tasks.py`** — stamps out one ordinary r3 job per grid cell (here `MODELS × DATASETS`):
  copy the template, substitute `{PLACEHOLDERS}`, **merge each cell's own dependencies** into the
  template `r3.yaml`, give each cell a **unique main tag** (so re-running skips committed cells),
  then `xr3 check` + `xr3 commit`. A sweep is just many ordinary jobs — no sweep system.
- **`auto_submit.py`** — submits cells to SLURM **up to a concurrency cap, resumably**: it counts
  what's already queued/running and what's already finished (`output/done_batch_*` markers) and
  submits only the missing work. Re-run until done; this is how you stay under the cluster's
  submit limit (e.g. `AssocMaxSubmitJobLimit`) for a large sweep.

`template_job/` is itself a compute job (see [`../compute-job/`](../compute-job/)) with `{BRACES}`
placeholders and an optional **array/batch mode** (`--batch-index`/`--batch-count`) so one heavy
cell can run as a SLURM array over batches.

## Use
1. Edit the axes (`MODELS`, `DATASETS`) and `per_cell_dependencies()` in `setup_tasks.py`.
2. `python setup_tasks.py --dry-run`, then `python setup_tasks.py --commit`.
3. `python auto_submit.py --status`, then `python auto_submit.py --max-jobs N` (re-run to finish).

## Adapt points (don't copy blindly)
- `free_slots()` and `submit()` in `auto_submit.py` are the only scheduler-specific pieces — point
  them at your `squeue` / `xr3-slurm`.
- To compose the finished sweep, a single `find_all` over the cells' shared tag reads each cell's
  committed results — **read them, don't hand-copy them** (the provenance invariant;
  RESEARCH_WORKFLOW.md).
