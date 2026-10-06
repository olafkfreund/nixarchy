---
status: draft
issue: 1203
author: olafkfreund
---

# Intent: the session check does not race the shell's reload

## Problem

`checks.session` can fail on any pull request for a reason unrelated to the
change. It failed PR #1202 (run 37515619040, job `system`) and passed on a
re-run of the same commit.

The sequence in `tests/session.nix`:

- `:735` runs `hyprctl reload` to drop the Hyprforge test file.
- The shell then reloads its plugins. The log shows a burst of "Handler was
  registered but will not be used because another handler is registered"
  warnings from 131.4 s to 131.8 s.
- `:742` runs `omarchy-menu summon install` at 130.9 s, during that reload,
  with no wait in between.
- `omarchy-menu` asks the shell over IPC with the default 2 s timeout. The
  shell is busy, the timeout expires, and it prints "omarchy-shell is not
  running" and exits 1, although the shell process (pid 10576) is alive and
  logging.

So the check fails on timing, not on the behaviour it tests (#1069: summoning
opens a menu). #1189 gave keybind summons a 10 s IPC timeout for the same
reason on real machines, but the test calls `omarchy-menu` directly and still
gets 2 s.

A red check that passes on a re-run teaches people to re-run rather than
read. It also costs about 25 minutes of self-hosted runner time each time.

## Proposed outcome

- The menu section of `checks.session` waits until the shell can answer
  before it summons, so a slow reload delays the check instead of failing it.
- A shell that never comes back still fails the check, with a message that
  says so rather than "omarchy-shell is not running".
- The check still proves #1069: a summon opens a menu.

## Affected users and systems

- `tests/session.nix` only. No user-facing change.
- The self-hosted runners on p620 and p510 (fewer wasted re-runs).

## Constraints

- No `sleep` with a guessed length. Wait on a condition, with a timeout
  that is headroom for a loaded runner, as the file does elsewhere.
- Do not weaken what the test asserts.
- Follow `tests/AGENTS.md`, especially the rule on piping into `grep -q`.

## Open questions

1. **What to wait on.** `omarchy-shell shell ping`, as `:2366` does after a
   restart, may answer before a reload starts, which only moves the race. The
   spec has to establish what `hyprctl reload` triggers in the shell and what
   signals the reload is finished.
2. **Other reloads.** `:719` has the same shape, but nothing IPC follows it
   directly. Should the fix go into a helper that every `hyprctl reload` in
   the file uses?
3. **The IPC timeout.** Should the test also pass
   `OMARCHY_SHELL_IPC_TIMEOUT=10s`, matching what a keybind summon gets since
   #1189? Doing so on its own would hide a shell that answers slowly in
   general.
