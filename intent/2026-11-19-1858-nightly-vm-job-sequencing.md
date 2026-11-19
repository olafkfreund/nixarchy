---
status: draft
issue: 1858
author: x
---

# Intent: put the nightly's keyboard-boot behind install-class sequencing

## Problem

The nightly's install-class VM jobs are meant to run at most two at a time
on p620 (#935; AGENTS.md §6: two concurrent installs succeed, three or four
fail at the in-guest timeout). Only `install-iso-net` is chained
(`needs: [install]`). `install`, `install-encrypted`, `keyboard-boot` and
`microvm` all start in the same second. On 2026-11-18 (run 44228069452) the
`keyboard-boot` guest froze with a clocksource watchdog timeout while two
installs ran beside it, and the job ran 2 hours to `cancelled`.

The `install-encrypted` comment also says the runner pool serialises jobs.
It does not, so the comment is wrong.

## Proposed outcome

No more than two install-class guests (`install`, `install-encrypted`,
`install-iso-net`, `keyboard-boot`) run on p620 at once in a nightly, and a
failure early in a chain does not skip the job after it. The comments in
`nightly.yml` describe the ordering that actually runs.

## Affected users and systems

`.github/workflows/nightly.yml` only, on the self-hosted p620 runners. No
module, option or user configuration.

## Constraints

- A CI-gate change (CLAUDE.md §11). Approved by the owner up front for this
  loop on 2026-11-19.
- `needs:`, not a concurrency group: a group cancels its second pending job
  (§6, and the existing `install-iso-net` comment).
- A chained job must keep `if: always()` so `report` still sees it.
- Must not lengthen the nightly past the job that already finishes last
  (`commit-independent`, about 52 minutes).

## Open questions

The issue asked for a host-load measurement first. Run 44449120419
(2026-11-19) sampled 1-minute load during the overlapping VM jobs: peak 54.8
across `install-encrypted`, `keyboard-boot` and `microvm`, peak 12.4 during
`install` alone. That is the measurement. The 2026-11-18 logs had been
deleted before anyone read them.
