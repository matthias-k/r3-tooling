# r3-tooling

**r3-tooling** is the house toolchain around [r3](https://github.com/mtangemann/r3): an
agent-facing **r3 skill**, the **`xr3` / `xr3-slurm`** command-line tools, the house
**`RESEARCH_WORKFLOW.md`** conventions, and a one-command **installer** that wires it all up
(r3 + xr3/xr3-slurm + foreman). Use the whole toolchain — or just the skill.

## Install

One command sets up r3 + xr3/xr3-slurm + foreman:

```bash
curl -fsSL https://raw.githubusercontent.com/matthias-k/r3-tooling/main/bootstrap.sh | bash
```

It prompts for the toolchain directory and the other settings — locations, SLURM head node,
whether to install the agent skill, and whether to wire the workflow into your `CLAUDE.md` —
then installs: a `uv` venv with r3 + foreman, the `r3` / `xr3` / `xr3-slurm` / `foreman`
commands on your `PATH`, an `xr3.yaml`, and an initialized `R3_REPOSITORY`. It prompts **even
when piped** (`curl … | bash`), reading from your terminal; pass `--yes` to run unattended
with all defaults, or `--dry-run` to preview. With no terminal and no `--yes` it errors
rather than silently taking defaults.

> Prefer to clone first (to read the script or hack on it)? Same result:
> ```bash
> git clone https://github.com/matthias-k/r3-tooling.git && cd r3-tooling && ./install.sh
> ```
> `r3`, `r3-tooling`, and `foreman` (via its public mirror `foreman-ai-builder-camp`) are all
> public, so `--clone-proto https` installs the whole toolchain without any GitHub key setup.

Re-run any time to update — the installer saves a `<toolchain-root>/update.sh`. Everything
lives in one canonical clone at `<toolchain-root>/r3-tooling`, so there's no "which clone?"
confusion. Full details — flags, manual steps, SLURM, the foreman tunnel — are in
**[`SETUP.md`](SETUP.md)**.

## What's in here

- **[`skills/r3/`](skills/r3/)** — the **r3 skill**: lets an agent operate r3 reliably
  (author jobs, wire dependencies, commit/checkout, query the job graph, trace provenance).
  Self-contained and usable on its own (see *Using the r3 skill on its own*).
- **[`extensions/`](extensions/README.md)** — the **`xr3` / `xr3-slurm`** command-line suite
  (the house dev + SLURM workflow), plus **[`CONTRACT.md`](extensions/CONTRACT.md)** — the
  assumptions these tools place on your jobs.
- **[`RESEARCH_WORKFLOW.md`](RESEARCH_WORKFLOW.md)** — the house research workflow: how we
  actually use r3/xr3 (project & path layout, `SPEC.md`→`PLAN.md`→implement, job archetypes,
  `run.sh`/environment, reports, gotchas).
- **[`agent-context.md`](agent-context.md)** — a short pointer you `@`-import into a
  `CLAUDE.md` so agents auto-discover the workflow (the installer can wire this for you).
- **[`examples/`](examples/README.md)** — copy-and-adapt starting points for the pieces
  the workflow describes (the report scaffold today; container/venv jobs and the sweep
  helpers to come).
- **`bootstrap.sh` / `install.sh`** — the one-command installer (above).

## Using the r3 skill on its own

The skill (**`skills/r3/`**) is self-contained — a `SKILL.md`, `reference/` files, and a
bundled `scripts/r3dev.py` — and works without the rest of the toolchain. The installer can
symlink it, or do it by hand so `git pull` keeps it current:

```bash
ln -s "$(pwd)/skills/r3" ~/.claude/skills/r3                  # for all your projects
# or:  ln -s "$(pwd)/skills/r3" <project>/.claude/skills/r3   # for one project
```

(Copy the directory instead for a pinned snapshot.) Claude Code activates it on r3 work —
writing an `r3.yaml`, wiring `find_latest`/`find_all` or git dependencies, committing/checking
out jobs, the Python API, tracing lineage — or you can invoke it explicitly.

## The one organizing principle: pure r3 vs extensions

- **`skills/r3/`** — the **pure r3 skill**: *only r3 core* (the self-contained job/commit model,
  dependencies + query grammar, the CLI + Python API, r3's non-obvious behaviors). **No `xr3`, no house
  conventions, no galvani specifics** — kept **upstream-ready** so it can move into r3 itself whenever (a
  directory move, not a disentangling job). Verified against r3 `main` (validity stamp in `SKILL.md`).
- **`extensions/`** — the house layer on top: the `xr3` / `xr3-slurm` tool suite (plus
  [`examples/`](examples/README.md), started, and the galvani `g` helper to come). These *reference* the pure skill and never leak into it. (The house *workflow*
  conventions — how the tools are actually used — live in the top-level [`RESEARCH_WORKFLOW.md`](RESEARCH_WORKFLOW.md).) **These tools add assumptions to your r3 jobs — see
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

What's next (the `xr3` skill, more `examples/`) is in **[`ROADMAP.md`](ROADMAP.md)**.

## Also in here (build provenance / maintenance)

Not needed to *use* the toolchain:

- `docs/specs/` — the design spec · `docs/superpowers/plans/` — the build plan.
- `docs/r3-upstream-doc-issues.md` — doc/code fixes to make in the r3 repo upstream.
- `docs/ideas/` — rough thoughts / planned additions not yet folded in (the `xr3` skill; the
  `research-workflow-additions.md` staging queue for new `RESEARCH_WORKFLOW.md` candidates — its
  original batch was folded in 2026-09-29). Indexed and prioritized in `ROADMAP.md`.
- `raw-material/r3-findings.md` — the **verified mined knowledge base** the skill was authored from
  (dense working material; kept for re-verifying the skill against future r3 versions).

## Status

- **`skills/r3/` — built, reviewed, on `main`.** Verified against r3 `main` `262a937` / v0.5.0; the
  `SKILL.md` validity stamp + a `git log <stamp>..main` recipe let a later session keep it current.
- **`extensions/` — the `xr3` / `xr3-slurm` suite is vendored** (extracted from the galvani `xr3` monolith:
  config-externalized, SLURM split into `xr3-slurm`, documented in `CONTRACT.md` + per-tool READMEs).
  `examples/` started (the report scaffold); still to come there: container/venv job examples, the sweep
  helpers, the galvani `g` helper.
- Remote-storage is held out of the skill for now (alpha post-merge); ⚠ path-promotion is idea-stage
  upstream and will eventually change `find` (the skill flags it).

*Bootstrapped 2026-08-16 from the r3-tutorial work.*
