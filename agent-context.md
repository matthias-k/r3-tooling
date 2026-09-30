# Research workflow — agent context

<!-- Maintained in the r3-tooling repo. Import it into a CLAUDE.md / AGENTS.md with
`@<path-to>/r3-tooling/agent-context.md` (the `@` line, backtick-free, on its own line) so
every session picks it up and updates arrive on `git pull`. Keep this file SHORT — it
points at the full workflow, it does not inline it (that would always-load 600+ lines). -->

**All computational research work runs as r3 jobs** — running an experiment, evaluating a
model on a dataset, building or processing a dataset, analysing results, producing a
report. Each job gets content-addressed provenance; don't hand-roll one-off scripts
outside a job for anything worth keeping or reproducing (throwaway exploration can be
looser, but it graduates into a job).

Before starting any such work, use r3 (via the **`r3` skill**) and follow the house
workflow in **`RESEARCH_WORKFLOW.md`** — the sibling of this file in the r3-tooling repo:
project & path layout, `SPEC.md`→`PLAN.md`→implement, job archetypes, `run.sh`/environment,
the develop→commit loop, reports, gotchas. **Read it before creating, running, or
restructuring an experiment.** Tooling setup (the `r3` / `xr3` / `xr3-slurm` commands on
`$PATH`, `$R3_REPOSITORY`): the repo's `SETUP.md`.
