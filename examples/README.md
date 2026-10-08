# examples

Copy-and-adapt starting points for the pieces the
[`RESEARCH_WORKFLOW.md`](../RESEARCH_WORKFLOW.md) describes. These are examples to learn from and
lift, not a library to depend on — keep them **generic and cluster-agnostic** (no personal paths,
no project-specific dependencies, no hard-coded SLURM partitions). The workflow doc remains the
source of truth; examples just save you retyping. Placeholders in `CAPS` / `{BRACES}`
(`PROJECT`, `DATASET`, `DATE_SLUG`, `USER`, `CLUSTER`) are yours to replace.

## What belongs here

An example earns its place for at least one of three reasons — reuse-frequency *ranks* candidates
but never by itself justifies one:

- **Reuse** — many jobs share the shape (save retyping).
- **Irreducibility** — it carries logic the workflow doc can only gesture at in prose, so a session
  won't reliably regenerate it (e.g. the venv relocation + read-only sealing; the array/batch
  submit-limit chunking).
- **Standardization** — the structure *is* reproducible but the good version isn't the default, so
  quality varies session to session; the example pins the hard-won defaults.

**Veto:** if the doc already reproduces something faithfully, strengthen the doc rather than ship a
duplicate example (two sources of truth drift). The design rationale is in
[`../docs/specs/2026-10-06-examples-first-batch-design.md`](../docs/specs/2026-10-06-examples-first-batch-design.md).

## Available

- **[`compute-job/`](compute-job/)** — a minimal **compute** job skeleton (`run.sh` /
  `run_inner.sh` / `run.py` / `config.yaml` / `r3.yaml` / `metadata.yaml` / `SPEC.md`). The thing
  you copy to start an experiment's `compute/` job; kept thin because the doc already regenerates
  the shape.
- **[`environment/`](environment/)** — the compute environment as an r3 dependency (the *provider*
  archetype), in two flavors: **[`venv/`](environment/venv/)** (self-contained interpreter, sealed
  read-only, no Singularity — laptop-reproducible) and **[`container/`](environment/container/)**
  (a Singularity image). One archetype, pick the flavor.
- **[`grid-search/`](grid-search/)** — fan a `template_job/` out over a grid (`setup_tasks.py`) and
  submit it to SLURM resumably, under the submit limit (`auto_submit.py`), including the array/batch
  mode for a single heavy cell.
- **[`raw-data/`](raw-data/)** — a "job you don't run": externally-received data held with a README
  as its provenance record (the `_raw`/entry-node archetype). No `run.sh`.
- **[`report/`](report/)** — the house report scaffold: `report.qmd` + `styles.css` with the
  standard section layout (`tl;dr` → Introduction / Method / Results / Discussion / Follow up ideas
  / Appendix). See [`report/README.md`](report/README.md).

## To come

- **End-to-end worked example** — genericize a whole runnable study (environment → dataset →
  compute → report, laptop-reproducible) as one piece, so a newcomer has a complete whole to copy,
  not only parts.
- **`find_all` aggregation report** — the many-inputs variant of the report scaffold (compose a
  sweep's cells by reading their committed results, never hand-copying). Deferred: a small delta on
  the report scaffold, and the provenance invariant is already covered in the workflow doc.
