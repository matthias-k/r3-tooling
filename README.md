# r3-tooling

Tooling and workflows around [r3](https://github.com/mtangemann/r3) — the agent-facing **r3 skill**,
`xr3`, worked examples, and house research conventions. Bootstrapped 2026-08-16 from the r3-tutorial
work.

## The one organizing principle: pure r3 vs extensions

- **`skills/r3/`** — the **pure r3 skill**: describes *only r3 core* (the job/commit model,
  dependencies + query grammar, the Python API, r3's non-obvious behaviors). **No `xr3`, no house
  conventions, no galvani specifics.** Kept **upstream-ready** so it can move into r3 itself whenever
  (MK is r3's *de facto* primary maintainer — the upstream repo is still Matthias Tangemann's — so
  it's realistically his call).
- **`extensions/`** — the layer *on top of* r3: `xr3`, the `RESEARCH_WORKFLOW` house conventions,
  tutorial-derived examples, the galvani `g` helper. These **reference** the pure skill; they never
  leak into it.

Keeping the seam clean means upstreaming the pure skill is a directory move, not a disentangling job.

## Layout

- `skills/r3/` — the pure r3 skill (build per `docs/specs/2026-08-15-r3-skill-design.md`)
- `extensions/` — `xr3`, migrated `RESEARCH_WORKFLOW` conventions, examples (to come)
- `docs/specs/` — design specs
- `raw-material/` — source inputs for building the skill (snapshots — **re-verify against r3 `main`**)

## Status / next

Skeleton only. Next: review + polish `docs/specs/2026-08-15-r3-skill-design.md`, then build
`skills/r3/` from it with the `writing-skills` skill — **verifying every r3 claim against r3 `main`**
(remote-storage held out until it merges; ⚠ path-promotion is in flight and changes `find`).
