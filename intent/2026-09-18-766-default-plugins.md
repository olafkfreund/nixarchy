---
status: approved
issue: 766
author: olafkfreund
---

# Intent: nixarchy-pkg, -podman, -distrobox and -microvm ship with nixarchy and are on by default

Closes #766.

## Problem

Four Omarchy shell plugins give nixarchy's own features a proper Omarchy
interface:

- [nixarchy-pkg](https://github.com/olafkfreund/nixarchy-pkg) for package management;
- [nixarchy-podman](https://github.com/olafkfreund/nixarchy-podman) for podman;
- [nixarchy-distrobox](https://github.com/olafkfreund/nixarchy-distrobox) for boxes;
- [nixarchy-microvm](https://github.com/olafkfreund/nixarchy-microvm) for microvms.

None of them reaches a nixarchy user unless that user finds the repo, adds a
flake input, sets `programs.nixarchy.plugins.<id>.src`, runs
`omarchy plugin enable`, and pastes a menu row and a key binding by hand. The
nixarchy repo references none of them. On the owner's own machines they arrive
through `/etc/nixos`, and two of the four were copied in by hand.

nixarchy's rule so far is that it installs plugins but never enables them
(`modules/AGENTS.md`, "plugins present, never on"). nixi is the one exception,
and nixi enables itself. That rule is why these plugins are optional extras
rather than part of the desktop.

## Proposed outcome

The owner's decision, 2026-09-18:

- **A fresh install** has all four installed and enabled, bar widget included,
  with no prompt. The ones tied to an off-by-default service appear when that
  service is turned on.
- **An existing flake install** gets them added and enabled at its next update,
  once.
- **After that, the user decides.** A plugin turned off in Setup > Plugins stays
  off through later rebuilds.
- Each plugin has a menu row where its feature lives, and that row never
  silently does nothing.
- Where a plugin is the better interface, it **replaces** the old one:
  - distrobox replaces the Boxes menu once it carries nixarchy's templates;
  - microvm replaces the Sandbox rows.
  - nixarchy-pkg is added beside the terminal package flow.
- **Podman gets a switch of its own:** `programs.nixarchy.services.podman`, a
  catalogue row, off by default. The podman plugin is on whenever podman is on,
  through that switch or through Boxes.
- The rule reversal and its reasoning are written into `modules/AGENTS.md` in
  the same change.

## Affected users and systems

Every nixarchy desktop, and every existing flake install on update. Affected
code:

- `flake.nix`: four inputs, re-exported packages, and `lib.inputSources` onto
  the ISO;
- `modules/home.nix`: `programs.nixarchy.plugins` and a one-time enable step;
- `pkgs/omarchy/default.nix`: the vendored default `shell.json`;
- `modules/apps.nix`: menu rows;
- `data/services.nix` and a new podman service module;
- boxes and microvm menus;
- tests (`options`, `plugin`, `menu-verbs`) and the manual.

Also the plugin repos themselves. The distrobox templates and nixarchy-pkg's
Apply both change there.

## Constraints

- **nixarchy never writes `shell.json` while a session runs.** The shell
  rewrites the whole file from memory and watches it, so two writers lose
  updates. Existing installs are enabled through upstream's own
  `omarchy plugin enable`, and fresh installs through the vendored defaults.
- **Mode A stays inert.** Importing the module with nothing enabled changes
  nothing, and that is proved across the Home Manager fixture split, because
  `modeAInert` alone cannot see a Home Manager default leak.
- **Opt-out exists** per plugin and for all four together. Opting out stops
  nixarchy installing or enabling them. It does not reach into a user's
  `shell.json`.
- **Inputs** are commit-pinned with `nixpkgs.follows`, following the nixi
  precedent, and their growth of the offline ISO is measured against
  `iso-budget`.
- **Templates have one source.** The distrobox plugin reads nixarchy's box
  templates and does not keep its own copy.
- Every new check is proven to fail first (§1). A new `checks.<name>` needs a
  workflow edit by a human (§4, §11).

## Decisions (owner, 2026-09-18)

- **Bar:** all four widgets go in the **right** section of the bar.
- **Keybindings:** new installs get the plugins' suggested binds in the seeded
  `bindings.lua`: Super+Alt+N (pkg), Super+Alt+O (podman), Super+Alt+D
  (distrobox), Super+Alt+V (microvm). Existing installs get the menu rows only,
  because nixarchy seeds `~/.config/hypr` once and never edits it afterwards.
  The spec checks each bind against what Omarchy and nixarchy already bind.
- **`nixarchy box` is retired** once the distrobox plugin creates boxes from
  nixarchy's templates. The CLI (`pkgs/box.nix`, `nixarchy-box`), its menu rows
  and the `box` verb in the `nixarchy` dispatcher go. What stays, and what that
  means:
  - `data/box-templates.nix` stays the single source of templates. A command
    being retired cannot export it, so nixarchy generates it as a file the
    plugin reads (for example `/etc/nixarchy/box-templates.json`).
  - `services.boxes.machines` (declared boxes) does not go through the CLI and
    is unaffected.
  - `checks.box-template` and `checks.box-boot` test through the CLI today
    (`tests/box-boot.nix:95` runs `nixarchy box create`). They are retargeted
    at the path the plugin takes (distrobox with a template from the generated
    file), so box creation stays tested end to end. Renaming or dropping a
    `checks.<name>` is named in workflows (`build.yml:1504`), so that edit is
    raised for a human, not made by an agent (AGENTS.md §4, §11).
  - The manual (`docs/manual/boxes.md`, README, `docs/index.md`) moves from
    the CLI to the panel.

## Open questions

None. The owner answered the three open questions (bar, keybindings,
`nixarchy box`) above.
