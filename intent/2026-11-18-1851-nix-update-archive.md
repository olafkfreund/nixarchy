---
status: draft
issue: 1851
author: olafkfreund
---

# Intent: `nix run .#update` can bump a version again

## Problem

The nightly `update.yml` failed on 2026-11-18 (run 44241816081). It found
`owe` 0.2.15 → 0.2.16 and `checkmate` 0.1.2 → 0.1.3, and bumped neither.
Both failed the same way:

```
error: opening file "/nix/store/qqx615zdg3l88ad669clj9i71c26yd2p-source": No such file or directory
nix_update.errors.UpdateError: failed to retrieve hash when trying to update checkmate.src
```

It reproduces locally on plain nix 2.35.6, so it is not the runner. The cause
is in nix-update 1.16.0, the version our nixpkgs pin ships with nix 2.35.6:
after nix-update rewrites the version in a package file, it runs
`nix flake metadata --json` (`options.py:get_flake_store_path`) and expects
that call to have copied the edited tree into the store. Under nix 2.35 it
reports the dirty tree's store path without writing it:

```
clean: /nix/store/hm093…-source EXISTS
dirty: /nix/store/8ly43…-source MISSING   (nix flake metadata)
       the same path is written by `nix flake archive --json`
```

#1775 tried to fix this by running `nix flake archive` before each updater.
That cannot work: the path that goes missing is made inside nix-update, after
its own edit. It only looked fixed because no upstream released anything for
four nights, and an updater that finds no new version never re-resolves the
flake. **Every** version bump through `.#update` fails today, for all 18
packages that use nix-update, and nightly review #1849 will stay red until it
works.

## Proposed outcome

- `nix run .#update` bumps a package whose upstream has a new release, hashes
  included, on nix 2.35.
- The nightly `update.yml` opens its usual "Bump pinned packages" PR, and the
  first one carries `owe` 0.2.16 and `checkmate` 0.1.3.
- A check fails if the updater goes back to being unable to bump a version,
  because a green `update.yml` with nothing to bump is what hid this (§1, §4).
- #1775's dead workaround is removed, or replaced by the real fix.

## Affected users and systems

- `.#update` and `update.yml` (hosted runner), and anyone running
  `nix run .#update` by hand.
- The 18 `pkgs/apps/*.nix` updateScripts that call nix-update.
- Users are not affected: updateScripts live in `passthru` and do not change
  any package's output path. Whatever fix lands must not change the
  `nix-update` that a Mode A user gets from our overlay.

## Constraints

- No change to an app's build output (`outPath`), so no rebuild for users.
- A patch to nix-update must fail loudly at build time if upstream changes
  the patched line (`--replace-fail`), not silently stop applying.
- `.github/workflows/update.yml` is CI. Changing it needs a human (§11). The
  fix should not need to touch it.
- Local builds follow the §6 tiers (this is the cheap tier: evaluation plus a
  source fetch).

## Open questions

1. Report it upstream at Mic92/nix-update? §11 forbids filing in other
   people's repositories unprompted, so this needs your yes. The fix there is
   a one-word change (`metadata` → `archive`).
2. Should the `owe` and `checkmate` bumps ride in this PR as the fix's proof,
   or come from the next nightly run after merge? The recommendation is to
   ride: they are the failing case, and they prove the fix end to end.
