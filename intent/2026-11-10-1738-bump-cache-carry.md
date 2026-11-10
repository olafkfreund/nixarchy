---
status: draft
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

So `main` rebuilds whatever a bump compiled, and the next carry-needing bump,
or a codex version bump under the carry, will time out the same way.

## Proposed outcome

- **A bump that needs the carry passes CI with no hand push.** Each carried
  package is compiled at most once per bump run, not once per job.
- **The bump-branch push uploads the closures it should**, minus the
  commit-specific paths, as #1461 intended. A bump whose exclusion set cannot
  be computed still pushes nothing, and says so: that refusal stays.
- **A check fails when the bump push would push nothing on a runner like
  CI's.** At minimum, a fixture that varies the empty-path case.

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
  store diff, and no unfree paths.
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

   Recommendation: (a). It lives where the bump is tested, and runs only
   when a carry is `needed`, so `main` is untouched. (b) pushes from a job
   that has not yet proven the bump. (c) is today's state.
2. **The empty path: fix the read, or change what is excluded.** Once the
   cause is confirmed:
   - (a) obtain the source path another way that works under lazy trees,
     such as `builtins.getFlake`'s `outPath`, or `nix flake archive --json`,
     which CLAUDE.md §5 already names for inputs;
   - (b) exclude by derivation rather than by store-path referrers.

   Recommendation: (a), the smallest change. Decide in the spec from the
   measurement.
