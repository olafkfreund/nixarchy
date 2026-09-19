---
status: approved
issue: 714
intent: intent/2026-09-16-714-install-fail-fast.md
---

# Spec: bound cleanup of every dynamically created test VM

Approved revision, 2026-09-19: the owner authorized all remaining stages.
Replaces the unsafe shutdown()/release() fallback identified in the issue.

## Design

The six install-class test scripts run inside one generated try/finally.
A factory records each dynamically created machine before start(), including
partial starts. Its command starts with exec: the pinned driver launches via
Popen(shell=True), so process.kill() must target qemu, not a waiting shell.
All callers pass direct qemu commands. Existing restart shutdowns remain.

The finally kills every owned process without asking an unresponsive guest or
monitor, then waits with a timeout and joins the serial reader with a timeout.
An unreapable process or reader forces a failing exit after printing the original
exception, preventing a non-daemon reader from hanging interpreter shutdown.
No graceful shutdown is needed after the final assertion on disposable disks.

One shared implementation replaces the three monitor-based reap() copies and
covers the three tests with success-only cleanup. This reverses the earlier
no-helper decision: bounded process and thread cleanup is too subtle to copy
six times, and all nine creation sites need the same ownership contract.

## Alternatives rejected

- shutdown() then release() on exception: neither call is bounded.
- monitor quit: an unresponsive monitor can also block.
- registering machines in the driver: its release() has an unbounded join.
- lowering driver/job timeouts: hides the original failure and changes gates.
- only checking finally in source: accepts cleanup that hangs.

## Risks

The implementation reads process/serial_thread fields from the pinned driver.
The check uses the actual pinned driver source to assert those assumptions and
exercises real subprocess/thread cleanup without qemu. A normal VM run remains
necessary CI integration evidence; the cheap check cannot prove QEMU behavior.

## Verification

A PR-gated install-teardown check simulates an unresponsive guest with a real
SIGTERM-ignoring process and non-daemon stdout reader. It proves bounded exit,
original assertion preservation, partial-start cleanup, cleanup on success and
forced failure when a reader cannot finish. Source wiring covers all six tests.
Run against the previous missing/monitor cleanup first, then remove process.kill
from the fixed implementation and observe the deadline failure. No VM builds
while another agent or CI owns the install resources.
