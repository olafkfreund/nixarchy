---
status: approved
issue: 791
spec: spec/2026-09-19-791-microvm-mutations.md
---

# Plan: Safe MicroVM mutations

Owner approved continued issue planning and implementation without further approval on 2026-09-19.

## Steps

1. Add a standalone bash regression invoked from the existing microvm-template check. Capture old failures for invalid names, regex templates and a unit becoming active at lock acquisition.
2. Share name validation and stopped-VM lock checking; preserve prebuilt launch.
3. Run regression before/after against the packaged CLI and deliberate individual breaks, shellcheck, Nix format and parse.
4. Open PR Closes #791, recording full microvm-template CI separately.

## Rollback

Revert fix commit; no host deployment or live VM state changes.
