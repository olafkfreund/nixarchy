---
status: draft
issue: 697
author: olafkfreund
---

# Intent: the binary cache holds what users and CI download, within 5 GB

## Problem

nixarchy.cachix.org is on Cachix's free tier: 5 GB. When it is full, Cachix
deletes the paths that were **downloaded** longest ago. Pushing a path again
does not count as a use.

The cache is full of paths nobody downloads. Every job with `cachix-action`
pushes whatever that job built, on pull requests as well as `main`: VM test
runs, test drivers, disk images, and builds from branches that never merge.
Those push out the paths users and CI need:

- **Users.** On 2026-09-15 every KVM MicroVM template runner returned 404, a day
  after `main` had downloaded the same paths. A user's first
  `nixarchy vm run` became a build of QEMU instead of a download.
- **CI.** The same day, 31 of the 34 check results proven the afternoon before
  were gone. `build.yml` skips a check only when the cache holds its result, so
  every pull request's `omarchy` job had to build 47 checks instead of 15. That
  does not fit on the hosted runner, so it died, pushed nothing, and every
  re-run started from the same empty cache. #693 and #696 are blocked on it.

Nothing states what the cache is for, and nothing measures what goes into it,
so it will fill again after any clean-up.

## Proposed outcome

- **Explicit contents.** The cache holds a named list of paths, each there for a
  stated reason: a user downloads it, or CI relies on it.
- **Budget check.** The list's real cost is measured in CI and fails the build
  when it exceeds a stated share of the 5 GB, so the cache cannot quietly fill
  again.
- **No pushes from pull requests.**
- **Check results stay cached.** A pull request that changes one file builds
  the checks that file affects, not every check, and the `omarchy` job fits
  on the hosted runner again.
- **Upstream stays out.** Paths cache.nixos.org or hyprland.cachix.org already
  serve are not counted and not pushed. Cachix already skips them.

Measured so far, counting only what the upstream caches do not serve:

| path | cost | who downloads it |
|---|---|---|
| `omarchy` | 124 MiB | every user |
| `vm-toplevel` closure | 327 MiB | installs, CI |
| MicroVM KVM runner, first template | 424 MiB, 394 MiB of it a QEMU build every runner shares | `nixarchy vm run` |
| MicroVM TCG runner, each | 29 MiB | `checks.microvm-boot` |
| a check's result, the path alone | kilobytes | `build.yml`'s skip |

Still to measure: `reference-toplevel`, the ISO-related closures, the apps
built here, and the devenv and box outputs.

## Affected users and systems

- **Users:** anyone installing, updating, or running `nixarchy vm run`, who
  downloads from this cache.
- **Workflows that push:** `build.yml` (the `lint`, `devenv-presets`, `omarchy`,
  `apps`, `system` and `box` jobs), `omarchy.yml`, `update.yml`, and #696's
  nightly `runners` job.
- **Scripts:** `.github/scripts/cachix-push.sh`, `build-unless-proven.sh` and
  `already-proven.sh`.
- **Runners:** the hosted runners, and the four p620 runners through the shared
  store.
- **Cachix plan:** the free tier stays as it is; it is the constraint, not
  something to change.

## Constraints

- **Stay within 5 GB.** Nothing here may assume a paid plan.
- **CI gate changes.** Workflow and required-check changes need a maintainer
  (AGENTS.md §11). This work proposes them; it does not merge them.
- **Pushes stay non-blocking.** A failed push must not fail a build that
  succeeded (#235, `continue-on-error`). It must still be visible, and the
  budget check is a separate step that can fail.
- **Mode A and user flakes are untouched.** This concerns what is published,
  not the module.
- **The budget is computed, not hand-kept.** Paths change with every commit, so
  a number written into a file goes stale the same way the app counts did.
- **Every new check needs a failing run.** Break it and show it red before it
  goes green (§1).

## Open questions

1. **Budget share.** The proposal is 4 GB of the 5, leaving room for the
   in-between moment when a new `main` push arrives before the old paths age
   out.
2. **Branches that are not pull requests** (`omarchy.yml`, `update.yml` bump
   branches). Should they push nothing like pull requests, or push their
   allowlist so a bump PR is cached before it merges?
3. **The MicroVM KVM runners.** The shared QEMU build is 394 MiB. Is
   "`nixarchy vm run` is a download" worth that space, or should KVM runners
   leave the allowlist and users build QEMU once?
4. **Keeping allowlisted paths alive.** Cachix only counts downloads as use. The
   nightly probe fetches narinfo; if that is not enough to count, should the
   nightly download each allowlisted NAR, costing bandwidth rather than storage?
5. **The p620 PR** (`ci/generated-checks-self-hosted`, not yet opened). Keep it
   as a fallback, or drop it once check results are reliably cached?
