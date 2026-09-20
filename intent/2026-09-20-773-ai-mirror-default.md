---
status: draft
issue: 773
author: olafkfreund
---

# Intent: ai-mirror ships with nixarchy, and no agent can take the desktop without being handed it

Closes #773. Wave 2 of #766.

## Problem

The owner's decision (2026-09-19) is that [ai-mirror](https://github.com/olafkfreund/ai-mirror)
is installed by default: its binary, its bar widget in the right section, and
its kill-switch bind. nixarchy references it nowhere today.

It could not ship before, and the reason was specific rather than cautious.
`control.py`'s `set_owner` accepted `mode=agent` **from an agent**, with no
human in the loop, so a model that could reach the CLI could take the mouse and
keyboard. Worse, the red widget only lit for `owner == agent`, while
screenshots, clipboard reads and accessibility reads all worked without any
grant — observation happened with no visible mark at all.

**That is fixed upstream, and the fix is why this can proceed.** ai-mirror#11
merged today: `control agent` writes a *pending request*, a dialog drawn by the
bar widget is the only thing that grants it, a request lapses after 30 seconds,
grants end with the MCP server or after ten idle minutes, and observing
operations now write `watching` with a steady neutral mark on the bar. Verified
in the tree rather than taken from the PR title, along with the other two
prerequisites: LICENSE and NOTICE ship in the package outputs
(`flake.nix:15-16`) with a check at `:119`.

## Proposed outcome

- ai-mirror is on a default nixarchy machine: the binary, the bar widget, the
  kill switch.
- **No agent can reach it until the user says so.** No MCP registration
  happens by default, from any harness.
- **A machine that turns nixarchy off gains nothing**, including environment
  variables.
- The kill switch is reachable before control can ever be granted, not after.

## Affected users and systems

Every nixarchy install. `modules/home.nix`'s `defaultPluginSet`, the flake
inputs, and the seeded binds. Mode A is untouched.

## Constraints

- **Not behind `programs.nixarchy.mcp`.** That is a boolean defaulting **true**
  (`modules/nixos.nix:660`), so hanging ai-mirror's MCP registration on it would
  enable exactly the thing this issue exists to prevent, for everyone. MCP
  registration needs its own opt-in.
- **Do not import its Home Manager module wholesale.** It sets session-wide
  `GTK_MODULES`, `QT_LINUX_ACCESSIBILITY_ALWAYS_ON` and dconf
  (`flake.nix:97-98`). Accessibility is a user's own setting and nixarchy must
  not turn it on for them — nor force it off if they have it.
- **The kill switch ships in the seed**, `Super+Shift+Escape`, for new installs,
  the way #766's binds do. An existing home's `bindings.lua` is not edited.
- **A commit-pinned input with `follows`**, like every other plugin here.
- The existing module registers the plugin under the attribute `ai-mirror`
  rather than its manifest id; the default entry canonicalises that and must
  coexist with a user who already declared it.

## Open questions

1. **What does it cost?** Voice turned out to be 6.7 GiB against an estimate of
   one, which is why that one is a catalogue row rather than a default. ai-mirror
   is Python and QML and should be small, but "should be" is what the voice
   estimate was. Measure before deciding it is a default.
2. **Is the kill switch verifiable on an existing home?** New installs get the
   seed. A machine upgraded into this gets the widget and the binary without the
   bind, so the escape hatch is missing exactly where somebody might first grant
   control. Does that gate shipping it to existing homes?
3. **Does the neutral `watching` mark satisfy the observation concern**, or does
   nixarchy want observation off until granted too? Upstream chose to mark it;
   this is the last place to disagree before it is on every machine.
