---
status: approved
issue: 1950
spec: spec/2026-11-26-1950-hypr-shipped-fallback.md
coders:
  1: codex # the Lua harness: stubbing Hyprland's API is the tricky part
  2: codex # one substitution
  3: codex # one list entry
reviewers:
  - codex # its own review pass on the diff
---

# Plan: the Omarchy session starts when ~/.config/hypr lacks its files

Approved by the owner's standing pre-approval (2026-11-26).

Decisions: append `<OMARCHY_PATH or /usr/share/omarchy>/config/?.lua` to
`package.path` right after the bootstrap `dofile` in the packaged
`config/hypr/hyprland.lua`; user files win, user errors still raise.

## Steps

1. `tests/hypr-seedless.nix` (new): a `runCommand` with `pkgs.lua5_4` (or the
   Lua Hyprland embeds) that sets `OMARCHY_PATH` to the built package's
   `share/omarchy`, stubs the globals the config touches (read
   `default/hypr/*.lua` for what it calls: `hl`, `hyprland`, etc.; stub every
   call as a no-op that records), and runs `config/hypr/hyprland.lua` with
   `HOME` set to: an empty dir (must succeed, and a marker shows the shipped
   `hypr.monitors` loaded); a home whose `.config/hypr/monitors.lua` sets a
   marker (must load that one); a home with a syntax error in
   `.config/hypr/input.lua` (must fail and name the file). → red before step 2
   (the empty home fails with `module 'hypr.monitors' not found`).
   Traps: `''` string, no heredoc, printf fixtures (§5); `git add` the file;
   no `! cmd` assertions.
2. `pkgs/omarchy/default.nix`, beside the #1596 substitution: a
   `substituteInPlace ... --replace-fail` on the bootstrap `dofile(...)` line
   that appends the `package.path` line with `-- nixarchy: shipped defaults
   for a missing ~/.config/hypr file (#1950)`. → step 1's check passes.
3. `flake.nix` checks name list: `"hypr-seedless"` with a one-line comment. →
   `generated-checks.sh generated` lists it.

## Tests

§1 red/green of step 1; every generated check; `nix fmt -- --ci`;
`checks.grep-q-pipefail`.

## Rollback

Revert the commit.
