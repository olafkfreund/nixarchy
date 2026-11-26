---
status: approved
issue: 1950
author: x
---

# Intent: the Omarchy session starts when ~/.config/hypr lacks its files

Approved by the owner's standing pre-approval and "we also need to fix #1950 as
fast as possible" (2026-11-26).

## Problem

A user on a fresh install logs in and Hyprland shows `module 'hypr.monitors'
not found`. The session runs the packaged `hyprland.lua` (`modules/nixos.nix:133`),
which hard-requires `hypr.{monitors,input,bindings,looknfeel,autostart}` from
`~/.config/hypr`. Only the Home Manager seed creates those, so any account it
has not run for (a second account, Mode A without the per-user step, a failed
activation) gets a broken desktop. Every VM check logs in as `omarchy`, whose
seed has run (§3).

## Proposed outcome

A missing user file falls back to the shipped default; a user's own file still
wins and an error inside it still shows.

## Affected users and systems

Everyone who logs into the Omarchy session. No host change.

## Constraints

Must not change what an existing user file does. Must not hide a Lua error in
a user's file. A check must fail without the fix (§1).

## Open questions

None.
