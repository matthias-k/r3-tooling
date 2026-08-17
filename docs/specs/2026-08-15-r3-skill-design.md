# r3 skill for agents — design spec

*2026-08-15, first draft. **Revised 2026-08-16/17** after a source-verification pass against r3 `main`
and two design rounds (MK): CLI-first for the lifecycle; the Python API framed as r3's general
interface to the provenance graph (not a closed list of "escape hatches"); a **shape-agnostic**
local-tooling / extension principle (no assumption of xr3's structure); `path` promoted to a suggested
first-class attribute; stale claims corrected; query grammar completed. §12 records the resolved
decisions.*

## 1. Purpose & audience

A skill that lets an **agent** (MK + colleagues) operate r3 **reliably** — author a job, wire
dependencies, commit, run, find, check out — without rediscovering r3's non-obvious behavior. It is a
**foundation** that a house workflow doc can build on (in MK's case `RESEARCH_WORKFLOW.md`): an agent
reading such a doc, or dropped into an existing r3 job, should be able to lean on the skill to
understand what is actually happening. The skill itself names no house doc.

Audience is agents, not human newcomers — so it is a **reference/operating manual**, terse and
task-indexed, not a narrated tutorial. (The tutorial is the human-onboarding artifact; this is its
agent-facing complement.)

## 2. Architecture — the pure/extension seam (the spine of this design)

Everything is organized around one split, so the pure part stays **upstream-able to r3 core** (MK is
the de facto primary maintainer of r3 — the upstream repo is still Matthias Tangemann's — so
upstreaming is realistically his call whenever ready):

- **Pure r3 skill** (`skills/r3/`) — describes **only r3 core**: the job/commit model, dependencies +
  query grammar, the CLI + Python API, and r3's non-obvious behaviors. **No xr3, no house conventions,
  no galvani/`g` specifics, no house doc names.** Authored to r3-core neutrality and quality.
- **Extensions** (`extensions/…`, beside it, referencing it) — house wrappers, conventions, tutorial
  examples, the `g` galvani helper, containers, long-running/report conventions. These *build on* the
  pure skill and are explicitly MK's. **Their shape is deliberately unspecified** (see §5): one wrapper
  skill, several focused skills, a convention doc, or a future extension system — the pure skill is
  agnostic.

Lifting the pure skill upstream is a directory move, not a disentangling exercise.

## 3. Scope of the pure r3 skill

Target **r3 `main`** (grows with main). **Remote-storage held out** (§11). Sections:

1. **Mental model** — a job is a directory; `commit` freezes the *recipe* (code + resolved deps) by
   content **hash for integrity** — the id itself is a fresh `uuid4`, *not* content-addressed (identical
   recipes get different ids); a job is immutable after commit **except `metadata.yaml` and `output/`**;
   provenance = dependencies frozen (git commit hashes, job uuids) at commit time. Key facts &
   consequences the skill must make explicit:
   - **r3 is not an execution engine.** Its only runtime touchpoint in a job is a single `r3 checkout`;
     running is entirely your code — no runner/scheduler/`run.sh`/`commands:`. `run.sh` is a *user*
     convention r3 never reads.
   - **The job dir is a free-form container** — every non-ignored file freezes into the recipe (configs,
     design docs, specs, notes), not just code.
   - **`output/` is the one and only place results persist.** A job writes results *only* to
     `output/`. In an in-place committed run, writing elsewhere hits the read-only dir
     (`PermissionError`); in a checkout, non-`output/` writes land in throwaway scratch (next bullet).
   - **A checkout workdir is throwaway scratch.** `r3 checkout` builds a disposable workdir; only its
     `output/` symlink persists back to the store. That is a *feature*: write preprocessed data,
     expanded configs, or scratch there with repo-relative paths — no temp-dir juggling — all gone when
     the workdir is deleted. Dev twist (a common MK pattern): keep an **ignored `cache/`** (via
     `ignore: [/cache]`) so repeated dev runs reuse a prepopulated cache and stay fast, while the
     committed job — which excludes `cache/` — recomputes from scratch, keeping provenance honest.
   - **Frozen deps ⇒ reorganize later without breakage.** metadata (paths, tags) is mutable and *not*
     hashed, and committed deps freeze to uuids — so you can restructure your `path` namespace / re-tag
     to fit how you think *now*; committed jobs keep resolving, only new jobs/queries see the new
     layout (§7). This is a headline r3 property, worth stating plainly.
2. **Surface strategy** (§4) — CLI-first for the lifecycle; the Python API as r3's general interface to
   the provenance graph.
3. **Lifecycle** — author a job (`run.py`; `r3.yaml`/`metadata.yaml` optional, synthesized) → `commit`
   → run (**in-place** for a dependency-free job; **`r3 checkout <id> <workdir>`** — or an in-job
   `run.sh` — once it has deps, to materialize them) → `find` → `checkout` → `remove` →
   `rebuild-index` / `edit`. Distinct from committed-job checkout: the **dev-checkout** of an
   *uncommitted* job (§4).
4. **Dependencies + query grammar** — git deps (`repository`/`source`/`destination`, resolve→freeze to
   a commit hash at commit), job deps (`find_latest`/`find_all`, `source` + `recursive_checkout`
   materialization rules — symlink vs real copy), `ignore` (absolute patterns). The **complete,
   verified** Mongo-style query grammar (§6); tags are privileged by tooling, arbitrary metadata is
   queryable via the API.
5. **Metadata & conventions** — `tags` (the one field r3 *tooling* privileges today) and **`path` as
   the recommended organizing convention** (§7), plus `version`. metadata is mutable, **not
   content-hashed**, and must be **JSON-representable**.
6. **Non-obvious behaviors** — the agent-biting gotchas, drawn from `raw-material/tutorial-findings.md`
   (the verified mined inventory that supersedes `R3-GOTCHAS.md`) and §8, in a `reference/gotchas.md`
   loaded on demand. Highest-value live-on-main: unstable `find` order (no `ORDER BY` unless `--latest`;
   `rebuild-index` reshuffles); range ops match *all* rows on string fields (silent); github.com-only
   git deps; `rm -rf` fails on a committed job (`555`); a cosmetic `fatal:` on cold-cache commit.
7. **The verify habit + a validity stamp.** r3 `main` moves, so the skill's standing instruction is
   *confirm against live `r3 --help`/behavior/the source, not memory*, and it flags the version-sensitive
   areas. Concretely, **`SKILL.md` carries a validity stamp** — the r3 version + commit it was verified
   against (e.g. *Verified against r3 `262a937` / v0.5.0 on 2026-08-17*). That turns "re-verify" into a
   diff: a later session runs `git log <stamp>..main` on the r3 repo, focused on the flagged areas
   (CLI, query/`find`, checkout, path-promotion), to see what changed and plan a targeted update. Live
   example: MK intends to fix the unstable-`find`-order gotcha (add `ORDER BY`) — exactly the kind of
   change the stamp lets a future session catch and fold in.
8. **Local tooling may supersede parts of this** (§5) — the neutral, shape-agnostic principle that lets
   an environment's wrappers override, without the skill naming any.

**Skill format:** one `SKILL.md` (YAML frontmatter: `name: r3`, a description that triggers on r3 job /
`r3.yaml` / `find_latest` / committing / checkout / provenance work) + on-demand `reference/` files
(`gotchas.md`, `python-api.md`, `query-grammar.md`) + a bundled bare dev-checkout script (§4). One
skill, not a family (§12-Q4). Build it with the `writing-skills` skill.

## 4. Surface strategy — CLI-first for the lifecycle, the API for open-ended work over the graph

**Two interfaces, one guideline each:**

**The CLI is the permission-bounded default for the lifecycle verbs** — `init`, `commit` (prints the
bare job uuid), `checkout <id> <path>`, `remove <id>`, `find` (tag-only), `rebuild-index`, `edit <id>`
(opens `$EDITOR` on `metadata.yaml`, then reindexes). Rationale is permission management: allowlisting
`Bash(r3 …:*)` grants a **bounded, auditable verb set**; "use the Python API" instead means granting
`Bash(python:*)` or running scripts — effectively arbitrary code execution. Use the CLI for anything it
covers.

**The Python API is r3's general interface to the job graph and its metadata — for both reading and
reshaping it.** It is *not* a fixed list of fallbacks. **Reading:** arbitrary metadata queries,
following dependencies in any direction, tracing dependents, cross-checking versions/paths across the
graph, detecting outdated or superseded analyses. **Writing / reshaping** is just as central — e.g. a
bulk metadata edit to reorganize a `path` namespace across many jobs (`job.metadata` +
`job.save_metadata()` + `rebuild-index`, or `r3 edit` for one), which is *safe precisely because
committed deps are frozen* (§3, §7). Reach for it whenever the task is **working over the graph** rather
than running a single lifecycle verb. Convey this *open-endedly* — one loose, explicitly non-exhaustive
example at most (e.g. "*find every job, in any dependency order, that transitively uses repo X at commit
Y*"), and avoid a taxonomy that would fence agent creativity.

Entry points: `r3.Repository(path)` (`find(query, latest)`, `checkout`, `commit`, `remove`,
`find_dependents`, `jobs`, `repo[job_id]`) and `r3.Job(dir)` (`metadata`, `dependencies`, `files`,
`hash`, `timestamp`, `save_metadata`).

**Two named anchors** — marked so the skill stays cheap to maintain. They are examples of the API's
reach, not its extent, and they point in *opposite* directions:

- **`‹rich-query›`** *(a CLI gap r3 is likely to close)* — CLI `find` is hardwired to
  `{"tags": {"$all": tags}}`; richer queries (path, arbitrary metadata, `$glob`, ranges) are
  `repo.find(query, latest)` or `find_latest`/`find_all`. *Forward:* `r3 find` gaining `-q`/`--path` is
  planned upstream; prefer it when present, and rewrite this anchor then.
- **`‹dev-checkout›`** *(deliberately user-owned — the poster child for §5)* — running/iterating a job
  **before** committing it. r3 once shipped a `r3 dev checkout` CLI command and **removed it on
  purpose** (`4da2253`) because the right checkout/cleanup behavior varies per user; what remains is
  only the API primitive `repo.checkout(unresolved_dep, dir)` (resolves, then materializes). The
  vanilla reference loop is the tutorial's ~25-line **`r3dev.py`** (`for dep in
  r3.Job(d).dependencies: repo.checkout(dep, d)`, plus a `cleanup`); bundle a bare copy in the skill
  and frame it as a *starting point* — environments commonly have richer, house-specific wrappers.
  Contrast committed-job `r3 checkout`, which also copies the job's own files and symlinks `output/`
  back into the store; a dev-checkout materializes only the deps, in place, reversibly, with no output
  symlink (an uncommitted job has no store slot to point at). So this anchor is *not* a forthcoming r3
  feature — it is the clearest case of "local tooling may supersede" (§5). The skill must state the
  vanilla-r3 hazards that make a wrapper worth having (these are true of *any* dev-checkout, so they
  belong in the pure skill, unlike the wrapper's *solutions*): (a) a checked-out **git** dependency's
  `origin` is the r3 internal mirror, not the public upstream — add a remote to fetch/push real work;
  (b) **cleanup is destructive** — removing a git-dep directory you edited in place loses
  uncommitted/unpushed work, and the bundled bare `r3dev cleanup` `rmtree`s it with *no guard*, so the
  skill must warn before cleanup; (c) `output/`/`__pycache__` are dev throwaway to prune. (Verified
  against MK's xr3, which layers a clean-tree check + `--force`, bug-gating, and ignore-lists on these;
  that logic is house and stays in §5.) Even with no wrapper, an agent should run these checks *by hand*
  — e.g. confirm a checked-out git dep has no uncommitted/unpushed changes before cleanup; tooling only
  *enforces* the mitigation, it isn't a prerequisite for being careful.

## 5. Local tooling / extensions — shape-agnostic

The pure skill assumes **no extension shape**. It carries one general, upstream-safe principle and
names nothing house-specific:

> **Local tooling may supersede these.** Environments commonly wrap r3 — for commit, submission,
> history, richer find, dev-checkout, and more. If the user or the repo indicates such tooling exists
> (a project CLI on `PATH`, a house skill, the repo's CLAUDE.md/README), prefer it for that operation
> over the raw CLI/API.

That is the whole of what the pure skill says about extensions. Two supports:

- **Named anchors as precise hooks.** The §4 anchors (and the lifecycle verbs) are named so *external*
  guidance can point at them exactly ("here, `‹dev-checkout›` is `<tool>`") — but the pure skill never
  fills them in.
- **Guidance for whoever builds an extension** (kept in `extensions/`, not the skill): overrides live
  outside the pure skill and are **activated by the consuming context** (a repo CLAUDE.md/hook that
  says "use `<tool>` for r3 work here"), because description-based co-activation isn't reliable on its
  own. Override direction is one-way: extension → core, never core → extension. **The extension's form
  is undecided and intentionally unconstrained** — one wrapper, several focused single-aspect skills
  (commit / history / submission / …), or a full extension system are all compatible.
- **A convention checker is a broadly useful extension pattern.** A `check`/lint that validates a job
  against the user's conventions *before* commit (e.g. `path` matches the job's on-disk location, the
  tag scheme holds, required metadata is present, deps exist and aren't bug-flagged, git deps are
  clean) is a high-value adaptation for enforcing *your* conventions — the conventions are house, but
  the *pattern* generalizes across users. (MK's `xr3 check` is one instance.) Worth naming in the
  extension guidance as a recommended shape, without the pure skill carrying any specific rule.

## 6. Query grammar (complete, verified against `r3/query.py` on main)

MongoDB-style, but **only a subset is implemented** — advertise exactly this, no more:

- **Query-level (logical):** `$and`, `$or`, `$not`, `$nor`; plus **implicit AND** when a dict has
  multiple keys. Any other `$`-operator at query level raises `Unsupported operator`.
- **Field conditions:** `$eq` (also the implicit form `{field: value}`), `$ne`, `$in`, `$nin`, `$gt`,
  `$gte`, `$lt`, `$lte`, `$glob`, `$all`, `$elemMatch`.
- **Array semantics:** for `$eq/$ne/$in/$nin/$gt/$gte/$lt/$lte/$glob`, if the field is a JSON array the
  condition matches when **any** element satisfies it, else scalar compare. `$all` and `$elemMatch`
  bring their own array handling (they require an array field).
- **Not implemented — do NOT advertise:** `$exists`, `$type`, `$regex`, `$size`, `$mod`, `$expr`,
  `$text`, and **field-level `$not`** (`$not` is query-level only).
- **Caveats:** `$glob` is **SQLite GLOB** — case-sensitive, wildcards `*` `?` `[…]`, *not* regex or
  SQL `LIKE`. Query values are string-interpolated into SQL (not parameterized): `$gt/$gte/$lt/$lte`
  work only on **numeric** values — on a **string** field they **silently match *all* rows** (verified
  on main; semver is unqueryable this way). Use `$eq` for strings, store numeric versions; values with
  embedded quotes break — keep them clean.
- **Result order is UNSPECIFIED** except with `latest=True` (→ `ORDER BY timestamp DESC LIMIT 1`). A
  plain `find` / `find({})` has no `ORDER BY`, and `rebuild-index` re-inserts in filesystem order —
  never read `find` output as a timeline.
- **`find({})`** matches all jobs; **`latest=True`** = `ORDER BY timestamp DESC LIMIT 1`.

## 7. `path` as a suggested first-class attribute

Advertise `path` as **the recommended organizing convention** — a virtual-filesystem path
(`my-project/experiments/pilot`) that `find_latest`/`find_all` build on and that job/dependency
organization should lean on. Precision to keep the skill true to `main`:

- **`tags` is the only field r3's tooling privileges today** (`find --tag`, the `#tag` rendering in
  `find -l`).
- **`path` is a plain metadata field** — queryable like any other (API, or `find_latest: {path: …}`),
  but **not yet surfaced by the CLI** (no `--path`, not shown in `find -l`). `path` appears nowhere in
  r3's code on main; it is pure convention.
- **Coming:** first-class tooling per `../r3/kickoff_path_promotion.md` (`find -l` shows path before
  tags; `find --path` with wildcards; `r3 ls <prefix>` virtual-FS listing). Idea-stage only, so the
  skill promotes the *convention* now and flags the tooling as forthcoming.
- **Examples to seed suggestions (not prescriptions).** Give agents material to propose layouts,
  *less* opinionated than the tutorial. Paths are filesystem-like, from flat single segments to nested
  namespaces: `kodak`, `pca`, `report` → `datasets/kodak`, `my-project/experiments/pilot`,
  `combined-gaze-datasets/task0001_datasets/DAEMONS-source`. Properties to convey:
  - **A path need not be unique** — a whole sweep can share `path: pca`; `find_latest` resolves to the
    newest, `find_all` to all (add a distinguishing tag or a uuid to pin one).
  - **A path is a movable namespace** — re-`path` `kodak` → `datasets/kodak` later; committed jobs keep
    resolving (uuid pinning), new jobs adopt the new layout (the §3 reorganize property).
  - **path vs tags is a menu, not a rule** — path is the filesystem-like default; tags are an
    alternative or complementary index (a numbered `task000N_` layout can organize purely by tags; a
    `main-model` / `analysis` tag marks facets). Offer both; let the user choose.

## 8. Verified-against-main corrections (the verify-habit payoff)

Re-verification against `main` **changed several premises** the raw material leans on, and the whole
tutorial has now been mined into **`raw-material/tutorial-findings.md`** (a deduplicated,
verified-against-main inventory — the primary build input, superseding `R3-GOTCHAS.md`). The build
session must use these, not the pinned gotchas:

- **Pin reality:** local `main` == `origin/main` == `upstream/main` == `262a937`, `VERSION` **0.5.0**,
  `R3_FORMAT_VERSION` **1.0.0-beta.7**. `R3-GOTCHAS.md` is pinned to the older `c968f42`.
- **Packaging (PR #55) merged → "editable-install only" is STALE.** `pyproject.toml` ships
  `packages = ["r3"]`; `__init__.py` falls back to `importlib.metadata.version`; `git+https` installs
  work.
- **`r3 remove` refusal fixed → "mangled message, exit code 0" is STALE.** `Repository.remove` raises
  a clean `ValueError` listing dependent ids; the CLI maps it to exit 1.
- **`r3 checkout` confirmed present** on main (live `r3 --help` + `cli.py:103`) — the committed-job run
  path. (Dev-checkout of an *uncommitted* job is the separate, CLI-less concept in §4.)
- **Dev-checkout history (verified in git):** r3 once had a `r3 dev checkout` CLI command (`9b266a9`,
  2023); it was **intentionally removed** (`4da2253`, 2024 — the removal is in `main`, and touched only
  `cli.py`), leaving the `Repository.checkout` primitive intact. Dev-checkout behavior is deliberately
  user-owned — do **not** present it as a forthcoming r3 CLI feature. Second stale doc leftover:
  `../r3/docs/tutorial.md:59` still says "using `r3 dev checkout`" (a removed command).
- **Confirmed present on main:** PR #51 (CLI uses job ids), PR #54 (`output/` excluded; `Job.files`
  always appends `/output`), PR #50 (ignore patterns survive dir recursion).
- **New facts to fold into the skill/gotchas:**
  - Committing a git-dep job writes a `git tag r3/<job_uuid> <commit>` into the bare cache — a
    provenance pin against GC.
  - `r3 edit <id>` = open `$EDITOR` on `metadata.yaml`, then reindex (a CLI path to mutate metadata).
  - The read-only lock is **write-bit stripping**, not fixed octal modes: job dir + `r3.yaml` + code
    files get write bits removed; `metadata.yaml` and `output/` stay writable. Describe the *behavior*
    (which paths stay writable), not the `555/444/664` octals (umask-dependent).
  - Materialization precision: symlink-vs-copy for a job dep is decided purely by
    `str(source) == "." and recursive_checkout` (`storage.py` `checkout_job_dependency`). A non-`.`
    `source` yields a symlink regardless of the flag — the flag isn't "overridden," it just doesn't
    apply. Correct the gotcha's "forces `recursive_checkout=False`" wording.
  - Only `JobDependency` edges are tracked in the index's `job_dependencies` table (git deps aren't
    job edges).
  - **Job identity is a fresh `uuid4`**, not content-addressed (`storage.add`) — identical recipes get
    different ids; the content hash is integrity only.
  - **`for j in repo` is invalid** (no `Repository.__iter__`) — use `repo.jobs()` or `repo.find({})`.
  - An **unversioned git dep** resolves to the remote's **default-branch HEAD** (`ls-remote HEAD`), not
    literally `main`. **`recursive_checkout: true`** materializes the dependency's *own* transitive deps
    (a real recursive copy), not just a one-level copy.
  - Live gotchas (full set in the findings doc): **unstable `find` order**; **range ops match all rows
    on string fields**; **github.com-only** git deps; **`rm -rf` fails on a committed job** (`555`);
    cold-cache commit prints a cosmetic **`fatal:`**; a checked-out git dep is a **detached HEAD** whose
    `origin` is the internal mirror.
  - **A recursive job checkout omits `metadata.yaml` and `r3.yaml`** (`storage.py:217` `checkout_job`
    skips them). Because metadata is mutable, r3 won't reproduce it at checkout — so a downstream
    analysis must read parameters from a **committed file** (`config.yaml`), **never** from a
    checked-out dependency's metadata (e.g. after `find_all`). Surprising; surface it prominently.
- **No `commands:` field** (confirmed): vanilla r3 reads no `commands:` key; the `commands: run:` in
  `../r3/docs/tutorial.md:37` is an upstream doc leftover. The skill states `commands:` is inert.

## 9. Sources & locations (absolute paths)

- **This spec:** `tools/r3-tooling/docs/specs/2026-08-15-r3-skill-design.md`
- **r3 source — target `main`:** `tools/r3/` (working tree is on `feature/remote-storage`; read
  `main`, keep `remote.py`/remote-storage *out*). A clean `main` worktree is the safe way to read it.
  Package under `tools/r3/r3/`: `repository.py`, `job.py`, `query.py`, `cli.py`, `storage.py`,
  `index.py`, `utils.py`. Docs under `tools/r3/docs/`.
- **`raw-material/tutorial-findings.md`** — the **verified mined inventory** of the whole tutorial (this
  session's 6-agent pass, re-checked against `main`). **Primary build input; supersedes `R3-GOTCHAS.md`.**
- **`R3-GOTCHAS.md`** — `raw-material/R3-GOTCHAS.md` (pinned to `c968f42`, now superseded by the findings
  doc — kept for provenance); living original in `projects/r3-tutorial/`.
- **The r3 tutorial — worked examples:** `projects/r3-tutorial/r3-tutorial/` — `playbook.qmd`,
  **`r3dev.py`** (the bare dev-checkout loop to bundle), `docs/report-style.md`, `NOTES.md`,
  `R3-OBSERVATIONS.md`, `docs/superpowers/specs/`.
- **foreman** (Tangemann's web UI — context only): `tools/foreman/`.
- **On galvani — read-only via the `g` wrapper**
  (`~/…/presentations/2026-06_R3-and-agentic-science/scripts/galvani/g`; host `galvani-lustre`;
  allowlist `Bash(<that g path>:*)`) — **house context for the spec, not referenced by the skill:**
  - `RESEARCH_WORKFLOW.md` (migration source, §10):
    `g cat /mnt/lustre/work/bethge/mkuemmerer31/projects/research/docs/RESEARCH_WORKFLOW.md`
  - Real example jobs: `g ls …/2026-02-02_Prepare_Model_Release` and more under
    `…/projects/research/research/experiments/`.
- **Skills:** `writing-skills` (superpowers) to build it. House wrappers (xr3 etc.) — not on this
  machine yet; future `extensions/`.

## 10. `RESEARCH_WORKFLOW.md` migration list (spec/house context — pointer-first, §12-Q2)

Parts of `RESEARCH_WORKFLOW.md` are written as they are *only because no r3 skill exists yet*.
Relocate the r3-mechanics slices into the pure skill; leave house slices as an extension, replacing
moved content with a pointer. **Do this lazily** — a pointer now, migrate when the workflow doc is next
touched (it lives read-only on galvani; a big migration is out of scope for the build). This section
concerns MK's house tooling, not the skill's content.

- **Finding jobs** → grammar + `repo.find(query)` are **pure**; house `find`/`history` wrappers stay.
- **Config & dependencies** → `source:`-narrowing and `ignore`-a-cache are **pure**; container-revision
  policy stays.
- **Developing & committing** → what `commit` freezes + the `‹dev-checkout›` primitive are **pure**;
  house commit/check wrappers stay.
- **Promoting into a library** → "frozen `output/` is a ready-made oracle" is **pure**; the
  fidelity-vs-real-path method + dtype/bug lessons stay (house).
- **Long-running**, **Reports & writing**, **Open problems** → stay (house).

## 11. Non-goals

- Not a human tutorial (that exists). Not house conventions or wrapper internals beyond the neutral
  local-tooling principle. **Not remote-storage** — held out for the foreseeable future, not merely
  "until merge": it will be **alpha even post-merge** with an unstabilized API, and a reliability-first
  skill should not bake in a moving target. Not a frozen version pin — the skill **grows with r3 main**
  and carries the verify habit instead.

## 12. Resolved decisions

- **Q1 — repo name/layout:** RESOLVED. `r3-tooling`, `skills/r3/` (pure) vs `extensions/` (house).
- **Q2 — how much of `RESEARCH_WORKFLOW.md` migrates now:** RESOLVED → **pointer-only now, lazily**.
- **Q3 — wait for path-promotion?:** RESOLVED → **no**; advertise `path` as a suggested convention with
  tooling flagged forthcoming (§7).
- **Q4 — one skill vs a family:** RESOLVED → **one `r3` skill** + on-demand `reference/` files.
- **CLI-first vs API-first:** RESOLVED → **CLI-first for the lifecycle; the API as r3's general
  provenance interface** (§4), for permission management, framed open-endedly.
- **Extension mechanism:** RESOLVED → **shape-agnostic**; one neutral principle in the skill, override
  guidance in `extensions/`, no assumed form (§5).
- **Remote storage:** RESOLVED → out for the foreseeable future (§11).

## 13. Next steps

1. `writing-plans` on this spec → a build plan for `skills/r3/`. The whole tutorial is now mined into
   `raw-material/tutorial-findings.md` (verified vs `main`), so the plan can draw content from there
   rather than re-reading the tutorial.
2. Build the skill with `writing-skills`, **re-verifying every r3 claim against `main`** as authored;
   seed `reference/gotchas.md` from the findings doc's gotcha buckets (F, D, H) and bundle the bare
   dev-checkout script.
3. Stub `extensions/` once house wrappers land on this machine — shape TBD (§5).
