---
status: approved
issue: 701
author: olafkfreund
---

# Intent: an installed machine keeps the inputs it needs to rebuild offline

## Problem

An installed machine's automatic garbage collection can delete its own flake
inputs' sources. Nothing in the system closure references them, so a collection
below `min-free` takes them, and then:

- **offline**, the machine cannot evaluate or rebuild its own configuration at
  all;
- **online**, every rebuild after a collection downloads its inputs again.

This is not theoretical here. It failed `checks.install` on 2026-09-15
(`unable to download 'https://github.com/olafkfreund/nixarchy/archive/…':
Could not resolve host: github.com`), and it failed again overnight on PR #712,
on a branch that predated the disk work.

**This was fixed once and reverted.** #702 rooted every input source with
`system.extraDependencies`, and was proven red-then-green in CI. #706 reverted
it, not because the fix was wrong, but because up to 835 MiB of extra closure
pushed the then 20 GiB install-test disk under `min-free` (5 GiB), where Nix
2.34 segfaulted collecting.

Every one of those constraints has since moved. #708 made the supported disk
32 GiB, set `min-free`/`max-free` to 3/8 GiB, and pinned Nix 2.35. The install
that merged it measured **18.4 GiB free** on a fresh 32 GiB install.

## Proposed outcome

- **Offline rebuild:** after a full collection, an installed machine still
  evaluates and rebuilds its own configuration with no network.
- **Cost known, not assumed:** the closure that rooting adds is measured, and
  what a fresh install leaves free stays above `max-free` (8 GiB), which
  `checks.install` already asserts.
- **The user's flake is not the root:** what is rooted is nixarchy's own inputs,
  never whatever the user edits in `/etc/nixos`.
- **Proof:** `checks.install` collects and then evaluates offline, and that
  assertion is seen failing without the fix.

## Affected users and systems

- Every installed machine, whenever free space drops near `min-free`.
- `installer/host.nix`, the shared input-source walk, `tests/options.nix`,
  `tests/install.nix`.
- Not the ISO, which already roots its input sources.

## Constraints

- **Within the 32 GiB budget.** A fresh install must still leave more than
  `max-free` (8 GiB) free, and `checks.install` fails if it does not.
- **Mode A:** a host that imports the module without enabling it is untouched.
- **Seen red first** (AGENTS.md §1), in CI for the install assertion.
- **No bigger test disk to hide it** (§3), and no retrying until green (§10).
- The revert is on `main`; this re-lands the change rather than inventing a
  second mechanism.

## Open questions

1. **Root everything, or only what evaluation needs?** #702 rooted every input
   source. The alternative roots a smaller set (nixpkgs, home-manager, nixarchy
   itself) and accepts that a rarely used input is fetched again. Everything is
   simpler and was already proven; the smaller set costs less disk. The spec
   should decide on the measured numbers.
