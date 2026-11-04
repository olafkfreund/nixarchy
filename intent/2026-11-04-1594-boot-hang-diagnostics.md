---
status: draft
issue: 1594
author: x
---

# Intent: Fail fast with evidence when an install target's boot hangs

## Problem

Twice since 2026-11-02, the free-space check's target VM has frozen about
5 s into its first boot after install: on main in run 41693557421 and on
PR #1591 in run 41803215647. After its last systemd line the console
printed nothing but one `clocksource: Watchdog remote CPU 3 read timed
out`. Both were green on re-run. That is 2 first-attempt failures among
55 green install runs.

It is not host starvation, which is what #1594 first assumed:
- `install`'s VM, in the same job and the same window, finished normally;
- p620 has 128 threads and was at load about 8;
- p620's kernel log is silent in both windows.

The cause is unknown. Two things make it expensive and keep it unknown:

- **The wait burns the whole budget.** `wait_for_multi_user` in
  `tests/vm-cleanup.py` waits 900 s for "Reached target Multi-User System",
  whether or not the guest is making progress. So a hang costs 15 minutes,
  then a re-run, then a human diagnosis.
- **The failure probe asks the frozen guest.** On timeout the helper runs
  `systemctl list-jobs` through the guest shell (#1365). A frozen guest
  can't answer, so both logs say only "no answer from the guest within
  90 s". Nothing in either log can tell a wedged vCPU from a deadlocked
  unit or a stalled disk.

## Proposed outcome

When a target VM hangs while booting, the check:

1. notices the console has gone silent, and fails within a few minutes
   rather than at 900 s;
2. before failing, writes evidence gathered from outside the guest into the
   log. The guest's blocked tasks and per-CPU backtraces come through qemu
   sysrq, and each vCPU's registers through the qemu monitor. The next
   occurrence then says what is stuck.

A boot that is slow but still printing behaves as it does today.

This change does not fix the hang. The fix is a later change, chosen once
a dump names the cause.

## Affected users and systems

- `tests/vm-cleanup.py`, and so every check that calls
  `wait_for_multi_user`: install, free-space, install-iso, install-iso-net,
  reinstall-vm, and the install gate.
- CI's install job on p620's self-hosted runners.
- No user-facing module or package changes.

## Constraints

- **No retry.** A check that silently re-runs a hung boot turns a real bug
  green (§10).
- **It must never fail a healthy boot.** The silence threshold has to sit
  well above the longest gap a passing boot shows, measured from passing
  run logs and not guessed.
- **It must work against a frozen guest,** so it can't go through the guest
  shell or the backdoor. Everything is gathered from the host side: the qemu
  monitor and the serial console.
- **It is a CI-gate change** under §11, because it changes the install
  checks' timeout behaviour. A human merges it.
- **Prove it fails (§1):** a deliberately frozen guest (for example `stop`
  on the qemu monitor mid-boot) must trip it and produce the dump, and a
  normal boot must pass.

## Open questions

1. Does the silence detector apply to every caller of the helper, or only
   to first boots after install? Recommended: every caller, since the
   threshold is about silence and not about which boot it is.
2. Silence threshold: proposed 180 s, pending the gap measurement in the
   spec.
