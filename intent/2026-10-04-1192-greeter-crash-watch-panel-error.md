---
status: draft
issue: 1192
author: olafkfreund
---

# Intent: no crash watcher in the greeter, and panel load errors that say what failed

## Problem

1. `omarchy-crash-watch` (`modules/nixos.nix`) is a user unit wanted by
   `graphical-session.target` for every user, so it also starts in the SDDM
   greeter's user manager (`sddm`, uid 175). It can't work there: it fails
   and restarts every 5 s for as long as the greeter is up. That was more
   than 20 restarts in one sitting on p620, and it floods the journal.
2. Upstream `shell/shell.qml` (~line 1424) handles a panel `Loader` error with
   `errorString && errorString()`. Qt 6 `Loader` has no `errorString()`, so
   the handler throws `ReferenceError: errorString is not defined`, and the
   one message that should name the failing panel's real error is lost.

## Proposed outcome

- The crash watcher runs only in real user sessions; the greeter's user
  manager never starts it.
- A panel that fails to load logs its component error, or at least its
  source URL, with no ReferenceError.

## Affected users and systems

Every nixarchy machine with the SDDM greeter (the crash watcher), and every
nixarchy shell (the panel handler). Downstream: olafkfreund/nixos_config
Issue #2152 (p620, razer, p510).

## Constraints

- The crash watcher's behaviour in real sessions doesn't change. Its
  existing `ConditionEnvironment` and toggle `ConditionPathExists` stay.
- The shell fix is a carried patch with `--fuzz=0`, like the existing
  numbered patches, and is reported upstream to Omarchy.

## Open questions

None. Proposed design: `ConditionUser=!@system` on the unit, and a carried
patch replacing the handler line with
`sourceComponent ? sourceComponent.errorString() : String(source)`.
