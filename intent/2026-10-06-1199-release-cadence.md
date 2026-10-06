---
status: approved
issue: 1199
author: olafkfreund
---

# Intent: the release branch stays close to main without breaking users

## Problem

nixarchy already separates development from what users run. `main` takes
every PR and bot merge. Installed machines follow the `release` branch
(`installer/mkFlake.nix:36`), and only `release.yml` moves it, when a human
pushes a `v*` tag.

That split works. How often it is used does not:

- **The release branch is stale.** The last tag is `v4.0.4-1` (2026-09-18).
  On 2026-10-06 `main` is 305 commits ahead, and about 86 bug issues have
  closed since early September. A user who runs `nix flake update` gets none
  of those fixes.
- **The next release ships everything at once.** 305 commits in one bump is
  the "fixes and features break users" risk the split exists to prevent.
  Small, frequent releases are the protection, and nothing makes them happen.
- **A fix cannot ship on its own.** The only way onto `release` is a tag
  that is a descendant of it, and the tag guard (`release.yml`, "The tag is
  not behind main") refuses any commit that is not at main's tip unless
  `RELEASE_ALLOW_BEHIND_MAIN` is set. So an urgent fix ships together with
  every unreleased feature, or it waits.
- **The rule "release from a proven commit" fights the guard.** The best
  commit to release is the newest one nightly built and booted, but that one
  is usually a few merges behind main's tip, and the guard refuses it.
- **Stable nixpkgs is never booted.** `docs/manual/channels.md` says stable
  is evaluation-only because a second VM install would double the slowest
  job. p620 now runs four runners (it had two), so that cost reason is
  weaker.
- **"Stable" means two different things.** `nixarchy channel stable` switches
  nixpkgs to `nixos-26.05`. It does not touch the nixarchy `release` branch.
  A user who wants "the stable nixarchy" will reach for it and get something
  else.

## Proposed outcome

- `release` is never more than about a week behind a green nightly, and each
  release is small enough to read.
- A release is cut from a commit nightly has built and boot-tested, and the
  guard accepts that commit without an override.
- One fix can reach `release` as a packaging release (`vX.Y.Z-N+1`) without
  the rest of `main`, through a documented path.
- Stable nixpkgs gets a VM boot test on a schedule, and the channels page
  says so.
- The docs say plainly which "stable" is which: the nixpkgs channel and the
  nixarchy release branch.

## Affected users and systems

- Every installed nixarchy machine: what it gets on `nix flake update`.
- `.github/workflows/release.yml`, `nightly.yml`, possibly a new scheduled
  workflow.
- The self-hosted runner pool on p620 and p510 (more nightly VM time).
- `README.md` "Releases", `docs/manual/channels.md`.
- The maintainer: releases become routine work.

## Constraints

- `release` never moves backwards. The existing fast-forward-only rule stays.
- No release without a human approving it. Automation may propose a tag but
  must not push one.
- The tag-behind-main guard exists because of a real bad release
  (v4.0.2-7). Any relaxation must still catch that case: a tag that misses a
  fix that was already merged and tested.
- Version scheme stays as is: `v<omarchy version>-<packaging release>`.
- The release job must still fit the runner pool alongside the new stable
  nightly. A release must not wait hours behind a test VM.
- Machines that follow `main` (the maintainer's hosts) are unchanged.

## Open questions

1. **Cadence:** weekly on a fixed day, or "on demand, with a reminder once
   `release` is N days behind a green nightly"?
2. **Proposal mechanism:** a scheduled workflow that opens an issue or draft
   release naming the candidate commit, or a `just`/`nix run` command run by
   hand?
3. **Hotfix branch shape:** cherry-pick directly onto `release` and tag
   there, or a short-lived `hotfix/*` branch merged into both `release` and
   `main`?
4. **Stable nixpkgs boot test:** every night, or weekly to save runner time?
5. **Naming:** rename `nixarchy channel stable|unstable`, or keep the
   command and fix only the docs?
6. **Cut a release now** from the last green nightly, before any of this
   lands? That is a tag push, which ships to every user, so it is the
   maintainer's call.
