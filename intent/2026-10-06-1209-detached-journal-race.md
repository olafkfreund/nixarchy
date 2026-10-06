---
status: draft
issue: 1209
author: olafkfreund
---

# Intent: a detached rebuild's own output always reaches its log

## Problem

`nixarchy-apply --detach` runs the rebuild as the user unit
`nixarchy-rebuild` (`modules/apps.nix:3561`). `nixarchy-apply --log` reads that
run's output with
`journalctl --user -u nixarchy-rebuild --invocation=<id>`
(`modules/apps.nix:3522`). The rebuild panel's copy-log action uses it
(`pkgs/rebuild-panel/RebuildState.qml:130`).

When the run fails fast, its own last lines can be missing from that query.
Seen three times on 2026-10-06:

- The unit refused a feature branch, printing
  `nixarchy: refusing to rebuild from 'agent/unmerged' (...), not main.`
  (`pkgs/branch-guard.nix:45`), and exited 1.
- The line is in the journal: the VM console shows it, attributed to
  `nixarchy-apply[27151]`.
- The invocation-scoped query returns only systemd's own lines ("Started",
  "Main process exited", "Failed"), never the refusal, however long it waits.
  The 30 s wait #1133 added does not help.

The likely cause is journald attaching unit metadata after the fact. For a
process that writes and exits at once, journald can store the line without
`_SYSTEMD_UNIT` / `_SYSTEMD_INVOCATION_ID`, so a query filtered on them misses
it. The spec has to confirm this.

Who it hurts:

- **Users.** A detached rebuild that refuses, or fails in its first moments,
  can leave a log with no reason in it. The panel shows a failed rebuild, and
  the copied log says only that it failed.
- **CI.** `checks.session` asserts on that refusal. It failed on 2/2 local runs
  on p620 and on PR #1208, a merge with no file changes, so it now blocks
  merges on `main`.

## Proposed outcome

- `nixarchy-apply --log` for a run includes everything that run printed, even
  when it exits immediately.
- `checks.session`'s detached-refusal section passes reliably on p620 and in
  CI.
- The test keeps asserting that the refusal reaches the log the user sees.
  The point of #1037 was that the panel can see why.

## Affected users and systems

- Anyone using the rebuild panel or `nixarchy-apply --detach` / `--log`.
- `modules/apps.nix` (`nixarchy-apply`), possibly `pkgs/branch-guard.nix`,
  `tests/session.nix`, `tests/session-journal.py`.
- Every PR's `system` job.

## Constraints

- Do not weaken the test into "the unit failed". It must still prove that the
  refusal text reaches the log.
- No sleep with a guessed length to hide the race.
- `--log` must stay scoped to one run. Dumping unrelated history is what
  #986 fixed.

## Open questions

1. **The cause.** The spec confirms or rules out the journald metadata race,
   for example by checking the missing line's fields (`journalctl -o json`) in
   a VM run.
2. **Where to fix it.** In how the unit's output is written (so the line
   carries its own unit identity whenever it is logged), or in how `--log`
   reads it (a time window or a run marker instead of `--invocation`), or both.
3. **Unblocking merges now.** Fix first, or temporarily mark this one
   assertion as known-flaky while the fix lands? The intent's default is to
   fix it, not mask it.
