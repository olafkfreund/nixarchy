---
status: approved
issue: 1646
author: olafkfreund
---

# Intent: a check proves the stock NixOS ISO install path (#1646 Part B)

## Problem

#1646 Part A (#1669, merged) fixed the stock ISO's preflight. Before it,
`nix run ...#install` from a stock NixOS ISO skipped the network preflight
(no `/etc/nixarchy-iso-net`), so an install could fail after the disk was
wiped. Now the switch is `offline_by_design` (`installer/install.sh:2511`):
an **empty** substituter list (the offline install test VMs) skips the
preflight. A stock ISO has `cache.nixos.org` configured, so the preflight
runs there, and `SUBSTITUTE_FLAGS` adds our caches to every nix call.

`checks.installer-refusal` already runs the real installer on a stock-shaped
test node and proves the dark-cache refusal. Nothing boots the actual stock
ISO file and completes an install from it: every install check boots our own
image or a test node built from our modules.

Corrected after review (2026-11-08): the first draft stated Part A's gate backwards.

## Proposed outcome

- A check boots a stock NixOS minimal ISO, pinned by URL and hash, runs our
  installer on it with no image of ours, and completes an install. The run
  prints the time to the first log line, the bytes served and the peak
  overlay use. The dark-cache refusal stays with `checks.installer-refusal`.
- It runs nightly, not per pull request (a large download and a VM).
- `docs/manual/the-iso.md` gains "From a stock NixOS ISO".

## Affected users and systems

- Anyone installing from the stock ISO, the path #1646 opened.
- `tests/`, `.github/scripts/generated-checks.sh` (`nightly_only`),
  `.github/workflows/nightly.yml`, `docs/manual/the-iso.md`.

## Constraints

- **A CI-workflow change** (`nightly.yml`, the nightly list): the owner
  merges it (§4, §11).
- §3: this is "vary the variable that matters". The variable is "no
  substituter configured", which no VM here has.
- The ISO is ~1 GB. It goes in the nightly budget and never on a pull
  request. The free tier of the cache does not hold it (§6).
- §1: proven by dropping our caches from `SUBSTITUTE_FLAGS`, which must make
  the install case fail.

## Decisions (owner, 2026-11-08)

1. It runs nightly, in the nightly budget.
2. The stock NixOS 26.05 minimal ISO, pinned by URL and hash.

## Open questions (as drafted)

1. Is a nightly budget slot acceptable, or should this be manual-dispatch
   only? The recommendation is nightly. Part A's whole risk is a path no
   other check reaches.
2. Which stock ISO: the 26.05 minimal (matches the stable channel) or
   unstable? The recommendation is 26.05 minimal, the image a new user
   downloads.
