# r3-feedback — optional observer for your r3 sessions

An **opt-in** agent skill that quietly notes where the r3 toolchain (the r3 skill, the
`xr3`/`xr3-slurm` tools, the research workflow, the installer, the docs) trips you up while you
work, and writes it to a **local** log in `feedback/log/`. **Nothing is sent anywhere
automatically.** What you do with the log is up to you:

- **send it to the maintainer**, so the toolchain gets better for everyone, and/or
- **use it yourself** to sharpen your own workflow file (your `CLAUDE.md` / `AGENTS.md`, personal
  workflow notes, …).

## Turning it on

Pass `--feedback` to `install.sh` (or answer *yes* at its interactive prompt). This links the
skill into `~/.claude/skills` / `~/.codex/skills` and adds a short session-start block to
`~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` that activates it. The choice is saved in
`update.sh`, so updates keep it.

## What gets logged

Short, structured notes about **the toolchain's behavior** — three kinds:

- **friction** — something in r3 / xr3 / the workflow / install / docs was wrong, confusing, or missing;
- **correction** — you had to correct how the agent did the r3 work;
- **steering** — you had to add a step the workflow never prompted for (often the most useful signal).

The observer is instructed to record *what the tool did*, not your research — no dataset names,
paths, code, or project details. It isn't perfect, so read the log before sharing it (see below).

## Where the log lives

`feedback/log/<timestamp>_<session>.md`, one file per session. This directory is **git-ignored**,
so it is never committed and stays on your machine.

## Sending feedback (optional)

1. Open the files in `feedback/log/` and read them — or ask your agent: *"skim my r3-feedback log
   for anything private or sensitive before I share it."*
2. Redact anything you don't want to send.
3. Send it either way:
   - open an issue at <https://github.com/matthias-k/r3-tooling/issues> and paste the log
     (public), or
   - email it to Matthias Kümmerer at <matthias.kuemmerer@bethgelab.org> (private).

Thank you — every friction note makes the toolchain better for the next person.

## Improving your own workflow (optional)

Ask your agent: *"review my r3-feedback log and suggest improvements to my workflow file."* It
asks which file to target, groups the observations (recurring *steering* and *correction*
entries first), and **proposes** edits for you to approve. Nothing is changed without your OK.
Observations that are really toolchain bugs are worth sending upstream instead (above).

## Turning it off

- **Claude Code:** remove the `r3-feedback` block from `~/.claude/CLAUDE.md`, and optionally
  `rm ~/.claude/skills/r3-feedback`.
- **Codex:** remove the `r3-feedback` block from `~/.codex/AGENTS.md`. To keep the skill installed
  but inactive, add to `~/.codex/config.toml`:
  ```toml
  [[skills.config]]
  path = "<toolchain-root>/r3-tooling/feedback/skill/SKILL.md"
  enabled = false
  ```
- **And** re-run the installer (or `update.sh`) with `--no-feedback`, so future updates don't
  wire it back in.

---
Adapted from the "Task Observer" skill by Eoghan Henn ([rebelytics.com](https://rebelytics.com)),
used under CC BY 4.0.
