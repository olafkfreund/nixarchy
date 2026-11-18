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

It reproduces locally on plain nix 2.35.6, so it is not the runner. The
failure is a compatibility break observed on nix 2.35.6, in nix-update 1.16.0
(the version our nixpkgs pin ships, carrying that nix). When nix's behaviour
changed is not established. The mechanism:
after nix-update rewrites the version in a package file, it runs
`nix flake metadata --json` (`options.py:get_flake_store_path`) and expects
that call to have copied the edited tree into the store. Under nix 2.35 it
reports the dirty tree's store path without writing it:

```
clean: /nix/store/hm093…-source EXISTS
dirty: /nix/store/8ly43…-source MISSING   (nix flake metadata)
       the same path is written by `nix flake archive --json`
```

#1775 runs `nix flake archive` before each updater (`flake.nix:1654`). That
cannot fix the post-edit lookup: the path that goes missing is made inside
nix-update, after its own edit. Measured: both packages with a new release
failed this way; the ones without one passed. Inferred, not measured: every
version bump through any of the 18 nix-update updaters fails the same way,
and the four green nights since #1775 had nothing to bump. Nightly review
#1849 stays red until it works.

## Proposed outcome

- `nix run .#update` bumps a package whose upstream has a new release, hashes
  included, on nix 2.35.
- The nightly `update.yml` opens its usual "Bump pinned packages" PR, and the
  first one carries `owe` 0.2.16 and `checkmate` 0.1.3.
- A check runs a real version-and-hash update whose post-edit tree was not
  in the store beforehand, fails without the fix and passes with it (§1).
  Today `checks.update-app` only evaluates `update.drvPath`
  (`flake.nix:2805`) and never runs an updater, and a green `update.yml`
  with nothing to bump is what hid this (§4).
- The `update` app keeps its rollback of a failed updater's edits and its
  carry-on-to-the-next-package behaviour (#1537).
- #1775's dead workaround is removed, or replaced by the real fix.

## Affected users and systems

- `.#update` and `update.yml` (hosted runner), and anyone running
  `nix run .#update` by hand.
- The 18 `pkgs/apps/*.nix` updateScripts that call nix-update.
- Users are not affected: updateScripts live in `passthru` and do not change
  any package's output path. Whatever fix lands must not change the
  `nix-update` that a Mode A user gets from our overlay.

## Constraints

- The updater fix itself changes no app's build output (`outPath`): with
  versions and hashes held constant, no user rebuilds anything. The `owe`
  and `checkmate` bumps (question 2) do change their outputs, as any bump
  does.
- A patch to nix-update must fail loudly at build time if upstream changes
  the patched line (`--replace-fail`), not silently stop applying.
- `.github/workflows/update.yml` is CI. Changing it needs a human (§11). The
  fix should not need to touch it.
- Local builds follow the §6 tiers (this is the cheap tier: evaluation plus a
  source fetch).

## Open questions

1. Report it upstream at Mic92/nix-update? §11 forbids filing in other
   people's repositories unprompted, so this needs your yes. Whether
   `archive` can replace `metadata` there is for the spec: nix-update also
   reads `locked`/`resolved`/`original` from the metadata to keep a flake's
   subdirectory (`options.py:92-98`), which `archive`'s output may lack.
2. Should the `owe` and `checkmate` bumps ride in this PR as the fix's proof,
   or come from the next nightly run after merge? The recommendation is to
   ride: they are the failing case, and they prove the fix end to end.
