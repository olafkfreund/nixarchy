---
status: draft
issue: 1081
author: olafkfreund
---

# Intent: Keep RetroArch resources available after garbage collection

## Problem

`omarchy-install-gaming-retroarch` writes core, core-info, shader, and joypad
paths into `~/.config/retroarch/retroarch.cfg` once. Nixarchy currently supplies
generation-specific Nix store paths for those settings. After an update and
garbage collection, that saved configuration can point to deleted resources,
so RetroArch loses its cores, descriptions, shaders, or controller profiles.

## Proposed outcome

A RetroArch installation made through Omarchy keeps finding its configured
cores, core info, shaders, and joypad profiles after a system update and
garbage collection, provided RetroArch remains installed. The saved settings
follow the currently active packages rather than an obsolete generation.

## Affected users and systems

Users who install RetroArch through Omarchy's gaming installer on Nixarchy.
The affected code is the RetroArch patching in `pkgs/omarchy/default.nix`, its
core-directory helper, and the NixOS package profile that makes resources
available at stable paths.

## Constraints

- Preserve the installed RetroArch core selection and the user-owned paths for
  overlays and databases.
- Verify the actual package layout and profile links before choosing paths.
- Add a check that fails with the old behavior, then passes with the fix.
- Avoid VM checks locally and avoid unrelated installer or workflow changes.

## Open questions

- Which profile paths can expose each resource without a package collision?
- Should the installer repair existing `retroarch.cfg` files, or should the fix
  apply only when the user runs the installer again?
