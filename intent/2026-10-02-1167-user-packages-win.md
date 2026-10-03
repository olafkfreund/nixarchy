---
status: approved
issue: 1167
author: olafkfreund
---

# Intent: a user's own package wins over the one nixarchy brings

## Problem

`environment.systemPackages` becomes `system.path` through `buildEnv` with
`ignoreCollisions = true` (`nixos/modules/config/system-path.nix:207-211`).
When two packages ship the same file, the higher `meta.priority` keeps it;
on a tie, the package earlier in the list does. The other copy is dropped
silently.

nixarchy's packages come early in that list and carry the default priority,
so where a user installs a package that shares a binary with one of
nixarchy's, **nixarchy's wins**.

**Proven by #1164's new check in CI** (run 37074375513): with
`environment.systemPackages = [ pkgs.ffmpeg-full ]`, `system.path`'s
`bin/ffmpeg` is nixarchy's `ffmpeg`, not the user's. nixarchy's sits at index
49 of 313 and the user's at 143; both have the default priority. Nothing
warns; `which ffmpeg` points at the wrong build.

The Home Manager side already solved this for the packages it brings
unasked (`modules/home.nix:1004-1016`, `map lib.lowPrio`, #809). The system
side never got the same rule.

## Proposed outcome

- **A user's own package wins every file it shares with a package nixarchy
  brings.**
  - "User's own" means added by the user's configuration, at the default
    priority.
  - "Brings" means added by nixarchy's modules without the user asking for
    that package by name: runtime dependencies, default tools.
- **`checks.coexistence`'s `systempkg-own-ffmpeg` fixture (#1164) is green.**
  #1164 merges after this.
- **nixarchy's own collisions resolve the same as today:** among
  nixarchy's packages, the relative priority and order are unchanged, so
  nothing nixarchy ships changes which of its own binaries wins.

## Affected users and systems

- `modules/nixos.nix` (`environment.systemPackages`, `:1290` onwards, plus
  the Omarchy `runtimeDeps` spliced in), and any other nixarchy module that
  adds system packages unasked. To check: `modules/services/boxes.nix:114`,
  `modules/local-ai.nix:407`.
- Every installer-managed machine. The change is invisible unless a user's
  package overlaps one of nixarchy's, and then the user's now wins.

## Constraints

- **Packages a user explicitly chose through nixarchy keep their normal
  priority.** For example the app selection in `modules/apps.nix:1205`: they
  *are* the user's own choice. The spec decides where that line falls.
- **No `mkForce`, no edits to user lists. Mode A stays inert.**
- **Prove it (§1):** the #1164 fixture is red on `main` (already shown), and
  green with the fix. A probe that lifts nixarchy's `ffmpeg` back to normal
  priority must turn it red again.
- **Watch for a reversal:** a NixOS or other module that adds a package at
  default priority, overlapping a now-`lowPrio` nixarchy package, would also
  start winning over nixarchy. The spec must check whether any such overlap
  exists in the reference closure today, and what changes for it.

## Open questions

1. **How broad:** all of nixarchy's unasked system packages, or only the ones
   known to overlap common user installs? The proposal is all of them, as on
   the Home Manager side (#809). A list of known overlaps would be another
   hand-maintained list (AGENTS.md §4, "a hand-maintained list fails open").
2. **The app selection (`apps.nix`):** a package the user picked in the
   installer or the menu. The proposal is normal priority (the user asked
   for it by name), so it behaves as if the user added it themselves.

## Owner's answers (2026-10-03)

1. **All of nixarchy's unasked system packages,** not a list.
2. **Apps the user picks in the installer or menu keep normal priority.**
