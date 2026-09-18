---
status: draft
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

## Open questions

- **Bar space.** Four new bar widgets on a default desktop, three of them only
  when their service is on. Is a fixed bar position per plugin wanted (all in
  one section, and which), or wherever each plugin's manifest asks?
- **Keybindings.** nixarchy seeds `~/.config/hypr` once and never manages it.
  Should new installs get the plugins' suggested binds (Super+Alt+N/O/D/V) in
  the seeded `bindings.lua`, with existing installs getting only menu rows? Or
  menu rows only everywhere?
- **The distrobox cut-over.** Nothing happens until the plugin reads nixarchy's
  templates (`nixarchy box templates --json`). Does the `nixarchy box` CLI stay
  as the terminal interface afterwards, or is it retired too?
