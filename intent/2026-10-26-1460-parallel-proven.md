---
status: draft
issue: 1460
author: x
---

# Intent: the omarchy job finishes a nixpkgs bump inside its budget

## Problem

`build.yml`'s `omarchy` job has 45 minutes, and a nixpkgs bump does not fit
in them. It timed out twice on #1457. In job 121465539586 the time went like
this:

- **4 minutes** building the Omarchy tree.
- **18 minutes** in `already-proven.sh` before anything was built. The script
  learns each check's output path with a separate `nix eval` process, one
  check after another, for 152 checks. A nixpkgs bump makes every evaluation
  cold, so the heavy ones took 84 to 194 seconds each.
- **About 23 minutes** building the 64 unproven checks. The job was cut off
  on the last of 13 batches.

A timeout reports `cancelled`. On the first of these runs that hid a real
failure, `checks.bus-mcp`, until somebody read the log. Each re-run on a new
head pays the 18 minutes again.

## Proposed outcome

A nixpkgs bump's `omarchy` job finishes with a clear margin. The rows
`already-proven.sh` prints, their order, and its guards (the floor, the
fallback for a check that does not evaluate, the evaluator-statistics
channel) are unchanged.

## Affected users and systems

CI only:

- `.github/scripts/already-proven.sh`;
- its checks, `tests/proof-push.nix` and `tests/cache-budget.nix`;
- every workflow that calls it: `build.yml`'s `omarchy` and `system` jobs,
  and `nightly.yml`.

Nothing ships to users.

## Constraints

- **No CI-gate change:** no required-check renames, no branch-protection
  edits, no timeout change, unless the owner asks for one (AGENTS.md §11).
- **The hosted runner's limits:** 4 cores and 16 GB. Parallel evaluation
  must not run it out of memory.
- **Proven to fail (§1):** a check must show that the order of the rows and
  the floor still hold under parallelism.
- **Measured:** before and after, cold, on the same commit.

## Decisions (owner, 2026-10-26: "implement the fix then and make this faster. Use your recommendations")

1. **The timeout goes from 45 to 60 minutes,** as a margin for the build half.
2. **The build batch size stays at 5:** no measurement shows a gain, and a
   bigger batch pushes proofs later.
