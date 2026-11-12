---
status: approved
issue: 1763
author: olafkfreund
---

# Intent: the user-migration triage follows the commands a migration runs

## Problem

`checks.user-migrations-ledger` picks the Omarchy migrations that touch a
user's files by grepping each migration's own text for `HOME`, `XDG_CONFIG`,
`.config` or `shell.json`. A migration that changes user files only through
an `omarchy-*` command is invisible to it. #1760 hit this: quattro's
`1794390043` runs only `omarchy-cmd-editor-mimetypes --unless-chosen`, which
rewrites `~/.config/mimeapps.list`, and the triage did not list it. The edge
carry papered over that one case with a hand-written `via` field and a
hard-coded command name in the check, so the next migration of the same
shape will slip past again.

## Proposed outcome

- The triage also lists a migration when a command it runs (one level of
  `omarchy-*` calls) touches user files.
- Each such command has one recorded decision, saying whether its callers
  need a row, so `omarchy-state` and `omarchy-migrate` (39 of the 54 new hits
  on quattro) are decided once rather than per migration.
- Every migration this newly lists has a decided row in
  `data/user-migrations.nix`, or is in `predates`.
- The hard-coded command and the `via` field are gone.
- The check holds under both pins (`main`'s v4.5.0 and edge's quattro).

## Affected users and systems

CI only: `tests/user-migrations-ledger.nix`, `data/user-migrations.nix`, a new
command ledger, and `pkgs/AGENTS.md`. Nothing that ships changes, because a
decision row records what nixarchy already does.

## Constraints

- One level of calls, as the issue asks; deeper chains are a stated hole.
- A command the check cannot classify fails the check (fail closed), and an
  empty triage is not a pass (AGENTS.md §4).
- The check must fail on each removed row or decision (§1).
- The `via` field and the hard-coded command exist only on edge, so this
  lands as an `edge-candidate` carry after #1760 is promoted.

## Open questions

None. The owner pre-approved all changes for the open issues on 2026-11-12.
