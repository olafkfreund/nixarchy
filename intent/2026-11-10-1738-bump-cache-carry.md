---
status: approved
issue: 1738
author: olafkfreund
---

# Intent: a nixpkgs bump that needs the cargo carry builds and caches without a hand push

## Problem

Two failures. Together they meant a nixpkgs bump needing the #1722 cargo
carry could not pass CI without a person pushing to the cache from p620.
#1738's third item, the cache budget, is done (#1739). These two are what
is left.

1. **Every job compiles the carried codex.** The carry gives `codex` and
   `codex-acp` new derivations that cache.nixos.org does not serve. Each
   hosted job that reaches them builds them itself: `system-build`,
   `system-checks`, `system-session`, `omarchy`, `box` and `options-files`
   (`options-files` reaches codex at build time). That takes 20+ minutes on a
   cold runner. On #1737 (run 42773957660) all six hit `timeout-minutes` with
   no build failing. #1737 passed only after p620 pushed its `vm-toplevel`
   and `reference-toplevel` closures by hand, with owner approval. #1741 then
   went green because those paths were still cached.
2. **The bump branch's cache push pushes nothing.** `cachix-push.sh` in bump
   mode (#1461) builds its exclusion set from
   `nix flake metadata --json . | jq -r .path`. On the hosted runners that is
   empty, so the script warns `the flake source path is empty; a nixpkgs bump
   pushes nothing without the exclusion set` and exits 0.
   - Measured on #1737 and on #1741: four warnings each, and no `pushing …`
     line.
   - Older bump runs are deleted, so when this began is unknown.
   - `checks.cache-budget` tests bump mode with a stub whose
     `nix flake metadata` returns a path, so it could not see this (§3).
   - The likely cause is Determinate Nix, which `nix-installer-action@main`
     installs. Its lazy trees may not copy the flake source into the store,
     so `.path` is absent. Not yet confirmed.

So `main` rebuilds whatever a bump compiled, and the next dated nixpkgs bump
that changes a carried package's derivation will time out the same way. Codex
comes from nixpkgs, so a new codex version only ever arrives through such a
bump, and no other branch kind is affected.

## Proposed outcome

- **A bump that needs the carry passes CI with no hand push.** In a
  successful workflow attempt, one job produces each carried package, and
  every other job takes it from the cache. A re-run, or a cache outage, may
  compile again; that is accepted.
- **The bump-branch push uploads the closures it should**, minus the
  commit-specific paths, as #1461 intended. A bump whose exclusion set cannot
  be computed still pushes nothing, and says so: that refusal stays.
- **Two checks, because they answer different questions:**
  - a stub fixture in `tests/cache-budget.nix` for the empty or null-path
    refusal, which is today's stub-only gap;
  - an assertion with **real `nix`, in the runner environment CI uses**,
    that the exclusion set holds known commit-specific paths: at least one
    derivation that embeds the commit, not just the source path itself. A
    stub cannot see real `nix` change its output, which is how this bug went
    unseen (§3). An exclusion set of only `$src` is the failure this has to
    catch (open question 2).

## Affected users and systems

- **CI only.** `.github/workflows/build.yml`, `.github/scripts/cachix-push.sh`,
  `tests/cache-budget.nix`, and possibly `flake-update.yml`.
- **No machine's configuration changes.** Users see the effect only as bumps
  that land without stalling, and as cache hits on `main` after one.
- **The cache budget (#1739)** is involved, because the carry's packages are
  pushed. That was the reason for 3 GB.

## Constraints

- **These change CI gates (§11).** They are proposed in a PR, and the owner
  merges.
- **Only allowlisted closures are pushed (§6, #697):** nothing per job, no
  store diff, and no unfree paths. The carried packages are already inside
  the allowlisted `vm-toplevel` closure, so pushing them early is a subset of
  what the allowlist already permits, not a new entry. The spec must keep it
  that way: only packages `cargo-system-libs` marks `needed`, and only those
  that are in an allowlisted closure.
- **The exclusion set must keep refusing rather than pushing everything**
  when it cannot be computed.
- **Hosted runners only.** Nothing here may move work onto p620's
  self-hosted runners, which serve installs.
- **The measurement comes first.** The empty `.path` has a likely cause but
  no confirmation. The spec starts by reproducing it on a hosted runner, or
  under Determinate Nix locally.

## Open questions

1. **How to compile the carried packages once.**
   - (a) A new job that runs before the others on a bump branch. It builds
     each package `cargo-system-libs` marks `needed` and pushes it, and the
     heavy jobs `needs:` it.
   - (b) `flake-update.yml`, which opens the bump, builds and pushes the
     carried packages before it opens the PR.
   - (c) Leave it, and rely on the timeout plus a hand push when it happens.

   Recommendation: (a). It lives in the workflow that tests the bump, beside
   the jobs it unblocks, and runs only when a carry is `needed`, so `main` is
   untouched. Both (a) and (b) push before the heavy checks have proven
   anything. That is acceptable for the carried packages alone, because they
   are allowlisted and their own build is the proof. (c) is today's state.
2. **The empty path: what to exclude, under lazy trees.** The question is not
   only how to read the source path. Under lazy trees, the built derivations
   may not reference one top-level source store path at all. Then
   materializing the source separately (`builtins.getFlake`'s `outPath`,
   `nix flake archive --json`) gives a path nothing references. Its
   referrers-closure is itself, which passes the script's non-empty test, so
   the script would push commit-specific paths instead of refusing.
   - (a) If the measurement shows the built paths do reference a source path
     reachable another way, read that path, and keep the referrer exclusion.
   - (b) Otherwise, exclude by what makes a path commit-specific (for
     example, its closure containing the derivations that embed `self.rev`)
     rather than by referrers of the source.

   Recommendation: decide in the spec from the measurement. Either way, the
   real-`nix` check above must show that a known commit-specific path is
   excluded.

## Decisions (owner, 2026-11-10)

Approved as revised, with both recommendations: a producer job on the bump branch for the carried packages (Q1), and the exclusion design decided in the spec from a hosted-runner measurement (Q2).
