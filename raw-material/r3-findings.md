# r3 — verified findings (the skill's knowledge base)

> **Build provenance — not user documentation.** This is the internal, verified inventory the r3 skill was
> *authored from*; you do **not** need it to use the skill (see `skills/r3/`). It is dense working material,
> kept so a future session can re-verify the skill against a newer r3. **To use r3, read the skill, not
> this.**

The consolidated, deduplicated inventory of verified r3 behavior — mined from **all** the sources (the r3
source + test suite, r3's own docs, the r3 tutorial, `RESEARCH_WORKFLOW.md`, and real committed jobs) and
**re-verified against r3 `main` (`262a937` / 0.5.0)**. The **primary build input** for `skills/r3/`; it
supersedes `R3-GOTCHAS.md` (pinned to the older `c968f42`) wherever they differ. (The section labels A–O
are historical mining order, not a reading order.)

**Legend:** `[P]` pure r3 (skill material) · `[H]` house (exclude from the pure skill) ·
`[V]` verified against `main` source · `[?]` verify live during the build. Source refs are
`playbook.qmd:LINE` unless a file is named; r3 refs are `r3/<file>` in the `main` worktree.

---

## A. Mental model — headline framings & corrections

- `[P][V]` **Job identity is a fresh random `uuid4`, NOT content-addressed** (`storage.add`). commit records
  a content **hash of the recipe for integrity**, but the id is a new uuid — two identical recipes → two
  different jobs. (Fixes a misreading of the spec's "content hash → a uuid".)
- `[P][V]` **r3 is not an execution engine.** Its *only* runtime touchpoint in a job is a single
  `r3 checkout`; running is entirely the user's code. No runner, scheduler, `run.sh`, or `commands:`
  (1504-1510). The crisp form of "no `commands:` field" — headline it.
- `[P][V]` **The job dir is a free-form container; ALL non-ignored files freeze** — configs, design docs,
  specs, notes, not just executable code (1564). Reasoning/spec can freeze next to code + results.
- `[P]` **Jobs-outer / repos-inner inversion:** jobs are the outer layer; code repos live *inside* them as
  pinned, independently-evolving deps (1368).
- `[P][V]` (already in spec) `output/` is the sole results location; the checkout workdir is throwaway
  scratch; ignored-`cache/` dev pattern; frozen deps ⇒ reorganize later safely.

## B. Repository & CLI surface

- `[P][V]` The CLI finds the repo via **`$R3_REPOSITORY`** (or `--repository` on each verb) — every command
  reads it (143; `cli.py`).
- `[P][V]` Repo layout: `<repo>/{ jobs/<uuid>/, git/github.com/<owner>/<repo>/, index.sqlite, r3.yaml }`.
  The **repo-level `r3.yaml` only marks the repo format version** (`R3_FORMAT_VERSION = 1.0.0-beta.7`) —
  distinct from a job's `r3.yaml` recipe (a real point of confusion) (157-160, 308).
- `[P][V]` Verbs: `init`, `commit` (prints bare uuid), `checkout <id> <path>`, `remove <id>`, `find`
  (tag-only), `rebuild-index`, `edit <id>`. `init`/`remove` are silent on success; `remove` refuses with a
  clean `ValueError` + a **nonzero** exit (`ClickException`) on main, naming the dependents.
- `[P][V]` `find`: `-t/--tag` repeatable (AND); `-l/--long` → `uuid | timestamp | #tags`; **`--latest/--all`
  defaults to `--all`** (a bare `find` is already `--all`).
- `[P][V]` Install: `git+https` works on main (packaging fixed, PR #55); upstream **`stable`** branch tracks
  the latest release. Not on PyPI (name taken).

## C. The committed recipe (`r3.yaml`)

- `[P][V]` commit synthesizes/augments the stored `r3.yaml`: **`hashes:`** (per-file content hash + a `.`
  whole-job aggregate) + **`timestamp:`** + **`dependencies:`** (+ any `ignore:` you declared). A missing
  `metadata.yaml` is synthesized as `{}` (`job.py` hash/`to_config`, `storage.add`).
- `[P][V]` A job-dep entry retains **both** the loose query (`find_latest:`/`find_all:`) **and** the resolved
  `job: <uuid>`; a git-dep entry gains the resolved 40-hex `commit:`. `hashes:` gets one entry per dependency
  `destination` (dep content folded into the `.` hash) (539-547).
- `[P][V]` An omitted git-dep `source` is normalized to `source: .` in the stored `r3.yaml` (1172).
  *(§O: version-dependent — pre-2024 recipes omit it; default `.` when reading real recipes.)*
- `[P][V]` `metadata.yaml` is mutable, **not hashed**, and must be **JSON-representable** (`index.py`
  `json.dumps`; a bare YAML date → `TypeError` at commit). After commit the working-dir copy is irrelevant;
  edits target the stored copy (`r3 edit`, or edit-file + `rebuild-index`).
- `[H]` The stored `r3.yaml` may serialize a shared `find_all` query as YAML anchors (`&id001`/`*id001`) — a
  dump artifact; don't parse it literally (1300).
- `[P][V]` **Authoritative format spec:** `../r3/docs/repository_format.md` (v`1.0.0-beta.7`) pins the hash
  algorithm (SHA-256 over all files **except** `r3.yaml`/`metadata.yaml`/`output/`; per-dep string
  `<item>[@<commit>]/<source>`; final = lexicographically-sorted `<path> <hash>` lines, deps keyed by
  destination, `.` = overall), the `r3.yaml` key set (`dependencies`/`ignore`/`hashes`/`timestamp`), and
  that the index may be `index.yaml` *or* `index.sqlite`. `Repository()` refuses a repo whose `r3.yaml`
  `version` ≠ `R3_FORMAT_VERSION`.
- `[P][V]` **`ignore` is narrower than the docs imply.** `repository_format.md:61` calls them "patterns as
  used by git," but the implementation (`utils.find_files`) supports **only absolute, exact-segment
  patterns** (`/output`, `/cache`): it raises `NotImplementedError` on a non-`/` pattern, matches a
  top-level entry by exact name, and strips the prefix when recursing (so `/output` also hides
  `output/sub/x`). **No globs, no `.gitignore`.** Advertise the real (narrow) behavior, not "git-style".

## D. Dependencies & checkout (precision)

- `[P][V]` **Git deps: github.com ONLY** — two regexes (`https://github.com/…`, `git@github.com:…`), else
  `ValueError` (`job.py` `repository_path`). Both URL forms map to the **same** mirror cache
  `git/github.com/<owner>/<repo>`, so a warm cache can mask an https-auth failure; private repos need ssh.
- `[P][V]` An unversioned git dep resolves to the remote's **default-branch HEAD** (`git ls-remote origin
  HEAD`) at commit — *not* literally "main". `branch:`/`tag:` override, `commit:` pins; a resolved dep only
  ever writes `commit:` (branch/tag don't round-trip) (`utils.git_get_remote_head`).
- `[P][V]` Git-dep fetch is a **commit-time** side effect into the bare mirror; commit also writes
  `git tag r3/<uuid> <commit>` pinning it. Checkout reads the local mirror → works **offline**, and the
  mirror **preserves the pinned commit even if upstream force-pushes/rebases/GCs it** (`storage.add`,
  `checkout_git_dependency`).
- `[P][V]` At commit r3 **re-resolves** git deps: probes the mirror (`git cat-file` — a bare `fatal:` on a
  miss is r3 *checking*, not failing), then fetches the public remote if absent. Alarming-but-normal output
  next to the uuid (`repository.__contains__`).
- `[P][V]` **Git-dep files are NOT vendored** into the stored job — materialized only on checkout; a
  committed git-dep job run in place fails (`ModuleNotFoundError`) (342-350; `Job.files`).
- `[P][V]` **Job-dep materialization** (`storage.checkout_job_dependency`): symlink-vs-copy is decided purely
  by `str(source) == "." and recursive_checkout`:
  - `source: "."` + `recursive_checkout: True` (both defaults) → **recursive real copy** of the upstream's
    code files, its own `output` a symlink, and **its own deps recursively checked out too** (transitive).
  - otherwise → a **symlink**: `recursive_checkout: False` → symlink to the job **root**; `source: <subpath>`
    (e.g. `output`, or a single file `output/<f>`) → symlink straight to `<job>/<subpath>`. A non-`.` source
    means the flag doesn't apply (it isn't "overridden").
  - So **`source:` is code-vs-data scope, never data duplication** (`output` is always a symlink, or the whole
    dep is).
- `[P][V]` Committed-job `r3 checkout <id> <workdir>`: copies the job's own files (real), **symlinks
  `output/` back to the store** (results persist), materializes each dep by its own rule. Target workdir
  **must not pre-exist** (`os.makedirs`). Emits git scratch-clone chatter (`Initialized empty …/tmp/…`) —
  cosmetic (`storage.checkout_job`).
- `[P][V]` **A recursively-checked-out dependency has NO `metadata.yaml`** (nor `r3.yaml`): `checkout_job`
  copies the job's own files but **skips `r3.yaml`, `metadata.yaml`, and `output`** (output symlinked),
  then recurses into deps (`storage.py:217`). Because **metadata is mutable**, r3 deliberately won't
  reproduce it at checkout — it can't guarantee it matches commit time. **Consequence (surprising, call
  it out):** a downstream analysis must **not** read hyperparameters/labels from a checked-out
  dependency's `metadata.yaml` — e.g. after a `find_all`, don't pull each upstream's params from its
  metadata. Read run parameters from a **committed file** (`config.yaml` etc., which *is* copied). A
  *non-recursive* whole-job checkout (symlink to the job root) *does* expose `metadata.yaml` through the
  symlink — but don't rely on it either, for the same mutability reason.
- `[P][V]` A git-dep checkout lands on a **detached HEAD** at the resolved commit; `origin` is the internal
  mirror (a path inside `R3_REPOSITORY`). Contribute back: `git remote add upstream <URL>` → `git fetch
  upstream && git checkout main` (auto-tracking branch) → commit → push (1075-1100).
- `[P][V]` r3's checkout primitives **don't cleanly handle a pre-existing destination**: a job-dep symlink
  errors; a git dep's `shutil.move` **nests** the tree inside the existing dir. A dev loop must guard
  (skip/remove) itself — the "non-destructive checkout" behavior is **r3dev's** guard, not r3 core.

## E. Dev workflow (the `‹dev-checkout›` anchor)

- `[P][V]` Primitive: `repo.checkout(unresolved_dep, dir)` resolves, then materializes. The loop (`r3dev.py`,
  ~25 lines, public API): `for dep in r3.Job(d).dependencies: repo.checkout(dep, d)` (guarding existing);
  cleanup removes each dep **destination** (reversing the checkout). **Correction:** the *bare* r3dev
  cleanup touches only dep destinations — it does NOT remove `output/`/`__pycache__`; that is a
  richer-wrapper add-on (e.g. xr3's `dev-cleanup`), not part of the vanilla loop.
- `[P][V]` A dev checkout creates **no `output/` symlink** (an uncommitted job has no store slot; dev output is
  a throwaway local `output/`). **Committing after a dev run discards all dev artifacts**: the stored job has
  no materialized deps and a fresh empty `output/` — "a dev checkout cannot change what you commit" (because
  `Job.files` excludes `/output` + every dep destination) (864-869).
- `[P]` **dev-cleanup is hygiene + re-resolution** (drop stale deps to pick up newer upstreams next round),
  *not* recipe protection (commit already excludes those paths). **But** it can still destroy
  uncommitted/unpushed work you edited inside a checked-out git dep (`rmtree`) — both framings hold, keep
  distinct. Even without a wrapper, an agent should run the hazard checks by hand (git status of a git dep
  before cleanup).
- `[H]` `r3dev.py` is a user script — bundle a bare copy as the reference primitive; environments have richer
  wrappers (e.g. `xr3 dev-checkout/cleanup`).

## F. Query & find gotchas (verified live on main)

- `[P][V]` **`r3 find` (non-`--latest`) returns rows in unstable order** — the SQL has no `ORDER BY` except
  when `latest=True` (→ `ORDER BY timestamp DESC LIMIT 1`); `rebuild-index` re-inserts in filesystem
  (`iterdir`) order, visibly reshuffling. **Never treat `find` output as a timeline** (`index.py`).
  *(MK plans to fix this — add `ORDER BY timestamp` — so it is a prime validity-stamp diff candidate;
  correct as of the stamped commit.)*
- `[P][V]` **Range ops `$gt/$gte/$lt/$lte` interpolate the value UNQUOTED** (unlike `$eq/$ne`). On a **string**
  field this is a SQLite TEXT-vs-numeric compare → **matches ALL rows** (silent wrong results); semver can't
  be range-queried (lexicographic; `"1.10" < "1.9"`; numeric `1.10 == 1.1`). Store numeric versions; use
  `$eq` for strings (`query.py`). *(§N sharpens this: "match all" holds only when the value parses as a
  number; a non-numeric token like `v1.0` is invalid SQL → errors instead.)*
- `[P][V]` Query values are **string-interpolated into SQL** (not parameterized) — values with embedded
  quotes break; keep them clean.
- `[P][V]` Grammar (complete, `query.py`): logical `$and/$or/$not/$nor` + implicit-AND; conditions
  `$eq`(implicit)`/$ne/$in/$nin/$gt/$gte/$lt/$lte/$glob/$all/$elemMatch`. `$glob` = SQLite GLOB
  (case-sensitive, `* ? [..]`). **Not implemented:** `$exists/$type/$regex/$size/$mod/$expr/$text` and
  field-level `$not`. `find({})` → all.
- `[P][V]` `find_latest` = newest by **timestamp**, not highest `version`. Because CLI `find` is tag-only,
  **mirror `version` into a tag** (`v0.5`, `v1`) so `find` can locate generations (457, 663).

## G. Metadata, `path` & organization

- `[P][V]` `tags` is the only field tooling privileges (`find --tag`, `#tag`). `path` & `version` are pure
  conventions r3's code never reads (path-promotion is still idea-stage on main).
- `[P]` **`path` is a virtual namespace slot** — independent of storage (uuid) and of the files inside the
  job; usually mirrors the authoring folder but needn't (1370). Non-unique (a sweep shares a `path`), movable
  (re-path later, frozen deps unaffected), path-vs-tags is a menu.
- `[P]` **Seed layout schemes for §7 (as examples, less prescriptive than the tutorial):** dated
  `experiments/2026-…/`; typed stable homes (`models/main`, `datasets/kodak`, `baselines/`,
  `containers/default`); config-runs `search/run-000N/`. Story: combine several via `find_all`; graduate an
  experiment into a stable home by re-pathing (1372-1390). *(The schemes themselves are house — harvest as
  examples only.)*
- `[P]` **Consumer label-hygiene gotcha** (rooted in pure query semantics): a job's own metadata makes it
  match the queries that find its inputs — a report over `path: pca` must **not** itself carry `path:
  pca`/those tags, or a later `find_all` pulls it into its own lineage (1310).
- `[H]` `projects:`, numbered `task000N_` layouts, etc. are house metadata fields queried via the generic
  field mechanism — not special r3 features.

## H. Lifecycle operations (additions)

- `[P][V]` **Update an outdated job:** re-commit the authored working dir — commit re-resolves each
  `find_latest`/`find_all` to the now-current match (the authored dir keeps unresolved queries; commit
  resolves a fresh stored copy), then re-run (1390).
- `[P][V]` **Reclaim disk:** delete a job's `output/` (writable) — keeps provenance, loses reproducibility
  (GPU nondeterminism, dead URLs, dropped kernels); record the deletion in `metadata.yaml` so an empty
  `output/` reads as intentional (611).
- `[P][V]` `rm -rf` on a committed job **fails** (dir is `555`) and short-circuits a `&&` chain — `chmod -R
  +w` first, or use `r3 remove` (NOTES:49).

## I. Provenance-analysis via the API (open-ended; §4)

- `[P][V]` `find_dependents(job, recursive=True)` **bounds the blast radius** of a bad input — "is my
  submission compromised?" → the exact downstream set (1653).
- `[P][V]` **Bulk metadata reshape over the graph** (re-path many jobs; tag a buggy job's whole transitive
  subtree): iterate `repo.jobs()` / `repo.find({})`, edit `job.metadata`, `job.save_metadata()`, then
  `rebuild-index`. **`for j in repo` is INVALID on main** (no `__iter__`) — use `repo.jobs()`/`repo.find({})`.
- `[P]` The tag/`path` taxonomy over thousands of jobs **is** the registry — the index does a registry's job
  with nothing to run. Frame the API open-endedly (one loose example), per spec §4.

## J. Promotion oracle (pure kernel of a house method)

- `[P]` A committed job's frozen, immutable `output/` is a ready-made **regression oracle**: same inputs must
  reproduce it. Two forms — across-jobs (old job's frozen `output/` vs new) or within-one-job (old code beside
  new, assert equal: exact when merely moved, looser when the maths was rewritten) (1596, 1638). *(The
  promotion-as-its-own-job method + test placement are house.)*

## K. Hard limitation

- `[P][V]` **Secrets in committed configs are permanent** (committed = immutable) — an unsolved problem; don't
  commit secrets (1680).

## L. Confirmed house-only — never in the pure skill

xr3 (`find`/`check`/`commit`/`dev-checkout`/`history`/submission/`bugmark`), the galvani `g` helper, foreman
web UI, SLURM/arrays/submit + `output/done` resume marker, singularity containers + `run.sh`→`run_inner.sh`
split, Quarto/report rendering + `report-style.md` + blind-read gate, the tutorial's Kodak/PCA/`toy_vision`
domain content, and the whole Quarto playbook harness. **`run.sh` itself is a user convention** (r3 never runs
it) — the pure primitive is only "a committed job can `r3 checkout` itself to a throwaway workdir".

---

## M. From `RESEARCH_WORKFLOW.md` (house doc) — pure kernels worth the skill

The doc is house, but a few statements are **pure-r3 principles** worth surfacing:

- `[P]` **Query the index, don't grep the repo.** Jobs are content-addressed and their queryable metadata
  lives in the index — locate jobs with `find`/a query, never by grepping the store (slow, and it misses
  the point). Clean framing for the skill's find section.
- `[P]` **Ignored-cache refinement:** when an `ignore`d `cache/` speeds dev re-runs, **skip-if-present must
  verify a hash, not just existence** — else a stale/partial cache is silently reused. (Sharpens the §A
  ignored-cache pattern.)
- `[P]` **Dataset-as-a-job:** a dataset job's `run.py` should download **and smoke-test its loader at build
  time**, so schema problems surface immediately instead of three dependent jobs later.
- `[P]` Confirms the API escape-hatch (`r3.Repository(path).find(query)` to *use* results in Python) and
  `source:`-to-one-file narrowing.

Everything else is house → route to `extensions/`: SPEC/PLAN flow, the compute+report two-job split, xr3
verbs (`find -p/-t/-q`, `history`, `check`, `commit --remove`, `files`), container revisions, long-running
detached+resumable (`setsid nohup` + hash-cache + watcher), report conventions (tl;dr/charts/template/review
loop), and the promotion fidelity/real-path + compare-dtypes method.

## N. From the r3 TEST SUITE (authoritative behavior on `main`, 262a937)

The tests are the executable spec — these are net-new or sharpened vs A–M. `[V]` throughout (tested).

**Python API — signatures & types (for `reference/python-api.md`):**
- **Dependency constructors are `destination`-FIRST** (counter-intuitive): `JobDependency(destination,
  job, source=".", recursive_checkout=True, …)`; `GitDependency(destination, repository, commit=None,
  source=".", branch=None, tag=None)`; `FindLatestDependency(destination, query, source=".",
  recursive_checkout=True)`; `FindAllDependency(destination, query, recursive_checkout=True)`.
- **Two query-dependency families:** `find_latest`/`find_all` take a **dict Mongo query**; the
  **deprecated** `query`/`query_all` take a **string `#tag` mini-query** (space-separated tags AND'd) and
  **warn (`DeprecationWarning`) at construction**. Steer authors to `find_latest`/`find_all`.
  *(§O: but this string form is PERVASIVE in real 2023–24 recipes — the skill must recognize it when
  reading old jobs, not merely "avoid".)*
  `Dependency.from_config` dispatches on the key; `job` wins over `query` and retains the query.
- **`find_all`/`query_all` deps carry NO `source`** (source-less by design → whole job root, one subdir
  per job id). All other dep types default `source="."`.
- `to_config` emits `recursive_checkout` **only when `False`** (default `True` is omitted). An omitted git
  `source` normalizes to `.`.
- **Hashing:** an **unresolved** query dep's `.hash()` raises `ValueError`; only `JobDependency`/
  `GitDependency` hash. `JobDependency.hash` depends only on `job`+`source` (not destination/query);
  `GitDependency.hash` on repository+commit+source. `Job.hash()` is unchanged when `metadata.yaml` is
  rewritten **or deleted** (metadata not hashed).
- **`Job` caching API:** `Job(path, cached_metadata=…, cached_timestamp=…)`, `uses_cached_metadata()`/
  `uses_cached_timestamp()`, `reload_metadata()`, `save_metadata()`. `job.metadata` → `{}` when no file.
- **Repository lookup/membership:** `repo[id]`/`get_job_by_id(id)` → `KeyError` on unknown id; `x in repo`
  also accepts a **dependency** and validates its `source` exists in the target job; git-dep membership
  clones/fetches the mirror on demand (and caches) — a nonexistent commit → `False` (after a fetch), not
  an exception.

**Error semantics (the unhappy paths):**
- `Repository.init(existing)` → `FileExistsError`; `resolve` → `ValueError` on an unmatchable query or a
  nonexistent branch/tag; `remove` of an absent/already-removed job → `ValueError`; `find_dependents` with
  no `job.id` → `ValueError`.
- **The CLI reformats errors cleanly:** `remove`/`edit`/`checkout` on a nonexistent id → **nonzero exit**,
  id echoed, never a raw `KeyError`/traceback. A **failed `checkout` does not create the target dir.**
  Missing repo → names **both** `--repository` and `R3_REPOSITORY`; **`R3_REPOSITORY=""` counts as
  missing**; a bad repo path / outdated `version` names the offender. **`init` is the one verb that does
  NOT take `--repository`.**
- **`remove`-refusal** lists **all** dependents, **sorted**, under an explanation **prefix** line.

**Commit / storage invariants (sharper):**
- **`commit` excludes `/output` UNCONDITIONALLY** — even with no `ignore: [/output]`, nested output
  included; the committed job keeps an **empty `output/`**, output paths absent from `hashes:`. `commit`
  **strips all write bits** (u/g/o) from copied files (`test_repository.py:369-390` — the write-bit
  claim IS tested), sets `timestamp = datetime.now()`, creates exactly one `jobs/<id>`.
- **Storage vs Repository layering:** `Storage.init` creates only `jobs/` + `git/` — **not**
  `index.sqlite` or the repo-level `r3.yaml` (those are `Repository`-layer). `Storage.__contains__` is
  **path-aware**: a `Job` with a committed id but a *different* `path` is **not** contained (guards
  `remove`, which deletes `job.path`).
- **Git-dep checkout granularity:** `source: "."` → a full directory; `source: <subdir>` → that subdir's
  contents; **`source: <file>` → the destination is a *file* copy**. Git deps are **copied**; job deps
  **symlinked**.

**Query gotchas (net-new, high value — for `reference/query-grammar.md`):**
- **`$ne`/`$nin` on an ARRAY field do NOT exclude** — they match if *any* element differs, so
  `{"tags": {"$ne": "x"}}` returns essentially **every** job. A real MongoDB divergence + silent-wrong
  trap. (Scalar fields exclude correctly.)
- **JSON-type-strict matching:** in `$all`/`$elemMatch`/array-`$eq`, `28` (int) ≠ `"28"` (str). Store
  queryable values with a consistent, intended JSON type.
- **`$elemMatch` binds all sub-conditions to ONE element**; sibling top-level conditions may be satisfied
  by *different* elements. Use `$elemMatch` for "same element satisfies A and B".
- **Empty `$all` = match-all** (`{"tags":{"$all":[]}}` → all) — the mechanism behind a bare `r3 find`.
- **A scalar field can't carry two operators** (`{"f":{"$gt":1,"$lt":9}}` → `ValueError`); express ranges
  via query-level `$and` or `$elemMatch` on an array.
- **Unknown FIELD-level operators are SILENTLY coerced to `$eq`** (not rejected): `{"f":{"$regex":"x"}}` →
  `f = 'x'`. (Only *query-level* unknown `$ops` raise.) Sharpens "not implemented" → **silently wrong at
  field level**.
- `$eq`/implicit on an array = "contains"; `$in` = "contains any of"; `$glob` = "any element globs".
- **`find` serves index-CACHED metadata/timestamp** — editing `metadata.yaml` without `r3 rebuild-index`
  (or `Index.update`, which `r3 edit` calls) leaves `find` returning **stale** metadata. Concrete trap.
- **String-range reword (correction to §F):** `$gt/$lt/…` interpolate the value **unquoted**. If it parses
  as a **number**, comparison against a TEXT field matches all/none by SQLite type-ranking; if it's a
  **non-numeric token** (e.g. `v1.0`), it's **invalid SQL → error**, not match-all. Never range-query a
  string field; store numeric versions.

## O. From REAL committed jobs (galvani store sample of 22 + recent experiments)

Authoritative committed shapes across MK's whole store (**5,397 jobs, ~13 projects, 2023→2026**) plus
recent agent-driven experiment jobs. `[P]`=pure mechanic, `[H]`=house convention.

**Corrections/caveats for reading real recipes:**
- `[P]` **The legacy `query: '#tag'` job-dep form is PERVASIVE**, not just "deprecated-avoid": it's the
  workhorse in 2023–2024 jobs and **mixes with `find_latest` in one recipe** during the transition era.
  Teach it as *legacy you WILL encounter when reading old jobs* (recognize it), while steering *new* jobs
  to `find_latest`/`find_all`. Multi-tag `query: '#a #b'` (space-separated AND) seen live; `#tag` values are
  often full slash-paths used as one tag.
- `[P]` **Git-dep `source` normalization is version-dependent.** Current main writes `source: .`; the oldest
  (2023) stored recipes **omit `source` entirely** on git deps. When *reading* real recipes, treat git
  `source` as optional (default `.`). Serialization evolved generally — timestamp precision went
  second→microsecond in 2024-04; a strict parser must tolerate both.

**Dependency-shape variety (pure mechanics, enriched):**
- `[P]` **source→destination RENAMING** to disambiguate same-named files from different upstreams
  (`output/centerbias.hdf5` → `centerbias_SALICON_train.hdf5` vs `..._validation.hdf5`).
- `[P]` **Fan-out from one upstream** via multiple `source:` narrowings; **shared/nested destination dirs**
  (`centerbiases/…`, `pysaliency_datasets/…`) populated from *different* upstream jobs.
- `[P]` `source:` range in the wild: whole `output`, whole job root (`.`), a subdir, and a **single file deep
  in the tree** (`output/pretraining/final.pth`, `output/container.sif`).
- `[P]` **Git deps are always whole-repo** (no subdir/file narrowing seen), always resolved to a 40-hex
  `commit:` (no `branch:`/`tag:` round-trip — confirms §D); up to ~10 deps / 4 git repos per job. Recent
  jobs add `branch: dev` and **ssh URLs** (resolved to commit at commit).
- `[P]` **`find_all`/`query_all` fan-in is ABSENT** in the leaf-job sample — every dep pins one upstream.
  Don't over-index the skill on `find_all` (it's for report/aggregation jobs).
- `[P]` **`recursive_checkout: False` is rare but real** — absent from all 22 store recipes (default True
  omitted), but used in a recent experiment (`v4.1_run` dep, symlink a whole upstream).
- `[P]` **Container-as-a-dependency is ubiquitous** in recent jobs (`find_latest: {path:
  research/containers/default}, source: output/container.sif`) — the "environment is a job" pattern (`[H]`
  the container convention itself).
- `[P]` **Teaching example (§H):** the *same* loose query (`'#…/containers/default/v1'`) resolves to
  *different* frozen uuids across sibling jobs — the container was rebuilt and each commit re-resolved.

**Query grammar — real usage adds capabilities (for `reference/query-grammar.md`):**
- `[P][V]` **Dotted-path nested-field queries** work: `find_latest: {task_meta.seed: 42}`,
  `{task_meta.test-dataset: COCO-Freeview}` — `FieldQuery` emits `metadata->>'$.task_meta.seed'`, a valid
  nested JSON path. NOT in §6/§N — add it.
- `[P]` **Implicit-AND with sibling top-level fields** (no `$and`) is used interchangeably with explicit
  `$and: [...]`. `$glob` on tags is the dominant op, combined with a tags-contains equality and
  dotted-field equalities inside one query.
- `[P]` **Array-contains in production:** a list field (`task_meta.test-dataset: [COCO-Freeview]`) queried
  with a scalar (relies on §N's "`$eq`/implicit on an array = contains").
- `[P]` `path`/`projects` queried as ordinary index fields (`find_latest: {path: …, projects: …}`) — never
  read by r3 core, but first-class *queryable*; `path` used as an exact-match locator.

**`ignore` — reconciled (MK: "increasingly used in new jobs"):**
- `[P]` **Historically rare, now common in recent agent-driven jobs.** 0/22 old store-sample jobs declared
  `ignore` (leaf training jobs only produce `output/`, auto-excluded — nothing else to ignore). Recent
  experiment jobs use it heavily to exclude **dev/report artifacts** (`/report.html`, `/report_files`,
  `/render.sh`, `/__pycache__`, `/.pytest_cache`), **on-disk caches** (`/pysaliency_datasets` — the
  ignored-cache pattern), **`/.claude`** (agent working dirs), and redundantly **`/output`** (habit — already
  auto-excluded). Present `ignore` as a real, useful feature for any job emitting non-`output` artifacts —
  not niche.

**Metadata conventions (mostly `[H]`, for §7 / extensions):**
- `[H]` **Path-scheme eras** (great §7 variety, spans "beyond latest style"): 2023 shallow
  `project/taskNNNN_…`; 2024 deeply-nested numbered `taskNNNN_…/tasks/task0102_…`; 2024–25 dated
  `…/experiments/2025-…/…/tasks/seed-44`; 2026 typed stable homes `gold-standard/models/…`,
  `saliency-benchmarking/models/centerbias/CAT2000/test`; params encoded in path segments
  (`…/crossval3_seed42`).
- `[H]` **Intended convention (per MK): `path` is always PREFIXED BY THE PROJECT NAME** → project-local
  *and* globally unique; on lustre most projects mirror this as `projects/<project>/<project>/…`, so
  stripping the `projects/<project>/` root yields the `<project>/…` path (xr3's `_get_path`). The
  `projects:` metadata disambiguator is a **legacy** need the prefix convention removes. **Deviation:**
  `gaze-combined-datasets` uses the flipped prefix `combined-gaze-datasets/…` + relies on `projects:` — MK
  is migrating it to the standard prefix (a RESEARCH_WORKFLOW change; a lustre-session prompt is drafted).
- `[H]` **Tag-versioning changed:** older = version as an *interior* path node (`…/v1.0.0/tasks/…`); newer =
  **path emitted as nested tags with `/vX.Y.Z` at each truncation level** (`…/crossval3_seed42/v1.0.0`,
  `…/CAT2000/v1.0.0`, `…/tasks/v1.0.0`, `…/tasks`) → `find --tag` at multiple granularities. Flat identity
  tags on every job: user, cluster (`galvani`), project, and **colon-namespaced** scheduler tags
  (`autoslurm:restart_failed`). The store is **multi-author** (`bkr738` alongside `mkuemmerer31`).
- `[H]` `version` scalar is NOT used — instead a **`versions:` changelog LIST** (`{comment, version}`) in
  newer jobs. `origin:` ≈ `path` (immutable authoring-folder record vs the mutable `path` slot — supports §G
  "path is movable"). `task_meta:`/`gridsearch_meta:` hold per-job hyperparameters **in mutable metadata** —
  the exact §D trap (downstream consumers must read them via the index, never from a checked-out dep's
  metadata). `post_hoc_modifications:` = **real logged instances of the §H reclaim-disk pattern**. Plus
  `scheduler:`, `projects:`, `comment:`.
- `[P][V]` **JSON-representability honored in the wild:** every timestamp is a **quoted string** — real
  evidence of the §C "quote dates or hit `TypeError` at commit" rule.

## Still-open verify-live items (low priority; source-reasoned above but not run end-to-end)

- The commit-time `fatal:` cat-file line and the checkout scratch-clone chatter — cosmetic; confirm exact text
  if surfaced to users.
- `find` unstable-order and the string-range match-all are read from `index.py`/`query.py` on main; a 2-minute
  live repro would make them bullet-proof for the gotchas reference.
