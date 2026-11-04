---
status: approved
issue: 1596
author: x
---

# Intent: A supported load point for layout settings after looknfeel

## Problem

The nixarchy session starts Hyprland on the **store** copy of Omarchy's
`config/hypr/hyprland.lua` (`modules/nixos.nix`, `--config`), so a user can't
add a `require` to it. That file loads the user files in a fixed order:

    hypr.monitors → hypr.input → hypr.bindings → hypr.looknfeel →
    hypr.autostart → (hyprforge, added by nixarchy) → default.hypr.toggles

Layout settings (the master and monocle options, per-workspace defaults) need
to load **after** `looknfeel`, so they beat a theme's `looknfeel` block such as
Atmos's. They also need to load **before** `default.hypr.toggles`, so the
choices SUPER+L saved still win.

Two user files sit in that window. `hypr.hyprforge` is Hyprforge's own save
file, written by its GUI. `autostart.lua` is the only one a person or a
downstream config can take over. So
olafkfreund/nixos_config#2686 had to take over the whole of
`~/.config/hypr/autostart.lua` to `require("hypr.layouts")` from it. A
downstream config now owns a file the user is meant to edit for autostart, so
the user loses that file.

Asks 2 and 3 of #1596 are Omarchy's own code: SUPER+L cycling master and
monocle (`bin/omarchy-hyprland-workspace-layout-toggle`, `-current`), and bar
icons for both (`shell/plugins/bar/widgets/Workspaces.qml:138`). §11 sends a
change to how Omarchy behaves upstream, and nixarchy carries such a patch only
at the owner's request. They are listed here so the decision is recorded, not
designed.

## Proposed outcome

- The store `hyprland.lua` loads `~/.config/hypr/layouts.lua`, if it exists,
  immediately after `require("hypr.looknfeel")` and before
  `require("hypr.autostart")`. It uses Omarchy's own `require_optional`
  helper, as the Hyprforge line already does.
- **Precedence, stated:** `looknfeel` < `layouts` < Hyprforge's saves <
  SUPER+L's saved toggles. A declarative default loses to a choice made in a
  GUI or with a key.
- A machine with no `layouts.lua` behaves exactly as today.
- A downstream config can write `layouts.lua` and stop owning `autostart.lua`.
- `checks.session` proves the **order**, not just the load. It sets the same
  option to different values in `looknfeel.lua` and `layouts.lua` and reads
  back `layouts`' value with `hyprctl`. That fails if the require is missing,
  and also if it lands before `looknfeel` (codex and agy). The Hyprforge
  probe's "saved but never loaded" is the half this subsumes (§2).

## Affected users and systems

- `pkgs/omarchy/default.nix`, which gets one more `substituteInPlace` on the
  store `hyprland.lua`. The `data/bin-ledger.nix` row may not apply, since this
  isn't a `bin/` file, but the plan checks.
- `tests/session.nix`, which gets the probe.
- The manual's Hyprland page and `pkgs/AGENTS.md`, which name the load point.
- Downstream: olafkfreund/nixos_config, which can drop its `autostart.lua`
  takeover. That's a follow-up there, not part of this change.
- Edge: the same anchor has to exist in quattro's `hyprland.lua`, or edge's
  build fails on `--replace-fail`.

## Constraints

- **Mode A:** a user who never writes `layouts.lua` is untouched.
- **`--replace-fail`:** an upstream rewording of the `looknfeel` line must
  fail the build, not drop the load point silently.
- **Leave Hyprforge's line alone.** Hyprforge's Connect button matches its
  exact text (`pkgs/AGENTS.md#hyprforge-…`).
- Upstream files are not filed against unprompted (§11).
- **`checks.install-phase-budget`:** the in-phase comment is a `# Why:`
  pointer, and the explanation goes in `pkgs/AGENTS.md`.

## Open questions

1. Asks 2 and 3 (SUPER+L master and monocle, and the bar icons): carry them
   here as CARRIED patches at your request, or leave them for an upstream
   report you file yourself? Recommended: leave them out of this change. Each
   is a separate patch to Omarchy's code with its own check. Say if you want
   them carried, and they get their own intent.
2. The module name: `hypr.layouts` (`~/.config/hypr/layouts.lua`), as the
   issue proposes? Recommended: yes, since nixos_config#2686 already writes
   that name.
