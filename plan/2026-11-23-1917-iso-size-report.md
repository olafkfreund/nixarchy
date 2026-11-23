---
status: approved
issue: 1917
spec: spec/2026-11-23-1917-iso-size-report.md
---

# Plan: build before measuring the closure

Approved decision: build the toplevel, capture output, split with a here-string.

## Steps

1. `.github/workflows/nightly.yml`, "Report the ISO size": replace the `read < <(nix path-info ...)` with the build/capture/here-string lines → verify by actionlint, and the step as a bash script (pass and failure path).
   Traps: §4 process substitution; §1 run under bash, not zsh.

## Tests

actionlint; `wt-1917-step.sh` exit 0 with a closure size; the failure script exits 1.

## Rollback

Revert the commit.
