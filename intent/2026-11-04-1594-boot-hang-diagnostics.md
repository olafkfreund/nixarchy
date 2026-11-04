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

#1594 first called this host starvation, and the evidence makes that
unlikely, though it doesn't rule it out:
- `install`'s VM, in the same job and the same window, finished normally;
- p620 has 128 threads and was at load about 8;
- p620's kernel log is silent in both windows.

That narrows it down, but it can't exclude a stall specific to this one qemu
process. The cause is unknown. Two things make it expensive and keep it unknown:

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
2. before failing, writes evidence into the log in two tiers:
   - **Guaranteed, from the host:** each vCPU's state and registers through
     the qemu monitor (`info cpus`, `info registers -a`). This answers even
     when the vCPUs are wedged or paused.
   - **Best effort, from the guest kernel:** blocked tasks and per-CPU
     backtraces through sysrq. These print only if a vCPU can still take
     interrupts and sysrq is enabled at that point in the boot. When nothing
     prints, that absence is itself evidence of a hard lock.
   - **Then, as today,** the bounded #1365 systemd probe, which still names
     the stuck unit when the guest is alive but blocked.

   The next occurrence then says whether a vCPU, the kernel or a unit is
   stuck.

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
- **It must never fail a healthy boot.** Console silence is only a proxy
  for a hang: a unit that logs to the journal and not to ttyS0 is silent
  while it works. The threshold has to sit well above the longest gap a
  passing boot shows. That gap is measured from passing logs of **every**
  caller (network waits in install-iso-net, reinstall-vm, any TCG run), not
  guessed and not taken from free-space alone. If one caller's gaps make a
  threshold useless, that caller keeps the plain 900 s wait.
- **It must work against a frozen guest.** The guaranteed tier can't go
  through the guest shell or the backdoor.
- **Every step is bounded,** monitor calls included. `reap_owned_vms` avoids
  monitor RPC because the monitor itself can be what hung
  (`tests/vm-cleanup.py:8`). A monitor that doesn't answer is reported, and
  the check still fails promptly.
- **Leave time for sysrq output to drain** before raising. The callers'
  cleanup kills qemu straight away (`reap_owned_vms`), and that would cut
  the dump off.
- **It is a CI-gate change** under §11, because it changes the install
  checks' timeout behaviour. A human merges it.
- **Prove it fails (§1):**
  - qemu `stop` mid-boot must trip the silence detector and produce the
    monitor dump. A stopped guest can't answer sysrq, so this test doesn't
    exercise that tier.
  - A wedge made inside the guest (a unit that blocks without printing)
    must produce the sysrq output.
  - A normal boot must pass.

## Open questions

1. Does the silence detector apply to every caller of the helper, or only
   to first boots after install? Recommended: every caller, since the
   threshold is about silence and not about which boot it is.
2. Silence threshold: proposed 180 s, pending the gap measurement in the
   spec.
3. Feasibility, for the spec to settle before designing:
   - Can the pinned test driver show console progress during the wait
     without stealing lines from `wait_for_console_text`? Most likely by
     waiting in short windows inside the 900 s budget.
   - Is `kernel.sysrq` enabled early enough in the target's boot?
