---
status: draft
issue: 1518
author: x
---

# Intent: the nightly canary's eval gate finishes on a hosted runner again

## Problem

`nightly.yml`'s `canary` job ("what a user's flake update gets") runs on
GitHub-hosted `ubuntu-26.04`. It runs `nix flake update`, then
`.github/scripts/eval-gate.sh`, which evaluates all 35 targets (the cache
allowlist plus the `data/pin-fix.nix` probes) in one `nix path-info
--derivation` process.

It passed every night through 2026-10-29, in about 3.5 minutes. Since then it
has failed twice the same way, on two different hosted runners:

| run | batch started | runner shutdown signal |
|---|---|---|
| nightly 2026-10-30 | 03:09:51 | 03:14:18 (4.4 min) |
| rerun | 08:26:57 | 08:31:12 (4.3 min), then hung to the 30-min cap |

There is no evaluation error in either log. The two runs used the same
installer (v3.22.5, `--determinate`) and image (20261025.179.1) as the last
passing night, so the toolchain did not change. The code did: #1513 added the
`nixarchy-desktop` microvm runners (two full nixarchy + Home Manager
evaluations) to the allowlist, and #1515 changed the hyprland template.

It does not reproduce on p620. With tomorrow's lock in a scratch worktree, the
same `eval-gate.sh --batch-only` passes in 222 s at a 3.35 GiB anonymous peak;
on the current lock it peaked at 8.08 GiB. No target uses import-from-derivation
(each passes with `allow-import-from-derivation = false`). But p620 runs
upstream Nix 2.34.9, while the runner runs Determinate Nix. A shutdown signal
in the middle of evaluation is how a hosted runner looks when the VM runs out
of memory, so this is the leading explanation, but it is not measured.

It matters beyond the nightly: `flake-update.yml` gates every nixpkgs bump on
the same `eval-gate.sh`, on the same hosted image. The next bump whose gate
step runs is likely to die the same way, and a gate that cannot run stops the
bump.

## Proposed outcome

- The cause is measured on the hosted runner, not inferred: the canary log
  shows the gate's memory (and disk) when it dies, or when it passes.
- `eval-gate.sh` finishes on a hosted runner for both callers, the canary and
  the bump gate, with the same exit-code contract (0 evaluates, 1 names the
  failing targets, 2 the gate could not run) and the same target set.
- #1518 closes on a green nightly. #1519's `nightly.yml` row clears with it.

## Affected users and systems

- `.github/scripts/eval-gate.sh` (shared by `nightly.yml` and
  `flake-update.yml`), and possibly the `canary` step in `nightly.yml`.
- Nobody's machine. This is CI only. The risk is a nixpkgs bump stalling.

## Constraints

- No smaller target set. What the gate evaluates is the contract #1459 set:
  the canary and the bump must agree on what "evaluates" means.
- No move to p620's self-hosted runners. That is pure evaluation taking an
  install slot, and changing a job's runner is a CI-gate change under §11.
- Any workflow edit is a CI-gate change (§11). The owner approves it here.
- §1: a fix has to be shown making the difference on the hosted runner. That
  means a dispatched run, because no local machine reproduces it.

## Open questions

1. **Measure first, or fix and measure in one PR?** The cheapest fix
   regardless of cause is splitting the batch (several `nix path-info`
   processes, each freeing its heap). That is agy's recommendation, and codex
   would split only the two desktop runners into their own processes. A
   memory and disk sampler in the canary step would say which it was.
   Default: one PR that does both, with the sampler kept, so the next red
   night says why without a second investigation.
2. **How do we exercise it before merging?** The canary only runs from
   `nightly.yml` on `main`. Default: a temporary `workflow_dispatch` input
   or branch run of the canary job alone, if `nightly.yml` already allows it;
   otherwise the first nightly after merge is the test, and the PR says so.
