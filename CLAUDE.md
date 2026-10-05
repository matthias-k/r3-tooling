# r3-tooling — agent guardrails

Pure, upstream-ready r3 skill (`skills/r3/`) + MK's extensions (`extensions/`).
See `README.md` for layout and `docs/specs/2026-08-15-r3-skill-design.md` for the
design — **start there.**

Extensions (`extensions/`): the `xr3` (cluster-agnostic) / `xr3-slurm` (MLCloud SLURM)
tool suite. Before using or documenting them, read **`extensions/CONTRACT.md`** — the
single source of truth for the assumptions they place on r3 jobs — plus the per-tool
READMEs. Setup (env, PATH wrappers, config) is in **`SETUP.md`**. The `xr3-slurm`
extraction design is `docs/specs/2026-08-22-xr3-extraction-design.md`.

Invocation: `r3` / `xr3` / `xr3-slurm` are wrapper scripts in `$LUSTREWORK/bin` (on PATH),
so they run in any shell, subprocess, or subagent — no conda/PYTHONPATH discovery needed.

Two rules for any work in `skills/r3/`:

1. **Keep the pure/extension seam.** `skills/r3/` describes *only vanilla r3* — never
   put xr3, SLURM, containers, the `g` helper, or house conventions in it (those go in
   `extensions/`). If it isn't true of upstream r3, it doesn't belong in the skill.
   This is what keeps the skill upstreamable.
2. **Verify against r3 `main`, not memory.** Confirm every r3 claim against `../r3`
   (target `main`; keep `remote.py`/remote-storage out) and live `r3` behavior. Treat
   `raw-material/R3-GOTCHAS.md` (pinned to `c968f42`/0.5.0) as leads to re-verify, not truth.

## Editing the conventions (`RESEARCH_WORKFLOW.md` and the skills)

These docs are read by *many* future sessions, so a convention you add or sharpen
must generalize past the task you happen to be doing. When you touch them:

1. **Write the general guiding principle, not just the instance in front of you.**
   Ask what broader rule your specific case is an instance of, and lead with that.
   Place it by its weight — a foundational invariant belongs near the top, not
   buried in one section's bullet list.
2. **Avoid inherited furniture.** A rule written mid-task tends to carry that task's
   specifics (its artifacts, names, roles — e.g. a "leaderboard" or an "orchestrator"
   from an auto-research loop). Keep concrete cases as *illustrations* ("e.g.", "most
   often"), never as the definition or the scope.
3. **Guard both failure modes.** Over-narrow framing → other sessions don't realize
   the rule applies to them. Over-rigid framing → other sessions won't deviate when it
   would make sense. The general-principle-plus-illustration shape avoids both.
