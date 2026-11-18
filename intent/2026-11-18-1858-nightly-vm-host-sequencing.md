---
status: draft
issue: 1858
author: x
---

# Intent: the nightly's VM jobs share p620 with no ordering beyond one chain

## Problem

The nightly sequences exactly one pair of its self-hosted VM jobs:
`install-iso-net` has `needs: [install]` (`.github/workflows/nightly.yml:161`,
reasoning at 143-155, from #935). Nothing orders the others.
`install`, `install-encrypted`, `keyboard-boot` and `microvm` carry no `needs:`
(`nightly.yml:47-138`) and all four are `runs-on: [self-hosted, nixos, kvm, big]`.
`vm-host-free.sh` knows only the install-check/edge pair (#1365)
(`.github/scripts/vm-host-free.sh:7-11`), and the nightly is not a participant.

What actually limits concurrency is the number of runners, not any rule.
`gh api .../actions/runs/<id>/jobs` for the last eight scheduled nightlies shows
all of them on p620 runners (`p620-nixarchy`, `-2`, `-3`, `-4`); `repush` and
`digest` are self-hosted too (`nightly.yml:412`, `610`). Observed start times:

- 2026-11-18 (44228069452): `install`, `install-encrypted`, `microvm`,
  `keyboard-boot` all started 03:06:45-03:06:47. `install-iso-net` started
  03:09:26, when `install` ended. Those are job intervals: jobs overlapped, and
  a job spends part of its time building disk images before any VM runs, so
  this does not show four VM tests running at once (on 11-18 the `install` job
  ended 03:09:23 after 2m38s, and `keyboard-boot`'s guest began about 03:19:36,
  after `install-encrypted` ended). Build phases and VM execution need
  measuring separately.
- 2026-11-17 (44007836904): `keyboard-boot` started 03:09:33, two seconds after
  `install` released a runner. Five jobs, four runners: the fifth waited for a
  runner, not for a rule.
- Other nights (11-09 .. 11-16): same shape. Three or four VM jobs start in the
  same second; `install-iso-net` follows `install`.

So the workflow permits more concurrent VM-class jobs than the "two install-class
jobs at a time" limit AGENTS.md section 6 documents (a measured limit for
installs on an idle host). #935 is only the origin of the `needs:` comment: its
own later comment retracts the premise ("The premise of this issue is wrong, and
so was the fix for it", issuecomment-5829129838) and puts the hang down to
catastrophic regex backtracking in the test driver, so it is not evidence that
sequencing cured starvation. `keyboard-boot` was added (it is a full
desktop boot with LUKS, greeter and lock screen, `tests/keyboard-boot.nix`,
115-minute `globalTimeout`) outside that model.

Evidence for harm is thin and the issue is right to call it a hypothesis:

- On 11-18 `keyboard-boot` hung, `de` printing `clocksource: Watchdog remote CPU 3
  read timed out` at guest time 333 s (log 03:25:09), then nothing until the job
  hit its cap at 05:07:03 and was cancelled (#1855).
- That boot began about 03:19:36 (guest `Finished Save Transient machine-id` at
  7.99 s logged 03:19:44). `install-encrypted` ended 03:19:10 and `microvm` 03:15:19;
  only `install-iso-net` (to 03:22:04) overlapped most of the freeze window, and
  from 03:22:04 to 03:25:09 no other nightly VM job was running on p620. The
  freeze therefore is not explained by nightly overlap alone. Something else on
  p620 (a desktop session, an agent's local build, CI from another workflow)
  may have been present; none of that was measured.
- The same `Watchdog remote CPU ... read timed out` line appears in **successful**
  nights too: matching lines appear in successful nights (counted in per-job logs
  with `gh api repos/olafkfreund/nixarchy/actions/jobs/<id>/logs | grep -c
  'Watchdog.*read timed out'`; the per-night range is not established and 11-10's
  per-job logs gave 0 on re-count; 11-16's failure was `draft a real package`). On 11-17 it hit `microvm`, `install-encrypted` and
  both `keyboard-boot` guests, and the job still passed. The line by itself is not
  a starvation discriminator; this repo's #1365 signature is that plus long
  userspace boot, `udevd` worker kills and `dhcpcd` timeouts, and none of those
  were checked for here.

What is therefore known: the workflow permits more concurrent self-hosted VM-class
jobs than the model AGENTS.md section 6 documents, and one run hung. What is
not known: how many VM tests actually ran at once, or whether concurrency caused
that hang.

Also stale: the comment on `install-encrypted` says "Same runner pool; the runner
serialises the two jobs, which is the point" (`nightly.yml:87-90`). Four
runners with identical labels exist (AGENTS.md section 6), and the table above shows
`install` and `install-encrypted` starting in the same second on different
runners every night. The comment describes a property the workflow does not have.

## Proposed outcome

Whoever reads the nightly's header, and the `install-encrypted` comment, learns
the real concurrency model, and the model matches what section 6 says the host can
take, or section 6 is amended with a new measurement. Specifically:

1. A measurement exists of p620 load (and guest `userspace`, `udevd`, `dhcpcd`
   figures) during a nightly's overlapping VM jobs, so the decision below is made
   on data, not on one hang.
2. `keyboard-boot` and the other self-hosted VM jobs are either brought under an
   explicit sequencing rule, or the measurement shows they need none and the
   workflow says so.
3. The `install-encrypted` comment is corrected whatever else is decided.

## Affected users and systems

- The maintainer: a nightly that hangs a 2-hour job and is read as a product bug.
- p620, which is also the owner's desktop and the four runners' host, shared with
  `install-check.yml` and `omarchy-edge.yml` runs.
- Nightly latency: serialising `keyboard-boot` after the others adds its own
  runtime (`keyboard-boot` job durations 11-09..11-17 ranged 1m38s (11-10, no VM test run)
  to 23m38s (11-13); job duration mixes cached results, building and the test, so
  the VM time alone needs measuring) to a nightly that currently
  finishes VM work by about 03:30-03:45. Overall nightly completion is not
  gated by it either: `commit-independent` ran to 04:12 on 11-18.
- #1855's fast-fail change, which makes the next occurrence cheaper to read.

## Constraints

- Changing nightly job ordering, `needs:` or a host-free gate is a CI-gate change
  and needs a human (CLAUDE.md section 11).
- Use `needs:`, not a concurrency group, for ordering (`nightly.yml:152-155`: a
  group keeps one pending job and cancels the next).
- A chained job needs `if: always()`, and every job `report` and `digest` list
  must keep running (`nightly.yml:157-160`, `611`, `641`).
- No competing VM workloads while runners are busy (CLAUDE.md section 6 tiers;
  cheap checks stay allowed). Passive sampling (load average, busy-runner count)
  and the next scheduled nightlies need no local build or dispatch; a dispatch
  while an install runs would itself add the load being measured.
- `vm-host-free.sh` must keep failing closed on an API error (exit 2).

## Open questions

1. Is an added nightly wait acceptable if measurement supports sequencing
   (roughly one more VM job's runtime after the current chain)?
2. Should the first step be measurement-only (sample load on p620 across the
   next nightlies, e.g. a step recording `/proc/loadavg` and the busy runner
   count) before any gate change? Who runs or approves that step on p620?
3. Two separate decisions, not alternatives: (a) how many self-hosted VM jobs the
   nightly itself may run at once (`needs:` orders nightly peers); (b) whether
   exclusion must also span workflows. `vm-host-free.sh` only checks the other
   workflow's named job (lines 7-11), so a nightly caller alone would neither
   order nightly jobs nor make install-check/edge notice nightly work. The
   mechanism follows from (a) and (b).

## Could not verify

- p620 load at 03:19-03:25 on 2026-11-18, or what else ran on the host then.
- Whether any non-nightly workflow (install-check, edge `verify`) overlapped the
  nightly on 11-18; not checked against those workflows' run lists.
- Guest-side starvation signatures other than `Watchdog ... read timed out`
  (userspace boot time, `udevd` kills, `dhcpcd`) across the other nights.
- Earlier than 11-09 nightlies; only 11-09/10..11-18 were inspected.
