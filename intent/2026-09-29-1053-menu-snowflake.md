---
status: draft
issue: 1053
author: olafkfreund
---

# Intent: nixarchy-menu's bar button wears the NixOS snowflake

## Problem

nixarchy gives the bar's menu button the NixOS snowflake. It does this by
replacing the stock `omarchy.menu` button with
`pkgs/omarchy/menu-bar-widget.qml`. That works only while the stock menu is
the menu.

nixarchy-menu (`nixarchy.menu`, opted into with `defaultPlugins.menu =
true`) brings its own `BarWidget.qml`, and nixarchy never patches it. That
button draws the Omarchy glyph (`""`, font `omarchy`). So turning the
palette on turns the snowflake off, and the menu slot shows the Omarchy
mark.

This has already cost a user. olafkfreund/nixos_config dropped nixarchy-menu
from two machines to get the snowflake back (nixos_config#2070), and
nixos_config#2074 wants both. #1052 plans to turn nixarchy-menu on by
default. If it lands first, every nixarchy machine loses the snowflake.

## Proposed outcome

With nixarchy-menu enabled, the bar's menu button shows the NixOS snowflake
at the same size, position and dimming as the stock button does today.
Everything else about the button stays the same:

- left click toggles `omarchy.menu`;
- right click opens a terminal;
- the palette's bar items, such as the Timer countdown, still appear after
  it.

## Affected users and systems

- Everyone who sets `defaultPlugins.menu = true` today, and everyone once
  #1052 lands.
- `modules/home.nix` (the `menu` default-plugin entry), a new patch under
  `pkgs/`, and `tests/qml.nix` and `tests/options.nix`.
- nixarchy-menu itself is not changed. It stays distro-neutral.

## Constraints

- Use the PNG, not the SVG. quickshell ships no Qt SVG image plugin (see
  `menu-bar-widget.qml`).
- Apply the patch with `--fuzz=0`, like the other carried patches, so a
  nixarchy-menu bump that rewrites the button fails the build instead of
  shipping the Omarchy mark.
- Mode A is untouched, because default plugins resolve only where
  `programs.nixarchy.enable` is on.
- Independent of #1052 in code. That change flips `enableByDefault` and
  this one changes `src`, so whichever lands second rebases.

## Open questions

None. The design was approved downstream in nixos_config#2074
(`spec/2026-09-29-2074-nixarchy-menu-snowflake.md`). This repo's spec will
restate it against this tree.
