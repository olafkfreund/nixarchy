---
status: approved
issue: 1126
author: olafkfreund
---

# Intent: Wait for detached rebuild output in the session check

## Problem

`checks.session` waits for `nixarchy-rebuild` to report `Result=exit-code`,
then `detached_log` reads that invocation's user journal once
(`tests/session.nix:657-671`). It immediately asserts that the refusal from
`nixarchy-branch-guard` is present. The guard writes the refusal to stderr
(`pkgs/branch-guard.nix:43-54`); `nixarchy-apply --detach` runs the apply in a
`systemd-run --user` unit (`modules/apps.nix:3506-3511,3531-3544`), so the
test sees that stderr through the unit journal. A completed unit result does
not establish that journald has made every output line visible. The reported
main-run failure showed systemd's exit lines but no refusal, and later runs
passed without a relevant code change. This supports a journal visibility
race; the timing has not been reproduced locally.

The `ALLOW_BRANCH_DEPLOY=1` call to `detached_log` has a related blind spot:
it reads once and asserts only that the refusal is absent
(`tests/session.nix:676-679`). An unrelated nonempty journal can satisfy its
empty-log guard before any output from the allowed apply arrives. Another
single-shot assertion at `tests/session.nix:635-641` reads the failed
missing-flake unit's journal once after `Result=exit-code` and looks for
`does not exist`; it can race in the same way. Other journal observations in
this file are diagnostics only or wait for their expected line before reading
it (for example the display manager, Omarchy shell, and hypr-rdp probes).

## Proposed outcome

The session check waits for each detached invocation's expected output to
appear in that invocation's journal before asserting on the full log. A slow
user journal cannot turn a correct branch refusal or override into a false
failure or false pass. The missing-flake assertion receives the same
protection. The check still proves that the override reaches the unit and
that no branch refusal appears in its completed log.

## Affected users and systems

CI and contributors reading `checks.session` results; the booted desktop VM
and its `nixarchy-rebuild` user unit. This is test behavior, not a change to
`nixarchy-apply` or the branch guard on installed machines.

## Constraints

- Keep journal reads scoped to the completed invocation where an invocation
  ID is available, and keep the nonempty-log assertion.
- Bound waits so a missing message fails with a useful log rather than
  hanging; `checks.session` is a heavy VM check run by CI, not locally.
- Prove the revised assertion fails when the expected line never appears and
  that the old single read loses to delayed journal visibility. A delay
  before a program exits is insufficient by itself: the result wait would
  then also move later. Model late *visibility* after `Result=exit-code`.
- Do not change the rebuild unit, product scripts, or CI workflows to hide
  the test race.

## Open questions

1. **Owner decision: yes**, fix the missing-flake journal assertion in the
   same change. It has the same result-then-single-read pattern and expected
   stderr line, so leaving it would retain the same intermittent failure one
   section earlier.
2. **Owner decision:** wait for the positive `Enabled apps:` marker in the
   `ALLOW_BRANCH_DEPLOY=1` invocation, then assert that the refusal is absent.
   `modules/apps.nix:3560-3568` emits it only after the branch guard and
   flake-directory check, proving progress beyond the guard.
3. **Owner decision:** use a test-only delayed journal-visibility fixture
   that withholds the expected line on the first post-result read and exposes
   it later. Show the old single read red and the bounded wait green. A sleep
   before the refusal is printed would delay `Result=exit-code` too and would
   not model this race.
