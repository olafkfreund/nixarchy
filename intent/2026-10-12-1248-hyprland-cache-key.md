---
status: approved
issue: 1248
author: olafkfreund
---

# Intent: nixarchy trusts Hyprland's binary cache with the key Hyprland publishes

## Problem

nixarchy names `https://hyprland.cachix.org` as a substituter and pairs it with
the public key `hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE=`.
That is not the key the cache signs with. Two independent sources, read on
2026-10-12, publish `hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=`:

- the Cachix API, at `cachix.org/api/v1/cache/hyprland`;
- Hyprland's wiki, at `wiki.hypr.land/Nix/Cachix`.

`nix store verify --store https://hyprland.cachix.org` on a Hyprland 0.56.0
path reports `untrusted` with our key, and passes with the published one.

So no Nix that relies on our configuration accepts a path from Hyprland's
cache. Hyprland comes from hyprwm's flake (`flake.nix:79`), not nixpkgs, so
its build graph is not on `cache.nixos.org` either. Unless something else
supplies those paths, Hyprland and its libraries are built from source:

- on every installed machine that updates;
- in the installer;
- in CI, through `setup-nix`.

The wrong key has been in the repository since the first commit (`c5a2d566`).

The repository also states the opposite as measured fact.
`docs/internals/flake.md:118` says Hyprland is "**fetched** —
`hyprland.cachix.org`". `.github/scripts/cache-allowlist.sh` reasons that the
cache budget need not cover anything Hyprland's cache serves. Both may rest on
a premise that has not held.

The key appears in six places, three more than the issue names:

- `flake.nix:12`;
- `modules/nixos.nix:1062`;
- `.github/actions/setup-nix/action.yml:51`;
- `installer/cd.nix:819`;
- `installer/install.sh:51`;
- `installer/vm.nix:57`.

Reported by an outside contributor (#1248). It is also why #1236's board row
went red: the issue had no milestone when it was filed, which is fixed.

## Proposed outcome

- **Fetched, not built:** every machine, installer image and CI job that
  nixarchy configures accepts signed paths from `hyprland.cachix.org`, so
  Hyprland's build graph is downloaded rather than built.
- **One value:** the key is the same everywhere it is written.
- **Guarded:** something checkable catches the next time the key and its
  copies disagree, or the key stops matching what the cache signs with.
- **Docs that match:** `docs/internals/flake.md` and `cache-allowlist.sh`
  describe what actually happens.

## Affected users and systems

- **Installed machines, after their next rebuild:** these pick up the key
  through `nix.settings.trusted-public-keys` (`modules/nixos.nix`), gated by
  `programs.nixarchy.binaryCaches`.
- **The installer:** both ISO images, and the VM harness (`installer/cd.nix`,
  `installer/install.sh`, `installer/vm.nix`).
- **Anyone consuming the flake:** through its `nixConfig`, when they accept it.
- **CI:** every job that uses `.github/actions/setup-nix`. Build times may
  drop, and that changes what the cache budget sees.

## Constraints

- **This is a trust-root change.** Replacing a signing key decides what every
  machine accepts. The new value must come from the cache operator's own
  published sources, never from the issue text alone. Both sources above were
  read directly.
- **The setup-nix change needs a human.** `.github/actions/setup-nix` is CI
  plumbing every job uses. Changing a value there is a CI change (§11), so it
  goes in the PR for a human to merge, not assumed.
- **Mode A:** the module change stays behind `binaryCaches`, as it is now.
  Nothing new is turned on for someone who imports the module.
- **Coexistence (§14):** `trusted-public-keys` is a list that merges with the
  user's own. If a user already lists the correct key, they now get it twice,
  which is harmless. If they list the old one, it stays theirs.
- **Proving the fix (§1):** any check has to fail against today's key before
  it passes on the new one.

## Open questions

1. **Was the key always wrong, or did Hyprland rotate it?** This decides
   whether the "fetched" claim in `flake.md` was ever true, and whether a
   rotation should be expected again. That in turn shapes the guard. Proposed:
   find out in the spec (wiki history, Cachix metadata, the age of signed
   paths), and record it either way.
2. **What kind of guard:**
   - an offline check that every copy in the tree is the same, a `runCommand`;
   - a network check, nightly, that the key verifies a real path on the cache;
   - both.

   Proposed: both, because they catch different failures. The offline one
   catches a copy that drifts. Only the network one catches the key being
   wrong or rotated, which is this bug. Each would be its own check.
3. **One source for the key.** The six copies sit in Nix, bash and YAML, so
   one definition cannot reach all of them directly. Proposed: leave them as
   copies, and let the offline guard in question 2 hold them equal. Settle it
   in the spec.
