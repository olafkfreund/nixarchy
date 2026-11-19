---
status: draft
issue: 1858
spec: spec/2026-11-19-1858-nightly-vm-job-sequencing.md
reviewers:
  - codex   # independent read of a CI-gate change; reviews on the PR via "@codex review"
---

# Plan: put the nightly's keyboard-boot behind install-class sequencing

Approved decisions: chain `keyboard-boot` after `install-encrypted` with
`needs: [install-encrypted]` and `if: always()`. Leave `microvm` unchained.
No concurrency group, no `vm-host-free.sh` change, no new check. Fix the two
stale comments, and record the 2026-11-19 load measurement (peak 1-minute
load 54.8 with four VM jobs overlapping, run 44449120419).

The whole edit is one file and a few lines, so the session implements it
itself. No coder handoff.

## Steps

1. `.github/workflows/nightly.yml`, `install-encrypted` comment (about lines
   84-102): replace the claim that only `install-iso-net`'s `needs` orders
   anything with the two chains.
   `keyboard-boot` (about lines 117-125): add `needs: [install-encrypted]`,
   `if: always()`, and a short comment naming the chain.
   `install-iso-net` comment (about lines 146-156): replace "in no chain.
   Measuring in #1858" with the two chains and the measurement.
   → verify with `actionlint` and `yq`.
   Traps: §8, no literal skip-CI marker in the message; §4, widening the
   format (none here); `report`/`digest` `needs` already list
   `keyboard-boot`, so no change there.

## Tests

- `nix run nixpkgs#actionlint -- .github/workflows/nightly.yml` prints nothing.
- `nix run nixpkgs#yq-go -- '.jobs.keyboard-boot.needs[0], .jobs.keyboard-boot.if' .github/workflows/nightly.yml`
  prints `install-encrypted` and `always()`.
- `nix build .#checks.x86_64-linux.nightly-digest` passes (under the cheap-tier lock).
- `nix fmt -- --ci` passes.

## Rollback

Revert the commit. Nothing outside the workflow changes.
