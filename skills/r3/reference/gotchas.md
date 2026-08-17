# r3 gotchas — non-obvious behaviors

The behaviors that surprise agents. Read the relevant group before relying on a subtlety.
Query-operator traps live in `query-grammar.md`, not here.

## Commit & permissions

- **`output/` is excluded from every commit, unconditionally** — even with no `ignore:`
  declared, and even for nested `output/` deeper in the tree. The committed job keeps an
  **empty `output/`** directory; output paths never appear in `hashes:`. So a job's results
  are never frozen into the recipe hash — only regenerated into `output/` when the job runs.
- **The read-only lock is write-bit stripping, not a fixed mode.** On commit, r3 clears
  **all** write bits (user/group/other) from the job dir, its `r3.yaml`, and every copied
  code file — a directory ends up `555`, a file `444`. **`metadata.yaml` and `output/` keep
  their write bits** (both are mutable by design). The exact octal depends on the umask;
  what is guaranteed is *which paths stay writable*.
- **`rm -rf` on a committed job fails.** Because the job dir itself is stripped to `555`,
  you cannot unlink its contents; `rm -rf` errors and **short-circuits a `&&` chain**. To
  delete one, use `r3 remove`, or `chmod -R +w <jobdir>` first. (`r3 remove` restores write
  bits internally before deleting.)

## Checkout

- **A committed-job checkout workdir is throwaway scratch.** `r3 checkout <id> <workdir>`
  copies the job's own files (real copies — **but not `r3.yaml` or `metadata.yaml`**; see the
  next bullet), symlinks `output/` back to the store (so results
  written there persist), and materializes each dependency by its own rule. Only that
  `output/` symlink reaches the store — everything else in the workdir is disposable. The
  **target must not already exist** — checkout does `os.makedirs` on it, so if the target
  already exists it fails before creating anything. (A checkout that fails *midway* has no
  cleanup-on-failure and can leave a partial directory behind.)
- **A checkout omits `r3.yaml` and `metadata.yaml` — the job's own *and* every
  recursively-copied dependency's.** `r3 checkout` copies a job's code files but **skips
  `r3.yaml`, `metadata.yaml`, and `output/`** (output is symlinked); a dependency materialized
  as a recursive real copy (`source: "."` + `recursive_checkout: true`) is skipped the same
  way. Because metadata is mutable, r3 won't reproduce it at checkout — it can't guarantee the
  file still matches commit time. **Consequence (do not miss it):** a **running job cannot
  read its own `metadata.yaml`/`r3.yaml`** from the workdir, and a downstream analysis cannot
  read a dependency's — so keep any parameter you need at runtime (hyperparameters, seeds,
  labels) in a **committed regular file** (e.g. `config.yaml`), never in `metadata.yaml`. After
  a `find_all` fan-in especially, don't pull each upstream's params from its metadata — that
  file isn't there. (A non-recursive whole-job *symlink* does expose `metadata.yaml` through
  the link, but don't rely on it either, for the same mutability reason.)
- **The checkout primitive does not cleanly handle a pre-existing destination.** A job-dep
  symlink errors if its destination already exists; a git dep's move **nests** the tree
  inside the existing directory instead of replacing it. A dev-checkout loop must guard this
  itself (skip or remove destinations first) — the "non-destructive" behavior of a dev-loop
  wrapper is the wrapper's guard, not r3's.

## Git dependencies

- **github.com only.** Only `https://github.com/…` and `git@github.com:…` URLs are accepted;
  anything else raises `ValueError: Unrecognized git url` **when the URL is parsed** (at
  commit/checkout), **not at construction**. (A repo whose *name* contains a `.` — `owner/my.repo`
  — is also rejected.) Both accepted forms map to the same cache `git/github.com/<owner>/<name>`,
  so a warm cache can mask an https-auth failure — a private repo really needs ssh.
- **A checked-out git dependency lands on a detached HEAD, with `origin` pointing at r3's
  internal mirror** (a path inside the repository), not the public upstream. To contribute
  work back, add your own remote: `git remote add upstream <URL>`, then fetch/checkout a real
  branch before committing and pushing. Checkout reads the local mirror, so it **works
  offline**, and because commit writes a `git tag r3/<uuid> <commit>` into the mirror, the
  **pinned commit survives even if upstream force-pushes, rebases, or GCs it away**. This all
  applies to a **whole-repo** checkout (`source: "."` or omitted); a **narrowed `source:`** (a
  subdir or file) yields plain files with **no `.git`** — nothing to push back — and the
  whole-repo clone is **shallow (`--depth=1`)**, carrying no history.
- **A cold-cache `commit` may print a cosmetic `fatal:` next to the uuid.** Before fetching, r3
  probes the mirror with `git cat-file` to see whether the resolved commit is already present;
  on a miss git prints `fatal: …`. That is r3 *checking*, not failing — the commit succeeds and
  the uuid is the real output line. (An unpinned default-branch dep usually resolves to a commit
  already in the fresh clone, so you often won't see it; a pinned older commit is when it shows.)
  Alarming but normal.

## Find & query

- **`r3 find` returns rows in unstable order unless `--latest`.** The query has no
  `ORDER BY` except when `--latest`/`latest=True` is set (then `ORDER BY timestamp DESC LIMIT
  1`); `rebuild-index` re-inserts jobs in filesystem-iteration order, visibly reshuffling the
  results. **Never read `find` output as a timeline** — use `--latest`, or sort by
  `timestamp` yourself.
- **`find` serves index-cached metadata.** Results come from the SQLite index, not a fresh
  read of each `metadata.yaml`. If you edit a job's `metadata.yaml` directly and skip
  `r3 rebuild-index` (or `r3 edit`, which reindexes for you), `find` keeps returning the
  **stale** metadata.
- For the operator-level traps (silent `$eq` coercion of unknown operators, `$ne`/`$nin`
  not excluding on array fields, unquoted range comparisons matching all/erroring on string
  fields, JSON-type-strict matching, and the rest), see `query-grammar.md`.

## Metadata

- **`metadata.yaml` must be JSON-representable.** The index serializes it with `json.dumps`,
  so a value JSON cannot encode — most commonly a **bare (unquoted) YAML date**, which parses
  to a `date` object — raises `TypeError` at commit. The failure is a **partial commit**: r3
  copies the job into the store *before* it indexes it, so a bad value leaves an **orphaned,
  unindexed job** in `jobs/` — and because `rebuild-index` deletes the index and re-reads every
  job, that one orphan then makes `rebuild-index` itself fail (leaving `find` empty) until you
  `r3 remove <id>` it. **Quote dates** (and any other non-JSON scalar) so they store as strings.

## Errors

- Most `commit`/`checkout` failures surface as **raw Python tracebacks**, not clean messages —
  only a missing/invalid repository or an unknown job id are prettified. Read the exception at
  the *bottom* of the trace; it is not an r3 crash.
- **Two distinct commit-time dependency errors:** `ValueError: Cannot resolve dependency:
  <query>` — a `find_latest`/`find_all` matched nothing; and `ValueError: Missing dependency:
  <dep>` — a *resolved* job or git dep whose target (or `source:` subpath) isn't in the store,
  most often a **mistyped `source:`**.
- `r3 checkout` onto an **existing target** raises `FileExistsError` (the workdir must not
  pre-exist).
