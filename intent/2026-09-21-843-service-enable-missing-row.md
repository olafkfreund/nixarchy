---
status: draft
issue: 843
author: olafkfreund
---

# Intent: enabling a service works on an older services.nix

Closes #843.

## Problem

`~/.config/nixarchy/services.nix` is written once, at first login, and
nothing regenerates it. That's deliberate, because the file belongs to the
user. But when nixarchy later adds a service row (such as `#@ microvm`), a
user whose file predates it can't enable that service.
`nixarchy-service-enable microvm` (`modules/apps.nix:1260`) greps for the
marker, doesn't find it, and exits 1 with "no service 'microvm' in …" plus
a pointer to `/etc/nixarchy/services-template.nix`. Anything that calls it
fails: the Install menu's row, and nixarchy-microvm's permanent-VM create,
which failed this way on razer (file created 2026-09-01). That plugin now
warns up front and tells the user to copy the line by hand
(nixarchy-microvm#6), which is a workaround, not a fix.

`--help` is also taken as a service id today, so a caller can't ask what
the script can do.

## Proposed outcome

- `nixarchy-service-enable <id>` for an id that is in
  `/etc/nixarchy/services-template.nix` but missing from the user's file
  adds that row, exactly as the template has it and commented out, then
  enables it as usual. The output says a row was added.
- An id in neither file is still an error, with today's message.
- `nixarchy-service-enable --help` prints
  `usage: nixarchy-service-enable <service-id>` and a line saying a missing
  row is added from the template. nixarchy-microvm detects that line and
  stops warning.

## Affected users and systems

- `modules/apps.nix` (the script) and `tests/options.nix` (its test).
- Every caller of the script: the Install menu, nixarchy-microvm, and anyone
  typing it.
- Users with a `services.nix` older than a row.

## Constraints

- The user's file is theirs. Only the one missing row is added, and
  nothing else in the file changes. For a row they deleted on purpose, see
  open question 1.
- The id validation stays ahead of any sed or grep use.
- No new runtime dependencies beyond what the script already has.

## Open questions

1. **A row the user deliberately deleted.** Today that makes the id
   impossible to enable. After this change, running the script re-adds it.
   My lean: that's fine, since running `nixarchy-service-enable <id>` is an
   explicit request to enable that service.
2. **Where the row goes.** Either appended at the end of the attrset, just
   before the closing `}`, or inserted under its section heading as the
   template has it. My lean is before the closing `}`: simple, and robust to
   a user's reordered file.
