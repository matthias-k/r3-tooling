---
name: r3
description: Use when working with r3 jobs — authoring or reading an r3.yaml recipe, wiring find_latest/find_all or git dependencies, committing or checking out jobs, querying job metadata, the r3 Python API (Repository/Job), or tracing provenance/lineage across r3 jobs.
---

# r3 — operating manual

r3 stores computational jobs, their dependencies, and their outputs with provenance.
This is a terse, task-indexed reference; deeper detail lives in the sibling files
`reference/gotchas.md`, `reference/python-api.md`, `reference/query-grammar.md`, and
`scripts/r3dev.py` — load them on demand. r3 is driven by a **CLI** (the lifecycle verbs)
and a **Python API** (working over the job graph); the "CLI vs the Python API" section
covers when to use which, and each command is introduced below where it's first used. You
work against a **repository** — create one with `r3 init <path>` and point r3 at it via
`$R3_REPOSITORY` (or `--repository` per command).

> **Verified against r3 `main` `262a937` / v0.5.0 on 2026-08-17.** r3 grows with `main` —
> confirm claims against live `r3` before relying on a subtlety (see "Keep this current", below).

## 1. The model — a job is a self-contained directory

- **A job is an *isolated* directory** — self-contained, with everything it needs available
  locally. The intended model is that a job's code references **nothing outside its own
  directory** — because that isolation is what lets a committed job be an exact, reproducible
  record (its **provenance**). (r3 doesn't enforce it; reaching outside sometimes makes sense,
  at the cost of provenance — the reach isn't recorded or frozen.)
- **Dependencies keep a job self-contained — and are what give it provenance.** A dependency
  declares something that lives elsewhere — a **git repository**, or the **output of another
  r3 job** — and makes it **available locally** in the job (a shared library, an upstream
  dataset) without duplicating it. At `commit` each is **resolved and frozen to an exact
  version** (a git commit hash / an upstream job's uuid), so the dependencies *are* the record
  of what the job was built on. A committed job's dependencies are thus **always resolved**; an
  *unresolved* one (a loose `find_latest` query, an unpinned git ref) exists only in a working
  directory, before commit. You declare dependencies in the job (see "Authoring a job" and
  "Dependencies", below).
- **`checkout` is the procedure that realizes this.** From the frozen recipe it assembles a
  runnable, fully-local job, materializing each dependency in place — without needless copying
  (shared data is symlinked, not duplicated). Checkout is r3's only runtime touchpoint;
  running the assembled job is then your own code.
- **`commit` freezes the job.** It hashes your files (for integrity) *and* resolves each
  dependency to an exact version — a git **commit hash**, or another job's **uuid** — and
  records them in the recipe (`r3.yaml`). The job gets a **fresh `uuid4` identity** (not
  content-addressed: two identical recipes get two different ids).
- **That freezing is the provenance and reproducibility guarantee:** a committed job is a
  self-contained, immutable record of exactly what produced its results — **immutable except
  `metadata.yaml` and `output/`**.

Corollaries, true throughout r3:

- **r3 is not an execution engine.** There is no runner, scheduler, or "run this" field in
  the recipe — r3 never runs your job; `run.sh` is just a user convention.
- **The job dir is free-form.** Every non-ignored file freezes into the recipe — configs,
  modules, notes — not just executable code.
- **`output/` is the one place results persist.** Writing anywhere else during an in-place
  run hits the read-only job dir (`PermissionError`).
- **You can reorganize later without breaking anything.** Because `metadata.yaml` is mutable
  and *not* hashed, and dependencies pin to fixed uuids/commits, you can restructure your
  `path`/tags whenever — committed jobs keep resolving; only new jobs see the new layout.

## 2. Authoring a job

Authoring a job is **implementing whatever the job's purpose requires**, in the job directory:

- usually a **run file** — `run.py` / `run.sh` are the canonical names — but **r3 doesn't
  require one and doesn't care what a job *does***. Besides the common compute job (run →
  write results to `output/`), a job can **provide** something to downstream jobs (e.g. serve
  a model over a local API) or simply **hold** data.
- usually **config** — e.g. a `config.yaml` (just another file r3 freezes);
- often **more** — extra modules, whole sub-package directories, data-prep code;
- and **declaring the job's dependencies** — git deps and job deps (via `find_latest` /
  `find_all` queries). Constructing the right dependency queries is part of authoring, not an
  afterthought (syntax under "Dependencies", below).

**Making a git dependency importable is your job, not r3's** — r3 only materializes the
repo's files at `destination`. Two ways: narrow `source:` to the package subdir so
`destination` is directly importable, or check out the whole repo (the default) and add it
to `PYTHONPATH` / `sys.path` in your run script — a whole-repo checkout also makes editing
and upstreaming changes easier.

`r3.yaml` (the recipe) and `metadata.yaml` are **optional** — `commit` synthesizes them (an
empty `metadata.yaml`, and an `r3.yaml` recording the file hashes, resolved dependencies, and
a timestamp).

## 3. Dependencies

**Git dependency** — `{repository, destination, source?, branch?/tag?/commit?}`.
**github.com only** (https or ssh). With no pin, it resolves to the remote's
**default-branch HEAD** at commit and freezes the 40-hex `commit:` — a `branch:`/`tag:` is
frozen to the resolved commit, not preserved as a branch/tag. Cached as a bare clone under
`<repo>/git/github.com/<owner>/<name>`.

**Job dependency** — `{find_latest|find_all: <query>, destination, recursive_checkout?}`.
`source?` is **`find_latest`-only** — a `find_all` recipe takes no `source` (it always checks
out the whole job root, one subdir per match; a `source:` key on `find_all` raises
`TypeError`). Resolves at commit and keeps **both** the loose query and the resolved
`job: <uuid>`. Materialization:

- `source: "."` + `recursive_checkout: true` (both defaults) → a **recursive real copy**,
  including the dependency's own transitive deps.
- otherwise → a **symlink** (`source: output` symlinks to the upstream's `output/`; any
  non-`.` source is always a symlink).

So `source:` selects **scope, not duplication**. A `find_latest`/`find_all` that **matches
nothing fails the commit** (`ValueError: Cannot resolve dependency: <query>`) — a mistyped
query surfaces at commit, not silently. (A *resolved* dep whose target or `source:` subpath is
missing from the store fails similarly, with `Missing dependency`.)

**Reading old recipes:** the deprecated string form `query: '#tag #tag'` (space-separated
tags, AND'd) is common in older jobs — recognize it; steer new jobs to
`find_latest`/`find_all`.

**`ignore`** — absolute paths anchored at the job root, matched by exact path segments (may be
nested, e.g. `/code/__pycache__`); no globs, no `.gitignore`, and a pattern without a leading
`/` errors at commit. `output/` is excluded from every commit **unconditionally** anyway;
use `ignore` for other non-output artifacts (caches, rendered files, `__pycache__`).

## 4. A worked example

Authoring `mnist-eval`: it uses a library from github, depends on an existing dataset job
(found by its `path`), runs, and gets committed.

**Files in the job dir.** `r3.yaml` (the recipe):

```yaml
dependencies:
  - repository: https://github.com/example/toolbox   # the toolbox/ package → ./toolbox
    source: toolbox                                  #   narrowed so ./toolbox imports directly
    destination: toolbox
  - find_latest: { path: datasets/mnist }            # newest dataset job at that path
    source: output                                   #   its output/ → ./data
    destination: data
```

`metadata.yaml` (so you can find it later — see "Metadata & the `path` convention"):

```yaml
path: experiments/mnist-eval
tags: [mnist, eval]
```

`run.py` (run from the job dir, which is on `sys.path`):

```python
import os, toolbox                 # ./toolbox imports directly because of `source: toolbox` above
data = open("data/train.idx", "rb").read()   # data/ symlinks the dataset job's output/
os.makedirs("output", exist_ok=True)         # a dev run has no output/ symlink yet
open("output/results.json", "w").write(toolbox.evaluate(data))
```

(Whole-repo alternative: omit `source:` to check out the entire repo — handy for editing and
upstreaming — then add it to `PYTHONPATH` / `sys.path` in your run script; the import path then
depends on the repo's layout.)

**The flow:**

```bash
export R3_REPOSITORY=/path/to/repo          # or pass --repository each time

# 1. Develop: materialize the deps in place and test-run (dev output is throwaway).
#    (scripts/r3dev.py is bundled in this skill — copy it into your workspace or use its full path.)
python scripts/r3dev.py checkout mnist-eval
cd mnist-eval && python run.py              # writes a local output/ you can inspect
cd .. && python scripts/r3dev.py cleanup mnist-eval

# 2. Commit: freezes the recipe + resolves the deps; prints the job's uuid.
r3 commit mnist-eval                        # → a1b2c3…

# 3. Persisted results come from running the COMMITTED job via a checkout.
r3 checkout a1b2c3… /tmp/wd && cd /tmp/wd && python run.py
#   results now live in the store at <repo>/jobs/a1b2c3…/output/ (via the output/ symlink)

# 4. Find it again (find is tag-only; by path needs the Python API):
r3 find -t mnist -l
python -c "import r3; print(r3.Repository('$R3_REPOSITORY').find({'path':'experiments/mnist-eval'}))"
```

**What this shows:** a dev run's `output/` is **throwaway** — persisted results come from
running the **committed** job's checkout (step 3). You may `commit` with the dev deps still
materialized (`commit` ignores dependency destinations); `cleanup` is hygiene, and how you
re-resolve a moved upstream. The dev step (1) is **optional** — skip it for simple or
auto-generated jobs; for expensive jobs, smoke-test with reduced parameters rather than a full
run.

## 5. Running & the lifecycle (the details)

- **Run a dependency-free job in place** — `cd <jobdir> && python run.py`.
- **A job with dependencies** — `r3 checkout <id> <workdir>` first, to materialize the
  committed job and its deps into a fresh workdir, then run there. The workdir is **throwaway
  scratch**: only its `output/` symlink persists back to the store, so you can write
  preprocessed data / expanded configs / scratch there freely (repo-relative paths, no
  temp-dir juggling) — gone when you delete the workdir; the target must not already exist.
  (Dev trick: an **ignored `cache/`** in the job persists across dev runs for speed while the
  committed job still recomputes from scratch.)
- **Dev checkout** (running an *uncommitted* job): there is no CLI for this — r3 removed the
  command on purpose (the right behavior varies per user). The primitive is
  `repo.checkout(unresolved_dep, dir)`; `scripts/r3dev.py` is the ~25-line reference loop
  (`python scripts/r3dev.py checkout|cleanup <jobdir>`). A dev checkout materializes only the
  deps (no `output/` symlink) and **cannot change what you commit**. **It's optional** —
  authoring and `commit`-ing directly is fine (and usual for auto-generated jobs); when you do
  dev-run, it's typically a **smoke test** (shrink the hyperparameters/inputs), not the full
  job — re-running an expensive run just to test it is wasteful, and the committed job produces
  the real results anyway.
- **Update an outdated job** — re-commit the authored dir; `commit` re-resolves each
  `find_latest`/`find_all` to the now-current match.
- **Remove / reclaim** — `r3 remove <id>` deletes a job but refuses (nonzero exit) if another
  job depends on it. Reclaim disk by deleting a job's `output/` (record it in `metadata.yaml`
  so an empty `output/` reads as intentional). `rm -rf` on a committed job fails (its dir is
  read-only) — use `r3 remove`, or `chmod -R +w` first.

## 6. Finding jobs & queries

`r3 find [-t TAG]… [-l] [--latest]` lists jobs — **tag-only** (`-t` repeatable, AND'd; `-l`
long shows `uuid | timestamp | #tags`; lists all by default, `--latest` the newest match).

For anything **beyond tags** — including **`path`** — use the query engine, via the Python
API (`repo.find(query, latest)`) or inside a `find_latest`/`find_all` dependency. `r3 find`
cannot search by path yet (`--path` is planned), so "find by path" means the API, or giving
the job a tag you can search. The grammar is Mongo-style but a subset only — full grammar,
array semantics, and the sharp gotchas → `reference/query-grammar.md`.

After editing metadata by hand, run `r3 rebuild-index` to refresh the query index.

## 7. Metadata & the `path` convention

`metadata.yaml` is **mutable, not hashed**, and must be **JSON-representable** — a bare YAML
date raises `TypeError` at commit, so quote dates. Edit it via `r3 edit <id>` (opens
`$EDITOR`, then reindexes) or edit the file and `r3 rebuild-index`.

`tags` is the only metadata field r3's *tooling* privileges today (`find --tag`, `#tag`
rendering in `find -l`).

**`path` is the recommended organizing convention** — a virtual-filesystem path that
`find_latest`/`find_all` build on. It's queryable like any other metadata field, but not yet
surfaced by the CLI (`--path` / an `r3 ls` are planned). Treat these as examples, not rules:

- Flat (`kodak`) or nested (`datasets/kodak`, `my-project/experiments/pilot`).
- A `path` **need not be unique** — a whole sweep can share one; `find_latest` picks the
  newest, `find_all` returns them all.
- A `path` is a **movable namespace** — re-path later; frozen deps are unaffected.
- Groups often prefix paths with a project name for global uniqueness — one option, not a
  mandate.

## 8. CLI vs the Python API

**Prefer the CLI for the lifecycle verbs.** It is the permission-bounded default: allowlisting
`Bash(r3 …:*)` grants a bounded, auditable verb set, whereas driving the API means granting
arbitrary code execution. The full verb set:

| Verb | Does |
|------|------|
| `r3 init <path>` | create a repository (the one verb with no `--repository`) |
| `r3 commit <jobdir>` | freeze a job; prints the bare uuid |
| `r3 checkout <id> <workdir>` | materialize a committed job into a fresh workdir |
| `r3 remove <id>` | delete a job (refuses if another job depends on it) |
| `r3 find [-t TAG]… [-l] [--latest]` | list jobs — **tag-only** |
| `r3 rebuild-index` | rebuild the query index from the job files |
| `r3 edit <id>` | open `$EDITOR` on `metadata.yaml`, then reindex |

Every verb but `init` reads the repository from `$R3_REPOSITORY` or `--repository`;
`R3_REPOSITORY=""` counts as unset.

**The Python API is r3's general interface to the job graph — for reading *and* reshaping
it**, not just a fallback. Reach for it whenever the task is working over the graph rather
than running one lifecycle verb — e.g. *find every job, in any dependency order, that
transitively uses repo X at commit Y*. Two things the CLI does not cover that the API (or an
environment's own tooling) does: **querying beyond tags** (see "Finding jobs & queries") and
**dev checkout** (see "Running & the lifecycle"). Entry points are `r3.Repository(path)` and
`r3.Job(dir)` → `reference/python-api.md`.

**Inspecting a committed job — there is no `r3 show`.** A committed job lives read-only at
`$R3_REPOSITORY/jobs/<uuid>/`; the repository also holds `git/`, `index.sqlite`, and a
**repo-root `r3.yaml` that only marks the repository format version — not a job recipe** (a
common confusion). To inspect a job, read its `r3.yaml` / `metadata.yaml` / `output/` there, or
open it with `r3.Job(dir)`. **Job ids are full 36-char uuids** — there is no prefix / short-id
matching, so a partial id is treated as "not found".

## 9. Non-obvious behaviors

r3 has several agent-biting behaviors. **Before relying on a subtlety, read
`reference/gotchas.md`.** The three that bite most:

- `find` (without `--latest`) returns rows in **unstable order** — never read it as a
  timeline.
- A **checkout omits `r3.yaml`/`metadata.yaml`** — the job's own *and* a recursively-copied
  dependency's — so a running job can't read its own metadata; keep runtime parameters in a
  committed file (e.g. `config.yaml`), not *only* in `metadata.yaml` (a checkout can't read it
  back — though keeping them in metadata *too* is what lets you query jobs by seed/variant).
- `output/` is the **only writable, persisted** location in a job.

## 10. Local tooling may supersede parts of this

Vanilla r3 is the floor. Environments commonly wrap it — a richer `find`, a dev-checkout
helper, a submit wrapper, a pre-commit convention checker, and so on. If the user or the repo
indicates such tooling exists (a project CLI on `PATH`, a house skill, the repo's
CLAUDE.md/README), prefer it for that operation over the raw CLI/API.

## 11. Keep this current

r3 tracks `main`, which moves. **Confirm against live `r3 --help`, live behavior, or the
source — not memory** — before relying on any version-sensitive detail.

The validity stamp at the top turns re-verification into a diff: run
`git log 262a937..main` on the r3 repo, focused on the CLI, `find`/query, checkout, and
`path`-promotion areas, and fold in what changed. In particular, the unstable-`find`-order
behavior is expected to gain an ordering upstream — check for it.

Your environment may also layer house/lab conventions on top of vanilla r3 — see your
environment's own docs for those.
