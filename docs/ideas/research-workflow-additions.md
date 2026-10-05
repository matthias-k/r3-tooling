# Candidate additions for `RESEARCH_WORKFLOW.md` (+ the r3 skill)

Staging queue for house-workflow conventions not yet folded into
[`RESEARCH_WORKFLOW.md`](../../RESEARCH_WORKFLOW.md) (or, where they are pure-r3 truths, the
[`r3` skill](../../skills/r3/)). A hub/tooling session integrates these, then clears them from here.
Each item is tagged **[NEW?]** (probably missing) or **[CHECK]** (may already be covered — verify
against the live doc before writing).

> The assumptions the `xr3` / `xr3-slurm` tools place on jobs (the `output/done` marker, the
> `tags[0]`/`metadata.path` conventions, pathmap, SLURM config) are the single source of truth in
> [`extensions/CONTRACT.md`](../../extensions/CONTRACT.md); `RESEARCH_WORKFLOW.md` should **link** it
> rather than restate it. The conventions below are the *house workflow* around those tools.

> **History.** The original batch (the metadata-field schema, job archetypes, the
> checkout-omits-`metadata.yaml` hazard, the `run.sh`/`output/done` structure, what `check` enforces,
> repo-store housekeeping) was mined from the real r3 store in 2026-08 and **fully folded into
> `RESEARCH_WORKFLOW.md` on 2026-09-29** (housekeeping landed in `docs/r3-upstream-doc-issues.md`
> instead). This file was then emptied and is now the live queue for *new* candidates.

---

Source: the Agentic-Science-Hub gold-density case study
(`case-studies/2026-08-gold-density-precompute.md`). Most of that case study's r3 lessons —
resumability (whole-output-`tmp` failure mode, HDF5 append-resume, deterministic-failure caveat),
params-as-committed-file, dev-render — are **already** in `RESEARCH_WORKFLOW.md` (§Resumable jobs even
cites the `gold_density` job). The items below are the residue that is *not* yet captured.

## 1. Recursive-checkout *sourcing* as a workflow decision  **[NEW? — the main gap]**

`recursive_checkout` is documented in the r3 skill as a *mechanism* (it's the default for a job
dependency: `source: "."` + `recursive_checkout: true` → a recursive real copy of the whole upstream
job). What's missing is the **house decision** of when to lean on it — and it's the explicit
counterpoint to the existing *"Narrow dependencies with `source:`"* bullet in §Config & dependencies.

- **When.** A downstream job needs several heterogeneous inputs an upstream job already assembled — its
  `config.yaml` + its own dependencies (regularizers, data) + its frozen `output/` — and you'd
  otherwise re-declare or reconstruct each one downstream.
- **How.** Add *one* dependency that recursively checks the whole upstream job into a subdir
  (`find_latest: {path: <upstream>} → destination: model`, the `source: "."` + `recursive_checkout:
  true` defaults). It materializes the upstream's config, its deps (symlinked), and its `output/`. The
  consumer reads config + deps + params from that subdir (scoped `chdir` so relative paths resolve).
  Keep any library the consumer must *import* at top level — do **not** import from the upstream's
  pinned copy inside the subdir.
- **The two poles.** *Narrow with `source:`* when you consume one file; *recursive-checkout sourcing*
  when you need the upstream's whole assembled input environment. Same decision, opposite ends.
- **Pitfalls.** (1) Peak resource use is the upstream's — not reduced by this. (2) The recursive copy
  duplicates the upstream's git repos into scratch at checkout (harmless, not committed, but real disk
  at runtime). (3) **`chdir` output footgun** — resolve output paths to absolute (`.resolve()`)
  *before* chdir-ing into the subdir, or output lands in the wrong place.
- **When NOT to.** When you must *vary* those inputs, or the upstream isn't committed yet (reconstruct
  from a registry so staged cells still generate).
- **Evidence.** n=2: gold-density (collapsed a 4-part per-variant wiring layer to one dep across 19
  jobs); the earlier `effect-on-CC` report used the same shape. Target: §Config & dependencies (a new
  bullet beside "Narrow dependencies with `source:`").

## 2. Resumability blind spot: an expensive un-resumable *prefix*  **[NEW?]**

§Resumable jobs already covers per-unit checkpointing, whole-output-`tmp` as an anti-pattern, and a
*deterministic per-unit failure* looping forever. A third failure mode is missing: **resumability is a
property of the whole restart cost, not of one loop.** An expensive, un-resumable *prefix* that reruns
on every attempt defeats a perfectly resumable inner loop.

- **The trap.** In gold-density's CAT2000 thrash, a ~16-min subject-model build ran *before* the
  resumable export on every resubmit, so ~40 preempt/OOM attempts netted ~18 of 2000 images while
  burning ~10 h in rebuilds. The strategy degrades to `prefix_cost × failures`.
- **Fix.** Make the prefix resumable too (cache it to a keyed on-disk store), or don't rely on
  preempt/resubmit for that job. Measure *end-to-end* restart cost, not just the inner loop.
- Target: §Resumable jobs — add to the caveats (beside the deterministic-failure one).

## 3. Availability check: stat the output, not the index  **[NEW?]**

In a commit-≠-run system, "the job is in the index" ≠ "the job produced its output." A readiness check
that downstream work depends on must **stat the actual artifact** (`jobs/<uuid>/output/parameters.csv`
/ the `output/done` marker), not just that `xr3 find` returns the job.

- **Evidence.** gold-density hit this: 3 upstream jobs were committed but had not yet produced
  `parameters.csv`. Target: §Finding jobs (a short caution), or fold into the §Resumable `output/done`
  note (consumers gate on `done`, not on existence).

## 4. Minor / **[CHECK]** — probably already covered, verify before adding

- **Quarto local dev-render mechanics.** §Reports & writing has "dev-render before committing"
  (`xr3 dev-checkout .`, render in the working dir). The operational detail may be worth a line:
  `PYTHONPATH=<checked-out dep repos> quarto render report.qmd --to html --output-dir output_smoke`
  — the `PYTHONPATH` is the dev-checked-out deps (as in `run_inner.sh`), not a base-env install (stock
  python lacks `pysaliency` etc.); probe first (`which quarto`, `import pysaliency`, `nvidia-smi`) and
  write ad-hoc renders to `output_smoke/`, never the real `output/`. **[CHECK]** against §Reports.
- **Standalone `task_meta.yaml` root file.** §Config & dependencies already says "commit params a
  downstream reads as a file, not only `task_meta`." The gold-density nuance: a *standalone committed
  `task_meta.yaml` root file* survives checkout (checkout drops `metadata.yaml` but keeps other root
  files), and can be composed from the source job's own `task_meta.yaml` + the new job's fields.
  **[CHECK]** whether this positive prescription adds anything over the existing bullet.
