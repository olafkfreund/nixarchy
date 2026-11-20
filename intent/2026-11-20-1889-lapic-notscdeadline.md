---
status: approved
issue: 1889
author: x
---

# Intent: the installed target in install checks stops hanging on lost LAPIC wakeups

## Problem

About 0.7% of install-class builds on p620 (4 of 573 since 2026-11-04) hang the installed target 4.5-6.8 s into its second boot. BootHang (#1594) catches it, so the job fails on a change that has nothing to do with it (#1888). The dumps show every vCPU halted, the LAPIC timer in TSC-deadline mode, timer and IPI wakeups lost while NMI and sysrq arrive.

## Proposed outcome

The installed target in the test VMs no longer depends on the TSC-deadline LAPIC path that KVM emulates on p620, and a check proves the workaround is on the test target and never in what the installer writes for a user.

## Affected users and systems

The install, free-space and install-encrypted checks (tests/lib/installed-target.nix) and checks.install-seed-shape. No user system.

## Constraints

Test-only: the installed closure for a real user must not change. A 0.7% hang cannot be forced, so the fix cannot carry a red-then-green proof of the hang itself (CLAUDE.md §1); the PR says so.

## Open questions

None. The owner pre-approved the intent, spec and plan for this loop.
