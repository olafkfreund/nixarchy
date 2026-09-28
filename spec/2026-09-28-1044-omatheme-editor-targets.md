---
status: draft
issue: 1044
intent: intent/2026-09-28-1044-omatheme-editor-targets.md
---

# Spec: Pin omatheme editor targets into Nixarchy

## Design

Update the `inputs.nixarchy-omatheme.url` pin in `flake.nix` from
`ed384a0acc534d49faeac6dfbaf31f22586b64cb` to the merged omatheme commit
`935bb2b25f40cd735439e99b8d6b6ef1b6601b46`, then refresh the corresponding
`flake.lock` node without changing unrelated inputs.

The existing Nixarchy module wiring remains unchanged. The new input revision
provides the editor target options and runtime bridges transitively through the
current theme-engine integration.

## Alternatives rejected

- Updating to a moving `main` URL: breaks reproducibility for offline images
  and installed systems.
- Copying editor bridge files into Nixarchy: duplicates ownership and bypasses
  the omatheme package.
- Editing a host's generated NixOS configuration: the shared Nixarchy flake is
  the declarative source of truth.

## Risks

The newer input may expose evaluation or build incompatibilities in Nixarchy's
module wiring. CI must catch these before deployment. Razer's current runtime
files are from an older generation and will only change after a successful
rebuild and user-session service restart.

## Verification

- Evaluate and build the affected Nixarchy outputs.
- Run the repository's required checks, including install/system checks.
- Confirm the lock diff contains only the intended omatheme and nested
  Omarchroma revisions.
- Deploy to Razer and verify Foot, Vim, Neovim/LazyVim, terminal/shell targets,
  and live theme switching.
