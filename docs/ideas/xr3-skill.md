# Idea / kickoff: an `xr3` skill

**Status:** not started — a seed for the next session to brainstorm from (invoke
`superpowers:brainstorming` first). This is a *brief*, not a spec.

## Why

`projects/CLAUDE.md` bloated because it's the only always-loaded file, so durable
r3/xr3/workflow knowledge got crammed there — repeatedly — since agents didn't reliably
open the referenced `RESEARCH_WORKFLOW.md`. A **skill** fixes that structurally: it
**auto-activates on matching work** (r3/xr3 tasks) without an agent knowing to read
anything, and without weighing down CLAUDE.md. The existing **`skills/r3/`** proves the
model (and is more reliable than prose docs). An `xr3` skill is also one of the shapes the
top README explicitly left open ("one wrapper, several focused skills, or an extension
system — TBD").

Net goal: `projects/CLAUDE.md` and `RESEARCH_WORKFLOW.md` shrink toward thin pointers; the
*house workflow* + xr3/xr3-slurm usage live in a skill that surfaces when relevant.

## Questions to settle in the brainstorm

- **One skill or two?** `xr3` (cluster-agnostic) vs `xr3-slurm` (MLCloud) mirrors the tool
  split / the pure-vs-extension seam — but two skills is more overhead. Likely *one* `xr3`
  skill with an `xr3-slurm` section, unless MLCloud-specificity argues for a separable one.
- **Where does it live?** `skills/r3/` is deliberately **upstream-pure** (no house stuff).
  An xr3 skill is house-layer — `skills/xr3/`? `extensions/…`? Decide, and keep the pure r3
  skill uncontaminated (the `CLAUDE.md` seam rule).
- **Reference, don't restate.** Point at the single sources of truth —
  [`extensions/CONTRACT.md`](../../extensions/CONTRACT.md) and the tool READMEs — for the
  assumptions/commands; the skill adds the *workflow* they don't (SPEC→PLAN→implement, the
  compute/report split, the `output/done` discipline, when to use which command).
- **What migrates in, and in what order** relative to the `RESEARCH_WORKFLOW.md` integration
  (see [ROADMAP](../../ROADMAP.md)) — the deep metadata/check/singularity content now in
  `projects/CLAUDE.md`, and the house slices of `RESEARCH_WORKFLOW.md`. Sequencing matters so
  we don't half-consolidate and re-touch.

## Material to draw on

- **`skills/r3/`** — the working model (SKILL.md + `reference/` files + validity stamp).
- **`extensions/CONTRACT.md`**, **`extensions/xr3/README.md`**, **`extensions/xr3-slurm/README.md`** — the reference the skill points at.
- **`extensions/research-workflow-additions.md`** — house conventions (metadata schema, job archetypes, the checkout-omits-metadata hazard, what `check` enforces).
- **`research/docs/RESEARCH_WORKFLOW.md`** — the house workflow to fold in / re-home.
- **`docs/specs/2026-08-22-xr3-extraction-design.md`** §9 (documentation plan) and §10 (roadmap).

## Suggested first steps

1. `superpowers:brainstorming` to settle the questions above → a spec in `docs/specs/`.
2. `superpowers:writing-plans` → subagent-driven build (as the extraction was done).
3. Keep the pure/extension seam; verify r3 claims against `../r3` main.
