# SETUP — installing the r3 tooling (skill + extensions)

How to make `r3`, `xr3`, and `xr3-slurm` usable from everywhere: interactive shells,
**and** the places a shell *function* silently fails — non-interactive shells,
`subprocess`/`execvp`, cron, and agent/subagent tool-calls.

> Paths below are for this repo's maintainer (galvani/MLCloud, Lustre home). Colleagues:
> substitute your own Python env and checkout locations — the *shape* is what matters.

## 0. The r3 skill (for agents)

Install `skills/r3/` where your Claude Code finds skills (see the top [README](README.md)).
That's independent of the CLI setup below.

## 1. Python environment

The tools run under one Python env with **r3 editable-installed** and their deps:

```bash
conda create -n r3_lustre python=3.12       # (or your existing env)
conda activate r3_lustre
pip install -e /mnt/lustre/work/bethge/mkuemmerer31/r3   # r3, editable -> import r3 needs no PYTHONPATH
pip install click pyyaml executor tqdm       # xr3 needs click/pyyaml/executor; xr3-slurm also tqdm
```

Because r3 is **editable-installed**, `import r3` resolves to the checkout with no
`PYTHONPATH` — so the wrappers below only pin the interpreter, nothing else. (If you
instead keep r3 as a bare checkout, add `PYTHONPATH=<r3-checkout>` to the wrappers.)

## 2. Invocation — wrapper *scripts* on `PATH` (not shell functions)

**Why not a `~/.bashrc` function?** A function lives in shell state: it's invisible to
`execvp`, so `subprocess.run(["xr3", …])`, cron, `ssh host xr3`, and agent tool-calls
never see it — and it's not defined at all in shells that don't source your rc. A **file
on `PATH`** is what `execvp` resolves, and `PATH` is an exported env var, so it's
inherited by every child process. So: make each tool a tiny wrapper file, put its dir on
`PATH` once, and it resolves by name everywhere.

Create one wrapper per tool (here in `$LUSTREWORK/bin`, an always-mounted **shared**
Lustre dir — **not** `~/.local/bin`, which on this cluster is bind-mounted per-container
for `pip --user` isolation and so isn't shared host↔container):

```bash
# $LUSTREWORK/bin/xr3
#!/bin/bash
exec /mnt/lustre/work/bethge/mkuemmerer31/miniconda3/envs/r3_lustre/bin/python \
  /mnt/lustre/work/bethge/mkuemmerer31/projects/research/tools/r3-tooling/extensions/xr3/xr3 "$@"
```

…and likewise `xr3-slurm` (→ `extensions/xr3-slurm/xr3-slurm`) and `r3`
(→ `$LUSTREWORK/r3/r3/cli.py`). `chmod +x` all three.

Then put that dir on `PATH` in `~/.bashrc` (after `$LUSTREWORK` is defined):

```bash
export PATH="$LUSTREWORK/bin:$PATH"
```

Now `which xr3` resolves to the wrapper, and it works in every context above — no
function, no per-call `PYTHONPATH`/conda discovery.

## 3. Config

Copy [`extensions/xr3/xr3.example.yaml`](extensions/xr3/xr3.example.yaml) to
`~/.config/xr3.yaml` (on this cluster `~/.config` is on the shared Lustre home, so one
file serves host and container) and fill in your **pathmap roots** (working-dir → r3-path
mapping for `history`/`diff`/`check`/`commit`) and, for `xr3-slurm`, your `slurm:` section.
Point `$XR3_CONFIG` at it instead if you keep it elsewhere.

## 4. Verify

```bash
which r3 xr3 xr3-slurm          # -> $LUSTREWORK/bin/...
xr3 --help                      # workflow verbs (find/history/diff/check/commit/dev-*)
xr3-slurm --help                # submit / status / watch
# from a non-shell caller, the case a function fails:
python3 -c "import subprocess; subprocess.run(['xr3','--help'])"
```

## What the tools assume about your jobs

See **[extensions/CONTRACT.md](extensions/CONTRACT.md)** — the single source of truth
(the `output/done` marker, `tags[0]`/`metadata.path` conventions, `R3_REPOSITORY`, SLURM
config, GNU `diff`, …), each with *what breaks if you don't*. The per-tool
[`xr3`](extensions/xr3/README.md) / [`xr3-slurm`](extensions/xr3-slurm/README.md) READMEs
are the command reference.
