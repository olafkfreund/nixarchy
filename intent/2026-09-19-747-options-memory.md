---
status: approved
issue: 747
author: olafkfreund
---

# Intent: recover memory headroom for the option check

## Problem

`checks.options` consumes most of the hosted runner's available memory while
evaluating the option surface. The existing CI measurement recorded 11,719 MiB
of 16,384 MiB at `e382744` in run 35368958805, with wall time 2:49.39.
This is a measured headroom risk, not an established out-of-memory outage.

The first part of [#747](https://github.com/olafkfreund/nixarchy/issues/747)
is complete: the existing workflow records peak RSS and wall time. What retains
the memory is still unproven. `tests/options.nix` keeps three shared default
fixtures and many scenario-specific NixOS and Home Manager evaluations; #745
reduced repeated evaluation but increased measured peak RSS. New option
coverage continues adding fixtures: PR #782 adds two NixOS configurations.

## Proposed outcome

- Evidence identifies which evaluator state or fixture families account for
  the high peak, distinguishing measurements from hypotheses.
- A targeted change reduces peak memory on comparable runs while preserving
  every existing assertion and its on/off, standalone-home, and named-host
  distinctions.
- Before/after memory and wall time are recorded together, so a memory saving
  cannot conceal a substantial evaluation-time regression.
- The existing CI measurement continues showing the trend. Merely recording
  another number does not close the issue.

## Affected users and systems

- Contributors waiting for the hosted `system` CI job and its option check.
- `tests/options.nix`, its NixOS/Home Manager fixtures, and the proof lookup
  that evaluates the check before deciding whether it needs building.
- Local developers running the same evaluation, especially on p620 while its
  desktop and CI runners share resources.

## Constraints

- Profile before selecting a redesign; retained whole-system configurations
  are a hypothesis, not an established cause.
- Reuse the existing RSS/wall-time measurement; do not recreate instrumentation
  already delivered by #757 and #760.
- Preserve all behavioral coverage and mode distinctions. A lower peak obtained
  by dropping assertions is not an improvement.
- Splitting the check is a last resort: additional evaluations could undo
  the runtime gains from #742 and #745.
- Compare the same revision, evaluator version, cache settings, and command
  shape before attributing a difference to a change; account for concurrent
  plugin work when selecting the baseline.
- Do not run expensive local evaluations or VM builds while install jobs are
  active. Coordinate a quiet measurement window before profiling.
- No machine configuration, deployment, or CI gate changes are authorized by
  this intent. Any required workflow change must be proposed for human review.
- Follow the intent, spec, and plan approvals before implementation.

## Open questions

None for the problem framing. The spec must choose a measurable memory target
and acceptable runtime trade-off after the retained-state evidence is available.
