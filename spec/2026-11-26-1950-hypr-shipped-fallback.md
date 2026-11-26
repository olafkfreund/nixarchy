---
status: approved
issue: 1950
intent: intent/2026-11-26-1950-hypr-shipped-fallback.md
---

# Spec: the Omarchy session starts when ~/.config/hypr lacks its files

Approved by the owner's standing pre-approval (2026-11-26).

## Design

In `pkgs/omarchy/default.nix`, beside the existing `hyprland.lua`
substitutions (#1059, #1596), append the shipped config directory to Lua's
search path right after the bootstrap `dofile`:

`package.path = package.path .. ";" .. (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/config/?.lua"`

Bootstrap puts `$HOME/.config` and `$HOME/.local/state` first, so a user's
`hypr/monitors.lua` is found before the shipped `config/hypr/monitors.lua`;
only an absent file falls through. An error inside a user file still raises.
Codex reproduced the reported error with Omarchy 4.5.0 and an empty home, and
the fix in a Lua sandbox (diagnosis on #1950's team, 2026-11-26).

`checks.hypr-seedless` (new, cheap): run the packaged `hyprland.lua` under a
Lua interpreter with Hyprland's API stubbed, `OMARCHY_PATH` at the built tree,
and three homes: empty (must load, and must have loaded the shipped
`hypr.monitors`), a user `monitors.lua` (must load the user's, not the
shipped one), and a user file with a syntax error (must fail naming it).

## Alternatives rejected

- Seeding from the session launcher: duplicates the Home Manager seed's
  logic for five files and still leaves a Mode A user's other files unseeded.
- `require_optional` for the five: a missing `autostart` or `bindings` would
  give a session with no bar and no keys, silently.
- Patching upstream: on Arch the installer always writes these files, so
  upstream has no bug; this is ours.

## Risks

A user who deleted `bindings.lua` on purpose now gets the shipped bindings.
That matches what a fresh seed would give them.

## Verification

`checks.hypr-seedless` red before the substitution, green after; the
generated checks; `checks.session` is unchanged in behaviour and runs in CI.
