# Candidate additions for `RESEARCH_WORKFLOW.md`

House conventions observed in the real r3 repo store + `projects/` tree (and confirmed while building the
pure r3 skill) that look **under- or un-documented** in the current `RESEARCH_WORKFLOW.md`. These are for
the *house* doc, not the pure r3 skill. Each item is tagged **[NEW?]** (probably not yet in the workflow
doc) or **[CHECK]** (may already be covered — verify). Source: the free-exploration audit of
`…/mkuemmerer31/r3_repo` + `…/projects`, cross-checked against r3 `main`.

---

## 1. The `metadata.yaml` field schema  **[NEW? — the biggest gap]**

The workflow doc describes *how you work*, but not the **metadata field conventions** every job carries.
Worth codifying, because tooling (`xr3 check`, `find`) and readers depend on them:

- **`path`** — project-prefixed virtual path (`<project>/…`), globally unique via the prefix. *(This is the
  convention you're separately fixing for `gaze-combined-datasets` — see the lustre-migration prompt.)*
- **`tags`** — a list where:
  - `tags[0]` is the **primary version tag** = `<path>/vX.Y.Z`, and the path is *also* emitted as **nested
    tags with `/vX.Y.Z` at each truncation level** (e.g. `…/crossval3_seed42/v1.0.0`, `…/CAT2000/v1.0.0`,
    `…/tasks/v1.0.0`, `…/tasks`) — this is what lets `find --tag` match at multiple granularities;
  - plus **identity tags**: username, cluster (`galvani`), project;
  - **job-type tags**: `analysis`, `report`, `autoslurm`, colon-namespaced `autoslurm:restart_failed`;
  - **`bug/<name>`** tags (mark a job buggy; `xr3 check`/`dev-checkout` refuse deps carrying one).
- **`version`** — *not* a scalar; a **`versions:` changelog list** of `{comment, version}` entries.
- **`origin`** — ≈ `path` at authoring time; the immutable authoring-folder record vs. the mutable `path`.
- **`projects`** — the project name (a `find` disambiguator; being retired by the path-prefix convention).
- **`scheduler`** — `{automode, cluster, restart_failed}` (auto-submission state).
- **`task_meta`** / (older) **`gridsearch_meta`** — per-job hyperparameters (lr, seed, dataset, decays…).
- **`post_hoc_modifications`** — a list of `{action, timestamp}` (e.g. "deleted model checkpoints"); the
  concrete form of the workflow doc's "record an emptied `output/` in metadata."
- **`WIP`** — a list of work-in-progress items; `xr3 check` blocks commit while it is non-empty.
- **`comment`** — free-text.

## 2. Job archetypes beyond the compute job  **[NEW?]**

The doc's two-job split (compute + report) implies every job "runs and writes `output/`," but real jobs
include archetypes worth naming — **a job need not have a classical run file**:

- **Provider / server jobs** — e.g. a model job whose `run.sh` starts a local **HTTP server** serving the
  model; a downstream eval job checks it out and queries it (`run_inner.sh`: `if [ -d server ]` → start
  server, `curl http://localhost:$PORT/type` until ready, then run the client). Seen across
  `saliency-benchmarking/evaluation/tasks/*`. This is a genuinely different pattern from "compute →
  `output/`" and deserves a short section.
- **Container jobs** — a Singularity `.sif` is itself **built as an r3 job** and consumed by others via
  `find_latest: {path: research/containers/default}, source: output/container.sif`. *(The doc mentions
  "cut a container revision"; the "container is an r3 job you depend on" mechanic may be worth making
  explicit.)* **[CHECK]**
- **Data / holding jobs** — a job whose purpose is just to hold a dataset in `output/` for others.

## 3. ⚠ Correctness hazard: downstream can't read a dependency's `metadata.yaml`  **[NEW? — important]**

A checkout (including `r3 checkout` and any recursive-copy dependency) **omits the job's `metadata.yaml`
and `r3.yaml`** — verified against r3 `main` (`storage.checkout_job`). So a downstream job that fans in
upstreams (`find_all`) and wants their **hyperparameters** *cannot* read them from `task_meta` /
`gridsearch_meta` in the checked-out dep's `metadata.yaml` — that file isn't there. **House implication:**
keep such parameters in **both** places — `task_meta` (for *querying*, which is the whole point of params
in metadata) **and** a **committed regular file** (e.g. `config.yaml`, so a downstream consumer can read
them back across a checkout). Worth a one-line warning in the doc, since the house habit is to put params
in `task_meta` alone.

## 4. `run.sh` → `run_inner.sh` + SLURM/Singularity structure  **[CHECK]**

The doc calls these "host/SLURM wrappers"; the concrete structure seen everywhere: outer `run.sh` checks
out to `$SCRATCH/job` and dispatches; `run_inner.sh` runs `singularity exec --nv` with `PYTHONPATH` set to
the checked-out repos, and uses an **`output/done` idempotency marker** so a resubmit skips finished work.
If not already spelled out, a canonical template would help.

## 5. What `xr3 check` actually enforces  **[CHECK]**

`xr3 check` encodes the conventions above — it fails on: `path`/`origin` ≠ the job's location; `tags[0]`
not matching `<path>/vN`; any dependency carrying a `bug/…` tag; a non-empty `WIP`; and any
staged/unstaged/untracked change in a checked-out git dep. Listing these makes the conventions
self-documenting (and is a good spec for anyone re-implementing `check`).

## 6. Repo-store housekeeping  **[FYI, not workflow]**

The real `r3_repo` store also carries legacy `index.yaml`, `backup/`, and `git_old/` beside the live
`index.sqlite`/`git/`. Current r3 uses only `index.sqlite`; the rest is harmless cruft you may want to
prune at some point.

---

*Everything here is house-layer. The pure r3 truths behind them (checkout omits metadata; container/model
jobs are just jobs with `output/`; `path`/`tags` are conventions r3's core doesn't read) are already in the
pure skill; this doc is only the house conventions layered on top.*
