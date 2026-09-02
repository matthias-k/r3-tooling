# xr3 — a development-workflow CLI around r3

`xr3` is a **cluster-agnostic** wrapper that adds the day-to-day *development workflow* on top of bare
[r3](https://github.com/mtangemann/r3): querying the job graph, seeing what changed before you commit,
enforcing the house metadata conventions, and the develop-in-a-working-dir → commit loop. It is a single
Python script (`xr3`) plus small helpers (`xr3config.py`, `xr3pathmap.py`, `xr3diff.py`).

> **Assumptions.** `xr3` places a few requirements on your jobs and environment (a pathmap root, the
> `tags[0]`/`metadata.path` convention, `R3_REPOSITORY`, GNU `diff` for `diff`). They are listed —
> with *what breaks if you don't* — in **[../CONTRACT.md](../CONTRACT.md)**. Read that first.

## What it adds over bare r3

| Command | What it does | Bare r3? |
|---|---|---|
| `find` | Query the repo by `--tag` / `--path` (metadata.path GLOB) / `--query` (JSON), AND-ed; `--latest`, `--long`. | `repository.find`, no path-glob CLI |
| `history` | Version history of the job at a working-dir PATH; `--id` prints just job ids (composes into `xr3-slurm`). | — |
| `diff` | Diff a working dir vs its latest committed version — resolved `r3.yaml`, config, metadata; `--structured`/`--stat`/`--name-only`/`-i`. | — |
| `check` | Enforce house conventions: `path`/`origin` match location, `tags[0]`=`<path>/vN`, no `bug/`-tagged deps, no non-empty `WIP`, git deps clean/pushed. | — |
| `commit` | Freeze deps (queries→UUIDs, git→commits) and commit; runs `check` first; `--copy-previous-output`, `--remove-previous`, `--exclude-done`. | `repository.commit`, no dev-loop conveniences |
| `files` | List the files that *would* be committed for the job at PATH. | — |
| `dev-checkout` | Check dependencies into the working dir for development (real git clones + symlinks); sets up `upstream`. | — |
| `dev-cleanup` | Remove checked-out deps from the working dir (with uncommitted-change safety checks). | — |
| `git-check` | Report git dependencies with uncommitted/unpushed changes. | — |

Run `xr3 <command> --help` for the full flag reference (this README is the map, not the man page).

## Config

`xr3` reads `~/.config/xr3.yaml` (override with `$XR3_CONFIG`); a missing file falls back to defaults.
Copy **[xr3.example.yaml](xr3.example.yaml)** and edit. Sections `xr3` reads:

- **`pathmap.roots`** — the working-dir → r3-path mapping the pathmap-dependent commands (`history`, `diff`,
  `check`, `commit`) need. List each project root; an optional per-root `prefix` is prepended to the
  derived path. *A pathmap-dependent command with no matching root fails gracefully and points here.*
- **`blockers`** — `tags` (tag prefixes that block `check`/`dev-checkout`, default `["bug/"]`) and
  `block_on_wip` (a non-empty `metadata.WIP` fails `check`).
- **`dev_checkout`** — `ignored_destinations` / `ignored_repositories` to skip on checkout.

The SLURM tool reads its own `slurm:` section from the same file — see
[../xr3-slurm/README.md](../xr3-slurm/README.md).

## Invocation

`xr3` runs through your r3 Python environment (it imports `r3`/`executor`). Put it on your `PATH` (a symlink
or a shell function that sets `PYTHONPATH` to your r3 checkout, as you do for `r3` itself). Most commands
need `R3_REPOSITORY` set.
