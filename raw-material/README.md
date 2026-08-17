# raw-material — build provenance

Source inputs and mined knowledge used to **build** the r3 skill (`../skills/r3/`). You do **not** need
anything in this folder to *use* the skill — it's kept for maintenance and re-verification.

- **`r3-findings.md`** — the **verified, consolidated knowledge base** the skill was authored from: every
  non-obvious r3 behavior, mined from *all* the sources (r3 source + test suite, r3's own docs, the r3
  tutorial, `RESEARCH_WORKFLOW.md`, and real committed jobs) and re-verified against r3 `main`. Dense
  working material, not user documentation. **This is the file to update** (and re-verify against a newer
  r3) when you revise the skill.
- **`R3-GOTCHAS.md`** — an **earlier, superseded** gotcha catalog pinned to an older r3 (`c968f42`). Kept
  for provenance only; `r3-findings.md` supersedes it wherever they differ — don't rely on it.

**Keeping the skill current:** the `SKILL.md` validity stamp records the r3 commit it was verified against;
`git log <stamp>..main` on the r3 repo shows what changed since. Re-verify against `main`, update
`r3-findings.md`, then update the skill.
