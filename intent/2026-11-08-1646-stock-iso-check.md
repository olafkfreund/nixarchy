---
status: approved
issue: 1646
author: olafkfreund
---

# Intent: a check proves the stock NixOS ISO install path (#1646 Part B)

## Problem

#1646 Part A (#1669, merged) made `installer/install.sh` treat a machine
with no substituter configured as "this is a stock NixOS ISO". It takes our
caches on every nix call and skips the dark-cache preflight that would
otherwise refuse. Nothing tests that path on a real stock ISO. Every
install check boots our own image, which ships the substituters, so the
branch Part A added is reached only by `checks.installer-network`'s stubs.
The approved Part A plan names the follow-up: `tests/install-stock-iso.nix`,
its CI placement, and a manual section.

## Proposed outcome

- A check boots a stock NixOS minimal ISO, pinned by URL and hash. It runs
  the installer with no image of ours, and proves two cases:
  - with our caches dark, it refuses and leaves the target disk bare;
  - with them reachable, it installs. The run prints the time to the first
    log line, the bytes served and the peak overlay use.
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
- §1: proven by breaking Part A's gate (forcing the preflight back on) and
  watching the install case refuse.

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
