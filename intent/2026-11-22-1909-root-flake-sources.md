---
status: approved
issue: 1909
author: x
---

# Intent: a self-hosted job keeps its own flake source alive through the host's auto-GC

## Problem

Nightly run 44979123567 failed in "put dropped allowlist entries back in the cache" with `error: path '/nix/store/3b0k65700ilf85lhjy1mdvxmrq8g91w7-source' is not valid`. That path is the job's own checkout of `main` (15be21f) copied into the store, the flake every `nix build .#…` in the job evaluates.

The job ran on p620-nixarchy-2. p620's nix runs with `min-free = 100 GiB` and `max-free = 200 GiB`. Free space fell below 100 GiB overnight, so the job's own `nix build` started an auto-GC (`running auto-GC to free 117132738560 bytes`). It waited 45 minutes for the GC lock, then deleted garbage from 04:11 to 04:15:33. Eleven seconds later the evaluation failed on its flake source. Nothing held a GC root on that path: the job's first `nix shell --inputs-from .` had copied it, and later processes reused it without rooting it. The flake's inputs, nixpkgs among them, were exposed in the same way.

Ruled out: the weekly `nix-gc` timer (next run 2026-11-23), `nh clean` and `nix-optimise` (05:28), and the `nixos-upgrade` auto-switch, which started at 04:16:44, a minute after the failure.

Every self-hosted job (`nightly.yml`, `omarchy-edge.yml`'s verify, `weekly.yml`, `release.yml`) shares p620's store and is exposed the same way. Each one fails when the disk is low, on a line that has nothing to do with its change.

## Proposed outcome

A self-hosted job roots its flake source and every flake input before it builds anything, so an auto-GC during the job cannot take them. A cheap check proves that the rooting step names the source and every input.

## Affected users and systems

CI on p620's self-hosted runners only. No user system. The roots are per-job and go away with the runner's temp directory.

## Constraints

- A workflow change is a CI-gate change (CLAUDE.md §11): the PR is opened and left for the owner to merge.
- The host's `min-free`/`max-free` live in the config repo, which agents do not touch. Raising that policy is the owner's call; this PR only says so.
- The roots must be indirect (under the runner's temp directory), so nothing outlives the job.

## Open questions

None. The owner pre-approved intents, specs and plans for this batch.
