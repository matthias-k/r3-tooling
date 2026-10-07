# r3-feedback — optional feedback from your r3 sessions

During the AI Builder Camp we're learning where the r3 toolchain (the r3 skill, the
`xr3`/`xr3-slurm` tools, the research workflow, the installer, the docs) trips people up. If you
opted in at install time, your agent quietly notes friction while you work and writes it to a
**local** log in `feedback/log/`. **Nothing is sent anywhere automatically** — sharing is a
deliberate step you take if and when you want to.

## What gets logged

Short, structured notes about **the toolchain's behavior** — three kinds:

- **friction** — something in r3 / xr3 / the workflow / install / docs was wrong, confusing, or missing;
- **correction** — you had to correct how the agent did the r3 work;
- **steering** — you had to add a step the workflow never prompted for (often the most useful signal).

The observer is instructed to record *what the tool did*, not your research — no dataset names,
paths, code, or project details. It isn't perfect, so see "Before you share" below.

## Where the log lives

`feedback/log/<timestamp>_<session>.md`, one file per session. This directory is **git-ignored**,
so it is never committed and stays on your machine.

## Before you share (optional)

1. Open the files in `feedback/log/` and read them — or ask your agent: *"skim my r3-feedback log
   for anything private or sensitive before I share it."*
2. Redact anything you don't want to send.
3. Send it however you like — e.g. open an issue on the r3-tooling repo, or email the file to the
   organizers. _(Workshop organizers: put your preferred channel here.)_

Thank you — every friction note makes the toolchain better for the next person.

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
- **Or** re-run the installer (or `update.sh`) with `--no-feedback`, which also stops it being
  re-wired on future updates.

---
Adapted from the "Task Observer" skill by Eoghan Henn ([rebelytics.com](https://rebelytics.com)),
used under CC BY 4.0.
