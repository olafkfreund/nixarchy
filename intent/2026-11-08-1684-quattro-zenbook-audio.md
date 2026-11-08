---
status: draft
issue: 1684
author: olafkfreund
---

# Intent: edge adopts quattro d9cc361, classifying the Zenbook 14 audio package

## Problem

Edge is held on quattro `6194f46`. The 20 commits up to `d9cc361` include
`b5883f774` ("Set up the ASUS Zenbook 14 UX3480QA's disk unlock, audio and
sleep", omacom/omarchy#18079), which adds `asus-zenbook-14-ux3480qa-audio` to
`install/omarchy-other.packages`. `checks.omarchy-package-ledger` refuses an
install-list entry with no row in `data/omarchy-packages.nix`, so every edge
run since then stops there (#1684, signatures `c802f51` and `d9cc361`).

## Proposed outcome

- `data/omarchy-packages.nix` has a `skip` row for the package, matching the
  existing `asus-proart-p14-speaker-firmware` row: one laptop model, not
  targeted.
- Edge moves to `d9cc361` (or the newest commit at the time) and its checks
  pass, and #1684 closes.

## Affected users and systems

- Edge only, until edge's next merge into `main`. `main` pins the v4.5.0 tag
  and does not have this package.
- `data/omarchy-packages.nix` on `main` (the row is harmless there; the
  ledger reads only the pin's lists), and an `edge-candidate` carry.

## Constraints

- §8: a carry that classifies a new quattro commit also pins it. That means
  the rows, both copies in `flake.nix` (the input `url` and
  `omarchyVersion`), and `flake.lock`, then a `from_candidate=true` dispatch.
- The same commit adds `fix-asus-zenbook-14-ux3480qa-boot.sh` (disk unlock
  and sleep for that model). It is a hardware script, not a package, and
  installs nothing here; the carry records that decision rather than leaving
  it silent.
- Other checks may fail once the ledger passes, since the ledger was the
  first refusal. The dispatched run is the measurement.

## Open questions

1. Skip, as with the ProArt P14 row? The alternative is `nix = ...` with a
   module, and nixpkgs has no package for this model's audio fix. Skip is
   the recommendation.
2. Should the row go to `main` first (picked up at edge's next merge), or
   only in the carry? The 1498 precedent put shared changes on `main` and
   edge-only ones in the carry. This row is harmless on both.
