# extensions — the house layer on top of the pure r3 skill

Everything here builds on `../skills/r3/` (the pure r3 skill) and is deliberately kept *out* of it, so the
pure skill stays upstream-ready.

> **These tools add assumptions to your r3 jobs.** What they demand — and what breaks if a job doesn't
> comply — is the single source of truth in **[CONTRACT.md](CONTRACT.md)**. Read it before running the
> tools on your jobs.

## What's here

- **[`xr3/`](xr3/README.md)** — the **cluster-agnostic** development-workflow CLI: `find`, `history`,
  `diff`, `check`, `commit`, `files`, `dev-checkout`/`dev-cleanup`, `git-check`. (`xr3` + `xr3config.py`,
  `xr3pathmap.py`, `xr3diff.py`.)
- **[`xr3-slurm/`](xr3-slurm/README.md)** — **MLCloud-specific** SLURM submission & observation:
  `submit`, `status`, `watch` (absorbs `sattachx`/`sattachx_wait`). (`xr3-slurm` + `xr3slurmlib.py`.)
- **`scripts/run_job_locally`** — run a job's `run.sh` inside an interactive SLURM allocation (uses the
  scratch dir).
- **[`CONTRACT.md`](CONTRACT.md)** — the assumptions the tools place on jobs.
- **`research-workflow-additions.md`** — house conventions to fold into `RESEARCH_WORKFLOW.md`.

The two tools share one config file (`~/.config/xr3.yaml`, or `$XR3_CONFIG`); each reads only its own
sections. Copy [`xr3/xr3.example.yaml`](xr3/xr3.example.yaml) to start.

Rule of thumb: if it mentions `xr3`, a container, SLURM, `g`, or a house convention, it's an extension; if
it's true of vanilla r3, it belongs in the pure skill.
