---
status: draft
issue: 1052
author: olafkfreund
---

# Intent: Turn nixarchy-menu on by default

## Problem

nixarchy-menu (`nixarchy.menu`, v1.0.0) is the Raycast-style replacement for
the Omarchy menu: apps, the full Omarchy menu, calculator, conversions, files,
hotkeys, agent hand-off and Smart Match, in one palette. #946 wired it in as a
default plugin, but the only one that is **off** unless a host sets
`programs.nixarchy.defaultPlugins.menu = true`. So a fresh install, and every
existing machine that never set it, still gets the stock Omarchy menu, and the
menu nixarchy is built around is something a user has to know exists.

## Proposed outcome

On every nixarchy machine with the default plugins, `Super+Space`, every
`omarchy-menu` binding and the bar's menu button open nixarchy-menu from the
first login that has it — fresh installs, the ISO's installed system, and
existing machines at their next login after the switch.

A user who does not want it sets `defaultPlugins.menu = false`, or turns it off
in Setup > Plugins, and gets the stock Omarchy menu back, the same way every
other default plugin can be declined. nixarchy's own menu rows (Install ▸ Edit
app selection and the rest of the menu overrides) are still reachable from it.

## Affected users and systems

- Every nixarchy install, new and existing (Mode B). Mode A is untouched:
  default plugins resolve only where `programs.nixarchy.enable` is on.
- `modules/home.nix` (the `menu` entry and the `defaultPlugins` description).
- `tests/options.nix` (asserts the entry is opt-in today), and anything that
  boots a session and drives the stock menu (`checks.session`,
  `tests/menu-verbs.nix`, `tests/demo/` scenes, installer UI screenshots).
- `.github/scripts/readme-counts.sh` and the README's default-plugin counts.
- `docs/internals/flake.md` (#946 section) and the manual's plugin pages.
- Closure size: about 85 MiB (measured at #946) now reaches every machine and
  the reference closure the ISO carries (`iso-budget`).

## Constraints

- Declining must stay one line (`menu = false`) and must restore the stock
  menu, not leave the menu slot empty (#946's restore path).
- A user who already turned it off in Setup > Plugins stays off (enabled-once
  marker semantics).
- No network at runtime for first use: Smart Match models ship in the package.
- The ISO must stay inside its budget.
- The pin stays on a released commit (v1.0.0 today).

## Open questions

1. Should the ISO's live session also get it, or only installed systems?
2. `enableByDefault` exists only for this entry. Once it flips, delete the
   field (and readme-counts' third category), or keep it for a future opt-in
   plugin? Default proposal: delete it — nothing else uses it.
3. The one currently open issue in "Keeping the lights on" — is that the one
   you asked me to close, or did you mean #1052 (closed by this PR)?
