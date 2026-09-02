# xr3 extraction & cleanup — design

**Date:** 2026-08-22
**Status:** approved design, ready for planning
**Repo:** `tools/r3-tooling` (house extension layer; *not* upstream r3)

This document is meant to be readable top-to-bottom: it starts from what `xr3`
is today, explains what we are building and why, then gives the concrete
inventory, config, phasing, and deferred ideas.

---

## 1. Purpose

`xr3` is the house convenience CLI wrapped around [r3](../../skills/r3/). It has
grown into a ~2,100-line single-file script at `research/tools/scripts/xr3`.
Colleagues want to use it, but it cannot be shared as-is. This spec **moves `xr3`
into `r3-tooling`** and, along the way, cleans it up, pushes its personal
assumptions into config, and factors the one-big-script into a small **suite of
focused tools**.

**Standards note.** `r3-tooling` is deliberately *not* held to upstream-r3
standards. We do **not** commit to a stable API and may change command shapes as
we learn. As adoption grows we will tighten; for now, favor "works and is
shareable" over ceremony (YAGNI).

## 2. Background — what `xr3` is today, and why it can't be shared

Auditing every command shows three tiers of dependence on the author's setup:

- **Tier 0 — portable, zero config.** `find`, `files`, `git-check`,
  `dev-checkout`, `dev-cleanup`, and the dependency/WIP/git parts of `check`.
  These already work for anyone, on any cluster.
- **Tier 1 — needs the working-dir→r3-path mapping.** `history`, `diff` (default
  mode), the path/origin/main-tag assertions in `check`, and `commit -r/-c`. The
  mapping lives in `_get_path` (`xr3:332-356`) as a **hardcoded list of 8 of the
  author's absolute paths** (with qb/lustre duplicates and a
  `combined-gaze-datasets` special case). No colleague can use these until that
  list leaves the source.
- **Tier 2 — MLCloud-specific SLURM (mostly galvani so far).** All `submit*`,
  `watch`, `status`. Baked-in
  specifics beyond `HEADNODES=['galvani']`: a node-exclude
  `galvani-cn221,galvani-cn240` (`xr3:1657`), an absolute path to `sattachx_wait`
  (`xr3:1865`) vs. a bare PATH lookup elsewhere (`xr3:1694`), and the `done`-file
  `restart`/`failed` protocol.

The tiers are already cleanly separated by command (nothing in Tier 0 imports the
path map or SLURM), which is what makes the split below cheap.

**Cross-cutting house convention — the `done` marker.** Both tools assume a job
writes `output/done` on completion (per the house `run.sh`, `echo completed >
output/done`), sometimes with a `restart`/`failed` payload. It is *not*
slurm-only: `xr3-slurm` uses it for submit idempotency/restart and `status`, and
**`xr3 commit`** uses it via `--copy-previous-output`/`--exclude-done`. This
assumption must be **documented explicitly** in both tools' docs so a colleague
whose jobs don't write `done` understands why completion tracking / output-copy
behaves oddly.

## 3. What we're building — a suite, split along cluster-independence

The sharp line for the split is **cluster-independence**: the r3-*workflow*
commands are cluster-agnostic (everyone wants them); the SLURM part is
**MLCloud-specific** (mostly galvani so far; should port easily to ferranti, our
other MLCloud region, and likely to other SLURM clusters via config). So SLURM
becomes a **sibling tool**, not a module inside `xr3`, that others reconfigure or
swap out.

```
extensions/
  xr3/               # r3-workflow CLI — cluster-agnostic
    cli.py           # composes the command groups
    config.py        # loads user config (pathmap roots, blocker tags, ...)
    core.py          # Tier 0: find, files, check(deps), dev-checkout/cleanup, git-check
    pathmap.py       # working-dir -> r3-path mapping (roots from config)
    diff.py          # the diff engine (independent of pathmap — see §5)
  xr3-slurm/         # MLCloud submission + observation — self-contained
    cli.py           # submit, status, watch  (absorbs sattachx/sattachx_wait)
  scripts/
    run_job_locally  # moved as-is (standalone bash; see roadmap)
```

Packaging is kept light (no pyproject/entry-point ceremony required): a thin
`xr3` / `xr3-slurm` shim or bash function invokes the respective `cli.py`, as
today. Exact invocation mechanism is a planning detail.

**Module boundary note.** The *tiers* are clean, but a few kept commands span
them: `check`'s path/origin/main-tag asserts, `commit`'s default `--check`
(`_check_job` calls `_get_path` unconditionally, `xr3:429`), and `diff`'s
default-target resolution all need pathmap. So the split is: the pure *engines*
(`diff.py`, the Tier-0 helpers in `core.py`) stay pathmap-free, while their
*command wiring* in `cli.py` imports `pathmap` and gates on it. "Nothing in Tier 0
imports pathmap" holds for the engines, not the command layer.

## 4. Process — baseline first

**Phase 0 copies `xr3` and `run_job_locally` verbatim into `r3-tooling` and
commits them**, before any change. Every later change is then a reviewable diff
*inside* `r3-tooling`, so it's clear what moved vs. what was rewritten. The
`sattachx`/`sattachx_wait` sources (already staged in `tmp/`) move to
`raw-material/` as the absorption source, so the absorption is auditable too.

## 5. Design decisions (with rationale)

**Config, not source, for assumptions — the real unlock.** "Activate only the
slurm part / only the path-mapping part" is fundamentally a *runtime* concern: a
colleague activates a capability by having its config present and by the command
failing gracefully when it isn't — largely independent of how the code is filed.
So the priority is externalizing hardcoded values + actionable "configure X"
errors; the module split is secondary (maintainability).

**Pathmap roots come from config — not a marker file, for now.** An alternative
considered was a `.r3root` marker dropped at each project root and discovered by
walking up from the working dir (no central list; works across machines/users
unchanged). It's attractive but has a nasty failure mode: if someone forgets the
marker in a new project, the behavior is confusing and the cause is hard to
locate. A centralized config list is closest to today's behavior and changes less
in one go. **`.r3root` goes on the roadmap** (§10), to revisit if the need arises.
The config schema must support a **per-root path prefix**, not just a flat root
list, to preserve the existing `combined-gaze-datasets` rewrite in `_get_path`
(`xr3:351-352`) — otherwise the author's own gaze-datasets mapping breaks on
migration.

**`diff` is independent of the path mapping.** The diff engine compares two
explicit locations — committed-job↔committed-job, or committed-job↔working-dir.
The path mapping is used *only* to resolve the convenience default ("diff this
working dir against its latest committed version") when no explicit target is
given. So `diff` with an explicit `--compare-to <job-id>` (or two ids) is Tier 0;
only the default-target resolution is pathmap-gated.

**Compose instead of `location` wrappers.** `submit location` and
`watch-location` are just `pathmap + the real command`. Drop them; compose in the
shell / by agents:
`xr3-slurm submit $(xr3 history --latest --id .)`.
This means `xr3-slurm` needs **zero** knowledge of the path mapping.

**Absorb `sattachx` / `sattachx_wait` into `xr3-slurm watch`.** `sattachx_wait`
carries a hardcoded `#!/home/.../miniconda3/bin/python` shebang and its
poll-and-attach loop overlaps what xr3's `_watch` reimplements. Absorbing both
removes an external dependency and a hardcoded path, and de-duplicates the loop.
It keeps the by-job-name feature (see §7).

**Small conventions become config, not deletions.** `WIP`-blocking, the `bug/`
blocker-tag prefix, and the `IGNORED_*` dev-checkout skips are all house
conventions others might want to change or extend. Where trivial, move them to
config rather than hardcode or delete (details in §6, §8).

## 6. Command inventory (keep / prune / rename)

### `xr3` (r3-workflow)

Keep: `find`, `files`, `history`, `diff`, `check`, `commit`, `dev-checkout`,
`dev-cleanup`, `git-check`.

Changes:
- **`commit` loses `--submit`/`--observe`** — its only SLURM tie. Submission is
  now composed: `xr3 commit . && xr3-slurm submit $(xr3 history --latest --id .)`.
- **`history` gains `--id`** (print only the job UUID) so it composes into
  `xr3-slurm`: for `submit` the UUID is an r3 repo lookup; for `watch` the *same*
  string is a SLURM job name (`submit` sets `--job-name=<r3 id>`). One flag feeds
  both. (Today short-mode prints the job's *filesystem* path, `job.path`, not
  `metadata.path`; there is no `--format`.) No other `history` changes.
- **`check`** keeps its dependency / WIP / git-clean checks and its
  path/origin/main-tag consistency checks (pathmap-gated). Two behavioral notes:
  - **`origin`**: the metadata `origin` field is *only* used to assert
    `origin == path` when present (it predates the rename from `origin`→`path`).
    It is never used for lookup. Keep the enforce-if-present check now; **dropping
    `origin` entirely is on the roadmap** (§10).
  - **blocker tags & WIP**: the `bug/` prefix and WIP-blocking become **config**
    (default `["bug/"]`, WIP on) so colleagues can change/extend blockers. Note
    the live hardcoded `"bug/"` checks are in **two** places — `check` (`xr3:420`)
    *and* `dev-checkout` (`xr3:1315-1329`, with its `--allow-bugs` escape) — and
    **both** must read the blocker-tag config, or blocking is inconsistent. (This
    replaces the *dead* `FORBIDDEN_TAG_PREFIXES` constant — which was never the
    source of either check — with a live, configurable version.)
  - **main-tag enforcement**: the assertion that `tags[0]` matches the logical
    path is now **largely superseded by the `path` enforcement** and could be
    dropped. Keep it as-is for now; **roadmap** (§10): make it optional via config
    or remove it — but removal needs a replacement **version-tag mechanism**,
    since `tags[0]` currently encodes `path + semver` and is what lets us filter
    for a specific version.

### `xr3-slurm` (MLCloud submission + observation)

- **`submit`** — merges today's `submit jobs` + `submit query` (takes job ids
  and/or a tag/query); reads ids from args for the composition pattern
  (`xr3-slurm submit $(xr3 history --latest --id .)`). **Must preserve** the
  per-invocation overrides that today live *only* on the pruned `submit location`:
  `--partition`, `--mem`, `--verbose`, plus `--observe`/`-o` (attach after submit)
  and `--cluster`. **Merge caveat:** today `submit query` submits *locally*
  (`cluster=None` → `ExternalCommand`, `xr3:1531`) while `submit jobs`/`location`
  submit *over SSH* (`cluster='galvani'` → `RemoteCommand`, `xr3:1549`). The merged
  `submit` must consciously reconcile these two default execution targets, not
  silently pick one — see the "minimize headnode SSH" roadmap item (§10) for the
  intended end state (local when possible, SSH only for `sbatch`).
- **`status`** — kept (done/running/failed summary + per-job detail).
- **`watch`** — primitive is a **SLURM job name / id** (positional), which is what
  the absorbed `sattachx`/`sattachx_wait` operate on natively (and works for
  non-r3 SLURM jobs too — the pre-r3 feature worth keeping). Since `submit` sets
  `--job-name=<r3 id>`, it composes directly with the *same* output `submit` uses:
  `xr3-slurm watch $(xr3 history --latest --id .)`. In this mode `watch` needs
  **no** r3-repo or pathmap access. An **optional `--tag`/`-t` family mode** is
  retained for watching a whole family and attaching to a selected member
  (`--newest`/`--oldest`/`--oldest-running-job`/`--newest-running-job`) — the only
  mode that queries the repo by tag. (On reimplement, fix the latent bug at
  `xr3:1823`: the selection list has `newest-running_job` with an underscore vs the
  `newest-running-job` flag value, so that mode currently dies with "Invalid
  selection.")

Pruned:
- **`submit auto`** — superseded by `submit query`.
- **`submit location`**, **`slurm watch-location`** — replaced by composition
  (their per-invocation flags migrate onto `submit`/`watch`, as noted above).

## 7. `xr3-slurm` responsibilities & config

**Correction to an earlier assumption:** r3 does *not* set the SLURM job name — r3
is unaware of SLURM. The submission helper does. So `xr3-slurm submit` is
responsible for the sbatch options that make the rest work:

- **`--job-name=<r3 job id>`** — so `status`/`watch` can find the job by name.
- **`--output`/`--error`** into the job's `output/` dir (array-aware:
  `slurm_%A_%a.log` vs `slurm_%J.log`).
- **`--chdir=<job dir>`**, plus config-driven **node-excludes**, **partition**,
  **mem**.
- **`--comment=<job dir>`** (informational). The local-vs-SSH execution target is
  a `submit` concern (see the §6 merge caveat), not a fixed sbatch option here.

Config section `[slurm]`: headnodes, node-excludes, partition/mem defaults,
sattach behavior, done-file protocol. `xr3-slurm` reads only `[slurm]`; `xr3`
reads only its own sections. A colleague "activates" a part by filling in its
section; a command whose section is absent fails with an actionable hint.

> **Roadmap seed (see §10):** if `run.sh` carried relative `#SBATCH
> --output=output/slurm_%j.log` directives, `cd <jobdir> && sbatch run.sh` would
> reproduce exactly today's *run* behavior (compute + logs into `output/`, minus
> monitoring) with **no wrapper at all**. This is primarily a `RESEARCH_WORKFLOW`
> / r3-tutorial slurm-example concern, not an `xr3` one. `xr3-slurm`'s only future
> role would be to **set `--output` only if `run.sh` doesn't already**, allowing
> the script to override. `--job-name` would still need injection (run.sh can't
> know its own UUID). YAGNI for now.

## 8. Dead code / cruft to remove

**Deliberate feature removals** (user-facing but deprecated — not "dead code"):
- `bugmark` command + `_build_dependents_graph` + `_trace_bug_in_graph` +
  `_trace_bug` (`xr3:1992-2121`) — replaced by notebook-based bug marking. It is
  documented in `projects/CLAUDE.md`, so removal **must update that doc** (§9/§11).
  The bug-tag *checking* stays (now config-driven, §6).

**Dead code (verified unused by grep):**
- `_get_origin` (`xr3:300-302`) — only referenced inside a commented block.
- Commented-out code blocks: `_history` parallel block (`317-323`), `submit_auto`
  old query (`1715-1719`), `status` per-cluster loop (`1928-1937`), `if False:`
  (`1691`), commented sbatch options (`1653-1659`).
- `from joblib import Parallel, delayed` (`xr3:17`) — becomes dead once the
  commented `_history` block above is removed (its only use).

Change rather than delete:
- `FORBIDDEN_TAG_PREFIXES` (`xr3:31-33`) — dead as written; **resurrect as
  configurable blocker tags** (§6) instead of deleting the concept.
- `IGNORED_DESTINATIONS` / `IGNORED_REPOSITORIES` (`xr3:23-29`) — from M.
  Tangemann's dev-checkout (he `pip -e` installs some repos in-container and skips
  them; the author instead checks out everything locally to keep parallel
  commits/branches). **Move to config** (empty default) since it's trivial and
  colleagues may want it; the concept stays documented so it's easy to rely on.

**r3-internal API coupling (fragility to acknowledge).** Several *kept* paths use
r3 internals: `repository._resolve_git_dependency` (`xr3:121`, git-check path →
`core.py`) and `job._config` (throughout `diff` → `diff.py`). Per
`r3-tooling/CLAUDE.md` ("verify every r3 claim against `../r3` main"), a shared
tool pinned to r3 internals is a maintenance risk worth stating in the tool
README. Upside: removing `bugmark` + the commented `_history` block eliminates
*all* `repository._index*` coupling (`.storage`/`.add`/`.save`/`.find_dependents`),
the worst of it.

## 9. Documentation plan

Two audiences must not miss this: **colleagues and their agents**. The docs are
structured so the *contract* (what the tools demand of jobs) is impossible to
overlook, separate from the *pitch* (what they add over bare r3).

**Files:**
- **`r3-tooling/README.md` — signpost.** A short "Extensions" section: one line
  each on `xr3`/`xr3-slurm`, plus a **bold pointer** that they add assumptions to
  your r3 jobs and a link to the contract. Kept short so it stays maintained.
- **`extensions/CONTRACT.md` — the contract, single source of truth.** A concise
  **checklist** of every assumption the tools place on r3 jobs, each with *what
  breaks if you don't*: the `done` marker (§2), the working-dir==r3-path pathmap
  convention, `tags[0]` = `path + semver`, `run.sh` writing `output/done` and
  using the scratch dir, etc. Hard-linked from the top README, both tool READMEs,
  and `RESEARCH_WORKFLOW.md`. (Filename choice: `CONTRACT.md` over
  `ASSUMPTIONS.md` — states the relationship.) The checklist must also cover the
  **`R3_REPOSITORY` env var** (required by nearly every command), the **runtime
  deps** (`click`, `pyyaml`, `r3`, `executor`; `+tqdm` for `xr3-slurm`), and
  `diff`'s reliance on **GNU `diff`/`less`/`PAGER`** (fine on the Linux HPC, not on
  macOS/BSD — so `diff` is "portable" only in the HPC sense).
- **`extensions/xr3/README.md`, `extensions/xr3-slurm/README.md` — per-tool
  reference.** The "what this adds over bare r3" catalog (small table) + command /
  flag / config reference. Each opens with a short "Assumptions" callout that
  **links to `CONTRACT.md`** rather than duplicating it.
- **`extensions/README.md`** — stays the map (pure-vs-extension); updated to list
  the vendored tools and link the contract.
- **`research/docs/RESEARCH_WORKFLOW.md`** — links to `CONTRACT.md` instead of
  restating the assumptions.
- **`projects/CLAUDE.md`** — currently documents `xr3 bugmark`, `xr3 submit
  location`, `xr3 status`, `xr3 watch`; update for the removed/moved/renamed
  commands.
- **`r3-tooling/CLAUDE.md`** — a short pointer so agents discover the extensions
  and the contract.

**Make the tools point at their own docs (the strongest "can't miss"):**
- Graceful gating messages name the doc: a pathmap/slurm command that fails for
  missing config prints "…see `CONTRACT.md`" — un-missable at the moment of
  friction (this reuses the gating from §5).
- `--help` epilog (and optionally a tiny `xr3 doctor`) names the assumptions and
  links the contract.

## 10. Deferred / roadmap (captured, not built now)

- **`.r3root` marker mechanism** — auto-discover the project root by walking up,
  as an alternative/addition to config-listed roots. Deferred over the
  "forgotten marker" failure mode.
- **Drop `history`/`diff` pathmap dependence by reading `metadata.path`** — instead
  of *deriving* the r3 path from the filesystem location (pathmap), `history` and
  `diff` could read `metadata['path']` straight from the working dir's
  `metadata.yaml` and query the repo for it. This needs **no pathmap config** and
  is robust to a moved/copied working dir (it uses the job's own declared
  identity). It would shrink Tier 1 to just `check`/`commit`'s enforcement — the
  one place that genuinely must derive the expected path from the filesystem to
  *verify* `metadata.path`. Endorsed as a good direction; deferred only to avoid
  changing too much in this one extraction.
- **Drop `origin` entirely** — once no active jobs rely on the `origin`→`path`
  compatibility check.
- **Make main-tag enforcement optional/removable** — superseded by `path`
  enforcement (§6); removal first needs a replacement version-tag mechanism to
  preserve version filtering.
- **Push sbatch `--output` into the run.sh template** — see §7; primarily a
  `RESEARCH_WORKFLOW` / tutorial change enabling plain `cd <jobdir> && sbatch
  run.sh`. `xr3-slurm` would then set `--output` only if run.sh doesn't.
- **Minimize headnode SSH** — `xr3-slurm` currently routes *every* slurm command
  (`squeue`, `status`, `sbatch`) through an SSH `RemoteCommand` to the headnode
  when a cluster is set. But read-only queries (`squeue`/`sacct`) work locally on
  a compute node; only `sbatch` genuinely needs the headnode (env-var overrides).
  Today `submit query` / `status` can fire many SSH logins, which admins dislike.
  Fix: run read-only slurm commands locally when possible; SSH only for `sbatch`.
- **`watch --path '<glob>'`** — add a `metadata.path` GLOB selector to `watch`'s
  family mode, reusing `xr3 find`'s `--path` query (`_build_query`). Convenient for
  watching all jobs under a path prefix.
- **Configurable blocker tags / WIP** — shipping in §6, but "add more blocker
  kinds" is open-ended and can grow here.
- **Fold `run_job_locally` into `xr3-slurm`** — it assumes the SLURM scratch dir
  for environment building, so it conceptually belongs there. Kept standalone for
  now; do not reimplement.
- **`examples/`** — documented, adaptable templates that can't be used as-is but
  encode powerful patterns for colleagues (and their agents): start with
  `auto_submit.py`, then `setup_tasks.py`.
- **`xr3-slurm`: MLCloud-general → SLURM-general** — the immediate aim is
  MLCloud-general (galvani + ferranti) purely through config (headnodes, excludes,
  partitions, sattach behavior). Broader portability to non-MLCloud SLURM clusters
  is likely but unverified; revisit any deeper generic/site split when such a user
  actually appears (YAGNI).

## 11. Phasing

0. **Baseline** — copy `xr3` + `run_job_locally` verbatim into `r3-tooling`;
   commit. Move `sattachx*` from `tmp/` to `raw-material/`.
1. **Remove dead code + prune** (`bugmark`, `submit auto`, `location` wrappers,
   `_get_origin`, commented blocks).
2. **Externalize config** — pathmap roots, blocker tags/WIP, `IGNORED_*`; add
   graceful gating. Kills the hardcoded path list.
3. **Module split** (`core`/`pathmap`/`diff`/`config`/`cli`); make `diff`
   pathmap-independent; `commit` drops `--submit`; `history` gains `--id`.
4. **Extract `xr3-slurm`** (submit/status/watch); absorb sattach; own the sbatch
   options (§7).
5. **Move `run_job_locally`** into `scripts/`.
6. **Write docs** — per §9: `extensions/CONTRACT.md`, the two tool READMEs, the
   top/extensions README signposts, the `CLAUDE.md` pointer, and the
   help-epilog/gating doc pointers; then update
   `research/docs/RESEARCH_WORKFLOW.md`, `projects/CLAUDE.md` (removed/moved/
   renamed commands), and `docs/ideas/research-workflow-additions.md` to link the
   contract and match the new tools, commands, config, and composition patterns.

## 12. Out of scope

- Upstreaming anything into r3 core (`skills/r3/` stays pure).
- A plugin/entry-point extension system (revisit as adoption grows).
- Any change to r3 itself, or to the run.sh template convention (§7 roadmap).
