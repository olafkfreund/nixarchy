---
status: draft
issue: 1132
author: olafkfreund
---

# Intent: Bound the keybindings menu's Lua scan

## Problem

The shipped `omarchy-menu-keybindings` runs `lua` with no deadline while it
reads the user's `~/.config/hypr/hyprland.lua`. Its stub Hyprland API cannot
make every user script progress. A loop such as `while true do end` keeps the
scan alive, and opening the menu again can leave another Lua process consuming
CPU. The pinned Omarchy script calls `build_lua_bind_cache` from
`output_binding_records_uncached`; the unbounded `lua <<'LUA'` is in the
process substitution at lines 65-78 of the installed 4.0.4 script.

The issue's missing-`coreutils` claim does not hold for this tree:
`pkgs/omarchy/default.nix:15,185-186` already puts `coreutils`, including
`timeout`, in `runtimeDeps`, and `modules/nixos.nix:1204-1208` installs those
dependencies beside the Omarchy package. The script is copied from the pinned
Omarchy input into `$out/share/omarchy/bin` at
`pkgs/omarchy/default.nix:410-435`; this repository currently has no patch
for its Lua scan.

## Proposed outcome

Opening the keybindings menu cannot leave a Lua bind scan running indefinitely.
The scan stops after a short deadline, and ordinary bindings remain usable
when Lua bindings cannot be read. A check exercises the built Omarchy script
against a looping user Lua file, proves the old behavior fails, and confirms
the fixed run ends without a surviving scan process.

## Affected users and systems

- Omarchy shell users who open the keybindings menu, especially those with a
  user Lua config that waits on a real Hyprland call or loops against the scan's
  stub API.
- The pinned Omarchy package patch in `pkgs/omarchy/default.nix` and a cheap
  package-level check in `tests/`; no host or upstream repository changes.

## Constraints

- Patch the copied upstream script with a failing anchor, so an upstream
  rewording cannot silently remove the deadline. Keep the package's existing
  `coreutils` runtime dependency; do not add it twice.
- Preserve the no-Lua path and the menu's other binding sources. Timeout is a
  graceful loss of supplemental Lua-derived bindings for that scan, not a
  reason to leave the menu spinning.
- The test must use the built package script, bound its own broken-case run,
  and clean up only processes it started by PID. No broad process kill.
- This is an intent gate: no package build, test run, patch, push, or PR yet.

## Open questions

1. **Deadline:** Recommend `timeout 3 lua` at the single process substitution.
   Three seconds bounds a menu interaction while allowing an ordinary config
   scan to finish. Measure a normal scan in the later check before changing it.
2. **Timeout behavior:** Recommend treating an expired Lua scan like absent
   Lua: omit Lua-only bind metadata for that invocation and continue with the
   other binding sources. Keep any diagnostic to stderr so menu output remains
   parseable.
3. **Proof:** Recommend a cheap check that invokes the built script with a
   `while true do end` user config, verifies a bounded return and no surviving
   Lua process, and first goes red when the deadline patch is removed. The
   harness must terminate only its own test processes on the red run.
