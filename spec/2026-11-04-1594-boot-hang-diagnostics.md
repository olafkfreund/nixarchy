---
status: approved
issue: 1594
intent: intent/2026-11-04-1594-boot-hang-diagnostics.md
---

# Spec: Fail fast with evidence when an install target's boot hangs

## What was measured

- **Callers.** `wait_for_multi_user` (`tests/vm-cleanup.py:45`) has two call
  sites: `tests/free-space.nix:574` and `tests/install.nix:371`. The other
  files that load `vm-cleanup.py` (install-iso, install-iso-net,
  install-encrypted) never call it. That answers intent question 1: every
  caller is a first-boot-after-install wait on KVM.
- **Healthy gaps.** 65 passing waits, taken from the install job logs of the
  last ~30 green `install-check` runs. The whole wait took 13–17 s. The
  longest silence between two console lines was **6.4 s**, and the other
  gaps were around 5.4 s: the sd-boot menu timeout. The script that measured
  this sits in the PR.
- **The two hangs.** The console went silent at 4.6 s and at 5.8 s, and the
  wait ran out its full 900 s, plus the 90 s probe.
- **Test driver** (pinned nixpkgs,
  `nixos/lib/test-driver/src/test_driver/machine/__init__.py`):
  - The serial thread appends every line to `machine.full_console_log`
    (1531) and then queues it on `last_lines`, which `wait_for_console_text`
    consumes (1394–1427).
  - A bounded `wait_for_console_text` goes through `retry` and raises once
    its timeout runs out.
  - `send_monitor_command` (1120) writes to the monitor socket and blocks on
    the prompt with no timeout.
- **sysrq.** The kernel boots with `CONFIG_MAGIC_SYSRQ_DEFAULT_ENABLE=0x1`.
  systemd's `50-default.conf` sets `kernel.sysrq = 16` (sync only) when
  `systemd-sysctl` runs, about 1 s in. A hang at 5 s has the dump keys
  already disabled.

## Design

All changes are in `tests/vm-cleanup.py`. The callers stay as they are.

1. **A windowed wait with a silence detector.** `wait_for_multi_user` gains
   `silence=120`. It reads `len(machine.full_console_log)` on entry, then
   loops over `machine.wait_for_console_text(regex, timeout=w)`, where
   `w = min(15, silence left, budget left)`, so neither limit overshoots by
   a window. It catches only `test_driver.errors.RequestedAssertionFailed`,
   which `retry` raises (driver 197). After each empty window it compares
   the log length with the last one it saw:
   - if the log grew, the silence clock resets;
   - if there has been no growth for `silence` seconds, it fails with
     "console silent for N s";
   - if the overall 900 s budget runs out, it fails as today.

   Lines stay with the driver's own queue, so later `wait_for_console_text`
   calls behave as now. The regex is single-line, so restarting the buffer
   per window loses nothing. 120 s is about 19× the longest healthy gap and
   7× the longest whole wait.
2. **Host-side evidence first, bounded.** Before the existing #1365 probe, a
   daemon thread with a 30 s join sends these on the monitor:
   - `info cpus`, then `info registers -a`;
   - after 5 s, `info cpus` and `info registers -a` again.

   Two samples tell a vCPU spinning in one place (same RIP, not halted) from
   halted vCPUs (an idle wait that is blocked) or a moving RIP (a livelock).
   It **prints each response**, because monitor output never reaches the
   console log (driver 1120–1129, 1531). If the monitor doesn't answer, it
   prints "monitor did not answer within 30 s" and goes on. A thread
   orphaned by that join can't race a later monitor user: the helper always
   raises next, and the callers' `reap_owned_vms` does no monitor RPC
   (`vm-cleanup.py:8`).
3. **Then the #1365 systemd probe, unchanged,** still bounded at 90 s,
   because it names the unit when the guest is alive but blocked.
4. **Raise with the reason** (silence or overall timeout), so the failure
   line says which detector fired.

The cost of a hang drops from 990 s to about 120 + 35 + 90 ≈ 245 s.

**§1 proof, as a permanent check.** `checks.boot-hang-detect`, in a new
`tests/boot-hang-detect.nix`, is a minimal nixosTest with one tiny machine
that loads `vm-cleanup.py`:

- **Case A:** start the machine, `stop` it on the monitor before multi-user,
  and call `wait_for_multi_user(m, timeout=120, silence=20,
  probe_timeout=5)`. It must raise "console silent" in under 60 s (expected
  about 20 + 5 + 5 s). The text the helper printed must hold `info
  registers` output from the paused vCPU, captured by having the helper
  return or attach it to the exception rather than by scraping the log.
- **Case B:** a separate, fresh machine boots normally through the same
  helper and returns. It is never the stopped one resumed, because that
  machine may still hold an orphaned probe thread on its shell.

The break that must turn A red: disable the silence branch. A then reaches
the 120 s overall timeout, so the message and the elapsed-time assertions
both fail.

## Alternatives rejected

- **sysrq dumps (`sendkey alt-sysrq-w/l`).** Disabled at hang time by
  `kernel.sysrq = 16`. Enabling them (with `sysrq_always_enabled` or a
  sysctl) changes the installed target's closure, and so the system we ship
  and the "rebuild builds nothing" assertion. This was the intent's
  best-effort tier. It is dropped, and the second register sample takes its
  place.
- **Scanning `full_console_log` for the regex ourselves.** Lines would pile
  up on the driver's `last_lines` queue, and a later `wait_for_console_text`
  could match stale text.
- **`dump-guest-memory` or a gdbstub.** Gigabytes per failure, or a debugger
  in CI. Too heavy for a 4 % flake. Reconsider if the registers don't
  explain it.
- **Retrying the boot.** Turns a real bug green (§10).

## Risks

- **A future slow boot looks silent.** That would take a unit that prints
  nothing to ttyS0 for 120 s before multi-user. None does today (6.4 s
  max). If one appears, the failure names silence and the fix is raising
  the argument at that call site.
- **Log noise.** Each empty window logs a "waiting for …" section whose
  timeout exception the helper catches. The driver's `nested()` only
  yields (`logger.py`), so a caught timeout records no failure. A healthy
  boot takes one or two windows.
- **Raw RIPs need a symbol map** to read. The reference closure's kernel
  output has `System.map`. The plan decides whether the test has it in
  scope to symbolise inline, or whether `tests/AGENTS.md` gets the one-line
  lookup.
- **CI placement of the new VM check.** It's unclaimed, so
  `generated-checks.sh` would build it in the `omarchy` job. The plan
  checks whether that job can run a VM, as other small VM checks are
  placed, and otherwise claims it where they are built.
- **CI gate (§11).** Editing `vm-cleanup.py` triggers the install job
  through `install-gate.nix:45`, which runs the real callers. A human
  merges.

## Coexistence

None. Test-only. No module, option or package changes.

## Verification

- `checks.boot-hang-detect`: case A red with the break and green without
  it, and case B green. Failing output goes in the PR.
- The install job (install plus free-space) green on the PR, so healthy
  boots pass through the new loop.
- Local: the cheap tier any time, and the VM checks only when CI is idle
  (§6), all run before push.
