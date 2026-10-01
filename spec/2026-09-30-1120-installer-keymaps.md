---
status: draft
issue: 1120
intent: intent/2026-09-30-1120-installer-keymaps.md
---

# Spec: Offer only available installer console keymaps

## Design

1. Remove `Arabic\tara` and `Thai\tth-tis` from
   `installer/brand/keymaps.txt:6,43`. Keep the other 43 rows as they are.
   This file feeds the wizard through `UI_KEYMAPS` in
   `installer/install.sh:24,621-627`, and the chosen value becomes the
   generated host's `console.keyMap` through
   `installer/install.sh:1486` and
   `installer/template/host/configuration.nix:15`. The wizard currently
   ignores a failed `loadkeys` at `installer/install.sh:627`, so the bad
   choices can advance to a later failure. No runtime remapping is added.

2. Add a cheap `checks.installer-keymaps` in `flake.nix` beside the existing
   installer checks around `flake.nix:1947-2028`. Give it the real
   `installer/brand/keymaps.txt` and `pkgsFor.${system}.kbd`; the installer
   itself substitutes that same package at `flake.nix:965-987` into
   `KEYMAPS` (`installer/install.sh:38`). For every nonempty tab-separated
   menu row, require a non-dangling file or symlink named `<keymap>.map.gz`
   anywhere under that package's `share/keymaps`. Reject a malformed row or
   an empty menu too. Report the label and missing keymap on failure. Follow
   the installed package tree, not an independent list of accepted names.
   `installer/install.sh:681-688` already accepts regular and symlinked
   maps for unattended answers; preserve that behavior.

3. The menu remains a Linux console keymap choice. The pinned upstream
   Omarchy `install/provisioning/setup-form.sh:32-80` also omits Arabic and
   Thai. Omarchy's Hyprland layout is separately configured in
   `config/hypr/input.lua:4-15`; do not silently turn the removed labels
   into a Latin console layout or change desktop input settings here.

## Alternatives rejected

- Map Arabic or Thai labels to `us` or another Latin console keymap: it
  would tell users that a script-specific layout was selected when it was
  not. Users can select a real console map, then configure XKB separately.
- Keep the rows and fall back only after `loadkeys` fails: the generated
  `console.keyMap` would still be wrong unless the wizard changed the
  user's choice silently.
- Add custom Arabic or Thai console maps or change the installer to build
  console maps from XKB: this is substantially more work and support surface
  than the issue warrants; neither map ships in the pinned `kbd` 2.9.0 tree.
- Check only the two known bad names: another missing entry could still
  reach the same late failure after a menu or `kbd` update.

## Risks

- Arabic and Thai no longer appear in the console-layout menu. Users who
  need those scripts in the desktop must configure the Hyprland/XKB layout
  separately; this change does not offer a scripted desktop-layout prompt.
- A future `kbd` update can remove or rename a map. The check must use the
  package wired into the installer, including valid symlinked maps, so this
  becomes an early, actionable failure.
- The check proves that a map file exists, not that a real keyboard's
  physical layout or every key combination is correct. The existing wizard
  and VM checks retain their current coverage.

## Verification

1. Recount the shipped menu against the pinned `kbd` tree: before the
   change, `ara` and `th-tis` are the only failures among 45 rows; after
   removing them, all 43 rows resolve. `nix eval --raw
   .#nixosConfigurations.reference.pkgs.kbd.outPath` identifies the pinned
   package without building it.
2. Break-prove `checks.installer-keymaps`: save the corrected menu with `cp`
   outside the worktree, append a fake tab-separated map entry, build the
   check and capture its nonzero result naming that label and map. Restore
   the saved file with `cp` (never `git checkout`), then build it again and
   capture its green result. The original `ara`/`th-tis` rows should also
   make the check red before the menu fix.
3. Run `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and
   `nix run nixpkgs#deadnix -- --fail .` after any `.nix` edits. Run the
   cheap installer-keymaps check under the shared build lock. No VM check
   is needed locally for this menu-data correction.
