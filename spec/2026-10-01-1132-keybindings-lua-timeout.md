---
status: approved
issue: 1132
intent: intent/2026-10-01-1132-keybindings-lua-timeout.md
---

# Spec: Bound the keybindings menu's Lua scan

## Design

The pinned Omarchy 4.0.4 `bin/omarchy-menu-keybindings:65-78` calls
`build_lua_bind_cache` and starts `lua <<'LUA'` in a process substitution.
Its stub API executes the user's `hyprland.lua` at line 228. A nonterminating
config keeps that producer alive and the menu waiting for its pipe.
`output_binding_records_uncached` calls the scan before reading Hyprland and
static bindings at lines 439-455.

In `pkgs/omarchy/default.nix:410-435`, where the pinned tree is copied into
`$out/share/omarchy`, add one `substituteInPlace --replace-fail` for that
script's exact `lua <<'LUA'` command, changing it to `timeout 3 lua <<'LUA'`.
The shell's process-substitution reader then reaches EOF after the timeout
and continues with the existing dynamic and static binding paths. An absent
Lua executable keeps the existing `omarchy-cmd-present lua || return 0` path.
No configuration file or upstream repository changes. `coreutils` already
supplies `timeout` in `runtimeDeps` at `pkgs/omarchy/default.nix:15,185-186`;
`modules/nixos.nix:1204-1208` includes those dependencies in the installed
profile. Do not add a duplicate package declaration.

Register a cheap `tests/keybindings-lua-timeout.nix` check in the uniform
checks list in `flake.nix:1759-1911`. It runs the **built** Omarchy package's
`omarchy-menu-keybindings --print` with a temporary HOME whose user
`hyprland.lua` is `while true do end`. Supply a real Lua executable and
minimal `hyprctl`/`xkbcli` stubs so the rest of the menu runs without a
desktop. The check bounds the outer command, asserts it finishes promptly,
asserts the static bindings remain visible, and records the scan's PID so it
can assert no Lua process survives. Its cleanup kills only its own recorded
PID, including on a red run. An ordinary terminating Lua config remains a
positive control for Lua-derived bindings. Omarchy's bins are symlinks, not
`writeShellApplication` wrappers (`pkgs/omarchy/default.nix:426-435`), so the
check also runs ShellCheck explicitly on the patched script.

## Alternatives rejected

- Skip the Lua bind cache entirely: users would permanently lose the extra
  key and dispatcher metadata that the menu reconstructs for Lua bindings.
- Parse Lua statically or add a custom execution sandbox: both duplicate a
  complex upstream parser when a process deadline solves the runaway case.
- Add `coreutils` again: it is already in the runtime dependency list, so
  another declaration would not improve the installed PATH.
- Use an outer menu timeout only: it could leave the Lua child consuming CPU
  after the menu exits, which is the reported failure.

## Risks

- A legitimately slow Lua config loses its supplemental Lua-derived binding
  metadata after three seconds for that menu opening. The normal Hyprland and
  static binding sources still run. The check should measure a simple config
  as a positive control; changing the deadline needs measured evidence.
- The built package includes no ShellCheck wrapper for vendored scripts, so a
  syntax error in the patched command would otherwise escape package build.
- A timeout must stop the Lua process itself. A check that only observes the
  menu's exit would miss a surviving child; the PID assertion is required.

## Verification

1. Build the Omarchy package under the shared build lock after the repository
   CI-load gate for non-cheap builds. A reworded upstream command fails the
   `--replace-fail` anchor.
2. Run the cheap registered check against the patched package. Before the
   fix, or with the timeout patch removed using a copy-aside restore, it must
   fail because the looping scan exceeds the outer bound; the harness then
   terminates only its recorded child PID. Capture that red output.
3. Restore the patch and show the same check green: the menu returns within
   the bound, static bindings remain, the loop's Lua PID is gone, and a
   terminating Lua config still contributes a Lua binding. Put red and green
   lines in the PR.
4. Run `nix fmt -- --ci`, statix and deadnix for the Nix changes; inspect
   `git diff --stat` after formatting. Stage new files before flake builds.
