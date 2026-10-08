# Examples — first batch (design)

**Status:** draft for review. **Date:** 2026-10-06. Implements ROADMAP item 3 (`examples/`).
Scope: decide *which* examples `examples/` should carry next, *where each is sourced from*,
and *how* each is genericized — before authoring any of them.

## Context: what we learned before choosing

Two pieces of evidence reshaped the list (details in the hub observer log, session
`e1118207`):

1. **The workflow doc already regenerates the bare skeleton.** On the other cluster region
   (ferranti), a session given *only* the toolchain + `RESEARCH_WORKFLOW.md` — no examples —
   built a full `natural-image-statistics` project (env → dataset → compute → report) whose
   `run.sh` is **verbatim** the doc's portable-runner template, with correct `r3.yaml` deps,
   the full tag stack, the compute/report split, and a committed `SPEC.md`. So an isolated
   "base compute job" example would mostly duplicate the doc (two sources of truth → drift).
2. **The portable region is the better *source* than the large one.** galvani is ~5,387
   Singularity+SLURM jobs — the *least* cluster-agnostic material. ferranti does the same arc
   with a venv / `python-build-standalone` env and **no Singularity**, i.e. laptop-reproducible
   — which is exactly what `examples/README.md` demands ("generic and cluster-agnostic").

### Selection principle (for `examples/README.md`)

An example earns its place for **at least one** of three reasons — and reuse-frequency
*ranks* candidates but never by itself *justifies* one:

- **Reuse** — many jobs share the shape (save retyping).
- **Irreducibility** — it carries logic the workflow doc can only gesture at in prose, so an
  agent won't reliably regenerate it (e.g. venv relocation + read-only sealing; array/batch
  submit-limit chunking).
- **Standardization** — the structure *is* reproducible but the *good* version isn't the
  default, so quality varies session to session; the example pins the hard-won defaults.

**Veto:** if the doc already reproduces it faithfully (the bare skeleton), don't also ship it
as an example — strengthen the doc instead.

## First batch (decided)

Target layout under `examples/` (each is copy-and-adapt, generic, cluster-agnostic):

| # | Example | Dir | Source | Why it earns its place |
|---|---------|-----|--------|------------------------|
| 1 | Minimal compute-job skeleton stub | `compute-job/` | authored (mirrors ferranti compute) | reuse (quick copy-paste start); kept minimal to not duplicate the doc |
| 2 | venv environment job (Flavor B) + design note | `environment/venv/` | ferranti `environments/default` | irreducibility + standardization (sealing, bundled Quarto) |
| 3 | Singularity container env (sibling flavor) | `environment/container/` | galvani `*/containers/default` | reuse (galvani default); the cluster-side sibling of #2 |
| 4 | Grid fan-out + array/batch orchestration | `grid-search/` | galvani gold-standard Gen-2 | irreducibility (submit-limit-aware chunked submission) |
| 5 | `_raw` "job you don't run" stub | `raw-data/` | authored (tutorial §11.2 pattern) | standardization (tiny; teaches the entry-node archetype) |

Framing to carry through #2/#3: **one "environment-provider" archetype, two flavors** — venv
for laptop/off-cluster, container for the cluster. `environment/README.md` states the choice.

### Per-example genericization notes

- **#1 compute-job/** — `run.sh` (the portable template, verbatim from the doc), `run_inner.sh`
  (env-consumer form: `PY="env/$(cat env/interpreter_path.txt)"; PYTHONNOUSERSITE=1 … "$PY"
  run.py`), a trivial `run.py` (read `config.yaml` → compute → write `output/results.json`),
  `config.yaml`, `metadata.yaml` (full tag stack with placeholders), `r3.yaml` (depends on the
  venv env + a dataset), `SPEC.md` stub, `README.md`. **Keep it deliberately thin** — it exists
  to be copied, and it cross-references the doc rather than re-teaching it.
- **#2 environment/venv/** — lift the ferranti Flavor-B job; **strip** the study packages
  (`zuko`, `torch`, sklearn) down to a minimal scientific stack + the report toolchain
  (Quarto + jupyter), leaving `requirements.txt` as a clearly-marked placeholder. **Keep** the
  mechanics that are the whole point: `uv python install --install-dir output/py`, install into
  the interpreter, self-contained Quarto, `requirements.lock.txt`, `interpreter_path.txt` /
  `quarto_path.txt`, and the **read-only seal** (`chmod -R a-w output/py`). Ship a distilled
  `DESIGN.md` (genericized from `~/python-env-as-r3-dependency.md`): Flavor A vs B, why
  relocatability, the console-script shebang gotcha, "system libs not captured."
- **#3 environment/container/** — keep the `container.def` *pattern* (docker/CUDA base → apt →
  Quarto → conda/pip `requirements.txt`) and the clean `run.sh` (`singularity build --fakeroot
  output/container.sif container.def` + `output/done`). **Strip hard:** MATLAB (mpm/licensed),
  the dropbear/ssh dev-container tooling (mention as an optional comment, don't bake in), the
  project `requirements.txt`, and any pinned checksums for licensed installers.
- **#4 grid-search/** — the pattern, not the KDE domain: `template_job/` (a `{PLACEHOLDER}`
  compute job) + `tasks/` + `setup_tasks.py` (build configs from building blocks → copy
  template → substitute `config.yaml`/`metadata.yaml` → **merge per-task deps into the template
  `r3.yaml`** → skip-existing via `r3 find` → `xr3 check`/`commit`) + `auto_submit.py` (chunked,
  `AssocMaxSubmitJobLimit`-aware array resubmission + `done_batch_*` markers). **Author a clean
  generic version** with a toy 2-axis grid; **do not** strip the real script (it carries KDE
  models, `datasets.yaml`, collaborator-specific configs). Repoint everything at `xr3` /
  `xr3-slurm` (the real ones still call the obsolete monolith).
- **#5 raw-data/** — `metadata.yaml` (entry-node tags incl. `dataset`) + a `README.md` that *is*
  the provenance ("received from X on DATE, copied by hand to `output/`; each file is …") +
  `output/.gitkeep`. **No `run.sh`.** ~15 lines total.

### Leak-safety checklist (applied to every lifted file)

Strip before committing: absolute paths / `$HOME` / `$LUSTREWORK`; usernames and collaborator
tags; hard-coded SLURM partitions (e.g. `*-galvani,bethge`); project/domain names (model,
dataset, library names); licensed-tool installers (MATLAB) and their checksums; any real data.
Verify: `grep -rinE '(galvani|bethge|mkuemmerer|/home/|/mnt/lustre|matlab|partition)'` over the
new example dirs returns nothing but intentional placeholders.

## Also in scope (small)

- **`examples/README.md`**: record the selection principle above; move #1–#5 from "To come" to
  "Available" as they land; keep "generic and cluster-agnostic" as the gate.

*(The report scaffold needs no change: its current `tl;dr`/heading guidance already reflects the
report-content lessons — it was written after those were fixed on ferranti.)*

## Out of scope (deferred, with reason)

- **`find_all` aggregation report** — deferred; judged low marginal value (the mechanics are a
  small delta on the existing report scaffold, and the provenance invariant is already in the
  doc intro).
- **End-to-end worked example** (genericizing the whole ferranti `natural-image-statistics`
  project) — attractive, but larger; revisit after the first batch. The compute-job stub (#1)
  + the two env flavors cover the pieces newcomers need first.
- **Provider/server, third-party-model export, report-template generator, agentic
  research-log** — niche or still-stabilizing; watch.

## Review decisions (2026-10-09)

1. **Directory names** — approved as proposed (`compute-job/`, `environment/{venv,container}/`,
   `grid-search/`, `raw-data/`).
2. **venv knowledge** — fold into `environment/venv/README.md`; **no separate `DESIGN.md`**.
3. **Order** — author all five at once.
