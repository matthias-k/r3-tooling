# xr3 extraction — execution handoff

Resume state for the xr3 extraction/cleanup work. Read this first after a context reset.

## Status (2026-09-01)

- **Branch:** `xr3-extraction` (in `tools/r3-tooling`). **Kept open** — the user chose NOT to merge
  to `main` per-phase; do not merge without asking.
- **Done:** Phases 0, 1, 2, 3 (lean), **4 (xr3-slurm extraction — complete)**. **Next:** Phase 5 (move
  `run_job_locally`; decide on further internal split), then Phase 6 (docs / CONTRACT.md).
- **Execution mode:** subagent-driven-development (fresh subagent per task, controller verifies,
  final independent review on the larger phases). Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

### Phase 4 result (commits `32d3092`..`8663ccf`, 9 commits)

`extensions/xr3-slurm/` is a self-contained sibling tool: `xr3-slurm` CLI (455 lines) + pure
`xr3slurmlib.py` (106 lines, stdlib-only, unit-tested) + `tests/` (7 tests). Commands: `submit`
(merged old query+jobs; job-ids and/or `--tag`/`--query`; `--cluster` defaults to `slurm.submit_host`
= SSH-to-headnode, `--cluster ""` submits locally; `--partition`/`--mem`/`--verbose`/`--observe`
per-invocation; config-driven `--exclude`), `status` (config headnodes), `watch` (job-name/id
primitive via absorbed sattach, `+ --tag` mode; the `newest-running_job` typo fixed). `sattachx`/
`sattachx_wait` absorbed (raw-material sources deleted). SLURM code + unused imports removed from
`xr3` — **golden gate `ALL DATA COMMANDS IDENTICAL`** confirms kept commands byte-unchanged. Config
lives in `xr3config.DEFAULTS["slurm"]` (`headnodes`/`submit_host`/`exclude_nodes`/`partition`/`mem`);
dev fixture `dev/xr3.config.local.yaml` carries real galvani values. 17/17 unit tests pass. `xr3` is
now 1440 lines (was 1830). **Env note:** live SSH-to-galvani (submit-non-dry/status/watch polling)
is UNREACHABLE from this container — verified by `--dry`/`--help`/golden instead.

**Deferred from Phase 4 (accepted, not bugs)** — for later if wanted: `_running_jobs_by_name`/
`_all_slurm_jobs` near-duplication (predates extraction); the 3x debounce-timer idiom in
`_watch_by_tag`; `datetime.utcnow()` vs `now()` cosmetic mix; `xr3.example.yaml`'s `slurm:` uses real
`galvani` rather than a placeholder (tidy in Phase 6); `slurm` config ships non-null galvani defaults
so a config-less colleague silently gets galvani (reconcile with spec §7's "actionable hint" in Phase 6);
no try/except around the watch poll loop (faithful to original); `R3_REPOSITORY` read via bare
`os.environ[...]` in xr3-slurm (pre-existing pattern).

Design authority: **`docs/specs/2026-08-22-xr3-extraction-design.md`** (the spec). Phase plans live in
`docs/superpowers/plans/2026-08-*-xr3-extraction-*.md`.

## Environment invariants (CRITICAL — hard to rederive)

The base Python here **cannot** import `r3`/`executor`. Run `xr3` via the `r3_lustre` conda env; run the
pure unit tests (`xr3config`, `xr3pathmap`) with base Python. Export before any run:

```bash
export R3_REPOSITORY=/mnt/lustre/work/bethge/mkuemmerer31/r3_repo
export XR3="env PYTHONPATH=/mnt/lustre/work/bethge/mkuemmerer31/r3 /mnt/lustre/work/bethge/mkuemmerer31/miniconda3/envs/r3_lustre/bin/python $(git -C . rev-parse --show-toplevel)/extensions/xr3/xr3"
export XR3_JOBDIR=/mnt/lustre/work/bethge/mkuemmerer31/projects/research/research/experiments/2026-08-04_DAEMONS-in-pysaliency
export XR3_PATH_GLOB='research/experiments/2026-08-04_DAEMONS-in-pysaliency*'
export XR3_CONFIG=$(git -C . rev-parse --show-toplevel)/dev/xr3.config.local.yaml
```

- **Golden harness:** `dev/xr3_golden.sh check` — captures `files`/`history`/`find`/`check` and strict-diffs
  vs the Phase-0 baseline (`dev/golden/baseline/`, gitignored). The equivalence target is that baseline;
  **do NOT re-capture it.** Behavior-preserving changes must print `ALL DATA COMMANDS IDENTICAL`.
  (The `help.txt` diff is informational and cumulatively shows earlier-phase command removals — expected.)
- **Golden target** `$XR3_JOBDIR` has one committed version, id `c47aba9d-b2d9-443a-b939-9c377365300f`,
  metadata.path `research/experiments/2026-08-04_DAEMONS-in-pysaliency`.
- **Unit tests:** `python -m pytest extensions/xr3/tests/` (base python) → **10 passed** currently
  (4 `test_xr3config.py` + 6 `test_xr3pathmap.py`).
- **Transient Lustre note:** runs occasionally fail with `Input/output error` / `Cannot send after
  transport endpoint shutdown` — a filesystem hiccup, not a code bug. Retry once or twice.
- `pytest` is present in both base (9.x) and `r3_lustre` (8.x). `pyyaml` in base. `dev/xr3.config.local.yaml`
  (real pathmap roots) is gitignored; `dev/golden/` and `__pycache__`/`.pytest_cache` are gitignored.

## Current file layout (`extensions/xr3/`)

- `xr3` — the CLI, single file, **1830 lines** (still holds the SLURM code Phase 4 will extract).
- `xr3config.py` — config loading: `load_config`, `config_path`, `DEFAULTS`, `_deep_merge`. Config lives at
  `$XR3_CONFIG` or `~/.config/xr3.yaml` (YAML); missing → defaults.
- `xr3pathmap.py` — `PathmapError`, `resolve_job_path(fs_path, config, config_source=None)` (pure, pathlib).
- `xr3.example.yaml` — committed config template for colleagues.
- `tests/test_xr3config.py`, `tests/test_xr3pathmap.py`.
- `_get_path` in `xr3` routes through `xr3pathmap.resolve_job_path(..., config_source=str(xr3config.config_path()))`
  and translates `PathmapError → click.ClickException` (graceful, traceback-free gating for all pathmap commands).
- `_config()` is `functools.lru_cache`d in `xr3`; blockers/WIP/ignored-deps read from `_config()["blockers"]`/`["dev_checkout"]`.

Config schema (Phase 2 subset; `[slurm]` arrives in Phase 4):
```yaml
pathmap: {roots: [{path: /abs, prefix: optional}, ...]}
blockers: {tags: ["bug/"], block_on_wip: true}
dev_checkout: {ignored_destinations: [], ignored_repositories: []}
```

## Phase 4 — extract `xr3-slurm` (NEXT)

Goal: move the SLURM code out of `xr3` into a **separate sibling tool** `extensions/xr3-slurm/`, self-contained
and MLCloud-specific (mostly galvani; should port to ferranti/other SLURM via config). Spec §3, §6, §7, §10.

**SLURM symbols to move (current line numbers in `xr3`):** `HEADNODES` (26), `submit_query` (1463),
`submit_jobs` (1486), `_submit_job` (1499, contains the deferred `if False:` at 1593), `check_for_slurm_job`
(1602), `get_all_slurm_jobs` (1613), `watch`/`_watch` (1635/1638), `status` (1721), `make_external_command`
(1821). The `submit` and `watch` Click groups + their subcommands. (`_check_git_*`/`diff`/`find`/`check`/`commit`/
`dev-*` STAY in `xr3`.)

**Settled design (from spec + prior discussion):**
- Name: `xr3-slurm`. Commands: **`submit`** (merge today's `submit jobs` + `submit query`), **`status`**, **`watch`**.
- **`watch` primitive = a SLURM job name/id** (positional), which is what the absorbed `sattachx_wait` uses
  natively. Since `submit` sets `--job-name=<r3 id>`, it composes: `xr3-slurm watch $(xr3 history --latest --id .)`.
  Keep an **optional `--tag`/`-t` family mode** (the existing `--newest`/`--oldest`/`--*-running-job` selection).
  On reimplement, FIX the latent bug at old `_watch`: `'newest-running_job'` (underscore) vs the
  `newest-running-job` flag value — that mode currently dies with "Invalid selection."
- **Absorb `sattachx` + `sattachx_wait`** (sources staged in `raw-material/sattachx*`): fold their poll-and-attach
  logic in, removing the external dependency AND the hardcoded `#!/home/.../miniconda3/bin/python` shebang.
- **`submit`** must preserve the per-invocation overrides that today live only on the (already-pruned) `submit
  location`: `--partition`, `--mem`, `--verbose`, `--observe`/`-o`, `--cluster`. **Merge caveat:** today
  `submit query` submits *locally* (`cluster=None → ExternalCommand`) while `submit jobs` submits *over SSH*
  (`cluster='galvani' → RemoteCommand`) — the merged `submit` must consciously reconcile these, not silently
  pick one (see the SSH-minimization roadmap in spec §10: read-only `squeue`/`sacct` locally, SSH only for `sbatch`).
- **`xr3-slurm` owns the sbatch options:** `--job-name=<r3 id>` (for status/watch lookup), `--output`/`--error`
  into the job's `output/` (array-aware `slurm_%A_%a.log` vs `slurm_%J.log`), `--chdir`, config-driven
  node-excludes/partition/mem, `--comment=<jobdir>` (informational). r3 does NOT set the job name — the wrapper does.
- **Clean up the deferred `if False:` block** in `_submit_job` (collapse `if False: RemoteCommand… else: ExternalCommand…`
  to just the live line) as part of the sattach rewrite.
- **`[slurm]` config section:** headnodes, node-excludes, partition/mem defaults, sattach behavior, done-file protocol.
  `xr3-slurm` reads only `[slurm]`; `xr3` reads only its own sections. Add real galvani values to the dev fixture.
- **`done`-marker convention** (spec §2): `xr3-slurm` (submit idempotency/restart, status) AND `xr3 commit`
  (`--copy-previous-output`/`--exclude-done`) assume jobs write `output/done`. Document in Phase 6.

**Verification for Phase 4** (SLURM can't be golden-verified — no live submit in tests): use `--dry` runs
(the submit path has a `dry` flag that prints the `sbatch …` command without submitting) to characterize the
constructed sbatch command; structural/`--help` smoke; `xr3`'s own golden must stay `ALL DATA COMMANDS IDENTICAL`
(removing SLURM must not touch the workflow commands). Consider a small unit test for the sbatch-option
construction if it's factored into a pure function.

**Invocation:** `xr3-slurm` is a sibling script run as `python extensions/xr3-slurm/<script>`; it will need its
own thin entry + to import `xr3config` for the `[slurm]` config (add `extensions/xr3-slurm` or a shared path).
Decide the module/import layout at plan time (keep it light; the user dislikes over-engineering).

## Deferred / later

- **Phase 5:** move `run_job_locally` (already vendored at `extensions/scripts/run_job_locally`) to final place;
  **then decide** whether a further internal split of `xr3` (`diff.py`, `core`/`cli`) is worth it on the smaller file.
- **Phase 6 — Docs:** `extensions/CONTRACT.md` (single source of truth for what the tools demand of jobs — the
  `done` marker, pathmap convention, `tags[0]`=path+semver, `R3_REPOSITORY`, GNU diff/less, runtime deps), tool
  READMEs, top/extensions README signposts, `projects/CLAUDE.md` (documents removed/moved commands), and
  `research/docs/RESEARCH_WORKFLOW.md`. The `"see CONTRACT.md"` pointer already emitted by pathmap gating is a
  deliberate forward-reference — Phase 6 must deliver that file.

## Process notes

- Observer log for this work: `Agentic-Science-Hub/observer/log/2026-08-22T19-52-58Z_xr3-extract.md`
  (5 observations logged; append-only).
- User preferences observed: config-over-env; commit often / reviewable increments; YAGNI (don't over-engineer);
  keep the pure r3 skill (`skills/r3/`) upstream-clean — extensions never leak into it.
