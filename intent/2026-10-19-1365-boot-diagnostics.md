---
status: approved
issue: 1365
author: olafkfreund
---

# Intent: an install VM that never reaches multi-user.target says why

## Problem

Twice on 2026-10-19, an installed target VM never reached `multi-user.target`.
The check died at `wait_for_console_text(r"Reached target Multi-User System",
timeout=900)`: once in `install` (main c335cad7), once in `free-space` (#1358).
It was not tied to any change, and the five other installs that day passed.

The guest was not frozen. sddm logged at 111 s, and the kernel's clocksource
watchdog at 357 s. So some unit kept `multi-user.target` from being reached,
and the test cannot say which: it watches only the console, then fails with
"action timed out". Two occurrences produced no evidence. A third would
produce none either.

## Proposed outcome

When that wait times out, the test first asks the guest what systemd is
waiting on (pending jobs, failed units, and the boot's recent warnings and
errors), prints it, and then fails as before. The next occurrence names its
stuck unit, and #1365 can then be fixed rather than guessed at.

Passing runs change in nothing: no extra time, and no extra output.

## Affected users and systems

- `tests/install.nix:371` and `tests/free-space.nix:574`, the two places
  with this wait. Test code only; nothing a user installs changes.
- The `install` job in `install-check.yml`.

## Constraints

- The probe must not hang the test. Ask the guest through the backdoor with
  a short bound, and if the backdoor is not up, say so and fail with the
  original error. A diagnostic that turns a 15-minute failure into a
  90-minute timeout is worse than none.
- The original failure must still be the failure: re-raise it, never
  swallow it.
- §1: the diagnostic path is proved by making the wait fail on purpose (an
  unreachable console pattern with a short timeout) and seeing the dump
  printed, then the original error.
- A VM proof runs only when CI is idle (§6), or through CI.

## Open questions

- **One shared helper, or the same few lines in both files?** I propose a
  small shared function in the module both already import, if there is one,
  so the two copies cannot drift. Otherwise the lines go in both files.
