# Roadmap

Forward-looking index for `r3-tooling`. One line + status + link per item; the details
live in the linked docs (this file is the map, not the spec).

## Done

- **Full-toolchain installer** — `install.sh` (uv venv, editable r3+foreman, PATH wrappers,
  base-root config, optional skill install; re-run = update) + `SETUP.md` rewrite + the
  `xr3` base-root pathmap change. See `docs/specs/2026-09-16-full-toolchain-install-design.md`.
- **xr3 extraction & hardening** — the galvani `xr3` monolith split into the shareable
  `xr3` / `xr3-slurm` suite (config-externalized, SLURM separated, `xr3diff.py` extracted),
  documented (`extensions/CONTRACT.md` + per-tool READMEs + `SETUP.md`), merged to `main`.
  See `docs/specs/2026-08-22-xr3-extraction-design.md` and
  `docs/superpowers/HANDOFF-xr3-extraction.md`.
- **`RESEARCH_WORKFLOW.md` re-homed into the repo** (2026-09-29) — the house workflow doc now lives at
  the repo root (was `research/docs/`, which isn't versioned), so it gets git history and ships with the
  toolchain. The `research-workflow-additions.md` conventions (metadata schema, job archetypes, the
  checkout-omits-metadata hazard, what `check` enforces) were folded in, plus a portable `run.sh`
  (scratch/launcher fallbacks) for off-cluster use. *Residual:* slicing its pure-r3 mechanics into
  `skills/r3/` and its house slices into the `xr3` skill rides with item 1 below. Genericizing the
  user-specific bits (paths, project list) for the workshop is the next phase.

## Near-future (in rough order)

1. **An `xr3` skill** — the biggest lever: a skill (like `skills/r3/`) that auto-activates
   on r3/xr3 work, so the house workflow surfaces without agents having to read a doc, and
   `projects/CLAUDE.md` / `RESEARCH_WORKFLOW.md` shrink to thin pointers. Kickoff brief:
   **[`docs/ideas/xr3-skill.md`](docs/ideas/xr3-skill.md)**.
2. **Genericize `RESEARCH_WORKFLOW.md` for sharing** *(workshop-driven)* — the doc is re-homed and
   content-complete (see Done), but still written as "how *I* work": absolute paths, a concrete project
   list, personal `~/.config/xr3.yaml` / `R3_REPOSITORY`. Factor the user-specific bits into clearly
   labeled examples (most environment values already live in `xr3.yaml` + `SETUP.md`, so this is lighter
   than it looks) so colleagues can adopt it on their laptops. Fallback: a `workshop` branch that strips
   specifics.
3. **`examples/`** — *first batch landed (2026-10-09)*: report scaffold + **compute-job** skeleton,
   **environment** provider in two flavors (**venv** Flavor-B, sealed read-only + **container**),
   **grid-search** (`setup_tasks.py` + a resumable, submit-limit-aware `auto_submit.py`, repointed at
   `xr3`/`xr3-slurm`), and a **raw-data** entry-node stub. Design doc + the "what belongs here"
   selection principle: `docs/specs/2026-10-06-examples-first-batch-design.md`. Still to come: an
   end-to-end worked example and a `find_all` aggregation report. See `examples/README.md` for the
   running index.

## Finer-grained / tool-level

The per-command / per-tool roadmap (minimize headnode SSH, `watch --path` glob, drop
`history`/`diff` pathmap dependence via `metadata.path`, `.r3root` marker, drop `origin`,
optional main-tag enforcement, push sbatch `--output` into the run.sh template,
MLCloud-general → SLURM-general) lives in **`docs/specs/2026-08-22-xr3-extraction-design.md`
§10**. Accepted-but-deferred cleanups from the extraction are in
**`docs/superpowers/HANDOFF-xr3-extraction.md`**.

## Also here (pre-existing)

- The pure `skills/r3/` skill — kept upstream-ready; remote-storage held out for now (see
  the top `README.md` status).
- **Cross-user readability of committed jobs** — commit preserves restrictive read bits, so a
  job can be readable by its owner but not by others; enforcement (a configurable `xr3 check` /
  `commit` step) belongs with decentralized sharing, not a standalone check. Mechanics + future
  hook: [`docs/ideas/cross-user-readability.md`](docs/ideas/cross-user-readability.md).
