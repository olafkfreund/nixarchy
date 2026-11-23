---
status: approved
issue: 1917
intent: intent/2026-11-23-1917-iso-size-report.md
---

# Spec: build before measuring the closure

## Design

`top=$(nix build --no-link --print-out-paths <toplevel>)`, `info=$(nix path-info -Sh "$top")`, then `read` from a here-string. Capture-then-split per CLAUDE.md §4, so `set -e` sees each failure.

## Alternatives rejected

- `continue-on-error` on the report: hides it (§4, a step that cannot run reads as passing).
- Rooting the toplevel elsewhere: the store dropping it is legitimate; the step must not assume it.

## Risks

A build of the reference toplevel: it is an allowlisted cache entry, measured at 37 s locally.

## Verification

Run the new step under bash: prints the closure, exit 0. Point it at a missing attribute: exits 1 with nix's error. The next nightly passes the job.
