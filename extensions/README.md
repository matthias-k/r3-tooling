# extensions — the layer on top of the pure r3 skill

Everything here builds on `../skills/r3/` (the pure r3 skill) and is deliberately kept *out* of it, so
the pure skill stays upstream-ready. To come:

- **`xr3`** — the CLI wrapper (`find` / `history` / `files` / `commit` / `check` / `submit`).
- **`RESEARCH_WORKFLOW.md`** — house research conventions, migrated from the research project. The
  r3-mechanics slices move *into* the pure skill; the xr3/convention slices land here (spec §5).
- **`examples/`** — worked examples (from the r3-tutorial).
- the galvani **`g`** read-only access helper.

Rule of thumb: if it mentions `xr3`, a container, SLURM, `g`, or a house convention, it's an extension;
if it's true of vanilla r3, it belongs in the pure skill.
