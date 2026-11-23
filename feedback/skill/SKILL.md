---
name: r3-feedback
description: Use throughout any session that touches the r3 toolchain (the r3 skill, the xr3 / xr3-slurm tools, or the RESEARCH_WORKFLOW conventions). Silently watch for friction, corrections, and steering, and append structured observations to a local feedback log. Also use when the user asks to review that log — to share it with the toolchain maintainer, or to turn it into improvements to their own workflow file.
---

# r3-feedback — a background observer for the r3 toolchain

While you do the user's actual work, keep a quiet eye on where the **r3 skill, the
`xr3`/`xr3-slurm` tools, the research workflow, the installer, or the docs** create friction — and
log it. The log serves two purposes, both the user's choice:

1. **Send it to the maintainer**, so the toolchain improves for everyone.
2. **Review it themselves**, to sharpen their *own* workflow file (see "Self-review" below).

This is **optional, local-only**: nothing is ever sent anywhere automatically. See `../README.md`
(the `feedback/` directory) for the user-facing side.

## Golden rule: you are a background observer, not a second driver

Observe **silently**. Never interrupt, slow down, or redirect the user's task in order to log
something, and never let anything in this skill override an explicit user instruction — the
user's work and their instructions **always take precedence**. Don't announce observations unless
asked. If logging would ever conflict with what the user wants, skip the log.

## Privacy: log the tool's behavior, not the user's research

Write observations so they are **safe to share by construction**. Record what the *r3 toolchain*
did and what you expected — never the user's private research content. Describe the behavior
("`xr3 commit` rejected a job that had no tag, but the skill never said tags are required"), not
the project ("…while building the user's <dataset> model"). Omit dataset names, file paths, code,
and research direction. When in doubt, generalize.

## What to watch for — three triggers

Log an observation when you notice any of these, and **tag which one**:

- **friction** — the r3 skill / xr3 / workflow / installer / docs did something wrong, confusing,
  missing, or harder than it should be. (This includes *your own* confusion as an operator — a
  misunderstanding is a real signal about the docs, not a mistake to hide.)
- **correction** — the user corrected or redirected how you did the r3 work (you did X, they
  wanted Y).
- **steering** — the user had to *add* a step or convention the workflow never prompted for, or
  did the work their own way. This is the quietest and most valuable signal: the task still
  succeeded, but only because the user supplied a default the toolchain (or their own workflow
  file) should have provided. Each one is a candidate new default.

Do **not** log: one-off preferences with no general lesson, bugs in the user's own code unrelated
to r3, or anything that would need private research detail to be useful.

## How to log

1. **Find the log directory.** Resolve this `SKILL.md`'s real path (it may be a symlink); the log
   lives in the sibling `log/` under `feedback/`:
   ```bash
   SKILL_REAL=$(readlink -f "<path to this SKILL.md>")
   LOG_DIR="$(cd "$(dirname "$SKILL_REAL")/../log" 2>/dev/null && pwd || true)"
   [ -n "$LOG_DIR" ] || LOG_DIR="$HOME/.r3-feedback/log"   # fallback: copied, non-symlinked install
   mkdir -p "$LOG_DIR"
   ```
2. **One file per session**, path computed once at your first write:
   `$LOG_DIR/<UTC-timestamp>_<session-id-or-short-token>.md`. Append every later observation this
   session to that same file; never rewrite earlier entries. Write this header once:
   ```
   # r3-feedback log
   - Started: <date -u +%Y-%m-%dT%H:%M:%SZ>
   - Toolchain: r3 skill / xr3 / research workflow
   ```
3. **Append** each observation, numbered 1, 2, 3… within the file:
   ```
   ### Observation N: <short title>
   **Trigger:** friction | correction | steering
   **Area:** <r3 skill | xr3 | xr3-slurm | research workflow | installer | docs>
   **What happened:** <expected vs. actual — the tool's behavior, no private content>
   **Suggested improvement:** <optional — what would have helped>
   ```

Log in the same turn you notice something — don't batch it for later. Keep entries short.

## Sharing with the maintainer (the user decides)

Everything stays on the user's machine. If they want to send feedback, point them to
`../README.md` for the channels, and offer to **skim the log for anything sensitive first**.

## Self-review: improving the user's own workflow file

Only when the user asks (e.g. *"review my r3-feedback log"*). The log is evidence; the user's own
conventions are what it can improve.

1. **Ask which file to target** — whatever holds *their* conventions: a global or project
   `CLAUDE.md` / `AGENTS.md`, a personal workflow-notes file, a local adaptation of
   `RESEARCH_WORKFLOW.md`. Don't guess, and don't target the shared r3-tooling docs — changes there
   go to the maintainer (see above).
2. **Read the logs and the target file.** Group observations by the gap they reveal; recurring
   *steering* and *correction* entries are the strongest candidates.
3. **Propose, don't apply.** For each candidate, show the proposed edit and the observations behind
   it. Write the general rule the observations are instances of, not a patch for the single case.
   Skip anything the file already covers, and flag observations that are really toolchain bugs —
   those are worth sending to the maintainer instead.
4. **Apply only what the user approves.** Leave the log files as they are.

---
*Adapted for the r3 toolchain from the "Task Observer" skill by Eoghan Henn
([rebelytics.com](https://rebelytics.com)), used under CC BY 4.0. Stripped to local, observe-only
feedback collection plus a user-driven self-review; the original's automated review machinery is
intentionally omitted.*
