---
status: draft
issue: 1889
spec: spec/2026-11-20-1889-lapic-notscdeadline.md
coders:
  1: coder   # the work was drafted by the fix-1889 fork; finished by the session
reviewers:
  - codex    # "@codex review" on the PR
---

# Plan: lapic=notscdeadline on the instrumented installed target

Decisions carried from the approved spec: add `lapic=notscdeadline` to `etcInstrumentation`s `boot.kernelParams` only; assert in `checks.install-seed-shape` that it is present exactly when instrumented; record why in `tests/AGENTS.md`. Test-only; a 0.7% hang cannot be forced, so the PR says the hang itself is unproven and the nightly install chain is the sampler.

## Steps

1. `tests/lib/installed-target.nix` (etcInstrumentation, ~line 111): add `"lapic=notscdeadline"` after `"sysrq_always_enabled"`, with a `# Why: tests/AGENTS.md#lapic-notscdeadline (#1889)` note. `tests/install-seed-shape.nix`: keep each cases `.config`, compute `lapic`, fail with a `LAPIC` line unless `lapic == instrumented`. `tests/AGENTS.md`: a `lapic-notscdeadline` section after "Boot hang detect".
   → verify: `nix build .#checks.x86_64-linux.install-seed-shape` passes; with the param removed it fails on every instrumented case (§1).
   Traps: §5 nixfmt vs the nixpkgs-fmt hook (`nix fmt`, read `git diff --stat`); a flake sees only tracked files (`git add`); `git checkout HEAD -- <path>` to restore after the break.

## Tests

`install-seed-shape` red and green as above; `nix fmt -- --ci`, statix, deadnix. The install-class VM checks run in CI.

## Rollback

Revert the PR; nothing outside the test VMs changes.
