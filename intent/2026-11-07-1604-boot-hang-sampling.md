---
status: draft
issue: 1604
refs: 1594
predecessor: intent/2026-11-04-1594-boot-hang-diagnostics.md
author: x
---

# Intent: The next install-target hang names the wakeup that never came

## Problem

#1597 made a hung install target fail after 120 s of console silence with
two `info registers -a` samples, and #1604's latest comment says no dump has
arrived. Two have. Both are in p620's raw build logs, not in the job logs
(read them with `bzcat <log> | tr '\r' '\n'`):

| run | raw log under `/nix/var/log/nix/drvs/` | last systemd line | after it |
|---|---|---|---|
| 42100028034, 2026-11-05, PR #1637 | `f9/an94rxl1qrrqs48488r3slf7cryx0q-vm-test-run-nixarchy-install.drv.bz2` | `[4.927] Finished Update is Completed.` | nothing |
| 42188883153, 2026-11-06, main | `g8/mp8kfiy2pvw91m9h8wk3iyqbx0xb5d-vm-test-run-nixarchy-install.drv.bz2` | `[4.455] Finished Update is Completed.` | `[63.3] clocksource: Watchdog remote CPU 1 read timed out` |

Both are the `install` check's `target`, on its first boot from its own
disk. Both dumps show the same thing. In both samples, 5 s apart, all four
vCPUs are halted (`HLT=1`) at one idle RIP: `ffffffff8d47d5cf`, and
`ffffffffbd67d5cf` under a different KASLR base. The two addresses are the
same offset modulo KASLR's 2 MiB alignment.
The #1365 systemd probe then got no answer within 90 s.

What that rules in and out:

- **Not a spin or a livelock.** Neither would show every vCPU halted twice.
- **Starvation doesn't fit.** A starved guest has runnable work. Every vCPU
  of this one is idle. On 2026-11-06 the guest kernel also ran a timer about
  60 s into the silence and printed from it, so it was getting CPU time.
- **So the guest is waiting for a wakeup that never comes**: a device
  completion, an IPI, or a timer that never fires. The register dump can't
  say which, because a halted vCPU looks the same in all three cases.

Two readings of these logs were wrong, and #1594 and #1604 still carry them:

- PR #1637's comment called the monitor reply empty, and host starvation
  likely. The reply was complete. Every monitor line ended in `\r\n`, and
  nix's log rendering drops the text before a `\r`, so the job log showed one
  blank line per register while the raw log held all of them. #1643
  (`e9cd2ca3`, 2026-11-06 10:25) fixed that rendering. Both hangs above are
  older, which is why their job logs look empty.
- #1604's comment says no dump has arrived. Both of these predate it.

Every NixOS test VM boots with `clocksource=acpi_pm`. That includes the
installed target, because `etcInstrumentation` in
`tests/lib/installed-target.nix:106` (written into the target's flake by
`tests/install.nix:232`) imports nixpkgs' `nixos/modules/testing/test-instrumentation.nix:223`. Whether it
plays a part is unproven. The installer guests boot with it too (6.18
kernel) and haven't hung, and the targets that hang run 7.x. So two
variables separate them, and neither has been tested.

## Proposed outcome

The next hang's log says which of timer, IPI or device it is. On
`BootHang`, `_diagnose` in `tests/vm-cleanup.py` (`sample_monitor`, around
line 94) also records:

1. **Interrupt-controller state, in both samples:** `info lapic <n>` for
   each vCPU (pending IRR/ISR bits, LVT timer mode and current count),
   `info pic` (IOAPIC redirection entries and the i8259), and `info irq`.
   Comparing the two samples shows whether the timer is counting, whether a
   vector is stuck pending or in service, and whether a level-triggered line
   is waiting on an EOI that never came.
2. **A poke, then a watch.** After the samples, the probe injects one event
   through the monitor and watches the console for about 15 s, recording
   whether the guest prints anything:
   - `nmi`. This reaches every vCPU without going through the IOAPIC. A
     kernel that wakes prints its unknown-NMI message.
   - `sendkey alt-sysrq-w`. This takes the device path (i8042 → IOAPIC →
     LAPIC). With `kernel.sysrq=16` the kernel still prints `This sysrq
     operation is disabled`, and that line is the signal.

   If the guest prints after the NMI but not after the key, interrupt
   delivery works and a device interrupt went missing. If it prints after
   neither, the vCPUs are not being woken at all. If it resumes booting,
   that names the cause outright, and the check still fails (see
   Constraints).

The log states the outcome in one line per poke. `tests/AGENTS.md#boot-hang-detect`
gains a reading guide for it, the same way it has one for the registers.

This doesn't fix the hang. It makes the next occurrence say where to look.

## Affected users and systems

- `tests/vm-cleanup.py` (`_diagnose`), so every caller of
  `wait_for_multi_user`: install, free-space, install-iso, install-iso-net,
  reinstall-vm, the install gate.
- `checks.boot-hang-detect`, which has to prove the new output appears.
- `tests/AGENTS.md#boot-hang-detect`.
- CI's install job on p620. No module, package or shipped closure changes.

## Constraints

- **No retry, and no pass after a poke.** A guest the poke unsticks still
  fails the check, and the log says so. Otherwise the probe turns a real bug
  green (§10).
- **Bounded.** The monitor thread is joined at 30 s today. The new commands
  and two 15 s watches get a stated budget, and a monitor that stops
  answering still ends the probe.
- **The shipped closure is untouched.** No `sysrq_always_enabled` and no
  kernel parameter on the installed target for diagnosis. The sysrq signal
  works with the shipped `kernel.sysrq=16`.
- **A healthy boot is unaffected.** All of this runs only after `BootHang`.
- **The check can fail (§1).** `checks.boot-hang-detect` must assert the new
  commands' output is in the dump, and it must be shown failing with that
  output removed.
- `microvm-boot` stays out of scope, per the owner's 2026-11-05 decision on
  #1604.

## Open questions

1. **Both pokes, or one?** Recommendation: both, NMI first. Its path skips
   the IOAPIC, so the order splits "nothing wakes the vCPUs" from "a device
   interrupt was lost". If the NMI unsticks the guest, the key's result is
   moot, and the log should say that.
2. **`info virtio-queue-status` for the root disk?** In-flight requests
   with no completion would name the disk directly. It needs the device's
   QOM path. Recommendation: add it if the spec can find the path without
   guessing (`info virtio` lists them), and skip it otherwise.
3. **Symbolise the idle RIP once?** Recommendation: yes, once, in the spec,
   against that kernel's `System.map`, to confirm it is the idle loop. Not
   in the check.
4. **Also try `clocksource=kvm-clock` on the install targets?**
   Recommendation: yes, but as a separate experiment, after this probe lands
   and has captured one hang. The reasons:
   - Changing the clock now confounds the next dump.
   - The base rate is about one hang in 25-30 install runs (2/55 by
     #1594's count), so "no hang since" needs about 75 clean runs to mean
     anything at 95%.
   - The installer guests also boot `acpi_pm` and don't hang, which weakens
     it as the sole factor.

   It would be a test-only override on the installed target's
   test-instrumentation import, so the shipped closure stays the same. The
   7.x-versus-6.18 kernel difference is a second candidate experiment with
   the same caveats, and it should not run at the same time.
5. **Correct #1594 and #1604 now, or with the PR?** Recommendation: now,
   with the comment text below. Both issues currently say "no dump has
   arrived" or "starvation likely", and the next agent will act on that.
