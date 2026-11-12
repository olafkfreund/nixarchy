---
status: approved
issue: 1763
intent: intent/2026-11-12-1763-migration-triage-follows-commands.md
---

# Spec: the user-migration triage follows the commands a migration runs

## Design

**A command ledger.** New file `data/user-migration-commands.nix`, one row
per `omarchy-*` command that some migration runs and whose own script
matches the user-file grep (`HOME|XDG_CONFIG|\.config|shell\.json`):

```nix
"omarchy-state" = { follow = false; reason = "writes only Omarchy's own markers under ~/.local/state"; };
"omarchy-theme-set-browser" = { follow = true; reason = "rewrites the browser's theme files in ~/.config"; };
```

`follow = true` means the command's callers are triaged like a direct hit.
`follow = false` needs a reason saying why its writes are not user files a
migration decision is about. Rows take the existing `edge = "only" | "absent"`
markers, so the file holds under both pins.

**The check** (`tests/user-migrations-ledger.nix`) gains one step after the
direct grep. For every migration the grep did not list, it collects the
`omarchy-[a-z0-9-]+` words it names. Each one that exists in `bin/` and
matches the grep must have an active command row; otherwise the check fails
with "commands a migration runs with no row in
data/user-migration-commands.nix". A migration with a `follow = true` command
joins the triage. The check also fails on:

- a command row the pinned source does not need (stale, the same rule as
  migration rows);
- a row missing `follow` (a boolean) or `reason`;
- an empty command list when the scan found commands (§4: an empty list is
  not "all decided").

**Removed:** the edge-only block that hard-codes
`omarchy-cmd-editor-mimetypes`, the `via` validation, and the `via` field on
`1794390043`. That row stays, now listed because `omarchy-cmd-editor-mimetypes`
is `follow = true`.

**The grep also matches `~/`.** Migration `1786098807` writes
`~/.agents`, `~/.claude`, `~/.codex` and `~/.pi` through a tilde and matches
neither the old grep nor a command, so the pattern used for migrations and
for commands becomes `HOME|XDG_CONFIG|\.config|shell\.json|~/`. On quattro
that lists 8 more migrations directly, some of them only through a comment
(a safe-side row).

**Rows.** The step-1 check computes, per pin, which migrations newly need a
row; this spec does not prescribe a count. An id that is in v4.0.6's
`migrations/` and is triaged on **both** pins joins `predates`. Otherwise it
gets a decided row, marked `edge = "only"` when only quattro needs it.
Omarchy's migrations do not run here (`omarchy-migrate` refuses), so each
decision records what nixarchy does instead: mostly `not-needed`, with the
reason. Measured by hand on 2026-11-12, there are about 23 command-triaged
migrations on quattro and 19 on v4.5.0.

**A command row's `edge` marker says on which pin the row is needed**, not
where the script exists. `omarchy-update-keyring` matches only on quattro,
and only because `GNUPGHOME` contains `HOME` (a temporary keyring), so it is
`follow = false, edge = "only"`, and its caller `1787589206` is not
triaged on either pin.

**Docs:** `pkgs/AGENTS.md` "User-file migrations (#1610)" says that a bump
may also name a command, which gets a `data/user-migration-commands.nix` row,
and that only one level of calls is followed. The header comments of both
data files say the same.

## Alternatives rejected

- **A row for every migration that reaches any command** (the issue's 54):
  39 of those are `omarchy-state` and `omarchy-migrate` and would be the same
  "not-needed" written 39 times. One decision per command is the same fact,
  recorded once.
- **Follow calls recursively:** commands call `omarchy-state` and other
  shared helpers, so a deep walk lists nearly every migration. The issue asks
  for one level, and a deeper walk is left as a stated hole.
- **Keep `via`:** it marks one known case by hand, so it is exactly the
  hand-maintained list §4 warns about.

## Risks

- A word match can name a command the migration only mentions in a comment or
  echo. The cost is one extra command row, never a missed migration; that is
  the safe side.
- A row needed on one pin only needs its `edge` marker, and a `predates` id
  must be triaged on both pins; the check is built on both.
- Still not seen: writes through a sourced helper, through `$OMARCHY_PATH`
  scripts that are not `omarchy-*` commands, or more than one call deep.
  Named in `pkgs/AGENTS.md` as the remaining holes.
- CI only; nothing that ships changes.

## Verification

- `checks.user-migrations-ledger` is green on edge's pin and on `main`'s
  v4.5.0 pin (the stable scratch tree).
- Break proofs (§1), each failing for its own reason:
  1. delete the `omarchy-cmd-editor-mimetypes` command row → the "no row"
     failure, naming it;
  2. set it to `follow = false` → `1794390043` is reported as a stale row;
  3. delete one new migration row → it is listed as missing;
  4. add a command row nothing calls → reported as stale;
  5. drop a command row's `reason` → malformed.
- `nix fmt -- --ci`, statix, deadnix.
