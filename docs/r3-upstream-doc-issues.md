# r3 repo — doc/code discrepancies to fix upstream

Running log of places where the **r3 repo's own docs/comments** disagree with the code/behavior on
`main`, found while building the r3 skill. Verified against r3 `main` @ `262a937` / v0.5.0. For MK to
reconcile in the r3 repo (these are r3-repo doc fixes, not skill content).

| # | Location | Doc says | Code/behavior on main | Note |
|---|----------|----------|-----------------------|------|
| 1 | `docs/tutorial.md:37` | `commands:` → `run: python run.py` | Vanilla r3 reads **no `commands:` key** — inert (a cluster-executor concept). | `cli.py`/`job.py` read no such key. Leftover. |
| 2 | `docs/tutorial.md:59` | "using `r3 dev checkout`" | The `r3 dev checkout` **CLI command was removed** (`4da2253`); only the `Repository.checkout` primitive remains. | Stale — references a deleted command. |
| 3 | `docs/repository_format.md:61` | `ignore`: "patterns as used by git" | `utils.find_files` supports **only absolute, exact-segment patterns** (`/output`); raises `NotImplementedError` on a non-`/` pattern; no globs; no `.gitignore`. | Doc overstates capability. |
| 4 | `docs/repository_format.md:59` | dependency key `query` (generic) | Code emits specific keys **`find_latest` / `find_all`** (and deprecated `query` / `query_all`). | Format doc is behind the code. |
| 5 | `docs/repository_format.md:15` | index may be `index.yaml` **or** `index.sqlite` | Current r3 implements **only `index.sqlite`** (no `index.yaml` handling in source). | Informational, not a bug: `index.yaml` is a **legacy** format; real long-lived repos still carry a stale `index.yaml` leftover beside the live `index.sqlite`. Doc could note sqlite is current. |
| 6 | `docs/repository_format.md:54,59` | `source` documented uniformly for dependency entries | **`find_all`/`query_all` deps carry no `source`** (source-less by design); only `job`/`find_latest`/`query`/git deps have one. | Test-confirmed (`test_job.py`). |
| 7 | remove-refusal message (any doc/docstring showing old layout) | explanation written *between* the dependents | Now an explanation **prefix line above** the sorted dependents (`test_repository.py:79-82` records the change). | Grep docs/docstrings for the stale layout. |

<!-- Append rows as the test-suite / job mining surfaces more. Keep the "verified against main @ <commit>"
     stamp in mind: a discrepancy is only worth reporting once confirmed against current main. -->
