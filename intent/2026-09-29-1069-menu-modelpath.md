---
status: draft
issue: 1069
author: olafkfreund
---

# Intent: Super+Space opens a menu on every nixarchy install

## Problem

Since #1054, nixarchy-menu replaces the stock Omarchy menu. Its
`providers/OmarchyMenu.qml:5` imports
`file:///run/current-system/sw/share/omarchy/shell/plugins/menu/MenuModel.js`.
A nixarchy system profile does not link `/share/omarchy` (`reference`'s
`system.path.pathsToLink` has neither `/share` nor `/share/omarchy`), so the
import fails. The chain goes unavailable in turn (`OmarchyMenu`, then
`Registry`, then `NixarchyMenu`), and with the stock menu disabled,
**Super+Space opens nothing**. This hits fresh installs, and any machine at its
next login after rebuilding main. `demo-scene-menus` records exactly this.
nixi's `MenuSearch.qml` has the same import and fails too.

## Proposed outcome

On every nixarchy install, Super+Space and `omarchy-menu summon <route>` open
the menu. A check fails if the menu ever stops opening.

## Affected users and systems

Every nixarchy machine (Mode B). The changes are in `modules/nixos.nix` and
`tests/session.nix`.

## Constraints

Mode A is untouched (under `mkIf cfg.enable`). This is a hotfix: smallest
change first, with the proper fix as a follow-up in nixarchy-menu.

## Open questions

None. The owner chose the expedited hotfix on 2026-09-29.
