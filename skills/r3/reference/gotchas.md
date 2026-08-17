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
  copies the job's own files (real copies), symlinks `output/` back to the store (so results
  written there persist), and materializes each dependency by its own rule. Only that
  `output/` symlink reaches the store — everything else in the workdir is disposable. The
  **target must not already exist** — checkout does `os.makedirs` on it, so if the target
  already exists it fails before creating anything. (A checkout that fails *midway* has no
  cleanup-on-failure and can leave a partial directory behind.)
- **A recursive checkout of a job dependency omits that dependency's `metadata.yaml` and
  `r3.yaml`.** When a dep materializes as a recursive real copy (`source: "."` +
  `recursive_checkout: true`), r3 copies the upstream's code files but **skips its
  `r3.yaml`, `metadata.yaml`, and `output/`** (output is symlinked). Because metadata is
  mutable, r3 will not reproduce it at checkout — it cannot guarantee the file still matches
  what it was at commit. **Consequence (surprising — do not miss it):** a downstream analysis
  must read an upstream's parameters (hyperparameters, labels, seeds) from a **committed
  file it froze into the recipe** (e.g. a `config.yaml`), **never** from a checked-out
  dependency's `metadata.yaml`. After a `find_all` fan-in especially, do not pull each
  upstream's params from its metadata — that file is not there. (A non-recursive whole-job
  symlink *does* expose `metadata.yaml` through the link, but don't rely on it either, for
  the same mutability reason.)
- **The checkout primitive does not cleanly handle a pre-existing destination.** A job-dep
  symlink errors if its destination already exists; a git dep's move **nests** the tree
  inside the existing directory instead of replacing it. A dev-checkout loop must guard this
  itself (skip or remove destinations first) — the "non-destructive" behavior of a dev-loop
  wrapper is the wrapper's guard, not r3's.

## Git dependencies

- **github.com only.** Only `https://github.com/…` and `git@github.com:…` URLs are accepted;
  anything else raises at construction. Both forms map to the same cache
  `git/github.com/<owner>/<name>`, so a warm cache can mask an https-auth failure — a private
  repo really needs ssh.
- **A checked-out git dependency lands on a detached HEAD, with `origin` pointing at r3's
  internal mirror** (a path inside the repository), not the public upstream. To contribute
  work back, add your own remote: `git remote add upstream <URL>`, then fetch/checkout a real
  branch before committing and pushing. Checkout reads the local mirror, so it **works
  offline**, and because commit writes a `git tag r3/<uuid> <commit>` into the mirror, the
  **pinned commit survives even if upstream force-pushes, rebases, or GCs it away**.
- **A cold-cache `commit` prints a cosmetic `fatal:` next to the uuid.** Before fetching, r3
  probes the mirror with `git cat-file` to see whether the commit is already present; on a
  miss git prints `fatal: …`. That is r3 *checking*, not failing — the commit succeeds and
  the uuid is the real output line. Alarming but normal.

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
  to a `date` object — raises `TypeError` at commit. **Quote dates** (and any other
  non-JSON scalar) so they store as strings.
