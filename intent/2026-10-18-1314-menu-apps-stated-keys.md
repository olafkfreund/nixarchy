---
status: approved
issue: 1314
author: olafkfreund
---

# Intent: nixarchy-menu and nixi keep the rest of a row that a partial menu override names

## Problem

#1305 bug 3: a row in the user's menu file
(`~/.config/omarchy/extensions/omarchy-menu.jsonc`) that states only some
keys, say only `label`, blanks every key it does not state. Upstream's
`mergeMenuSources` copies the whole normalised override, and normalisation
fills unstated keys with empty values. #1311 fixed this for the stock menu
by patching `MenuModel.js` in `pkgs/omarchy/default.nix:2074-2078`
(`1305-menu-stated-keys.js`, `1305-menu-merge-stated.js`). Omarchy 4.0.5 has
not fixed it upstream; the patch still applies.

Two other readers of the same menu do not get the fix:

- **nixarchy-menu** (the command palette). Its source imports
  `file:///run/current-system/sw/share/omarchy/shell/plugins/menu/MenuModel.js`,
  but its build rewrites that to a raw copy from its `omarchy` input
  (its `flake.nix:50-51`, `:139`), which nixarchy makes follow its own.
- **nixi** (the guide). `MenuSearch.qml:22` imports the same system path and
  calls `MenuModel.mergeMenuSources` at `:104`; its build copies the raw file
  the same way.

So, with a partial override, a row searched in nixarchy-menu or nixi shows a
blank label, icon or action, while the stock menu shows the right one.

Today `modules/apps.nix` hides this for nixarchy's own overrides: it writes
every override as a full row (#1315 covers removing that). A partial override
the user writes by hand is not covered.

## Proposed outcome

- A partial override in the user's menu file keeps the unstated keys in
  nixarchy-menu and nixi, exactly as in the stock menu.
- The three readers share one `MenuModel.js` behaviour, so the next fix to it
  cannot reach one and miss the others.
- A check fails if either reader goes back to the unpatched merge.
- #1315 (removing `modules/apps.nix`'s full-row merge) is unblocked.

## Affected users and systems

- Everyone using nixarchy-menu or nixi with a hand-written partial override.
- `flake.nix` (both inputs and how their packages are built), possibly the
  nixarchy-menu and nixi repositories, and `pkgs/omarchy/default.nix` only if
  the patched file has to be exposed.
- Users importing nixarchy-menu or nixi outside nixarchy, if the fix lands in
  those repositories.

## Constraints

- No regression in the stock menu: `checks.menu-model-merge` stays green.
- nixarchy-menu cannot take nixarchy as an input (its `flake.nix:9-11`: that
  would be circular).
- The patched `MenuModel.js` lives in nixarchy's 128 MiB tree; neither plugin
  should depend on the whole tree for one file.
- Changes to the nixarchy-menu and nixi repositories go through their own pull
  requests; both are the owner's repositories.
- §1: the check must be shown failing with the raw file.

## Open questions

1. **Where the fix lives.** (a) nixarchy hands both packages its patched
   `MenuModel.js` (one patch, nixarchy-only; outside nixarchy they keep the
   bug), or (b) each repository carries the same patch (three copies to keep in
   step, but fixed everywhere). The spec should measure whether (a) is possible
   through the packages' existing arguments without forking their builds.
2. Should nixi's and nixarchy-menu's own test suites (`tests/tst_menumodel.qml`
   in nixarchy-menu) gain a partial-override case, or is one check in nixarchy
   enough?
