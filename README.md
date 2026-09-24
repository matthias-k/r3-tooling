# r3-tooling

An agent-facing **r3 skill** — a Claude Code skill that lets an agent operate
[r3](https://github.com/mtangemann/r3) reliably (author jobs, wire dependencies, commit/checkout, query
the job graph, trace provenance). Plus a home for house **extensions** — the `xr3` / `xr3-slurm` tool suite
and `RESEARCH_WORKFLOW` conventions. Bootstrapped 2026-08-16 from the r3-tutorial work.

## Using the r3 skill

The skill is **`skills/r3/`** — self-contained (a `SKILL.md`, three `reference/` files, and a bundled
`scripts/r3dev.py`). Install it wherever your Claude Code discovers skills — e.g. symlink it so `git pull`
keeps it current:

```bash
ln -s "$(pwd)/skills/r3" ~/.claude/skills/r3                  # for all your projects
# or:  ln -s "$(pwd)/skills/r3" <project>/.claude/skills/r3   # for one project
```

(Copy the directory instead if you prefer a pinned snapshot; use whatever skill-install method your team
already uses.) Claude Code then activates it on r3 work — writing an `r3.yaml`, wiring
`find_latest`/`find_all` or git dependencies, committing/checking out jobs, the Python API, tracing lineage
— or you can invoke it explicitly. **Nothing else in this repo is needed to use the skill**; the rest is
how it was built and kept current.

## The one organizing principle: pure r3 vs extensions

- **`skills/r3/`** — the **pure r3 skill**: *only r3 core* (the self-contained job/commit model,
  dependencies + query grammar, the CLI + Python API, r3's non-obvious behaviors). **No `xr3`, no house
  conventions, no galvani specifics** — kept **upstream-ready** so it can move into r3 itself whenever (a
  directory move, not a disentangling job). Verified against r3 `main` (validity stamp in `SKILL.md`).
- **`extensions/`** — the house layer on top: the `xr3` / `xr3-slurm` tool suite, `RESEARCH_WORKFLOW`
  conventions, and (to come) examples and the galvani `g` helper. These *reference* the pure skill and never
  leak into it. **These tools add assumptions to your r3 jobs — see
  [`extensions/CONTRACT.md`](extensions/CONTRACT.md).**

## Extensions: the xr3 / xr3-slurm suite

Vendored in [`extensions/`](extensions/README.md):

- **[`xr3`](extensions/xr3/README.md)** — cluster-agnostic development-workflow CLI (`find`, `history`,
  `diff`, `check`, `commit`, `dev-checkout`/`dev-cleanup`, …).
- **[`xr3-slurm`](extensions/xr3-slurm/README.md)** — MLCloud SLURM submission & observation (`submit`,
  `status`, `watch`).

**They place assumptions on your jobs** (a pathmap root, the `output/done` marker, `tags[0]`/`metadata.path`
conventions, SLURM config, …). Those, and what breaks without them, are the single source of truth in
**[`extensions/CONTRACT.md`](extensions/CONTRACT.md)** — read it before pointing the tools at your jobs.

### Install the full toolchain

Clone the repo and run the installer — one command sets up r3 + xr3/xr3-slurm + foreman:

```bash
git clone git@github.com:matthias-k/r3-tooling.git && cd r3-tooling && ./install.sh
```

`./install.sh` prompts for the locations (press Enter to accept each default); add `--yes` to take all
defaults non-interactively, or `--dry-run` to preview. It creates a `uv` venv with r3 + foreman, PATH
wrappers (`r3`, `xr3`, `xr3-slurm`, `foreman`), an `xr3.yaml`, and an initialized `R3_REPOSITORY`, and
writes a `<toolchain-root>/update.sh` you can re-run any time to update. Flags, manual steps, SLURM, and the
foreman tunnel are in **[`SETUP.md`](SETUP.md)**.

**One canonical clone.** The toolchain works from a single clone at `<toolchain-root>/r3-tooling` (default
`~/r3-toolchain/r3-tooling`, alongside the `r3`/`foreman` clones it manages). If you run `install.sh` from
some other clone, it creates/uses that canonical one and re-runs from it — so the wrappers, the skill
symlink, and `update.sh` all point at one place (no "which clone?" confusion). The initial clone you made
to get `install.sh` is then disposable. Pass `--no-relocate` to run a clone in place instead.

Once this repo is public, the first install becomes a true one-liner via **`bootstrap.sh`** (it asks for the
toolchain dir, clones into `<toolchain-root>/r3-tooling`, and runs the installer):

```bash
curl -fsSL https://raw.githubusercontent.com/mtangemann/r3-tooling/main/bootstrap.sh | bash
```

> The install can't be a `curl | bash` of a lone `install.sh` because it needs the checked-out repo (it wires
> up `extensions/` and `skills/r3`) — hence a clone. `r3` is public; `foreman` and this repo are private for
> now, so cloning needs SSH access to GitHub (use `--clone-proto https` for the public parts only).

What's next (the `xr3` skill, folding in `RESEARCH_WORKFLOW.md`, `examples/`) is in **[`ROADMAP.md`](ROADMAP.md)**.

## Layout

**Use-facing:**
- `skills/r3/` — **the pure r3 skill** (install this).
- `extensions/` — the **`xr3` / `xr3-slurm`** tool suite, `CONTRACT.md`, and house conventions.

**Build provenance / maintenance** (not needed to *use* the skill):
- `docs/specs/` — the design spec · `docs/superpowers/plans/` — the build plan.
- `docs/r3-upstream-doc-issues.md` — doc/code fixes to make in the r3 repo upstream.
- `docs/ideas/` — rough thoughts / planned additions not yet folded in (the `xr3` skill; the
  `research-workflow-additions.md` conventions to migrate). Indexed and prioritized in `ROADMAP.md`.
- `raw-material/r3-findings.md` — the **verified mined knowledge base** the skill was authored from
  (dense working material; kept for re-verifying the skill against future r3 versions).

## Status

- **`skills/r3/` — built, reviewed, on `main`.** Verified against r3 `main` `262a937` / v0.5.0; the
  `SKILL.md` validity stamp + a `git log <stamp>..main` recipe let a later session keep it current.
- **`extensions/` — the `xr3` / `xr3-slurm` suite is vendored** (extracted from the galvani `xr3` monolith:
  config-externalized, SLURM split into `xr3-slurm`, documented in `CONTRACT.md` + per-tool READMEs). Still
  to come: `examples/`, the galvani `g` helper.
- Remote-storage is held out of the skill for now (alpha post-merge); ⚠ path-promotion is idea-stage
  upstream and will eventually change `find` (the skill flags it).
