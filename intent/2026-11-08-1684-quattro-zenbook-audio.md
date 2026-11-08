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
run that tries to advance the pin stops there (#1684, signatures `c802f51` and `d9cc361`).

## Proposed outcome

- `data/omarchy-packages.nix` has a `skip` row for the package, matching the
  existing `asus-proart-p14-speaker-firmware` row: one laptop model, not
  targeted.
- Edge moves to `d9cc361` (or the newest commit at the time) and its checks
  pass, and #1684 closes.

## Affected users and systems

- Edge only, until edge's next merge into `main`. `main` pins the v4.5.0 tag
  and does not have this package.
- An `edge-candidate` carry only. The row cannot go to `main` first: the
  ledger fails a row whose name no pinned list has (stale,
  `data/omarchy-packages.nix:22-24`), and `main` pins v4.5.0.

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

1. Is this one laptop's hardware support in scope? If not, the row is
   `skip`, as the ProArt P14 row is (`data/omarchy-packages.nix:483`). That
   is the recommendation.
2. When edge next merges into `main`, the row must travel with the pin. If
   `main` keeps the v4.5.0 tag, the row goes stale there. The edge-to-`main`
   merge already reruns readme counts against the pin (§8, #1537); should
   the ledger be named alongside it?
