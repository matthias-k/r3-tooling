# Research workflow conventions

House style for structuring research experiments in the r3 workflow. The goals:
consistency across experiments, provenance-first reproducibility, and easy
exploration (e.g. browsing jobs by path). Some conventions are global, some
situational — the notes say which. Grounded in worked examples (the
MathTutorBench and Spatial-Saliency prompt-opt experiments).

> This doc is the canonical home for these conventions. It supersedes the
> per-agent memory note of the same name (now a pointer here). Edit it here.

**Where knowledge lives — read the right doc.** This doc is *how we work*. The
mechanics it builds on live elsewhere, one home each:

- **pure r3** (`r3.yaml`, `find_latest`/`find_all`, commit/checkout, the Python API,
  the query grammar) → the **r3 skill** (`skills/r3/`).
- **how `xr3` / `xr3-slurm` work, and what they require of jobs** → the **r3-tooling
  docs**: `extensions/CONTRACT.md` (the assumptions tools place on
  jobs — single source of truth) plus the per-tool READMEs.
- **how *we* use all of it** (habits, house structure, the flows) → *this doc*.

**Adapting this to your setup.** This doc describes one person's environment
(MLCloud/galvani: SLURM + Singularity, lustre home). Two kinds of specificity are
flagged so you can translate them:

- **Environment values** — `$R3_REPOSITORY`, the pathmap roots, scratch — are set
  *once per machine* (env vars + `~/.config/xr3.yaml`; the `r3` / `xr3` / `xr3-slurm`
  commands themselves are on your `$PATH` via `install.sh`), not per experiment. Values
  shown here are the author's defaults; see `SETUP.md`.
- **Cluster/scheduler specifics** — anything tagged **_(MLCloud/SLURM)_** assumes the
  galvani SLURM + Singularity setup. On a laptop or another cluster, translate it:
  `run.sh` already falls back off-cluster (§4), and the compute environment is a
  swappable r3 dependency (a laptop container or a venv job). §5 is the most
  cluster-specific.

Project names in examples (`gold-standard`, `saliency-benchmarking`, `research`, …) are
the author's — substitute your own. The **methodology** (SPEC→PLAN, the compute/report
split, archetypes, metadata conventions, the review loop) is environment-independent.

## Contents

1. **Project & path layout** — directory layout, the eponymous-subdir rule, `metadata` conventions.
2. **Experiment structure** — `SPEC.md`→`PLAN.md`→implement; the compute/report split.
3. **Job archetypes** — the kinds of job (compute, compute+report, provider/server, container, `_raw`/`src` entry nodes).
4. **Job structure & execution** — `run.sh`→`run_inner.sh`, singularity conventions, running a job locally.
5. **Environment & containers** — SLURM scratch, container builds, working inside the container.
6. **Finding jobs** — querying the index (`xr3 find` / `history`, the Python API).
7. **Config & dependencies** — config-over-env, narrowing deps, on-disk caches, params-in-two-places.
8. **Developing & committing** — the dev loop, pre-commit habits, clean git deps, upstreaming to a git dependency.
9. **Promoting experiment code into a library** — two-part verification against a frozen-output oracle.
10. **Resumable jobs** — checkpointing, the `output/done` marker, resubmit loops.
11. **Long-running tasks** — detached + resume-safe work that outlasts a session.
12. **Reports & writing** — concision, `tl;dr`, honest charts, computed numbers, the review loop.
13. **Known issues / gotchas** — environment/tooling traps (e.g. Quarto + PID namespace).
14. **Open problems** — unsolved (stochastic-compute-vs-report; secrets in r3).

## Project & path layout

r3 `metadata.path` values are **project-local and prefixed with the project
name**, which keeps the working-dir→r3-path mapping trivial (feeds the pathmap
commands `xr3 history` / `diff` / `check`) *and* guarantees paths are globally
unique across projects.
The directory layout is built to make that automatic:

- **One eponymous job subdirectory per project.** Each project dir
  (`projects/<proj>/`) contains a subdirectory with the *same name*
  (`gold-standard/gold-standard/`, `research/research/`) under which **all r3
  jobs live**. A job's filesystem path under `projects/` thus reads as
  `<proj>/<proj>/…`, and its r3 path is that with the doubled name collapsed to
  one: filesystem `gold-standard/gold-standard/models/gold_standards/…` → r3
  path `gold-standard/models/gold_standards/…`. (This is the layout that makes
  `_get_path`'s prefix-strip in `xr3` work — see *Finding jobs*.)
- **Non-job work sits parallel to it**, not under it: `docs/`, `scripts/` /
  `tools/`, `libraries/` (library clones for quick edits), `notebooks/`,
  `sources/` — siblings of the eponymous subdir, kept out of the r3 path space.
- **Inside the job subdir: stable paths + `experiments/`.**
  - **Stable paths** for durable infrastructure and canonical artifacts —
    `containers/` (the compute container), `datasets/`, `models/` (with a
    `models/main` for the project's principal model), `evaluation/`. These are
    the consolidated, long-lived jobs.
  - **`experiments/`** holds timestamped `YYYY-MM-DD_name` sub-experiments —
    analyses, model-extension tests, one-offs. The exploration tier (see
    *Experiment structure*).
- **Experiments feed back into stable jobs.** A sub-experiment that works out
  later informs an update to a stable job (e.g. a new `models/main` revision).
  Experiments explore; stable paths consolidate the result.

**Recurring sub-structure within an experiment (or a stable path):**

- **`compute` + `report`** — the heavy job and its analysis, as two nested r3
  jobs. This is the common case; see *Experiment structure* for the split and
  why compute is committed first.
- **`template_job/` + `tasks/` matrix** for grids / ablations / model×dataset
  ×variant sweeps. A single *templated* job carries `{PLACEHOLDER}` segments in
  its `metadata.path` (e.g.
  `…/models/gold_standards/tasks/{MODEL}/{DATASET}/{JOB_TYPE}`,
  `…/evaluation/tasks/{DATASET}/{MODEL}`), and the instantiated grid lands as a
  nested `tasks/<axis1>/<axis2>/…` directory tree — one committed job per leaf.
  A generator (`auto_submit.py` / autoslurm; `gridsearch_meta` / `task_meta` in
  metadata) fans the template out over the axes. Deeply nested `tasks/` trees
  are the norm for the big sweeps in `gold-standard` and `saliency-benchmarking`.

**Older projects may differ.** These conventions have converged over time;
pre-existing projects can deviate (e.g. `gaze-combined-datasets` predates the
eponymous-subdir rule — jobs live under numbered `tasks/taskNNNN_*` and `tmp/`
instead). Match a project's own established layout when extending it; apply the
conventions above to new projects and new job trees. **Setting up a new project
also means registering it** in `pathmap.roots` (`~/.config/xr3.yaml`), or the
pathmap commands (`xr3 history` / `diff` / `check` / `commit`) can't resolve its
jobs — see *Finding jobs*.

**metadata conventions.** Every job carries a `metadata.yaml`. Beyond what r3 itself
needs, the fields the house relies on (which of these the tools *enforce*, and exactly
how `tags[0]`/`path`/`WIP`/`bug/` are checked, is in
`extensions/CONTRACT.md` — the single source of truth; this is the
convention layered on top):

- **`tags[0]` = the primary version tag** = `<path>/vX.Y.Z`. The path is *also* emitted
  as **nested tags truncated at each level**, each with the `/vX.Y.Z` suffix (e.g.
  `…/crossval3_seed42/v1.0.0`, `…/CAT2000/v1.0.0`, `…/tasks/v1.0.0`, `…/tasks`) — this
  is what lets `xr3 find --tag` match at multiple granularities.
- **identity + type tags** alongside it: username, cluster (`galvani`), project name,
  job type (`analysis`, `report`, `autoslurm`, colon-namespaced like
  `autoslurm:restart_failed`), and **`bug/<name>`** to mark a job (and, by convention,
  its dependents) buggy.
- **`path`** — the project-prefixed logical path (see above); **`origin`** — the same
  value frozen at authoring time (the immutable authoring-folder record vs. the mutable
  `path`).
- **`versions`** — a **changelog list** of `{version, comment}` entries, not a scalar.
- **`task_meta`** (older jobs: `gridsearch_meta`) — per-job hyperparameters (lr, seed,
  dataset, …) for *querying*; see *Config & dependencies* for the rule to also commit
  them as a regular file.
- **`post_hoc_modifications`** — a list of `{action, timestamp}` (e.g. "deleted model
  checkpoints"); the concrete form of recording an emptied `output/` in metadata.
- **`WIP`** — a list of work-in-progress items; a non-empty `WIP` blocks commit.
- **`scheduler`** — `{automode, cluster, restart_failed}` auto-submission state;
  **`projects`** — project membership; **`comment`** — free text.

## Experiment structure

- **`SPEC.md`, not `DESIGN.md`**, for the design doc. Flow:
  **`SPEC.md` → `PLAN.md` (checkbox tasks) → implement.** Both are reviewed
  before moving on.
- **Split most experiments into two nested r3 jobs** — a compute/`train` job and
  an `analysis`/`report` job — under one experiment dir, e.g. `<exp>/dataset` +
  `<exp>/report`, or `<exp>/compute` + `<exp>/report`. The compute job is fully
  provenanced and committed to r3 *before* the report is written, so you don't
  have to write the report before having results; the report job depends on the
  compute job's frozen `output/`. `PLAN.md` can make the report a Part B where an
  agent reads results and drafts it, reviewed interactively after.
- **Timestamped sub-experiments** (`YYYY-MM-DD_name`) at the experiment-tree
  level when forks aren't purely sequential; semver `vN` versions within a
  sub-experiment for iterations.

## Job archetypes

Most jobs "run and write `output/`," but that's not the only shape — a job **need not
have a classical run file**. The archetypes in use:

- **Compute → `output/`** (the default). A `run.py` produces artifacts under `output/`;
  downstream jobs depend on them.
- **Compute + report** — the heavy job and its analysis as two nested jobs; see
  *Experiment structure* for the split and why compute commits first.
- **Provider / server jobs** — `run.sh` starts a local **server** (e.g. an HTTP server
  serving a model) instead of computing to `output/`; a downstream eval job checks it
  out, starts it, waits until ready, then queries it. The `run_inner.sh` pattern:
  `if [ -d server ]` → start the server, `curl http://localhost:$PORT/…` until it
  answers, then run the client. (Seen across `saliency-benchmarking/evaluation/tasks/*`.)
- **Container jobs** — a Singularity `.sif` is itself **built as an r3 job** (see
  *Environment & containers*) and consumed by others as a dependency
  (`find_latest: {path: research/containers/default}, source: output/container.sif`).
- **Source / entry-node jobs (`_raw`, `src`)** — for non-public datasets and prior-work
  models, commit a **minimal job with no run file** — a `README.md` documenting the
  data's human provenance ("raw data received from X, manually copied to `output/`")
  plus `metadata.yaml` — and **hand-populate its `output/`** with the external data.
  This introduces un-provenanced external data into the graph as a labelled **entry
  node** that downstream jobs depend on. Examples: `datasets/MIT300_raw`,
  `datasets/CAT2000_raw`, `…/local_global_attention_model/src`. This is *the* documented
  way to depend on external data until r3 has a first-class option for it.

## Job structure & execution

House structure for a job's entry scripts (the mechanics of the `output/done` marker
itself are in `extensions/CONTRACT.md`):

- **`run.sh` (the SBATCH entry point)** is a thin, generic wrapper — treat it as
  something you don't go looking in. It guards against redoing finished work, checks the
  job out to scratch, runs the logic, and marks completion. It is written to run
  **unchanged both under SLURM and off-cluster** (laptop/workstation): the scratch
  location and the launcher fall back automatically.
  ```bash
  [ -f output/done ] && exit 0                 # idempotency guard: a complete resubmit no-ops
  JOB_DIR="${SCRATCH:-$(mktemp -d)}/job"       # node-local scratch under SLURM; a temp dir off-cluster
  r3 checkout $R3_JOB_ID "$JOB_DIR"
  cd "$JOB_DIR"
  if [[ -z "${SLURM_JOB_ID}" ]]; then
      STEP_CMD="bash"          # off-cluster: no SLURM, run directly
  elif [[ -z "${SLURM_STEP_ID}" ]]; then
      STEP_CMD="srun bash"     # in sbatch, not yet in a step: launch as a step
  else
      STEP_CMD="bash"          # already inside a step (e.g. run_job_locally in a compute job): no nested srun
  fi
  $STEP_CMD run_inner.sh
  echo "completed" > output/done
  ```
  Under SLURM `$JOB_DIR` is exactly **`$SCRATCH/job`** — what `run_job_locally` assumes
  (see below, and CONTRACT.md); off-cluster it's a throwaway `mktemp -d` you inspect and
  clean up yourself. The `SLURM_STEP_ID` branch is the catch for running *inside* a step
  (e.g. `run_job_locally` within a compute job), where a nested `srun` would fail. The
  compute environment itself is a **swappable r3 dependency** — the singularity
  container-job on the cluster, a laptop container-job or a venv-job locally — so the
  per-system difference lives in `run_inner.sh`'s environment-entry line, not here.
- **`run_inner.sh` (the actual logic)** varies by archetype (see *Job archetypes*): a
  pure-compute job calls `singularity exec` directly; a Quarto-report job defines a
  `run_in_container` wrapper and loops over `*.qmd`; a compute+report job does both.
- **Singularity conventions** _(MLCloud/Singularity)_ **— all jobs use:** `--nv` (GPU passthrough); `--home
  "$SCRATCH/home"` (a writable, disposable home); `--bind $(pwd) --bind $R3_REPOSITORY`
  (so symlinked dependencies resolve); `--env PYTHONPATH=<checked-out repo dirs>` (the
  dev-checkout'd git deps, *not* a base-env install). Some add `-p` (PID namespace, for
  process cleanup) — but see *Known issues* for a Quarto interaction.
- **Running a job locally** _(MLCloud/SLURM)_**.** The sanctioned way to exercise the full
  `run.sh`/singularity path outside normal SLURM submission is
  `extensions/scripts/run_job_locally <job-dir>`, **inside an
  interactive SLURM allocation** (it reuses `$SCRATCH`). It is the only way to test
  `run.sh`/`run_inner.sh` themselves; for a quicker inner loop that skips them, see
  *Developing & committing* → in-container dev testing.

## Environment & containers

**_(MLCloud/SLURM)_** — this whole section assumes the galvani SLURM + Singularity
setup; a laptop or another cluster differs (see *Adapting this to your setup* at the top).

- **SLURM scratch.** Cluster nodes have node-local NVMe scratch at
  `/scratch_local/<user>-<SLURM_JOB_ID>/`; `$SCRATCH` points there inside a job. It is
  **wiped** when the job ends (SLURM cleans up via cgroups), so nothing durable lives
  there — persistent caches go on lustre (see *Long-running tasks*).
- **The compute container is an r3 job.** Containers are built from a `container.def`
  via `singularity build --fakeroot` (runs locally, **no SBATCH**), committed as an r3
  job under `containers/`, and consumed by other jobs as a dependency (see *Job
  archetypes* → container jobs). Cut a new revision when a project matures or packages
  become broadly useful (see *Config & dependencies*). Current default container
  (2026-04): Ubuntu 24.04, CUDA 13.1.1, Python 3.13, Quarto 1.9.37.
- **Working inside the container.** Claude Code / VS Code run both on the host and
  **inside a running job's container** (VS Code remote-ssh into a SLURM job). Inside, the
  working directory is typically under `$SCRATCH/job/` or a bind-mounted lustre path, and
  there are no `singularity`/`$SCRATCH`/SLURM binaries — which shapes how you test and
  submit (see *Developing & committing*).

## Finding jobs

Don't `grep` the r3 repository to locate jobs — slow, and it misses the point
(jobs are content-addressed; queryable metadata lives in the index). Query the
index instead:

- **`xr3 find`** searches the whole repo (wraps `repository.find`):
  - `-p/--path GLOB` — match `metadata.path` (literal SQLite GLOB; add `*`
    yourself, e.g. `-p '*DAEMONS*'`). The usual way in. This globs the r3 path
    directly, so it needs no filesystem→path mapping and works for any project.
  - `-t/--tag` (repeatable) — jobs carrying all the given tags.
  - `-q/--query` — arbitrary Mongo-style query as JSON, merged in. Bare
    fragments get brace-wrapped, so the key must be quoted:
    `-q '"tags": {"$all": ["research"]}'`. This already exposes the full query
    grammar (`$glob`, `$in`, `$elemMatch`, …).
  - `--long` → `id | datetime | path | tags`; `--latest` → only the newest match.
- **`xr3 history <dir>`** is the narrower tool: the version chain of the single
  job at a path. It maps the filesystem dir to its r3 `metadata.path` via the
  configured **pathmap roots** (`~/.config/xr3.yaml`; this clean mapping is exactly
  what the eponymous-subdir layout in *Project & path layout* buys), so it — and the
  other pathmap commands (`diff` / `check` / `commit`) — only work under a configured
  root; a **new project must be added to `pathmap.roots` in your config first** (see
  `extensions/CONTRACT.md`). `find -p` has no such requirement, so
  prefer it for new or cross-project search.
- **Escape hatch — r3 has a Python API** (`r3.Repository(path).find(query)`
  returns `Job` objects). Drop to a throwaway snippet when you need to *use* the
  results in Python (read a metadata field, follow dependencies, post-filter), or
  when the query is simply easier to build in code than as CLI JSON.

## Config & dependencies

- **Config: avoid env-var overrides** (hard to track). Use a `config.yaml` once
  an experiment is complex enough; inline Python constants are fine for short
  jobs. Keep `run.sh` generic — treat it as a wrapper you don't go looking in.
- **Container / packages**: `pip install --user` at runtime is fine for quick
  experiments. Cut a new research-container revision once a project matures or
  becomes standalone, or once packages are clearly useful across many future
  jobs (then bundle them).
- **Dataset jobs**: a `run.py` that downloads AND smoke-tests the loader at build
  time, so schema problems surface immediately, not three jobs later.
- **Narrow dependencies with `source:`.** Point a dependency at the one file you
  actually use (`source: output/final_sac.zip`, `destination:
  DAEMONS_final_sac.zip`) rather than checking out a whole job output. It states
  the real requirement, reads better in the job dir, and survives the upstream
  job gaining other outputs.
- **r3-ignore an on-disk cache for expensive inputs.** A dev-tree directory
  listed in `r3.yaml`'s `ignore` (e.g. `pysaliency_datasets/` holding downloaded
  archives and expensive intermediates) makes a job cheap to re-run while
  iterating, while a fresh `r3 checkout` still starts empty and rebuilds from
  scratch. Skip-if-present must verify a hash rather than just existence.
- **Params a downstream job reads → commit them as a file, not only `task_meta`.** An
  `r3 checkout` (and any recursive-copy dependency) **omits the upstream job's
  `metadata.yaml` and `r3.yaml`**, so a downstream job that fans in many upstreams
  (`find_all`) **cannot** read their hyperparameters from `task_meta`/`gridsearch_meta`
  across the checkout — that file isn't there. Keep such params in **both** places:
  `task_meta` (for *querying* — the whole point of params in metadata) **and** a
  committed regular file (e.g. `config.yaml`) so a consumer can read them back.

## Developing & committing

Jobs are **developed in a working directory, then committed** to the r3 repo. The house
loop:

1. **edit** the job files (`run.sh`/`run_inner.sh`, `config.yaml`, `r3.yaml`,
   `metadata.yaml`, `report.qmd`, …);
2. **`xr3 dev-checkout .`** — check out dependencies (real clones for git repos,
   symlinks for data/containers) so you can develop and smoke-test against them;
3. **develop & smoke-test** locally (in-container dev testing below, or `run_job_locally`
   for the full path);
4. **review what will be committed** — `xr3 files .` (the file list) and `xr3 diff .`
   (config/metadata/code vs the last committed version);
5. **`xr3 check .`** → **`xr3 commit .`** (commit runs `check` by default);
6. **`xr3 dev-cleanup .`** to remove the checked-out deps.

**Submit with `xr3-slurm`, never by hand** _(MLCloud/SLURM)_ (and never with the obsolete
monolith `xr3-obsolete`): `xr3-slurm submit $(xr3 history --latest --id .)` submits the latest
committed job for this dir; or `xr3-slurm submit --tag <tag>` / `<job-id>`. Per-command
detail for everything above is in the r3-tooling tool READMEs
(`extensions/xr3/README.md`, `…/xr3-slurm/README.md`); what the tools
*require* of a job is in `…/extensions/CONTRACT.md`.

- **Running `xr3` / `r3` / `xr3-slurm`.** These are wrapper scripts on your `PATH`
  (installed by `install.sh` — see `SETUP.md`), so they resolve **by name in any context**
  — interactive *and* non-interactive shells (an agent's Bash tool, cron, `srun bash -c`)
  and `subprocess`/`execvp` — with no `PYTHONPATH`, env activation, or explicit path
  needed. The wrapper pins the r3 install's environment, where `r3` is editable-installed.
  `$R3_REPOSITORY` must be set (once, at install/login — see `SETUP.md`). `xr3` is the
  cluster-agnostic dev workflow; `xr3-slurm` is SLURM submission/observation
  _(MLCloud/SLURM)_. Setup + what the tools assume about jobs: `SETUP.md` and
  `extensions/CONTRACT.md`.
- **SLURM commands (`squeue`/`scancel`/`sacct` … and `sbatch`).** On a compute/bare node
  these run directly. **Inside a container** (no SLURM binaries — e.g. a VS Code remote
  session in a running job) tunnel them: `ssh galvani "squeue -u $USER …"`, `ssh galvani
  "scancel <id>"`. Read-only queries (squeue/sacct) are safe to run this way from anywhere —
  useful for an agent's Bash tool to check/kill jobs. **`sbatch` is the exception: submit it
  via `ssh galvani` even from a node.** Submitting from inside a running job *seems* to leak
  that job's `SLURM_*` env vars (e.g. `$SLURM_STEP_ID`) into the new submission and cause
  problems (unconfirmed root cause). This is why `auto_submit.py` runs `squeue` locally
  (`SLURM_QUERY_MODE`) but always `sbatch`es over SSH.
- **In-container dev testing**: when working inside the container (no
  `singularity`/`$SCRATCH`), test a job by calling `run.py` (or the entry script)
  directly with the in-container python (`pip install --user` any missing deps);
  `run.sh`/`run_inner.sh` are host/SLURM wrappers and can't be exercised from
  inside.
  - **Iterate reports the same way — render Quarto locally, skip the SLURM
    round-trip.** Inside the container, re-render a report's `.qmd` straight from
    its working dir instead of the commit → `xr3-slurm submit` round-trip on every change:
    ```bash
    PYTHONPATH=pysaliency:libmkuemmerer:<other dep repos from r3.yaml> \
        quarto render report.qmd --to html --output-dir output_smoke
    ```
    `PYTHONPATH` is the **checked-out dependency repos** (as in the job's
    `run_inner.sh`), *not* a base-env install — the container's stock python
    usually lacks `pysaliency`; it comes from the dev checkout. For an even
    cheaper loop, run just the key cells (model load + one eval + one plot) as a
    throwaway script under the same `PYTHONPATH`. **Probe first** — `which
    quarto`, `python -c "import pysaliency"` (with that `PYTHONPATH`),
    `nvidia-smi` — because a given session may be *outside* the container or in
    one without a GPU/quarto; fall back to the commit → `xr3-slurm submit` flow if any fail.
    **Write ad-hoc renders to `output_smoke/`**, never the real `output/` that
    `xr3 commit` bundles.
- **Pre-commit habit**: run `xr3 files .` before `xr3 commit .` to confirm no
  stray/large temp files would be committed (a dependency dropped from `r3.yaml`
  stops being auto-ignored — check for it), then `xr3 check .` → commit.
- **Commits are revertible → "commit often, move fast".** `xr3 commit --remove-previous`
  (`-r`) deletes the previous job at the same path; add `--copy-previous-output` (`-c`)
  to copy the previous output first (`--exclude-done`/`-x` skips the `done` marker) —
  copying breaks provenance, so use carefully.
- **Keep git dependencies clean — tools write into the checkout.** `xr3 check`
  fails on any staged/unstaged/untracked change in a checked-out repo, and
  running a library's own test suite routinely creates untracked files there:
  pytest's `.pytest_cache/`, pysaliency's autouse download-cache fixture
  (`download_cache/`, relative to cwd), and any non-public test data you place at
  the path the tests expect. Create such things in a `trap … EXIT` and remove
  them there, rather than editing the library's `.gitignore` — that is an
  unrelated edit riding along in a feature PR. Disable what you can
  (`pytest -p no:cacheprovider`) and push temp dirs outside the checkout
  (`--basetemp=`, pointed at the r3-ignored cache).

### Upstreaming changes to a git dependency

When an experiment needs changes to a git-dependency repo (e.g. adding a model or
loader to a released package, or promoting code into a library), the changes are
developed **inside the dev-checkout of that repo** and land upstream via a normal
PR before the job is committed. The mechanics of the dev-checkout are the part that
isn't obvious:

- **`xr3 dev-checkout` leaves git deps in detached HEAD, with `origin` pointing at
  the `$R3_REPOSITORY` bare cache**, not github. It also adds an **`upstream`**
  remote pointing at the canonical github repo. So the first move is to get onto a
  real branch off upstream:
  ```bash
  cd <dep>/ && git fetch upstream
  git checkout -b feature-<name> upstream/<base>   # <base> = the r3 dep's branch, e.g. main or dev
  ```
  Develop and commit on that feature branch in place.
- **Keep the feature branch local until verification passes** — no push while
  iterating. Push only once it works end-to-end; then open the PR and (repo owner)
  merge into the base branch.
- **Re-running `xr3 dev-checkout` is safe** — it skips dependencies already present,
  so it will not clobber your in-progress feature branch. (Conversely it will not
  *update* an already-checked-out dep either; to move a dep onto a new commit, update
  it in git directly, or `dev-cleanup` that dep and re-checkout.)
- **The committed *job* can only run after the changes are pushed and the job is
  committed** (commit freezes the git dep to a pushed commit). To validate
  end-to-end *before* pushing, run the job's `run_inner.sh` directly in the
  dev-checkout — it binds the working dir and puts the checked-out `DeepGaze/` (your
  local feature branch) on `PYTHONPATH`, so it exercises exactly the unmerged code.
  This is the host/SLURM/singularity path (needs a GPU node for GPU jobs), so it is
  typically the human collaborator who runs it.
- **`xr3 dev-cleanup` guards unpushed work**: it checks the checked-out commit
  against what the dependency would resolve to, so a committed-but-unpushed change
  trips the guard. (The one gap: committing on a new branch, not pushing, then
  switching back to the base branch — unrealistic in practice.)
- **`xr3 commit` is a thin wrapper around `r3 commit`, which refreshes the bare
  cache**, so a branch/tag in `r3.yaml` resolves to the freshly-pushed/merged commit
  without a manual cache fetch.
- **`ignore:` is job-level, not dep-level.** r3-ignoring a path keeps it out of the
  *job* commit, but `xr3 check` separately requires each **git-dependency checkout**
  to be clean (no untracked/dirty files). Those are different checks: files written
  *inside* a dep's directory dirty it regardless of `ignore`. This only bites when
  something writes into the dep — e.g. running the dep's own pytest suite (autouse
  cache fixtures, `.pytest_cache/`) or placing test fixtures at a path inside it; a
  job whose `run.py` only reads the dep and writes to `output/` never dirties it and
  needs no cleanup. When it does bite, remove the offending files in a `trap … EXIT`
  (see "Keep git dependencies clean" above), don't edit the dep's `.gitignore`.

**Sequence, end to end:** `dev-checkout` → branch off `upstream/<base>`, develop +
commit locally → validate in the dev-checkout (smoke-test `run.py` cheap; then a real
end-to-end `run_inner.sh` run, human-run for GPU jobs) → push, PR, merge → get the dep
onto the merged base commit (`git fetch upstream && git checkout <base>` in the dep,
or `dev-cleanup` + re-checkout) with a clean tree → re-run to confirm nothing changed
→ `xr3 check` → `xr3 commit`. The `xr3 commit` step is therefore blocked on an
external merge and is the last thing that happens. First applied in the
DAEMONS→pysaliency promotion (`research/experiments/2026-08-04_DAEMONS-in-pysaliency`).

## Promoting experiment code into a library

When bespoke experiment code graduates into a shared library, the r3 job whose
frozen `output/` the old code produced is a ready-made oracle: the new
implementation has to reproduce it. Split the verification in two, so that a real
regression cannot hide behind an expected difference:

- **Fidelity check** — drive the new code with *exactly* the inputs the old job
  used, and demand exact equality. Any difference is a porting bug.
- **Real-path check** — drive it the way the library will actually be used, and
  assert that the differences are precisely the ones you can name, with their
  expected magnitudes hardcoded as tripwires. Never widen a tolerance to absorb a
  difference you have not explained.

**Compare dtypes, not just values.** Value equality hides representation bugs: an
object-dtype array of `False` compares equal to a float array of `0.0`, and the
difference only surfaces on serialization (`Object dtype has no native HDF5
equivalent`). Cheap in-memory comparisons will pass while the library is broken
for anyone who saves the result.

**Expect to find bugs in the old code, and do not reproduce them.** Fix them in
the library and attribute the residual difference explicitly, rather than
replicating a bug to make the comparison come out clean.

First applied in `research/experiments/2026-08-04_DAEMONS-in-pysaliency`, which
found both of the above: the dtype trap, and that the original DAEMONS import
script never flushed its last accumulated scanpath — so every DAEMONS dataset in
r3 is missing one trial per split.

## Resumable jobs (preemption · OOM · wall limits)

Make any non-trivially-long job **resumable** — a killed run continues instead of restarting from
zero. Low bar: if a restart-from-zero would hurt, do it. The payoff is more than crash-recovery:

- **Preemptable partitions** (cheaper, but jobs get killed mid-run) become usable freely.
- **Request modest resources** and accept the occasional **OOM** → resubmit, instead of
  over-provisioning memory/GPU to guarantee headroom.
- **Wall-time limits stop mattering much** — a job that hits the wall just resumes next run, so you
  don't have to size `--time` precisely.

How:

- **Checkpoint at the natural work unit** (per image / batch / trial). On start, **skip units already
  done** — verify by content/key/hash, not bare existence — and write each unit durably as you go.
- **Signal completion with an `output/done` marker**, never "the output file exists"; consumers gate on
  it, and guard the entry script (`[ -f output/done ] && exit 0`) so a complete resubmit no-ops.
  Resume = resubmit the same job.
- **Atomicity must match the resume unit.** Atomic-write *per unit* is resumable (separate per-trial
  files via tmp+rename; the keyed on-disk cache in *Config & dependencies* above). Atomic-write of the
  *whole output* — one big `.tmp` renamed only at the very end — is crash-safe but **discards all
  in-flight work on a kill**, the opposite of resumable. For a single multi-item output file, append in
  place instead (e.g. HDF5 `export_model_to_hdf5(overwrite=False, flush=True)`: skips items already in
  the file, flushes each).
- **Pair with a resubmit loop** (`auto_submit.py` / autoslurm restart-on-failure): resumable job +
  preemptable partition + resubmit = self-healing — the submitter just resubmits until `done`.

Caveats: a present-but-partial output is why completion needs the separate `done` signal; in-place
per-unit writing has a small mid-write corruption window (if a resumed open fails, drop+recompute that
unit); a *deterministic* per-unit failure (one item always OOMs) loops forever on resubmit — that needs
more resources, not resume. First applied in
`experiments/2026-08-20-distribution-metrics-saliency-gold-standards/gold_density` (per-image HDF5
append-resume; the initial whole-file tmp+rename had made an OOM'd job restart from image 0).

## Long-running tasks (detached + resumable)

For work that outlasts an interactive session — a container SSH/VS Code
connection often drops on laptop sleep or a location change, killing
harness-managed background jobs — launch it **detached** and make it
**resume-safe** so a death costs nothing.

- **Detach from the session** with `setsid nohup`, log into the job's `output/`
  (timestamped, matching `run_job_locally`'s `output/slurm_manual_<ts>.log`),
  stdin from `/dev/null`:
  ```bash
  mkdir -p output
  setsid nohup <cmd> > "output/run_$(date +%Y%m%d_%H%M%S).log" 2>&1 < /dev/null &
  disown
  ```
  The process reparents to init (verify: `ps -o pid,ppid,sess` → PPID 1, own
  session) and survives disconnection. Log in `output/` so anyone can `tail -f`
  it anytime. Gotcha: under `setsid`, `$!` is the *wrapper* PID, not the real
  process — get the actual PID with `pgrep -f <script>` (for a `kill -0` liveness
  check in the watcher).
- **Make it resumable via an on-disk cache on _lustre_** (not node-local
  `$SCRATCH`, which is wiped): cache each expensive unit (e.g. every LLM API
  call) keyed by its inputs, written atomically (tmp file + rename). On restart
  the script replays cache hits instantly and only redoes unfinished work — a
  killed process loses no work and spends nothing twice. **Resume = re-run the
  same command.**
- **Controls:** monitor `tail -f output/run_*.log`; stop `pkill -f <script>`;
  resume by re-running (re-detach with the same `setsid` form if needed).
- **Caveat + fix:** a detached process is no longer a Claude-Code background
  task, so the agent won't get an automatic completion ping. Recover the ping by
  pairing it with a **throwaway, non-detached harness watcher** that polls for the
  done-marker (or the process disappearing → died, resume needed) and exits —
  which notifies the agent. If the connection drops, only the cheap watcher dies;
  the detached compute keeps running and you just restart the watcher. No compute
  lost. (Watcher: `until grep -q '^done$' output/run_*.log || ! pgrep -f <script>;
  do sleep 30; done`.)

First used in the MathTutorBench zero-shot-baseline (the OpenRouter judge run,
5k+ cached API calls).

## Reports & writing

- **Be concise.** Detail where warranted (key investigations, discussion), terse
  elsewhere; lean on tables/figures over prose; don't narrate what a figure
  shows; cut filler/hedging. Default *shorter* than feels natural.
- **tl;dr = the headline result, not a summary of everything.** The `tl;dr`
  callout states the single most important result(s) — what you'd say if the
  reader read nothing else — not a section-by-section overview. One or two
  sentences; name the number and the comparison that matter. E.g. "some current
  models zero-shot outperform the paper's *finetuned* reward model", not "we
  evaluated N models on M prompts and analysed position bias, prompt
  sensitivity, …". Supporting caveats belong in the body, not the tl;dr.
- **Charts: clean and honest.** Error bars where there's a CI; don't truncate a
  bar axis to exaggerate (start at 0 or a meaningful floor like chance); direct-
  label thresholds; highlight the one mark that carries the point; no legend for
  a single series (the title names it). See the `dataviz` skill for the fuller
  method.
- **Compute numbers in prose; don't hand-copy them.** A hand-typed figure drifts
  from the analysis silently. Use Quarto inline code (e.g. `` `{python} f"{x:.2f}"` ``
  reading a value computed in an earlier cell) so the prose is a view of the
  computation. Compute each value near where it's used rather than in one big cell
  up front; coarse rounded magnitudes are fine in the tl;dr. (Inline `{python}`
  needs the rendering container's Quarto ≥ 1.4.)
- **Keep all code accessible.** Don't `#| echo: false` a cell in a code-fold report
  — it drops the code from the rendered HTML entirely (not even uncollapsible).
  Suppressing *output* (`#| output: false`) is fine, e.g. to keep loading noise out
  of the report.
- **Report sections**: house template is `research/experiments/report_template/`
  — a `tl;dr` callout, then Intro / Method / Results / **Discussion** /
  **Follow up ideas** / Appendix. Keep a "Follow up ideas" section to seed future
  brainstorms; write future-experiment ideas there. An open-ended "let the agent
  explore the data and report anything interesting" section is welcome (trim
  later).
- **Report review loop**: research reports can be improved via a human-gated
  review→revise loop mapped onto the r3 path-version chain (independent
  single-stance reviewer agents → `REVIEW.md` → human picks issues → revise).
  First matured in the MathTutorBench `pedagogical-reward-data/report` job
  (`SPEC_REVIEW.md` + `REVIEW_LOOP.md` + `reviewers/`); extract to a shared skill
  once it's been applied a few times.

## Known issues / gotchas

- **Quarto 1.9 + PID namespace + dual-format output.** Quarto 1.9.37 (Deno 2.x) has a
  bug where `mkdirSync({recursive: true})` fails with `ENOENT` when running inside a
  Singularity PID namespace (`-p`) **and** rendering to multiple formats at once
  (`--to gfm --to html`). Single-format renders work fine with `-p`. Workarounds:
  render the formats separately; drop `-p`; or pre-create `$HOME/.cache/quarto/sass`
  and `$HOME/.local/share/quarto/logs`.

## Open problems (unsolved — design later)

### Co-developing a report against still-evolving *stochastic* compute
When compute is a stochastic LLM run, re-running committed code never reproduces
the output, so the frozen output *is* the artifact. This fights the clean
compute→report split when you want to iterate on the report before compute is
final. Options weighed (Spatial-Saliency v5/v5.1), none fully satisfying:
1. **Single job** (compute+report together, `copy_dev_output_to_r3`): lowest
   friction; provenance loss minor (re-running wouldn't reproduce anyway). Cost:
   can't re-render the report reproducibly without re-touching compute.
   *Pragmatic default for now.*
2. **Proper split, report depends on the committed (possibly still-running)
   compute job**: purest provenance, but recommit→recheckout churn on every
   compute code change is painful during active development.
3. **Split, but compute runs in its dev tree and the report mocks the dependency**
   via a symlink to `../compute/output`: keeps single-job iteration speed and
   ends in the clean split. *Refinement:* give the report a fixed
   `compute_output/` path (dev symlink now, real r3 dep at commit) so
   `report.qmd` is byte-identical in dev and committed modes. Candidate standard
   once an experiment genuinely co-evolves report + compute.

### Secrets handling in r3
API keys (academiccloud, OpenRouter, …) currently live in committed
`config.yaml`, so they land in the r3 repo. Tolerable for now (low-value,
user-owned, revocable keys) but wrong in general. Options to design later: an
untracked `secrets.yaml` (r3-ignored) merged into config at runtime; reading keys
from env vars injected by `run.sh`; or a small secret store. Needs a convention
so keys never enter committed jobs. First hit in the MathTutorBench
zero-shot-baseline (academiccloud key, then an OpenRouter billing key).
