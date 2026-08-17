# r3-tooling

An agent-facing **r3 skill** — a Claude Code skill that lets an agent operate
[r3](https://github.com/mtangemann/r3) reliably (author jobs, wire dependencies, commit/checkout, query
the job graph, trace provenance). Plus a home for house **extensions** (`xr3`, `RESEARCH_WORKFLOW`
conventions — *coming*). Bootstrapped 2026-08-16 from the r3-tutorial work.

## Using the r3 skill

The skill is **`skills/r3/`** — self-contained (a `SKILL.md`, three `reference/` files, and a bundled
`scripts/r3dev.py`). Install it wherever your Claude Code discovers skills — e.g. symlink it so `git pull`
keeps it current:

```bash
ln -s "$(pwd)/skills/r3" ~/.claude/skills/r3                  # for all your projects
# or:  ln -s "$(pwd)/skills/r3" <project>/.claude/skills/r3   # for one project
```

(Copy the directory instead if you prefer a pinned snapshot; use whatever skill-install method your team
already uses.) Claude Code then activates it on r3 work — writing an `r3.yaml`, wiring
`find_latest`/`find_all` or git dependencies, committing/checking out jobs, the Python API, tracing lineage
— or you can invoke it explicitly. **Nothing else in this repo is needed to use the skill**; the rest is
how it was built and kept current.

## The one organizing principle: pure r3 vs extensions

- **`skills/r3/`** — the **pure r3 skill**: *only r3 core* (the self-contained job/commit model,
  dependencies + query grammar, the CLI + Python API, r3's non-obvious behaviors). **No `xr3`, no house
  conventions, no galvani specifics** — kept **upstream-ready** so it can move into r3 itself whenever (a
  directory move, not a disentangling job). Verified against r3 `main` (validity stamp in `SKILL.md`).
- **`extensions/`** — the house layer on top: `xr3`, `RESEARCH_WORKFLOW` conventions, examples, the galvani
  `g` helper. These *reference* the pure skill and never leak into it. **Shape deliberately undecided** (one
  wrapper, several focused skills, or an extension system — TBD), so most is **not vendored here yet**.

## Layout

**Use-facing:**
- `skills/r3/` — **the pure r3 skill** (install this).
- `extensions/research-workflow-additions.md` — house conventions to fold into `RESEARCH_WORKFLOW.md`.

**Build provenance / maintenance** (not needed to *use* the skill):
- `docs/specs/` — the design spec · `docs/superpowers/plans/` — the build plan.
- `docs/r3-upstream-doc-issues.md` — doc/code fixes to make in the r3 repo upstream.
- `raw-material/r3-findings.md` — the **verified mined knowledge base** the skill was authored from
  (dense working material; kept for re-verifying the skill against future r3 versions).

## Status

- **`skills/r3/` — built, reviewed, on `main`.** Verified against r3 `main` `262a937` / v0.5.0; the
  `SKILL.md` validity stamp + a `git log <stamp>..main` recipe let a later session keep it current.
- **`extensions/` — not started** beyond the research-workflow notes; `xr3` (currently on galvani) will be
  added once its shape is decided.
- Remote-storage is held out of the skill for now (alpha post-merge); ⚠ path-promotion is idea-stage
  upstream and will eventually change `find` (the skill flags it).
