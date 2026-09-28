---
status: approved
issue: 1044
author: olafkfreund
---

# Intent: Pin omatheme editor targets into Nixarchy

## Problem

Nixarchy currently pins an older nixarchy-omatheme revision. It includes the
Foot 1.28 compatibility fix, but not the merged runtime targets for Vim,
Neovim, and LazyVim. Razer therefore cannot receive the complete runtime theme
engine through the normal Nixarchy rebuild.

## Proposed outcome

Nixarchy pins the merged nixarchy-omatheme revision `935bb2b`, so its default
theme engine includes Foot validation and live Vim/Neovim editor bridges while
preserving the existing declarative integration.

## Affected users and systems

Nixarchy users using the default omatheme integration, especially the Razer
host used for deployment validation and offline/system builds.

## Constraints

- Update only the Nixarchy omatheme input and its lock data.
- Keep the change declarative and reproducible.
- Do not edit any host's generated NixOS configuration outside this repository.
- Validate evaluation, build/install checks, and live runtime behavior on Razer.

## Open questions

None.
