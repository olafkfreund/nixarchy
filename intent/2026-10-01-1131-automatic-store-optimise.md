---
status: approved
issue: 1131
author: olafkfreund
---

# Intent: Deduplicate the store on installed machines

## Problem

Installer-managed machines have two space-recovery mechanisms, but neither
deduplicates files that are still in the Nix store. `installer/host.nix` sets
`min-free`/`max-free` to collect unreferenced paths under space pressure and
uses `programs.nh.clean` to prune old generations. A search of `installer/`,
`modules/`, and `tests/` found no `nix.optimise.automatic` or
`auto-optimise-store` setting. Identical files in live paths can therefore
occupy separate disk space, which matters at the 32 GiB minimum disk size.
The reported roughly 9 GiB saving on nixbook is motivation, not a measured
saving for a nixarchy installation.

## Proposed outcome

An installer-managed machine periodically hard-links identical Nix store
files when the machine is on AC power. Its existing generation cleanup and
pressure-triggered garbage collection keep their current roles. The store
scan runs at idle CPU and I/O priority. A check proves that the installed host
enables optimisation and a Mode A adopter with Nixarchy disabled does not
acquire the timer.

## Affected users and systems

- Machines whose generated host imports `installer/host.nix`, including the
  reference and VM configurations used to check an installed system.
- Owners of 32 GiB disks, for whom any recoverable space is most useful.
- Mode A adopters who import the Nixarchy module into their own system; their
  existing Nix policy must remain theirs.
- Desktop workloads sharing disk bandwidth with `nix-optimise.service`.

## Constraints

- Prefer NixOS's `nix.optimise.automatic` timer over daemon-side
  `auto-optimise-store`, which adds optimisation work to each build.
- Do not add `nix.gc.automatic`: `programs.nh.clean` already owns generation
  cleanup, and nixpkgs warns when both are enabled.
- Preserve the installer-only 3/8 GiB `min-free`/`max-free` policy and the
  Mode A off-state. No background store job should appear merely from
  importing a disabled Nixarchy module.
- Check the resolved NixOS options in both states, showing the check red
  without the new setting before accepting it as coverage (root `AGENTS.md`
  §1; `modules/AGENTS.md`).
- Do not build, deploy, or run store optimisation as part of this intent gate.

## Open questions

1. **Where should the policy live?** Approved: `installer/host.nix`, beside
   its existing disk and cleanup policy. That file is imported only by
   installer-managed hosts. A `mkDefault` in `modules/nixos.nix` would extend
   this disk-wide background policy to Mode A when Nixarchy is enabled and
   requires extra care to leave its disabled state inert.
2. **When should it run?** NixOS defaults to daily `03:45`, with a persistent
   timer and up to 30 minutes of random delay. A sleeping laptop can catch up
   when it wakes. Approved: keep the default schedule initially; measure
   runtime and contention before adding a custom calendar.
3. **How should desktop I/O be limited?** `nix-store --optimise` scans and
   hashes store files, so the first pass can compete with interactive work.
   Nixbook gives its background upgrade `CPUWeight = 20` and `IOWeight = 20`.
   The pinned nixpkgs optimiser already uses `Nice = 19`, idle CPU and I/O
   scheduling, and `ConditionACPower = true`. Approved: retain those native
   defaults, with no extra CPU or I/O weights; add weights only if a real
   installed machine shows contention. Measure savings and duration on that
   machine rather than extrapolating from nixbook's result.
