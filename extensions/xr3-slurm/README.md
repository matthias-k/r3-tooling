# xr3-slurm — SLURM submission & observation for r3 jobs

`xr3-slurm` submits committed r3 jobs to SLURM and watches them run. Unlike `xr3` (cluster-agnostic), this
tool is **MLCloud-specific** — galvani today, portable to ferranti and other SLURM clusters purely through
config. It is a single Python script (`xr3-slurm`) plus a pure, unit-tested helper module
(`xr3slurmlib.py`); it absorbs the old `sattachx`/`sattachx_wait` attach helpers.

> **Assumptions.** `xr3-slurm` assumes a `slurm:` config section, SSH access to the headnode, committed
> jobs (dir named by UUID) with a `run.sh`, and — importantly — the **`output/done` marker convention**
> that drives resubmit idempotency and status. All of these, with *what breaks if you don't*, are in
> **[../CONTRACT.md](../CONTRACT.md)**. Read that first.

## What it does

| Command | What it does |
|---|---|
| `submit` | Submit jobs selected by `JOB_IDS` and/or `--tag`/`--query`. Sets `--job-name=<r3 id>`, config-driven `--exclude`, array-aware `--output`. Skips already-`done` jobs (`--restart-failed` to retry `failed` ones). `--dry` prints the `sbatch` command without submitting. Per-invocation `--partition`/`--mem`/`--verbose`; `--observe` attaches after submit. |
| `status` | For jobs whose `tags` match the given GLOBs: show `done`/`restart`/`failed` (from `output/done`) alongside live SLURM state (via `squeue` across configured headnodes). `--summary`/`--details`. |
| `watch` | Attach to a running job by **SLURM job name/id** (positional) — composes with `xr3`: `xr3-slurm watch $(xr3 history --latest --id .)`. Or `--tag` family mode (`--newest`/`--oldest`/`--newest-running-job`/`--oldest-running-job`) to select from matching r3 jobs. |

Run `xr3-slurm <command> --help` for the full flag reference.

### `submit` — local vs headnode

`sbatch` needs a submission host, so `submit` defaults to **SSH-to-headnode** (`slurm.submit_host`). To
submit locally when you're already on the headnode, pass `--cluster ""` (or set `submit_host: null`).
Job selection unions explicit `JOB_IDS` with `--tag`/`--query` matches (de-duplicated).

## Config

`xr3-slurm` reads only the **`slurm:`** section of `~/.config/xr3.yaml` (`$XR3_CONFIG` to override); `xr3`'s
own sections are ignored here. See **[../xr3/xr3.example.yaml](../xr3/xr3.example.yaml)**:

```yaml
slurm:
  headnodes: ["galvani"]   # hosts to SSH for squeue/sacct (status, watch --tag)
  submit_host: galvani     # sbatch SSH target; null (or --cluster "") to submit locally
  exclude_nodes: []        # e.g. ["galvani-cn221", "galvani-cn240"]
  partition: null          # default --partition (per-submit --partition overrides)
  mem: null                # default --mem (per-submit --mem overrides)
```

## The `output/done` marker (why it matters)

`xr3-slurm` — and `xr3 commit --copy-previous-output`/`--exclude-done` — assume each job's `run.sh` writes
`output/done` on completion. `submit` uses it for **idempotent resubmit** (skip finished jobs; body
`restart` forces a rerun; body `failed` + `--restart-failed` retries), and `status` reads it for the job's
done state. See [../CONTRACT.md](../CONTRACT.md).

## Invocation

Runs through your r3 Python environment (imports `r3`/`executor`/`tqdm`); `submit`/`status`/`watch --tag`
need `R3_REPOSITORY` (plain `watch <name/id>` talks only to SLURM). Put it on your `PATH` like `xr3`.

## Roadmap

Minimize headnode SSH (run read-only `squeue`/`sacct` locally on a compute node, SSH only for `sbatch`);
`watch --path` GLOB selector; fold in `run_job_locally`. See the design spec §10.
