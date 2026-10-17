---
status: approved
issue: 1320
author: olafkfreund
---

# Intent: Arch-only menu rows say why they can't be used, instead of vanishing

## Problem

#1304 Part 3 hid nine menu rows that cannot work on NixOS, using
`when = "false"`:

- Windows VM, install and remove;
- Hybrid GPU;
- Direct boot;
- Hermes, install and remove;
- Perplexity, install and remove;
- Brave Origin removal.

Hiding them was the only choice that stayed safe whichever of #1301 and #1304
landed first. #1301 has now landed (#1308), and the menu honours `disabled`. A
row can now be shown dimmed with a reason, and it cannot be selected.

A hidden row does not answer "why can't I install X here?". A user coming
from Omarchy on Arch, where the row exists, is left looking for it.

## Proposed outcome

Each of those rows appears dimmed and cannot be selected. Its description says
in one line why it does not apply on NixOS. Where there is something to do
instead, it says what. The rows still cannot run their Arch action.

## Affected users and systems

- Everyone on the Omarchy menu.
- `modules/apps.nix`: the nine `when = "false"` overrides.
- `data/menu-actions.nix`, whose `hidden:` entries change class, and
  `data/menu-exceptions.nix`.
- `checks.menu-actions` and `checks.menu-guards`. `menu-guards`' `unavailable`
  cases count `disabled: true` rows, so its floor may move.

## Constraints

- **No route may run a dimmed row:** not a click, the keyboard, search, or
  `omarchy menu summon <alias>`. Upstream's `openRoute` runs a row by alias
  before any visibility check (omacom/omarchy#15742), so whether it honours
  `disabled` must be checked, not assumed.
- **Mode A:** nothing outside the menu changes.

## Open questions

1. **Is this wanted at all?** Hidden is quieter, and dimmed is more honest.
   That is the owner's UX call.
2. **Which rows?** All nine, or only those a NixOS user would plausibly look
   for, such as Windows VM and Hybrid GPU?
