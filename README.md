# r3-tooling

Tooling and workflows around [r3](https://github.com/mtangemann/r3): the agent-facing **r3 skill**
(built), plus a home for house **extensions** (`xr3`, the `RESEARCH_WORKFLOW` conventions — *coming*).
Bootstrapped 2026-08-16 from the r3-tutorial work.

## The one organizing principle: pure r3 vs extensions

- **`skills/r3/`** — the **pure r3 skill**: describes *only r3 core* (the self-contained job/commit
  model, dependencies + query grammar, the CLI + Python API, r3's non-obvious behaviors). **No `xr3`,
  no house conventions, no galvani specifics.** Kept **upstream-ready** so it can move into r3 itself
  whenever (MK is r3's *de facto* primary maintainer — the upstream repo is still Matthias Tangemann's
  — so it's realistically his call). Verified against r3 `main` (see the validity stamp in `SKILL.md`).
- **`extensions/`** — the layer *on top of* r3: house tooling (`xr3`), the `RESEARCH_WORKFLOW`
  conventions, tutorial-derived examples, the galvani `g` helper. These **reference** the pure skill and
  never leak into it. Their **shape is deliberately undecided** (one wrapper, several focused skills, or
  a full extension system — TBD), so most of it is **not vendored here yet**.

Keeping the seam clean means upstreaming the pure skill is a directory move, not a disentangling job.

## Layout

- `skills/r3/` — **the pure r3 skill** (`SKILL.md` + `reference/` + `scripts/r3dev.py`). Built.
- `extensions/` — the house layer.
  - **present:** `research-workflow-additions.md` — house conventions to fold into `RESEARCH_WORKFLOW.md`.
  - **planned:** `xr3` (currently on galvani), migrated `RESEARCH_WORKFLOW` conventions, worked examples.
- `docs/specs/` — the design spec.
- `docs/superpowers/plans/` — the build plan.
- `docs/r3-upstream-doc-issues.md` — doc/code discrepancies to fix in the r3 repo upstream.
- `raw-material/` — source inputs (`tutorial-findings.md` = the verified mined knowledge base; snapshots
  — **re-verify against r3 `main`**).

## Status

- **`skills/r3/` — built and on `main`.** Verified against r3 `main` `262a937` / v0.5.0; carries a
  validity stamp + a `git log <stamp>..main` re-verification recipe so a later session can keep it current.
- **`extensions/` — not started** beyond the research-workflow notes; `xr3` will be added once its shape
  is decided.
- Remote-storage is held out of the skill for the foreseeable future (alpha post-merge); ⚠ path-promotion
  is idea-stage upstream and will eventually change `find` (the skill flags it).
