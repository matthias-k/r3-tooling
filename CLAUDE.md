# r3-tooling — agent guardrails

Pure, upstream-ready r3 skill (`skills/r3/`) + MK's extensions (`extensions/`).
See `README.md` for layout and `docs/specs/2026-08-15-r3-skill-design.md` for the
design — **start there.**

Two rules for any work in `skills/r3/`:

1. **Keep the pure/extension seam.** `skills/r3/` describes *only vanilla r3* — never
   put xr3, SLURM, containers, the `g` helper, or house conventions in it (those go in
   `extensions/`). If it isn't true of upstream r3, it doesn't belong in the skill.
   This is what keeps the skill upstreamable.
2. **Verify against r3 `main`, not memory.** Confirm every r3 claim against `../r3`
   (target `main`; keep `remote.py`/remote-storage out) and live `r3` behavior. Treat
   `raw-material/R3-GOTCHAS.md` (pinned to `c968f42`/0.5.0) as leads to re-verify, not truth.
