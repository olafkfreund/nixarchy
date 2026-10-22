---
status: approved
issue: 1426
author: olafkfreund
---

# Intent: edge waits only for what collides with its VMs

## Problem

`omarchy-edge.yml`'s `wait-idle` job holds `verify` until **no other workflow
run of any kind** is in flight, for up to 3 hours. On 2026-10-22 edge run
39753280300 (#1423) waited almost the whole 3 hours, behind a docs PR's CI,
`main`'s push build, and a re-run of that build after a flaky udiskie test.
None of those boot VMs.

What actually breaks is an install's VMs sharing p620 with edge's VMs (#1365).
`verify` already guards against that: before each VM check it waits on
`.github/scripts/vm-host-free.sh edge`, and an install waits on
`vm-host-free.sh install`. So `wait-idle` is stricter than the problem it
exists for.

## Proposed outcome

`wait-idle` waits only for the thing `vm-host-free.sh edge` reports: an
`install-check` `install` job running. When none is, edge starts `verify` at
once. It still sleeps on a hosted runner, so a wait does not hold a VM runner.

Measured as: an edge run started while only `build` or `pages` is in flight
goes straight to `verify`.

## Affected users and systems

- `.github/workflows/omarchy-edge.yml`, the `wait-idle` job (about 10 lines).
- p620, which would now run edge's VM checks alongside package builds
  (`system-build`, `omarchy`) from other runs.

## Constraints

- A CI-gate change (CLAUDE.md §11): proposed in a PR, merged by the owner.
- Exit 2 from `vm-host-free.sh` (API unreadable) must still count as busy,
  as it does in `verify` and `install`.
- Keep the 3-hour bound, so a stuck install cannot hold edge forever.

## Open questions

1. **Package builds alongside edge VMs.** §6's table says a local VM check
   runs "only with nothing in flight". This change applies the narrower
   #1365 rule to CI's own edge VMs: edge would no longer wait out a
   `system-build` on p620. Recommendation: accept it. `verify`'s VM checks
   have per-check host checks already, and the stall in #1365 was VMs on VMs,
   not VMs on a package build.
2. **Drop `wait-idle` entirely instead?** `verify`'s per-check gate would then
   do the same waiting, but on a VM runner, holding it for up to 2 hours per
   check. Recommendation: keep the job, change only what it waits for.
