---
status: draft
issue: 1889
intent: intent/2026-11-20-1889-lapic-notscdeadline.md
---

# Spec: lapic=notscdeadline on the instrumented installed target

## Design

`etcInstrumentation` in `tests/lib/installed-target.nix` is the only source of the test-instrumentation file the install checks copy into the installed flake. Its `boot.kernelParams` gains `lapic=notscdeadline`, so the target guest programs its LAPIC timer in one-shot mode instead of the TSC-deadline MSR that KVM emulates with AVIC off. #1594 set the precedent with `clocksource=acpi_pm` for the same class.

`checks.install-seed-shape` already renders the real template for every case, instrumented and not. It keeps each cases config and fails with `LAPIC <case>` unless the param is present exactly when instrumented. The reason lives in `tests/AGENTS.md#lapic-notscdeadline`.

## Alternatives rejected

- Re-running on BootHang: hides the hang and costs an install slot every time.
- Turning on AVIC on p620 (`kvm_amd avic=1`): a host change on the owners desktop and every runner, for a test problem. Kept as the next variable if this does not hold.
- Pinning the target to the 6.18 kernel: tests a kernel users do not get. Also kept as a next variable.

## Risks

The param could reach a user install if the instrumentation text leaked into the template: install-seed-shape asserts it does not. If the hang is not the TSC-deadline path, it recurs; the nightly install chain shows that and #1889 reopens.

## Verification

`checks.install-seed-shape` passes with the change and fails on every instrumented case with the param removed. `checks.install`, `free-space`, `install-encrypted` run in CI (install job); locally only when no runner is busy.
