---
status: approved
issue: 1826
author: x
---

# Intent: package Omarchy's Cards and Checkmate

## Problem

Omarchy ships two more Qt apps of its own, Cards (github.com/omacom/cards) and
Checkmate (github.com/omacom/checkmate). nixpkgs carries neither and nixarchy
does not build them, so a nixarchy machine lacks two apps a stock Omarchy
machine has, the same gap #1572 closed for Hype, Monologue, Signed and Disktree.

## Proposed outcome

Both apps build from `nixarchy-apps`, are on PATH and in the launcher on a
default machine through `programs.nixarchy.omarchyApps.enable`, and can be
turned off one by one (`apps.cards.enable = false`) or all at once.

## Affected users and systems

Every machine with `preinstalls` on (the default). Mode A machines
(`programs.nixarchy.enable = false`) must see no change.

## Constraints

- Mode A untouched; `tests/options.nix` asserts both states.
- main's Omarchy tag pin does not list the two packages, so
  `data/omarchy-packages.nix` gets no rows (the ledger fails on a row with no
  name); they exist on edge only, and this change adds nothing there.
- Pin a release tag where upstream has one.

## Open questions

None. (Cards has tag v0.1.0 and two later commits; the tag is used.)
