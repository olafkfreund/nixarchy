---
status: draft
issue: 1346
author: olafkfreund
---

# Intent: every hosted job runs on an image we chose

## Problem

23 hosted jobs across 12 workflows, and the fallback at
`install-check.yml:329`, say `runs-on: ubuntu-latest`. GitHub moves that
label from Ubuntu 24.04 to 26.04 between 2026-10-19 and 2026-11-19
(actions/runner-images#14748). The kernel goes from 6.17 to 7.0 and systemd
from 255 to 259.

The move is gradual, so for a month the same job can run on either image,
and a failure that only 26.04 causes appears and disappears between re-runs.
A re-run that passes would then hide it (§10: a flaky pass is a bug report
deleted). Our hosted jobs depend on the image in specific ways: `/dev/kvm`'s
udev rule in `box`, the paths `Free disk space` deletes, the Determinate
installer.

The nine self-hosted `[self-hosted, nixos, kvm, big]` jobs do not use the
label and are out of scope.

## Proposed outcome

- Every hosted job names one image, and changing it is a deliberate, reviewed
  edit rather than GitHub's schedule.
- Which image is decided by a measurement: the hosted jobs run once on
  `ubuntu-26.04` before anything is pinned.
- A new job cannot quietly reintroduce `ubuntu-latest`.

## Affected users and systems

- `.github/workflows/*.yml`: 12 files, 29 lines.
- Every pull request's hosted jobs, the nightly, the weekly, releases.
- Contributors writing a new workflow job.

## Constraints

- A CI-gate change (§11): proposed in a PR, merged by a maintainer.
- The throwaway measurement must not evict a queued install (§6): it opens
  only when no install job is queued or running.
- Workflows that do not run on pull requests (nightly, release, review,
  weekly, wiki, update) cannot be measured on a throwaway PR; they first meet
  the pinned image after the merge.

## Open questions

1. **24.04 or 26.04.** The measurement decides; the spec records it.
2. Whether the guard belongs in `lint` (every PR, seconds) or the nightly.
   Lint is where a new job is written, so the default is lint.
