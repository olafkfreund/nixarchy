---
status: draft
issue: 1460
spec: spec/2026-10-26-1460-parallel-proven.md
---

# Plan: the omarchy job finishes a nixpkgs bump inside its budget

This carries the spec's decisions: parallel workers, verdicts read back in
argument order, the two heavy checks first and alone, the rest four at a
time behind a 4 GB available-memory floor, and `omarchy` at 60 minutes.

## Steps

1. **`.github/scripts/already-proven.sh`:** replace the serial loop with
   `check_one`, the heavy list, the pool and the ordered read-back. Keep the
   floor and the fallback. Verify against serial on the same tree, cold
   (rows and messages identical, anonymous peak no higher).
   Traps: §4 (`mapfile` and process substitution); §5 (an EXIT trap reading
   a local).
2. **`tests/proof-push.nix`:** add the 12-check out-of-order case, and prove
   it red by reversing the read-back.
3. **`.github/workflows/build.yml`:** `omarchy` `timeout-minutes` from 45 to
   60, with the reason in the comment. Verify with actionlint.

## Tests

- `nix build .#checks.x86_64-linux.{proof-push,cache-budget}`
- actionlint on `build.yml`

## Rollback

Revert the squash commit.
