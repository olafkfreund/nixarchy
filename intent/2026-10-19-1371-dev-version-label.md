---
status: draft
issue: 1371
author: olafkfreund
---

# Intent: a dev machine reports the Omarchy commit it is running

## Problem

`nixarchy version`, `omarchy version` and the About screen all print the
Omarchy package's `version`. That is `omarchyVersion` in nixarchy's
`flake.nix` (line 537): a literal, `"4.0.5"` on `main` and
`"edge-<date>-<rev>"` on `edge`, written by the edge workflow when it moves
the pin.

On the dev channel the Omarchy *source* is the user's own checkout. The
`omarchy` input follows a `git+file` URL, but the label stays the literal.
Measured on 2026-10-19: a dev build from checkout commit `2d3aa608` was
labelled `edge-20261019-81fd2d2`, a commit the machine was not running. The
same is true for anyone who overrides the `omarchy` input by hand.

Those are exactly the people who need the right answer: someone working on
Omarchy itself, comparing builds or reporting a bug against a commit.

## Proposed outcome

- When the `omarchy` input is the commit nixarchy pins, the label is
  unchanged: `4.0.5` on stable, `edge-<date>-<rev>` on edge.
- When it is any other commit (the dev channel, or a manual override), the
  label names that commit, for example `dev-<date>-<shortrev>`. Every place
  that prints the version shows it.
- A check fails if an overridden input still reports the pinned label.

## Affected users and systems

- `flake.nix` only (where the label is computed and passed to the package),
  plus a check.
- Dev-channel and custom-override users. Stable and edge users see no change.

## Constraints

- **No new automation.** The edge workflow writes only the
  `omarchyVersion` literal, and that stays as it is. The "is this the pinned
  commit" answer comes from data the flake already has: nixarchy's own
  `flake.lock` records the pinned Omarchy rev, and `inputs.omarchy.rev` is
  the rev actually built.
- **Edge merge:** `flake.nix` line 537 differs on `edge` (its literal), so
  the change must not touch that line. It goes where `main` and `edge` agree
  (they differ at lines 82, 537, 853, 968, …), proved by a trial merge into
  `edge-candidate`.
- §1: the check goes red when the override is reported with the pinned
  label.

## Open questions

- **The label's shape for a checkout.** I propose `dev-<YYYYMMDD>-<shortrev>`,
  mirroring edge's `edge-<date>-<rev>` and the channel's own name. A
  `custom` override gets the same label, since nothing in the build can tell
  dev from custom, and both mean "your own Omarchy commit".
- **Dirty or rev-less inputs.** A `path:` override has no rev. I propose
  `dev-<date>-unknown` rather than failing the build.
