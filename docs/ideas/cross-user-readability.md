# Cross-user readability of committed jobs

Not a standalone feature — captured mechanics plus a possible future enforcement hook, for
the decentralized repo-sharing / remote-storage design to build on.

## Mechanics (verified against r3 `main`)

- Commit copies files with `shutil.copy` and strips **only write bits**
  (`storage._remove_write_permissions`: `mode & ~0o222`), preserving read bits. So a `0o600`
  source (owner-only — e.g. weights written under `umask 0o077`) is stored `0o400`.
- `shutil.copy` **re-owns** the copy to the committer, so committed files are always the
  committer's, regardless of who owned the source.
- On an ACL store (`/work`: `default:group:bethge:r-x`, `default:mask::r-x`), a file's group
  readability follows its group-mode bit, which sets the ACL mask: `0o440` → group can read;
  `0o400` → `mask::---` → only the owner.

## Consequence

A committed job can be readable by its owner but **not by other users** — their checkout then
fails *reading* the source file. Because the committer owns everything post-commit, a
"can the committer read it" (self-readability) check **cannot** detect this: the problem is
intrinsically about *other* users, and "readable enough" is use-case specific (group-read vs
named ACLs vs per-collaborator).

## Future hook

Belongs with **decentralized repo sharing** (roadmap): once the sharing model defines the
intended audience, an `xr3 check` / `xr3 commit` step could enforce configurable required
permissions (group-read, named ACLs, …) declared in `xr3.yaml`, and flag or auto-`chmod`
offending files before commit. Deferred until the sharing model exists — a blunt group-read
check now would be wrong for private jobs and too coarse for finer ACL needs.
