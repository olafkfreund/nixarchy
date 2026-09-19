---
status: approved
issue: 783
author: olafkfreund
---

# Intent: Make the default-plugin layout check reliable

## Problem

The defaults node in `tests/plugin.nix` waits for the running shell to report
a default plugin enabled, then immediately reads `shell.json` from disk.
The shell can report enabled before its asynchronous configuration write
finishes. The check then rejects a working plugin because the disk still
contains the preceding bar layout. Issue #783 records this failure on #782
and a passing run of the same check on #780.

## Proposed outcome

The plugin check accepts a default plugin whose correct bar placement reaches
disk after the enabled response. It still fails within a bounded time when
the expected right-section placement never appears. Its first-login,
enable-once marker, and persistent user-disable assertions remain effective.
Closure requires captured evidence that delayed persistence fails the old
check and passes the corrected check, plus a passing plugin integration check.

## Affected users and systems

Contributors and CI runs executing `checks.x86_64-linux.plugin`, specifically
its defaults node. The false failure interrupts review of unrelated plugin
work. No installed host needs a configuration change or deployment.

## Constraints

- Confine implementation to the defaults-node layout-read check in
  `tests/plugin.nix`; coordinate with concurrent plugin work before rebasing.
- Preserve the expected plugin id and right-section assertion, and retain
  failures for missing or incorrect placement.
- Keep waits bounded; a fixed delay alone must not substitute for observing
  the required result.
- Capture the broken and repaired cases under the same delayed-write
  condition. Do not retry a flaky run until green and call that proof.
- Do not start local builds or VM tests while CI install jobs are active.
- Follow the intent, spec, and plan approval gates before implementation.

## Open questions

None.
