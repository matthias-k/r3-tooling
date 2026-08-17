# r3 Python API

Import as `import r3`. The two entry points are `r3.Repository(path)` (the job graph) and
`r3.Job(dir)` (one job on disk). Dependencies are constructed with the classes below.

## `r3.Repository(path)`

```python
repo = r3.Repository("/path/to/repo")          # opens an existing repository

repo.find(query, latest=False)   -> list[Job]  # Mongo-style query; latest=True -> newest one
repo.jobs()                      -> Iterable[Job]  # every job (== repo.find({}))
repo.commit(job)                 -> Job         # freezes a Job, returns the stored Job (with .id)
repo.checkout(item, path)        -> None        # materialize a Job or dependency into path
repo.remove(job)                 -> None        # delete a committed job (refuses if depended on)
repo.find_dependents(job, recursive=False) -> set[Job]   # jobs that depend on `job`
repo[job_id]  /  repo.get_job_by_id(job_id) -> Job       # KeyError if the id is unknown
```

- **`checkout(item, path)` resolves first.** `item` may be a `Job`, a resolved dependency,
  **or an unresolved query/git dependency** — `checkout` calls `resolve()` before
  materializing. That makes it the **dev-checkout primitive**: `repo.checkout(unresolved_dep,
  dir)` resolves the query (or git ref) to a concrete job/commit and materializes it in place.
- **`repo[id]` / `get_job_by_id(id)` raise `KeyError`** on an unknown id (the CLI wraps this
  into a clean nonzero exit).
- **`for j in repo` is INVALID** — `Repository` has no `__iter__`. Iterate with
  `repo.jobs()` or `repo.find({})`.
- `repo.rebuild_index()` mirrors `r3 rebuild-index`.

## `r3.Job(dir)`

```python
job = r3.Job("/path/to/jobdir")
job = r3.Job(path, id=None, cached_timestamp=None, cached_metadata=None)
```

| Member | Kind | Notes |
|--------|------|-------|
| `job.id` | attr → `str` or `None` | the job's uuid once committed (`None` before). `commit` returns a Job with it set; `repo[id]` keys on it. |
| `job.metadata` | property → `dict` | `{}` when there is no `metadata.yaml`. Mutating the dict does **not** write to disk. |
| `job.save_metadata()` | method | writes `job.metadata` back to `metadata.yaml`. Call it after any edit. |
| `job.dependencies` | property → `Sequence[Dependency]` | the job's declared dependencies. |
| `job.files` | property → `Mapping[Path, Path]` | files that would freeze (excludes `output/` and dep destinations). |
| `job.hash(recompute=False)` | method → `str` | the recipe content hash. |
| `job.timestamp` | property → `datetime` or `None` | commit time; `None` before commit. |
| `job.metadata = {...}` | setter | replaces the in-memory dict (still needs `save_metadata()`). |

**Caching API** (jobs read from the index carry cached metadata/timestamp so `find` need not
re-read every file):

- `job.uses_cached_metadata()` / `job.uses_cached_timestamp()` → `True` if served from the
  cache (possibly stale vs disk).
- `job.reload_metadata()` → re-read `metadata.yaml` from disk, dropping the cache.

## Dependency constructors — **destination-FIRST** (footgun)

Every constructor takes **`destination` as its first positional argument**, before the
job/query/repository it points at. This is easy to get backwards; use keywords when unsure.

```python
# Current (preferred) forms:
JobDependency(destination, job, source=".", recursive_checkout=True)
FindLatestDependency(destination, query, source=".", recursive_checkout=True)
FindAllDependency(destination, query, recursive_checkout=True)          # no `source`
GitDependency(destination, repository, commit=None, source="", branch=None, tag=None)
```

- `job` may be a `Job` (must be committed → has an `.id`) or a job-id string.
- `query` is a **dict** Mongo-style query.
- `FindAllDependency` takes **no `source`** — every matched job is checked out to a
  subdirectory of `destination` named by its job id.
- `GitDependency`: an empty `source` serializes to `.`; passing **both `branch` and `tag`**
  raises `ValueError`. With no `commit`, the ref resolves to a commit at commit time.
- **Unresolved query dependencies cannot be hashed** — `FindLatestDependency.hash()` /
  `FindAllDependency.hash()` raise `ValueError` (the hash would depend on the query result).
  Only `JobDependency` and `GitDependency` hash.

```python
# Deprecated string-tag forms — WARN (DeprecationWarning) at construction:
QueryDependency(destination, query, source=".")    # query = "#tag #tag" (space-separated, AND'd)
QueryAllDependency(destination, query_all)
```

Recognize the deprecated forms when reading old recipes; author new ones with
`FindLatestDependency` / `FindAllDependency`.

## Dev-checkout loop

Running an *uncommitted* job means materializing its dependencies in place, then cleaning up.
The pattern (the runnable version is `scripts/r3dev.py`):

```python
import os, shutil, r3

def checkout(repo, job_dir):
    for dep in r3.Job(job_dir).dependencies:
        dest = os.path.join(job_dir, str(dep.destination))
        if os.path.exists(dest):
            continue                       # guard: never overwrite an existing destination
        repo.checkout(dep, job_dir)        # resolves the dep, then materializes it

def cleanup(repo, job_dir):
    for dep in r3.Job(job_dir).dependencies:
        dest = os.path.join(job_dir, str(dep.destination))
        if os.path.islink(dest):
            os.unlink(dest)
        elif os.path.isdir(dest):
            shutil.rmtree(dest)            # DESTRUCTIVE — see the checkout gotchas
```

`cleanup` reverses the checkout by removing only the **dependency destinations**; the bare
loop does **not** clean the job's own `output/` or `__pycache__/` (a richer wrapper in your
environment may). A dev checkout creates **no `output/` symlink** (an uncommitted job has no
store slot), and committing afterwards discards the materialized deps and dev `output/`
regardless. `cleanup` `rmtree`s dependency directories with no guard, so it can destroy
uncommitted work you edited inside a checked-out git dep — check a git dep's `git status`
before cleaning. See the checkout section of `gotchas.md`.

## Working over the graph

The API is open-ended — reach for it whenever the task is reading or reshaping the graph
rather than running one lifecycle verb. Three illustrations (not a fixed menu):

- **Trace provenance *upstream*** — read what a committed job was built on, and recurse:

  ```python
  for dep in repo[job_id].dependencies:          # a committed job's resolved dependencies
      if isinstance(dep, r3.GitDependency):
          print(dep.repository, dep.commit)      # exact git repo + 40-hex commit
      else:                                       # a JobDependency
          print(dep.job, dep.source, dep.destination)   # upstream job uuid + what was taken
          upstream = repo[dep.job]               # walk up: recurse on its .dependencies
  ```

  `dep.job` is the upstream **uuid**; `repo[dep.job]` fetches it, so you recurse to trace a
  result's full lineage. (A committed job's stored `r3.yaml` records the same, frozen.)
- **Blast radius of a bad input** — `repo.find_dependents(job, recursive=True)` returns the
  exact transitive set of jobs that depend on `job` (answers "is anything downstream
  compromised?").
- **Bulk metadata reshape** — re-path or tag many jobs at once:

  ```python
  for job in repo.jobs():
      if job.metadata.get("path", "").startswith("old-project/"):
          job.metadata["path"] = job.metadata["path"].replace("old-project/", "new-project/", 1)
          job.save_metadata()
  ```

  Then `r3 rebuild-index` so `find` reflects the edits. This is safe because committed
  dependencies are frozen to job ids — reorganizing metadata never breaks a committed job.
