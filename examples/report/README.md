# Report scaffold

The house **report section layout** as a ready-to-copy Quarto report:
a `tl;dr` callout, then **Introduction / Method / Results / Discussion /
Follow up ideas / Appendix**. See *Reports & writing* in
[`RESEARCH_WORKFLOW.md`](../../RESEARCH_WORKFLOW.md) for the conventions these
sections encode (what the `tl;dr` is for, computing numbers in prose, honest
charts, the review loop).

This is a **scaffold, not a full r3 job** — it's `report.qmd` + `styles.css`, no
environment or `run.sh`. Drop these into a report job and fill them in. For the
full report-*job* setup (the `compute` → `report` split, `r3.yaml`, `run.sh` /
`run_inner.sh`, the dev-render loop), follow `RESEARCH_WORKFLOW.md`.

## Rendering

```bash
quarto render report.qmd --to html
```

Render inside your job's environment (container or venv) so the Python cells have
their dependencies — the render usually lives in a `run_inner.sh` that calls
`quarto render` within `singularity exec` (see the workflow doc). Output is
single-format **HTML**; add other formats only if you actually need them.
