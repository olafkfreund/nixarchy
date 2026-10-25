---
status: approved
issue: 1452
author: x
---

# Intent: a check that omarchy-default-agent's nixpkgs mapping is real

## Problem

`attr_for()` in `pkgs/omarchy/nix-bin/omarchy-default-agent` maps an agent id
to the nixpkgs attribute `nixarchy-pkg-add` installs. The script then
expects the command named by the id. Nothing checks either half. A nixpkgs
bump that renames an attribute or changes a `mainProgram` would make a menu
row install the wrong thing or nothing, silently. #1447 nearly mapped `amp`
to a text editor.

## Proposed outcome

A pull-request check fails, naming the arm, when an `attr_for` attribute is
missing from the flake's nixpkgs or does not install the command the id
names.

## Affected users and systems

CI only: one new `checks.<name>` and its test file. Nothing ships.

## Constraints

- Evaluation-cheap, and it must not abort a batch with an eval error (§13).
- No second copy of the mapping: parse the script (§4).

## Open questions

None.
