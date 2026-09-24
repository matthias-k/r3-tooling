# SETUP — installing the full r3 toolchain

This gets `r3`, `xr3`, `xr3-slurm`, and `foreman` all working from everywhere you'd invoke
them — interactive shells, non-interactive shells, `subprocess`/`execvp`, cron, and agent
tool-calls — sharing one Python env, one set of `PATH` wrappers, and one config file. There
are two ways to get there: run the installer (§1, recommended), or do the same steps by hand
(§3, for when you want full control or the installer doesn't fit your setup).

## 0. The r3 skill (for agents)

Install `skills/r3/` where your Claude Code (or codex) finds skills (see the top
[README](README.md)). That's independent of the CLI setup below — `./install.sh
--install-skill` does it for you automatically (symlinking into `~/.claude/skills` and/or
`~/.codex/skills`, see `--skill-target` in §1).

## 1. Quickstart — the installer

```bash
git clone git@github.com:matthias-k/r3-tooling.git r3-tooling && cd r3-tooling
./install.sh --yes        # accept all defaults, no prompts
# or, to preview first:
./install.sh --dry-run
```

**One canonical clone.** The toolchain lives in a single clone at `<toolchain-root>/r3-tooling`
(default `~/r3-toolchain/r3-tooling`, next to the `r3`/`foreman` clones it manages). If you run
`install.sh` from a *different* clone (like the one you just made above), it creates/uses the
canonical clone and re-runs from there, so the wrappers, the skill symlink, and `update.sh` all
point at one place — the clone you started from is then disposable. Use `--no-relocate` to run a
clone in place. Once this repo is public, `bootstrap.sh` makes the first install a one-liner:
`curl -fsSL <raw-url>/bootstrap.sh | bash` (it asks for the toolchain dir and clones there for you).

`./install.sh --help` lists every flag. The installer is **idempotent**: every interactive
prompt has a matching flag, so a saved, fully-flagged command (or `--yes`) doesn't just do a
first install — re-running it later **is** the update command (fast-forward-`git pull`s each
clone, re-syncs the editable installs, refreshes the `PATH` wrappers and the `.bashrc`
blocks). If a clone has local changes or has diverged from its remote, that repo is skipped
with an error rather than silently merged or overwritten — go resolve it by hand and re-run.

You don't have to remember those flags: at the end of every run the installer **prints the
exact `--yes`-flagged command that reproduces this install's settings, and saves it as
`<toolchain-root>/update.sh`** (default `~/r3-toolchain/update.sh`). Run that script any time
to update without prompts — it first `git pull`s the `r3-tooling` checkout itself (the one
step a plain re-run can't do, since the installer doesn't self-update), then re-runs with your
saved settings:

```bash
~/r3-toolchain/update.sh
```

After any run, `source ~/.bashrc` to pick up the new `PATH` and `R3_REPOSITORY`.

Common flags (all have real defaults, so `--yes` alone is a complete install):

- `--toolchain-root DIR` (default `~/r3-toolchain`) — where the `r3`/`foreman` clones and
  the venv live.
- `--bin-dir DIR` (default `~/bin`, or `$LUSTREWORK/bin` if that directory exists) — where
  the `r3`/`xr3`/`xr3-slurm`/`foreman` wrapper scripts are written.
- `--config PATH` (default `~/.config/xr3.yaml`) — the xr3 config file.
- `--projects-dir DIR` (default `~/projects`) — written into the config as a **base root**
  (§4), i.e. the directory whose subdirectories the pathmap covers.
- `--r3-repo DIR` (default `~/r3_repo`) — becomes `R3_REPOSITORY`.
- `--slurm-headnode HOST` (repeatable) / `--slurm-submit-host HOST` / `--no-slurm` — SLURM
  config for `xr3-slurm`, or opt out of it entirely.
- `--clone-proto ssh|https` (default `ssh`) — how `r3` and `foreman` are cloned.
- `--install-skill` / `--no-install-skill` (plus `--skill-target all|claude|codex`) — install
  the r3 agent skill from §0 as part of the same run.

`foreman` is currently a **private** repo, so the default `ssh` clone proto needs your GitHub
SSH key set up (the installer checks this in preflight and warns if it can't confirm access).
Once `foreman` is public, `--clone-proto https` works without any key setup.

## 2. What gets installed

The mental model, in one picture:

- **One shared `uv` venv** (`<toolchain-root>/.venv` by default) with `r3` and `foreman`
  **editable-installed**, plus `xr3`'s own runtime deps (`click`, `pyyaml`, `executor`,
  `tqdm`). r3 requires Python **>=3.9,<3.13**, which is why the installer defaults to
  `--python 3.12`.
- **Wrapper scripts on `PATH`** — `r3`, `xr3`, `xr3-slurm`, `foreman` — each a tiny shell
  script that `exec`s into that venv's interpreter (see §3 for why these are files, not shell
  functions).
- **One config file**, `~/.config/xr3.yaml` by default, with a **base root** over your
  projects directory (plus, unless `--no-slurm`, a `slurm:` section).
- **Optionally**, the r3 skill (§0) symlinked into `~/.claude/skills` and/or
  `~/.codex/skills`.

The clones themselves live under the toolchain root: `<toolchain-root>/r3` and
`<toolchain-root>/foreman`. Note that `r3-tooling` — the repo you cloned to get `install.sh`
and this guide — is a separate thing from those two; it stays wherever you cloned it in
step 1 and is *not* copied into the toolchain root.

## 3. Manual setup

If you'd rather not run the script — or want to understand exactly what it does — here's the
same install as explicit steps.

### 3.1 An environment with a compatible Python

r3 needs Python **>=3.9,<3.13**. Either a conda env or a plain venv works; with
[`uv`](https://docs.astral.sh/uv/):

```bash
uv venv --python 3.12 ~/r3-toolchain/.venv
```

(or `conda create -n r3_lustre python=3.12 && conda activate r3_lustre`, if you prefer conda.)

### 3.2 Clone and editable-install r3 and foreman

```bash
git clone git@github.com:mtangemann/r3.git ~/r3-toolchain/r3
git clone git@github.com:mtangemann/foreman.git ~/r3-toolchain/foreman   # private repo — needs ssh access

uv pip install --python ~/r3-toolchain/.venv/bin/python \
  -e ~/r3-toolchain/r3 -e ~/r3-toolchain/foreman
uv pip install --python ~/r3-toolchain/.venv/bin/python \
  click pyyaml executor tqdm    # xr3 needs click/pyyaml/executor; xr3-slurm also tqdm
```

(swap `uv pip install --python <venv>/bin/python` for `pip install` inside an activated conda
env, if that's what you used in 3.1). Because r3 and foreman are **editable-installed**,
`import r3` / `import foreman` resolve straight to the checkouts with no `PYTHONPATH` needed
— so the wrappers below only pin the interpreter, nothing else.

### 3.3 Invocation — wrapper *scripts* on `PATH` (not shell functions)

**Why not a `~/.bashrc` function?** A function lives in shell state: it's invisible to
`execvp`, so `subprocess.run(["xr3", …])`, cron, `ssh host xr3`, and agent tool-calls never
see it — and it's not defined at all in shells that don't source your rc. A **file on `PATH`**
is what `execvp` resolves, and `PATH` is an exported env var, so it's inherited by every
child process. So: make each tool a tiny wrapper file, put its dir on `PATH` once, and it
resolves by name everywhere.

Create one wrapper per tool. On this cluster, put them in `$LUSTREWORK/bin`, an
always-mounted **shared** Lustre dir — **not** `~/.local/bin`, which is bind-mounted
per-container for `pip --user` isolation and so isn't shared host↔container. (Elsewhere, any
directory you can put on `PATH` works.)

```bash
# $LUSTREWORK/bin/r3
#!/bin/bash
exec ~/r3-toolchain/.venv/bin/r3 "$@"
```

```bash
# $LUSTREWORK/bin/foreman
#!/bin/bash
exec ~/r3-toolchain/.venv/bin/foreman "$@"
```

```bash
# $LUSTREWORK/bin/xr3
#!/bin/bash
exec ~/r3-toolchain/.venv/bin/python \
  /path/to/r3-tooling/extensions/xr3/xr3 "$@"
```

```bash
# $LUSTREWORK/bin/xr3-slurm
#!/bin/bash
exec ~/r3-toolchain/.venv/bin/python \
  /path/to/r3-tooling/extensions/xr3-slurm/xr3-slurm "$@"
```

`chmod +x` all four, then put that dir on `PATH` in `~/.bashrc` (after `$LUSTREWORK` is
defined):

```bash
export PATH="$LUSTREWORK/bin:$PATH"
```

Now `which xr3` resolves to the wrapper, and it works in every context above — no function,
no per-call `PYTHONPATH`/conda discovery.

### 3.4 R3_REPOSITORY

Create and initialize the repository (an empty directory is **not** a valid repo — `r3 init`
writes the `r3.yaml` it needs, and refuses a path that already exists):

```bash
r3 init "$HOME/r3_repo"
```

then point `R3_REPOSITORY` at it in `~/.bashrc`, alongside the `PATH` line from 3.3:

```bash
export R3_REPOSITORY="$HOME/r3_repo"
```

(The installer does both for you: it runs `r3 init` when the repo is absent, or heals a
leftover empty directory in place.)

## 4. Config (pathmap + slurm)

Copy [`extensions/xr3/xr3.example.yaml`](extensions/xr3/xr3.example.yaml) to
`~/.config/xr3.yaml` (on this cluster `~/.config` is on the shared Lustre home, so one file
serves host and container) — or point `$XR3_CONFIG` at it if you keep it elsewhere — and edit
`pathmap.roots` for your layout.

**Base roots.** A `pathmap.roots` entry with no `prefix` is a **base root**: subpaths map
directly, so the first sub-directory under it becomes the first segment of the r3 logical
path. A single base root over `~/projects` therefore covers every project beneath it — you
don't need one root per project. You can list several base roots (they share one path space),
and a root can instead carry an explicit `prefix` if you want its derived paths prefixed.
`~` and `$VARS` in `path` are expanded.

This pathmap is what `history`/`diff`/`check`/`commit` use to turn "the directory you're
standing in" into an r3 logical path (`find` and `files` don't need it). `xr3-slurm` also
reads a `slurm:` section from the same file (headnodes, submit host, node excludes,
partition/mem defaults) — omit it, or pass `--no-slurm` to the installer, if you don't submit
jobs from this machine.

For the full list of assumptions these tools place on your jobs (and what breaks if you don't
follow them), see **[`extensions/CONTRACT.md`](extensions/CONTRACT.md)** — the single source
of truth.

## 5. Verify

```bash
which r3 xr3 xr3-slurm foreman   # -> your bin dir
xr3 --help                       # workflow verbs (find/history/diff/check/commit/dev-*)
xr3-slurm --help                 # submit / status / watch
# from a non-shell caller, the case a function fails:
python3 -c "import subprocess; subprocess.run(['xr3','--help'])"
```

## 6. Remote foreman (optional)

`foreman` is a web GUI for browsing your r3 repository. Run it on the cluster and tunnel it
to your laptop's browser rather than trying to expose it directly. `install.sh` prints a
pre-filled command for this at the end of every run:

```bash
ssh -L 8080:localhost:8080 <host> \
  'R3_REPOSITORY="<r3-repo>" "<bin-dir>/foreman" --port 8080'
# then browse: http://localhost:8080
```

(`<host>` defaults to your `--slurm-submit-host`/first `--slurm-headnode`, `<r3-repo>` to
your `--r3-repo`, `<bin-dir>` to your `--bin-dir` — the installer fills these in for you.)

## What the tools assume about your jobs

See **[extensions/CONTRACT.md](extensions/CONTRACT.md)** — the single source of truth
(the `output/done` marker, `tags[0]`/`metadata.path` conventions, `R3_REPOSITORY`, SLURM
config, GNU `diff`, …), each with *what breaks if you don't*. The per-tool
[`xr3`](extensions/xr3/README.md) / [`xr3-slurm`](extensions/xr3-slurm/README.md) READMEs
are the command reference.
