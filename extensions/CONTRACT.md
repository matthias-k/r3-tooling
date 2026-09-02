# CONTRACT — what the extensions assume about your r3 jobs

**Read this before using `xr3` / `xr3-slurm` on your jobs.** Bare [r3](https://github.com/mtangemann/r3)
makes almost no assumptions about a job's contents. The house tools in `extensions/` add a few — they buy
you real convenience (see each tool's README for the pitch), but a job that violates an assumption will
make the relevant command fail or misbehave. This file is the **single source of truth** for those
assumptions; the tools link here from their gating errors and `--help`.

Each item says **what it is** and **what breaks if you don't follow it**. Nothing here is required by r3
itself — only by these tools.

---

## Always required (nearly every command)

- **`R3_REPOSITORY` points at your r3 repo.** Set the env var (or pass `--repository`/`REPOSITORY_PATH`
  where a command accepts it). *Breaks:* `find`, `history`, `check`, `commit`, and all of `xr3-slurm` error
  out without it.
- **Python 3 + runtime deps on `PYTHONPATH`.** `xr3` needs `click`, `pyyaml`, `r3`, `executor`; `xr3-slurm`
  additionally needs `tqdm`. *Breaks:* `ImportError` at startup. (Both tools are single-file scripts run
  through your r3 Python environment.)

## For the pathmap-dependent workflow commands (`history`, `diff`, `check`, `commit`)

- **Your working directory maps to an r3 logical path.** These commands derive the job's r3 path from
  *where the working directory lives on disk*, via **pathmap roots** you configure (see
  [xr3 config](xr3/README.md)). Put your project roots in `~/.config/xr3.yaml` (or `$XR3_CONFIG`).
  *Breaks:* the command exits with a "configure a pathmap root … see CONTRACT.md" error. (`find` and
  `files` do **not** need pathmap.)
- **`metadata.path` matches the job's logical location**, and **`tags[0]` = `<path>/vX.Y.Z`** (the primary
  version tag is the path plus a semver). *Breaks:* `xr3 check` fails its path- and tag-consistency asserts
  (and `commit` runs `check` by default).
- **No `bug/…`-tagged dependencies and no non-empty `metadata.WIP`** (both configurable via the `blockers`
  config). *Breaks:* `check`/`dev-checkout` refuse the job.

> Roadmap: `history`/`diff` could instead read `metadata.path` straight from the working dir and skip
> pathmap entirely — see the design spec §10. Until then, they need a pathmap root.

## For `xr3-slurm` (SLURM submission / observation — MLCloud/galvani)

- **A `slurm:` config section.** headnodes, `submit_host` (the sbatch SSH target), node excludes, and
  partition/mem defaults live in `~/.config/xr3.yaml` (see [xr3-slurm](xr3-slurm/README.md)). *Breaks:*
  wrong cluster / no submission host. This is **MLCloud-specific** (galvani today; ferranti and other
  SLURM clusters via config) — not cluster-agnostic like `xr3`.
- **SSH access to the `submit_host`.** `sbatch` (and, by default, `squeue`/`sacct` polling) runs over SSH
  to the headnode. *Breaks:* submission/observation fail if you can't reach the headnode.
- **Committed jobs (dir named by UUID) with a `run.sh`.** `submit` operates on committed r3 job
  directories (whose name is the job's UUID) and submits their `run.sh`. *Breaks:* "not a valid UUID" /
  "No run script".
- **The `output/done` marker convention.** A job's `run.sh` writes `output/done` on completion. The body is
  normally a done sentinel; the special bodies **`restart`** and **`failed`** drive control flow:
  - `submit` **skips** a job whose `output/done` exists (idempotent resubmit), **except** body `restart`
    (always resubmits) or body `failed` with `--restart-failed` (rewrites to `restart`, resubmits).
  - `status` reports `done` / `restart` / `failed` from this file.

  *Breaks:* without the marker, `submit` re-runs finished jobs and `status` can't show completion; the same
  marker is what `xr3 commit --copy-previous-output` / `--exclude-done` rely on.
- **Jobs `xr3-slurm` submits are findable by their r3 id.** `submit` sets `--job-name=<r3 job id>`; `status`
  and `watch` correlate SLURM jobs back to r3 jobs by that name. *Breaks:* if you submit some other way
  without `--job-name=<r3 id>`, `status`/`watch` won't match those jobs.

## For `xr3 diff`

- **GNU `diff`, a pager (`less`), and `PAGER`.** `diff` shells out to the system `diff` and pipes through a
  pager. This is fine on the Linux HPC; **not** portable to macOS/BSD `diff`. *Breaks:* diff rendering off
  the HPC. (In this sense `diff` is "portable" only within the HPC.)

## For `scripts/run_job_locally`

- **The SLURM scratch dir.** It runs a job's `run.sh` against `/scratch_local/<user>-$SLURM_JOB_ID/job`
  (i.e. inside an interactive SLURM allocation, using `$SCRATCH`). *Breaks:* run it outside a SLURM
  allocation and there's no scratch dir.

---

*If a tool ever demands something not listed here, that's a doc bug — please add it.*
