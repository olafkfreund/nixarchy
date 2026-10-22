---
status: approved
issue: 1426
spec: spec/2026-10-22-1426-edge-wait-vm-host.md
---

# Plan: edge waits only for what collides with its VMs

## Approved decisions

- Edge's `wait-idle` stops counting every run in flight. It waits only while
  `.github/scripts/vm-host-free.sh edge` says an `install-check` `install`
  job is running. Edge VMs may run beside package builds (intent Q1).
- The `wait-idle` job stays, on the hosted runner, so a wait never holds a VM
  runner (intent Q2).
- Exit 1 (busy) and exit 2 (API unreadable) both mean wait. Poll every 60 s.
  Keep the 3-hour bound, the 200-minute timeout and an error on giving up
  that names what it waited on.
- `verify`'s per-check `host_free`, `install-check.yml` and
  `vm-host-free.sh` are untouched.
- A CI-gate change: the owner merges it (CLAUDE.md §11).

One file changes, so the lead implements it; no `coder` handoff.

## Steps

1. `.github/workflows/omarchy-edge.yml`, the `wait-idle` job (lines 393–422):
   - add `- uses: actions/checkout@v5` with
     `sparse-checkout: .github/scripts` before the step;
   - rename the step "Wait until no install is booting VMs";
   - replace the loop body: run `.github/scripts/vm-host-free.sh edge`,
     capture its output and exit code (`rc=0; what=$(…) || rc=$?`, as
     `verify`'s `host_free` does at line 460), break on `rc=0`, otherwise
     print `waiting (N min left): $what`, fail at the deadline with
     `::error::gave up after 3 hours waiting on: $what`, `sleep 60`;
   - the step drops `set -e` for the loop as `verify` does (`set -uo
     pipefail`), so a non-zero script exit is read, not fatal;
   - `RUN_ID` env is no longer needed: drop it (the script reads
     `GITHUB_RUN_ID`, which Actions sets);
   - rewrite the comment above the step: edge must not share p620 with an
     install's VMs (#1365); package builds are not waited for (#1426).
   → verify by `nix shell --inputs-from . nixpkgs#actionlint -c actionlint
     -ignore 'SC[0-9]+:(info|style):'`.
   Traps: a `gh`/`jq`-less image fails closed (exit non-zero → busy), which
   is wanted. Do not pipe the script into anything (§1, pipefail).

2. Same file, the comments that describe the old wait:
   - line 11 header: `wait-idle  wait until no install is booting VMs`;
   - line 32: `# wait-idle reads runs and jobs to see whether an install is running.`
     (`actions: read` stays: `vm-host-free.sh` uses the runs and jobs APIs).
   → verify by `grep -n 'idle CI' .github/workflows/omarchy-edge.yml` printing
     nothing.

3. §1 proof, in `/mnt/data/vmtest/1426-wait-proof.sh` (not committed):
   - extract the new and the old `run:` blocks from the workflow (new from
     the worktree, old via `git show origin/main:…`) into scratch scripts,
     with `sleep` shadowed by a function that exits 3 so "it waited" is
     observable at once;
   - a `gh` stub on `PATH` (and `GH` pointing at it) serving
     `tests/vm-host-free.nix`-style fixtures: `api …/runs` → a run list,
     `api …/jobs` → a job list, and `run list` → the old block's JSON;
   - cases:
     - **green**: new block, only a `build.yml` run in flight → exit 0,
       prints `free`;
     - **green**: new block, an `install-check.yml` run with `install`
       in progress → waits (exit 3) and printed `busy: …`;
     - **red**: old block, the same build-only fixture → waits (exit 3).
       That is #1426's bug, observed.
   Run under bash (`#!/usr/bin/env bash`). Check the extraction landed:
   print `grep -c vm-host-free` for the new block (≥1) and the old (0).

## Tests

- `actionlint` clean (step 1).
- `/mnt/data/vmtest/1426-wait-proof.sh`: two greens, one red, as above.
- CI on the PR: `lint` runs actionlint; `checks.vm-host-free` still passes.
- After merge: the next edge run with only `build`/`pages` in flight leaves
  `wait-idle` within a minute. Reported on #1426.

## Rollback

Revert the merge commit. `wait-idle` returns to waiting for an idle CI;
nothing else reads its output beyond `report`'s result check
(`needs.wait-idle.result`, line 519), which is unchanged.
