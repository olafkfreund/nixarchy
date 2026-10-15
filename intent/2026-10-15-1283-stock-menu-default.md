---
status: approved
issue: 1283
author: olafkfreund
---

# Intent: Omarchy's own menu is the default; nixarchy-menu is one click away

## Problem

Since #1052, every nixarchy machine starts on **nixarchy-menu** (#946), a
Raycast-style replacement for Omarchy's menu. The owner wants Omarchy's own
menu to be what a user sees by default, with nixarchy-menu still available
to anyone who prefers it.

Today there is no middle ground. `programs.nixarchy.defaultPlugins.menu`
(`modules/home.nix`, ~:768 and ~:1952) has two states:

- `true`, the default: install nixarchy-menu and turn it on at the first
  login;
- `false`: don't install it at all.

So a user who wants to try nixarchy-menu after this change would have to
edit their configuration and rebuild. Default plugins have no "installed,
not turned on" state.

## Proposed outcome

- **New machines start on Omarchy's own menu** (`omarchy.menu`).
- **nixarchy-menu is still installed**, and off.
- **A menu row switches between the two at runtime, with no rebuild.**
  nixarchy-menu is a clone of `omarchy.menu`, so enabling it takes the
  stock menu's slot and disabling it hands the slot back
  (`restoreCloneSource`). The switch already exists in the shell.
- **The row shows which menu is active**, the way the Channel rows do.
- **The manual says** which menu is the default, how to switch, and how to
  make either one permanent in configuration.

## Affected users and systems

- **Users:**
  - every new nixarchy machine (the default changes);
  - existing machines only in that they gain the switch row.
- **Code:**
  - `modules/home.nix` (default plugins: the new state, the post-boot hook);
  - `modules/apps.nix` (the menu row);
  - the manual;
  - `tests/options.nix`, `tests/session.nix` (it summons the menu,
    ~:784), and any check that assumes nixarchy-menu is on.
- **No change to nixarchy-menu itself** (a separate repository).

## Constraints

- **Existing machines are not migrated** (owner's decision). A machine that
  already turned nixarchy-menu on keeps it. Default plugins are turned on
  once and then belong to the user, and nothing here may switch a plugin off
  behind their back. The new row is how they switch back.
- **Mode A is untouched.** Everything stays inside `osConfig.programs.nixarchy.enable`.
- **Never write `shell.json` while the shell runs** (`modules/AGENTS.md`,
  #847). Switching goes through the shell's own IPC
  (`omarchy plugin enable/disable`), as the post-boot hook already does.
- **Turning a menu off must always leave a menu.** Whatever the switch does,
  Super+Space opens one of the two.
- **Every new check is proven to fail first** (CLAUDE.md §1). The `session`
  check keeps proving that Super+Space opens a menu, now on the stock
  default.

## Open questions

1. **Where the row lives.** _Setup ▸ Menu_ (new), or next to the plugin list
   under _Setup ▸ Plugins_? Resolve in the spec.
2. **Option shape.** Extend `defaultPlugins` to take `"installed"` as well as
   `true`/`false`, or give the menu its own option (e.g.
   `programs.nixarchy.menu.style = "omarchy" | "nixarchy"`) that sets the
   initial choice? Resolve in the spec, with the other default plugins in
   mind.
