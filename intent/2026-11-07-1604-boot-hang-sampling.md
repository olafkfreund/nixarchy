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

What that rules in and out, as far as two snapshots can:

- **No continuous spin or livelock.** Either would show a vCPU running in at
  least one sample. Two snapshots can't exclude work that ran between them.
- **Sustained starvation doesn't fit well.** A starved guest has runnable
  work, and every vCPU here is idle in both samples. On 2026-11-06 the guest
  kernel also ran a timer about 60 s into the silence and printed from it,
  so it got CPU time then. Starvation that comes and goes isn't excluded.
- **Working hypothesis: the guest waits for a wakeup that never comes**,
  whether a device completion, an IPI or a timer. The register dump can't
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

The next hang's log narrows down which of timer, IPI or device it is. The
evidence is suggestive, not a verdict. On `BootHang`, `_diagnose` in
`tests/vm-cleanup.py` (`sample_monitor`, around line 94) also records:

1. **Interrupt-controller state, in both samples:**
   - `info lapic <n>` for each vCPU: pending IRR/ISR bits and the LVT timer
     mode.
   - `info pic`: IOAPIC redirection entries and the i8259.
   - `info irq`.

   Comparing the two samples shows two things: whether a vector is stuck
   pending or in service, and whether a level-triggered legacy line is
   waiting on an EOI that never came. Two limits apply:
   - The target uses the TSC-deadline timer (`TSC deadline timer
     available` in its log), so the LAPIC's current count doesn't show
     whether a deadline is armed.
   - virtio devices interrupt through MSI-X, which bypasses the IOAPIC, so
     `info pic` can't see a lost virtio-blk completion.
2. **A poke, then a watch.** After the samples, the probe injects one event
   through the monitor and watches the console for about 15 s, recording
   whether the guest prints anything:
   - `nmi`. This reaches every vCPU without going through the IOAPIC.
     Linux usually prints its unknown-NMI message, but a registered handler
     can claim the NMI silently.
   - `sendkey alt-sysrq-w`. This takes the legacy device path (i8042 on
     IRQ 1 → IOAPIC → LAPIC; the target's log shows the i8042). With
     `kernel.sysrq=16` and `loglevel=7`, the kernel should still print
     `This sysrq operation is disabled`, provided the key sequence reaches
     the sysrq handler.

   Output after a poke is strong evidence: the vCPUs can be woken, and a
   guest that then resumes booting names its cause. Silence after a poke is
   weak evidence. It is consistent with vCPUs that don't wake, but also with
   an NMI that was handled quietly or a key that never reached sysrq. The
   reading guide has to say so. A guest that resumes still fails the check
   (see Constraints).

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
   with no completion would name the disk directly, and MSI-X makes this
   the only view of it (point 1). It takes both a QOM path and a queue
   index, and the target's virtio-blk has four queues. `info virtio` lists
   the paths. Recommendation: query every queue of the root disk, if the spec
   can get the path from `info virtio` without guessing. Otherwise skip it
   and record the gap.
3. **Symbolise the idle RIP once?** Recommendation: yes, once, in the spec,
   against that kernel's `System.map`, to confirm it is the idle loop. Not
   in the check.
4. **Also try `clocksource=kvm-clock` on the install targets?**
   Recommendation: yes, but as a separate experiment, after this probe lands
   and has captured one hang. The reasons:
   - Changing the clock now confounds the next dump.
   - The base rate is about one hang in 25-30 install runs (2/55 by
     #1594's count), so "no hang since" needs about 81 clean runs to mean
     anything at 95% (75 still leave a 6% chance of luck).
   - `clocksource=` picks what the kernel reads time from, not the device
     that fires timer interrupts (the clock event device, here the
     TSC-deadline LAPIC timer). A clean run under `kvm-clock` therefore
     wouldn't prove that a timer interrupt was being lost.
   - The installer guests also boot `acpi_pm` and don't hang, which weakens
     it as the sole factor.

   It would be a test-only override on the installed target's
   test-instrumentation import, so the shipped closure stays the same. The
   7.x-versus-6.18 kernel difference is a second candidate experiment with
   the same caveats, and it should not run at the same time.
5. **Correct #1594 and #1604 now, or with the PR?** Recommendation: now,
   with the correction comment drafted alongside this intent (not posted). Both issues currently say "no dump has
   arrived" or "starvation likely", and the next agent will act on that.
