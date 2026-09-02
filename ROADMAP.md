# Roadmap

Forward-looking index for `r3-tooling`. One line + status + link per item; the details
live in the linked docs (this file is the map, not the spec).

## Done

- **xr3 extraction & hardening** — the galvani `xr3` monolith split into the shareable
  `xr3` / `xr3-slurm` suite (config-externalized, SLURM separated, `xr3diff.py` extracted),
  documented (`extensions/CONTRACT.md` + per-tool READMEs + `SETUP.md`), merged to `main`.
  See `docs/specs/2026-08-22-xr3-extraction-design.md` and
  `docs/superpowers/HANDOFF-xr3-extraction.md`.

## Near-future (in rough order)

1. **An `xr3` skill** — the biggest lever: a skill (like `skills/r3/`) that auto-activates
   on r3/xr3 work, so the house workflow surfaces without agents having to read a doc, and
   `projects/CLAUDE.md` / `RESEARCH_WORKFLOW.md` shrink to thin pointers. Kickoff brief:
   **[`docs/ideas/xr3-skill.md`](docs/ideas/xr3-skill.md)**.
2. **Integrate `RESEARCH_WORKFLOW.md` into r3-tooling** *(high value — these are real additions
   the house workflow is still missing, not just a re-home)*. Re-home the research-workflow doc
   here (its r3-mechanics slices → the pure `skills/r3/`; its house-convention slices → the
   extensions / the xr3 skill), per design spec §5/§9, **folding in the conventions collected in
   [`docs/ideas/research-workflow-additions.md`](docs/ideas/research-workflow-additions.md)** (metadata
   schema, job archetypes, the checkout-omits-metadata hazard, what `check` enforces). Do *after* (or
   with) the xr3 skill so the consolidation happens once.
3. **`examples/`** — turn the `auto_submit.py` / `setup_tasks.py` family (which still call the
   now-obsolete monolith) into documented, adaptable templates colleagues can copy, and
   repoint them at `xr3` / `xr3-slurm`. Spec §10.

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
