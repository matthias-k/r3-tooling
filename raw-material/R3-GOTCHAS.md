# r3 — non-obvious behaviors (raw material for an r3 skill)

> **Superseded — kept for provenance.** This is an *earlier* gotcha catalog pinned to an older r3
> (`c968f42`). The current, verified knowledge base is **`r3-findings.md`**, which supersedes this wherever
> they differ. Don't rely on this file.

Everything about r3 that was **not** clear up front while building this tutorial — assumptions
that turned out wrong, and behaviors you can only learn by reading the source or probing. Verified
against the pinned r3 (`c968f42`, r3 `0.5.0`; some notes predate PR #54/#55). Intended as input for
a proper **r3 skill** — so a future agent doesn't have to rediscover these. Terse; group + prune later.

## CLI surface (post PR #51 — job-IDs)
- `r3 commit <path>` prints the **bare job uuid** (the job id), *not* a `/…/jobs/<uuid>` path. Likewise
  `find`/`checkout`/`remove` reference jobs **by id** + read `--repository` / the `R3_REPOSITORY` env var.
  (This changed in PR #51; pre-#51 they printed/took absolute paths — a version-sensitivity trap.)
- `r3 init <PATH>` — positional path that must **not** exist; prints nothing on success (errors only).
- `r3 find` — `-t/--tag` (repeatable, AND-combined), `--latest/--all` (default `--all`), `--long/-l`.
  Short output = bare uuid per line; long = `<uuid> | <YYYY-MM-DD HH:MM:SS> | #tag1 #tag2`. Interactive
  `find` is **tag-only** — the richer metadata queries (e.g. `path`) exist in the query engine but aren't
  exposed on the CLI. Reads `R3_REPOSITORY`.
- **No `commands:` field.** Vanilla r3 never reads a `commands:` key in `r3.yaml` (a cluster executor
  would); putting one in is inert. Jobs run manually (`python run.py`).

## The job / commit model
- A job is just a **directory**. Minimal job = a single `run.py`; **no `r3.yaml` or `metadata.yaml`
  required** to commit — r3 synthesizes them.
- `r3 commit` **synthesizes/augments the committed `r3.yaml`**: adds `dependencies: []`, `hashes:`
  (a content hash of `.` and each file), and a `timestamp`; keeps any `ignore` you declared. Missing
  `metadata.yaml` is synthesized as `{}`.
- Identity = a **uuid**; integrity = the recorded content **hashes**. `commit` freezes the **recipe**
  (code + resolved deps), not results.
- **The read-only lock is selective, not blanket** (immutability): dir `555`, `r3.yaml` + code files
  `444` — but `metadata.yaml` is deliberately left writable (`664`); see *Removing jobs* below.
  Gotcha: a naive `shutil.rmtree` over a workspace containing committed jobs **fails** on the locked
  parts — you must restore write bits first (walk + `chmod u+w`). (source: `storage.py
  _remove_write_permissions`.)

## output/ and ignore
- **`output/` is excluded from the commit by default** (as of **PR #54**). Before PR #54 it was **not**
  — output was copied in *and* folded into the `hashes`, unless you declared `ignore: [/output]`. r3
  always creates an empty `output/` in the committed job regardless.
- `ignore` patterns must be **absolute** (`/output`, not `output/`); matched against top-level entry
  names. **PR #50** fixed patterns being lost when recursing into subdirs (so `/output` also excludes
  nested `output/sub/x`). r3 does **not** read a `.gitignore`.

## Producing results (recipe → results loop)
- Results come from **running** the committed job, not from `commit`.
- **Dependency-free job → run it in place:** `cd <repo>/jobs/<uuid> && python run.py`. The committed
  dir is read-only but `output/` inside is **writable**, so results land straight into provenance.
  Constraint: the job must write **only into `output/`** (writing elsewhere hits the read-only dir →
  `PermissionError`). Scripts with no local imports create no `__pycache__`, so the dir stays clean.
- **Job with dependencies → `r3 checkout` first.** In-place breaks because deps aren't materialized in
  the store dir. `r3 checkout <uuid> <workdir>` builds a **writable, disposable** workdir with: the
  job's files (read-only), each dependency as a **symlink** (e.g. `dep -> <upstream>/output`), and
  `output -> <this job>/output` (writable symlink into the store). Run there; the workdir is scratch.

## Dependencies
- **`source` IS honored for git deps** (verified 2026-07-27 — MK had assumed r3 ignored it, because his own
  habit is to check out the whole library repo and adapt `PYTHONPATH`). `GitDependency.__init__` takes
  `source` (default `""` = whole repo) and `Storage.checkout_git_dependency` does
  `shutil.move(clone_path / dependency.source, destination / dependency.destination)` — i.e. it selects
  which subpath of the clone lands in the job. That's why `source: toy_vision` yields an importable
  `toy_vision/` and not `toy_vision/toy_vision/`; the tutorial relies on it.
- **Git dependency:** `dependencies: [{ repository: <github url>, destination: <dir>, source: <optional
  subpath> }]`. Only **github.com** URLs (https or ssh). With no `commit`/`branch`/`tag`, r3 resolves to
  the repo's **default-branch HEAD** (`git ls-remote origin HEAD`) **at commit time** and **freezes that
  commit hash** into the committed `r3.yaml`. `branch:`/`tag:` override; `commit:` pins. The repo is
  `git clone --bare`d into a **shared cache** at `<repo>/git/github.com/<user>/<name>` (dedup across jobs).
  (source: `repository.py _resolve_git_dependency`, `utils.py git_get_remote_*`.)
- **Job/data dependency:** `dependencies: [{ find_latest: {path: <metadata path>}, source: output,
  destination: <dir> }]`. Resolves the query to a job, freezes it to that job's **uuid** at commit
  (the committed dep keeps **both** the `find_latest` query *and* the resolved `job:` uuid, plus a
  content hash of the dependency). How `destination` is materialised (**a choice, not a trap** —
  verified 2026-07-24 via checkout probes):
  - **Materialised recursive checkout** — *only* when `source: "."` (default) **and**
    `recursive_checkout: true` (default): the upstream job's code files are **real copies**, its own
    `output` is a **symlink**, and its dependencies are recursively checked out. A self-contained,
    importable dir (`cd <dir> && python -c "import model"`) — often *desirable*, **not a dumb copy**.
  - **Symlink** — otherwise `destination` is just a **symlink**: `recursive_checkout: false` → symlink
    to the job **root**; **`source: <subpath>` (e.g. `output`) → symlink to `<job>/<subpath>`**, and a
    non-`.` `source` **forces `recursive_checkout=False`** (an explicit `recursive_checkout: true` is
    overridden). So `source: output` = a symlink straight to the upstream's data.
  - **No data duplication in any mode** (`output` is always a symlink, or the whole dep is).
  (source: `job.py` `JobDependency`/`FindLatestDependency`/`FindAllDependency`, `recursive_checkout:
  bool = True`.)
- Everything is **frozen at commit** (git commit hashes, job uuids) → old jobs keep working as upstreams
  evolve. This is the provenance payoff.
- **Git dep + job dep together — confirmed, no interaction quirk** (spike against real
  `experiments/kodak` + private `r3-tutorial-toy-vision`, 2026-07-24; probed job had no `run.sh`, so
  the real playbook experiment will carry a 5th `hashes:` key once it acquires one). Committed
  `r3.yaml` keeps both deps in full — frozen 40-hex `commit:` for the git dep, `find_latest` +
  resolved `job: <uuid>` for the job dep — with a `hashes:` entry per destination (`toy_vision`,
  `images`, `run.py`, `.`). `r3 checkout` applies each dependency's own rule independently in one
  workdir: `toy_vision/` (`source: toy_vision`) comes out a real directory, not a symlink (mechanism:
  the `shutil.move` under *Stage-1 spike findings*); `images` (`source: output`) is a symlink to the upstream job's
  `output`. Downstream code reads through the symlink with no special handling; the run lands in the
  *consuming* job's own store `output/`.
- **Git dependency checkouts (verified 2026-07-28, pin `c968f42`).** `checkout_git_dependency` does
  `git init` + `remote add origin <mirror>` + `fetch --depth=1 <commit>` + `checkout FETCH_HEAD` in a
  temp dir, then moves `tempdir/<source>` into place. So:
  - `source: <subdir>` → you get that directory only, **no git metadata** — you cannot commit from it;
  - **`source` omitted** → you get the whole repository, `.git` included, as a **shallow (depth 1),
    detached** clone whose **`origin` is the mirror inside the r3 repository**, not the public remote.
    To contribute back you add your own remote; `git fetch <yours> && git checkout main` gets you onto
    a tracking branch (the short name matters — `git checkout <remote>/main` detaches), and a plain
    `git push` then works even though the clone is shallow. `git fetch` alone does **not** un-shallow
    it.
  - r3 normalizes an omitted `source` to `source: .` in the committed `r3.yaml`.

## Dev checkout (running a job you haven't committed yet)
Verified 2026-07-27 against the pin, end-to-end (spike + the playbook's own asserts). This is what the
tutorial's `r3dev.py` is built on — ~25 lines, no private API.
- **`Repository.checkout(item, path)` accepts an *unresolved* dependency** and resolves it first
  (`checkout` → `resolve` → `Storage.checkout`), so you can hand it a raw `find_latest:` or a
  version-less git dep straight out of `r3.Job(job_dir).dependencies` — no manual resolve step.
- **It works into an uncommitted job directory**, materialising exactly what a real checkout would:
  a git dep as a **real directory**, a job dep (`source: output`) as a **symlink** into the upstream
  job's `output/`. That is the whole dev loop: `for dep in r3.Job(d).dependencies: repo.checkout(dep, d)`.
- **No `output/` symlink — the one way a dev checkout differs from a real one (beyond location).** A
  committed job's `r3 checkout` symlinks `output/` back to the stored job so results persist in the
  store; a dev checkout is of an *uncommitted* job, so there is no `jobs/<uuid>/output/` slot to point
  at — and its output is throwaway anyway. `r3dev.py` only loops over `.dependencies`, so it never
  touches `output/`; the dev run just writes a plain local `output/` (ignored at commit by `Job.files`).
  So beyond the location it is *not* the same as a real checkout: same dependencies, results **not**
  persisted. This is the accurate framing for the playbook's dev-checkout beat.
- **`path` may be a `str` or a `Path`.** `Storage.checkout_job_dependency` does
  `destination / dependency.destination`, which looks `str`-hostile but works, because
  `dependency.destination` is a `Path` and `PurePath.__rtruediv__` handles the reflected operand.
- **A dev checkout can never leak into the commit.** `Job.files` builds its ignore list as
  `["/output"] + ["/" + dep.destination for dep in dependencies]` (`r3/job.py`), so committing a
  dev-checked-out directory stores only your own files — verified: the committed job came out as
  `['config.yaml','metadata.yaml','output','r3.yaml','run.py']`, with `toy_vision/` and `images`
  absent but still present as **dependency hashes** in `hashes:`. So "clean up before you commit" is
  hygiene (and how you re-resolve a moved upstream), **not** a correctness requirement at this pin.
- **Checkout does not overwrite an existing destination** — skip it yourself (`dest.exists() or
  dest.is_symlink()`) or remove it first; a git dep's `shutil.move` would otherwise nest the fetched
  tree *inside* the existing directory.

## Removing jobs
- `r3 remove <uuid>` succeeds only if **no** committed job depends on it; otherwise it refuses and
  the job survives. At the pin the refusal message is mangled and the exit code is **0**
  (R3-OBSERVATIONS #5) — key assertions on the dependent uuid + the job's survival, not the wording.
- A job's **`output/` stays mutable and deletable** — that's deliberate: clearing old checkpoints or
  datasets reclaims disk while the job (and therefore the compute graph) stays intact. Convention:
  record the deletion in the job's `metadata.yaml` so an empty `output/` is legibly intentional.
- **`metadata.yaml` is not content-hashed.** A committed job's `hashes:` covers its files and its
  dependency destinations plus `.` (a hash of the index of those hashes, `job.py:169-193`) — metadata
  is absent, so re-tagging can never change a job's identity or move a frozen dependency.
- **The read-only lock is selective, and metadata is deliberately exempt.** A committed job dir is
  `555`, `r3.yaml` and the code files are `444`, but **`metadata.yaml` stays `664`** — `storage.py:139`
  skips it when locking, and `docs/repository_format.md` calls it the file that "may be changed at any
  time". Rewriting it needs no chmod (verified 2026-07-24). The permission split *is* the
  frozen-vs-mutable division, visible on disk.
- **`metadata.yaml` is near-schemaless.** r3 only assumes `tags` is a list of strings (`cli.py` renders
  `#tag`; `find` queries `{"tags": {"$all": [...]}}`). Everything else is free-form — but it must be
  **JSON-representable**, because `index.py` does `json.dumps(job.metadata)`: a bare YAML date
  (`created: 2026-07-24`) loads as `datetime.date` and raises `TypeError` at commit. **`path` appears
  nowhere in r3's code** — it's purely a convention that metadata queries (`find_latest: {path: …}`)
  build on; same for `version`. (xr3 imposes more structure by choice.)
- **Deleting a job's `output/` keeps provenance but can cost reproducibility.** Re-running is rarely
  bit-identical (GPU nondeterminism), so a regenerated output can differ from the one downstream jobs
  consumed — detectable via the dependency's content hash, but still a real hazard; and a job may not
  re-run at all later (dead dataset URL, newer GPUs dropping old kernels). Delete only when the record
  is enough and the data is genuinely disposable.

## Install / packaging (bug — PR #55 open)
- r3 currently **cannot be pip-installed non-editable** (`[tool.setuptools] py-modules = ["r3"]` but `r3`
  is a package dir → a wheel/`git+https` install ships the console script but no package →
  `ModuleNotFoundError: No module named 'r3'`). **Editable** installs work. Fix = **PR #55** (open). This
  is why this tutorial pins r3 via an editable local clone rather than a portable `git+https` URL.

## Repo layout (after `r3 init`)
- `<repo>/{ jobs/, git/, index.sqlite, r3.yaml }`. Jobs at `jobs/<uuid>/`; git bare caches at
  `git/github.com/<user>/<name>/`; `index.sqlite` = the search index (job metadata as JSON, queryable).
  After editing a job's `metadata.yaml` by hand, `r3 rebuild-index` to pick it up.

<!-- Add as we hit more (verify in the Stage-1 spike + later stages):
     git-dep freeze-at-commit (no-pin → main HEAD; the frozen commit shows in the committed r3.yaml);
     in-place run breaks once a job has a dep → r3 checkout materializes the dep (+ output symlink);
     in-job run.sh self-checkout (reads its own uuid from its store path) + run.sh→run_inner.sh for
     complex runs (Singularity/multi-step); r3 remove + the won't-remove-if-depended-on guardrail;
     r3dev dev-checkout/cleanup; xr3/foreman deltas; remote storage; bug-marking / find_dependents;
     r3 edit / rebuild-index / Python API; config.yaml conventions. -->

## Stage-1 spike findings

Verified in a throwaway `R3_REPOSITORY`, against pinned r3 `c968f42`, with a real git dependency on
`matthias-k/r3-tutorial-toy-vision` (spike-time HEAD `ac0734918577d9f209adb93bc5fef38f454948c2`).

**Headline finding — the URL scheme matters, and the plan's example is wrong for this repo.**
`matthias-k/r3-tutorial-toy-vision` is currently **private** (`gh repo view` → `isPrivate: true`).
Anonymous `https://github.com/...` git operations fail in this sandbox (no stored https credential
for github.com) with `fatal: could not read Username for 'https://github.com': No such device or
address`, which r3 surfaces as `executor.ExternalCommandFailed: ... exit code 128!` when the shared
git cache doesn't exist yet. SSH (`git@github.com:...`) works (an agent key is already loaded) and is
what this spike used throughout. **⇒ Tasks 4-6 must write the dependency's `repository:` as the SSH
form** (`git@github.com:matthias-k/r3-tutorial-toy-vision.git`) **or the toy-vision repo must be made
public** before those cells are recorded — the https form as sketched in the Task-2 brief will not
clone on a machine without stored https credentials for a private repo. SSH-only works for MK's live
demo (key already present) but is a portability wrinkle for anyone else running the playbook.

- **Cache-key collision gotcha:** `GitDependency.repository_path` maps *both* URL forms
  (`https://github.com/<user>/<repo>` and `git@github.com:<user>/<repo>.git`) to the identical
  on-disk cache path `<repo>/git/github.com/<user>/<repo>`. So once that bare clone exists (e.g. from
  an earlier SSH-declared dependency), a *later* job that declares the **https** form will resolve
  and commit successfully by silently reusing the existing cache — it never re-attempts an https
  clone. Confirmed: re-running the same https-URL job against a **fresh** `R3_REPOSITORY` (empty
  cache) reproduces the exit-128 failure above. Don't let a warm cache hide an https-auth problem
  when re-testing.

**Per-check results** (all 6 PASS; no change needed to the dependency/job shape itself):

1. **Freeze-at-commit — PASS.** The committed `r3.yaml`'s `dependencies[0]` gained a resolved
   `commit: ac0734918577d9f209adb93bc5fef38f454948c2` (repository/source/destination unchanged),
   exactly matching `git ls-remote git@github.com:matthias-k/r3-tutorial-toy-vision.git HEAD`. A bare
   clone appeared at `<repo>/git/github.com/matthias-k/r3-tutorial-toy-vision/`. `commit()` printed
   only the bare uuid (per the CLI-surface notes above). Aside: `GitDependency.to_config()` only ever
   writes `commit:` once resolved — `branch:`/`tag:` never round-trip into the committed `r3.yaml`,
   so a resolved dependency looks the same whether the source job had no pin, a `branch:`, or a
   `tag:`.
2. **`source: toy_vision` checkout layout — PASS, not nested.** `r3 checkout <uuid> $wd` produced
   `$wd/toy_vision/__init__.py` + `$wd/toy_vision/patches.py` directly — an importable `toy_vision`
   package, no `$wd/toy_vision/toy_vision/…` nesting. `$wd/output` is a symlink to
   `<repo>/jobs/<uuid>/output`. Why: `Storage.checkout_git_dependency` shallow-fetches into a tempdir
   then does `shutil.move(tempdir/<source>, $wd/<destination>)` — a plain rename of the leaf dir; it
   would only nest if `$wd/<destination>` already existed as a directory beforehand, which it
   doesn't here. **⇒ no root-package fallback needed** — `source: toy_vision` / `destination:
   toy_vision` (basenames matching) is the right shape as planned; toy-vision does not need
   re-pushing with its package moved to repo root.
3. **In-place run breaks — PASS.** `cd <repo>/jobs/<uuid> && uv run python run.py` fails with:
   ```
   ModuleNotFoundError: No module named 'toy_vision'
   ```
   (raised on `import toy_vision`, after `import numpy` already succeeded). Gotcha found along the
   way: from inside a job dir with no `pyproject.toml` above it, `uv run python …` does not error
   about a missing project — it silently falls back to whatever `python` is first on `PATH` (here:
   conda's base env, *not* the pinned r3-tutorial `.venv`), which happened to already have
   numpy/matplotlib installed. Re-ran with `uv run --project <r3-tutorial-repo> python run.py` and
   got the identical `ModuleNotFoundError: toy_vision`, so the finding is robust either way — but the
   playbook should pin `--project` (or invoke the venv's python by absolute path) for any in-place or
   checkout run cell rather than rely on ambient `PATH` fallback.
4. **Checkout run works + provenanced output — PASS.** From `$wd`, `python run.py` printed
   `ran: (100, 64)` and wrote `output/ok.txt`; the file appeared both at `$wd/output/ok.txt` (via the
   symlink) and at `<repo>/jobs/<uuid>/output/ok.txt` in the store.
5. **In-job `run.sh` self-checkout — PASS, verbatim, no tweak needed.** Ran the plan's script exactly
   via `uv run bash -c 'cd <repo>/jobs/<uuid> && bash run.sh'` (confirmed `which r3`/`which python`
   resolve to the pinned `.venv`): it derived its own job-id from `${BASH_SOURCE[0]}`, `mktemp -d`
   gave a fresh parent so `$wd/job` didn't pre-exist (satisfying checkout's must-not-exist
   constraint), checked out to `/tmp`, ran, and populated `<repo>/jobs/<uuid>/output/ok.txt` in the
   store. No `$0`-vs-`${BASH_SOURCE[0]}` issue arose — verbatim as given.
6. **`r3 remove` — PASS.** `uv run r3 remove <uuid>` (reads `R3_REPOSITORY` from env; `--repository
   DIRECTORY` is also a first-class option on `remove`/`commit`/`checkout` alike) on a job with no
   dependents exits 0 with **no stdout** (same silence-on-success style as `init`), deletes
   `<repo>/jobs/<uuid>/` from disk, and drops it from `uv run r3 find --all -l`. (Did not probe the
   won't-remove-if-depended-on guardrail in this spike; confirmed only by source reading —
   `Repository.remove` raises via `self._index.find_dependents(job)`.)

**Bottom line for Tasks 4-6:** dependency mechanics need no change from the plan — freeze-at-commit,
checkout layout, in-place failure, checkout success, and run.sh self-checkout all behave exactly as
designed. The one required change is the **`repository:` URL scheme** (SSH, or make the repo public)
plus, if the playbook shells out `uv run python run.py` from inside a job/checkout dir, pinning
`--project`/an explicit interpreter rather than relying on `PATH` fallback.

**Cold-cache stderr gotcha (hit while building the playbook cells, Tasks 4/6).** The playbook's
sandbox is fresh every render, so the *first* `r3 commit` of a job with a not-yet-cached git
dependency also bare-clones toy-vision as a side effect. That clone prints a `Cloning into bare
repository '<repo>/git/github.com/matthias-k/r3-tutorial-toy-vision'...` progress line to
**stderr**, while `r3 commit` prints the job uuid to **stdout**. The playbook's `run()` helper
merges `stdout + stderr` for display, so the combined output is the uuid **followed by** the
clone line, not just the uuid — asserting the whole (stripped) output equals the uuid fails on a
cold cache (though it can pass by accident on a warm cache, e.g. a second render in the same
sandbox where the bare clone already exists). **⇒ parse the committed job id as the first line of
`run()`'s output** (`out.strip().splitlines()[0].strip()`), not the whole output.

## Output noise & git chatter (display gotchas, from the Stage-0/1 rework)
- **`r3 checkout` of a git-dep job prints scratch-clone chatter that *looks* like a bug.** It fetches the
  dependency from the local bare mirror into an **internal tempdir**, so it emits
  `Initialized empty Git repository in /tmp/<scratch>/.git/` — a `/tmp` path that is **not** the checkout
  target you passed (reads like a copy-paste glitch) — then `From <repo>/git/…`,
  `* branch <sha> -> FETCH_HEAD`, `HEAD is now at <sha> …`. The fetch is from the **local mirror**, so
  checkout works **offline** (reproducibility-relevant, worth surfacing). If displaying to readers, drop
  the `Initialized empty …/tmp/…` line and keep `From/branch/HEAD`. (The commit-time cold-cache
  `Cloning into bare repository …` line is the related stderr gotcha above.)
- **Quiet git's detached-HEAD advice wall** from r3's internal git subprocesses by passing git config
  through the env r3 inherits: `GIT_CONFIG_COUNT=1`, `GIT_CONFIG_KEY_0=advice.detachedHead`,
  `GIT_CONFIG_VALUE_0=false`. (r3 shells out to git with the ambient env, so it propagates — there's no
  r3-CLI flag for it.)
- **The committed `r3.yaml` is the job's `config`; r3's own term is *resolving* a dependency** (loose repo
  → concrete commit, at commit time). Prefer these over invented analogies in any r3-facing docs/skill.
