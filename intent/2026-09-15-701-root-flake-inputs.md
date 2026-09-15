---
status: approved
issue: 701
author: olafkfreund
---

# Intent: an installed machine keeps the sources it needs to rebuild itself

## Problem

An installed nixarchy machine's automatic garbage collection can delete the
sources of its own flake inputs, including nixarchy, nixpkgs and home-manager.
Afterwards the machine can evaluate its configuration only if it can download
them again.

- **The trigger.** `installer/host.nix` sets `min-free = 5 GiB` and
  `max-free = 20 GiB`. When free space falls below 5 GiB, Nix collects
  unreferenced paths until 20 GiB is free. The comment beside it reasons that
  this only removes true garbage, such as what `nixarchy try` leaves behind.
- **What it misses.** The flake inputs' sources are unreferenced too. Checked on
  `main` at a62e715: `reference-toplevel`'s closure of 2,662 paths contains none
  of nixarchy's, nixpkgs's or home-manager's source paths.
- **Observed, not theoretical.** #698's `install` check evaluated `/etc/nixos`
  on the installed test machine. The disk was below the floor, the collection
  deleted nixarchy's source, and evaluation failed with
  `Could not resolve host: github.com`. The test machine is offline, as a
  laptop on a train is. The driver then hung until the 90-minute cap, so the
  failure read as a timeout. #698, a routine nixpkgs bump, is blocked on it.

The install image (`installer/cd.nix`) already roots these same sources through
`system.extraDependencies`, for the same reason. The installed machine never
got the equivalent.

## Proposed outcome

- **Offline rebuilds keep working.** An installed machine below its free-space
  floor still evaluates and rebuilds its configuration offline, for as long as
  nothing has changed that needs a download.
- **No repeat downloads.** A machine that is online does not download its
  inputs again after a collection.
- **A check that can fail.** Something proves this, and has been seen red with
  the fix removed (AGENTS.md §1).
- **#698 is unblocked on the merits.** Its install passes because the bug is
  fixed, not because the test disk grew or the job was re-run until green.

## Affected users and systems

- **Users:** everyone on an installed machine. The ones who feel it are
  offline, or on a disk near 5 GiB free.
- **Code:** `installer/host.nix`, the installed host module both the generated
  flake and `vm/configuration.nix` import. Possibly `modules/nixos.nix` if the
  fix belongs to the module rather than the installer's host.
- **Checks:** `checks.install`, which found it; a cheaper check should see it too
  (§2).
- **PRs:** #698.

## Constraints

- **Mode A is untouched.** A machine that imports `nixosModules.nixarchy` into
  its own configuration must not gain anything it did not opt into (§7).
- **Rebuilding stays a no-op.** `checks.install` asserts that a rebuild on the
  installed machine builds nothing. Rooting a path whose store path changes
  with every edit of `/etc/nixos` could break that, and make every edit a new
  generation.
- **The closure grows by source trees**, which are not small (nixpkgs is
  hundreds of MiB). That cost has to be stated and accepted.
- **Collection stays.** Still collect under space pressure (`nixarchy try`
  leftovers, old builds). The fix narrows what is garbage; it does not turn
  collection off.
- **No test-disk resize and no retry as the fix** (§3, §10).

## Open questions

1. **Which inputs to root.** Everything `inputs` hands the host, which since
   #693 includes the user's own flake inputs and `self`? Or only nixarchy and
   its inputs? Rooting the user flake's own `self` changes the system closure on
   every edit of `/etc/nixos`, which conflicts with "rebuilding stays a no-op".
2. **Where the fix lives.** In `installer/host.nix`, which only installed
   machines get, or in the module behind an option, so Mode A users can opt in?
3. **How cheaply it can be proven.** An evaluation check that the toplevel's
   closure contains the input sources is cheap, but it tests the arrangement.
   The property is an offline evaluation surviving a collection, which needs a
   VM. Is the cheap check plus `checks.install` enough?
