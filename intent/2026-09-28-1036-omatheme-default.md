---
status: approved
issue: 1036
author: olafkfreund
---

# Intent: Include omatheme as the default Nixarchy runtime theme plugin

## Problem

Nixarchy currently provides the Omarchy desktop and its plugin framework, but
the omatheme runtime engine is maintained separately and is not part of a
fresh Nixarchy installation. Users must discover and add it manually, so
Stylix and non-Stylix installations do not receive the same coordinated
runtime theme switching experience.

## Proposed outcome

A fresh Nixarchy installation includes and enables the pinned omatheme plugin
for the session user. The runtime engine is available without Stylix, while
Stylix users retain their declarative application configuration as the stable
template layer. Runtime palette changes, supported target synchronization, and
palette capture/restore work without a NixOS rebuild.

Users who manage themes independently can opt out without losing the rest of
the Nixarchy desktop or plugin system.

## Affected users and systems

- Nixarchy fresh installs and the offline ISO.
- Existing Nixarchy configurations that enable the default plugin set.
- `modules/home.nix`, the flake input set, and plugin validation/checks.
- Stylix and non-Stylix NixOS configurations.
- The first-login default-plugin enablement hook and runtime session PATH.

## Constraints

- Pin the external plugin through the Nixarchy flake; do not fetch mutable
  source at activation time.
- Preserve the existing distinction between plugin presence and one-time
  enablement, including users who turn a plugin off later.
- Keep Stylix optional and do not replace its declarative ownership model.
- Ensure the offline ISO does not require network access at first login.
- Add option checks for both Mode A (existing configuration) and Mode B
  (installer-managed configuration).
- Validate the plugin manifest and any runtime package inputs during the
  build, not only when the menu is opened.

## Open questions

- Which flake output should be pinned: the plugin package, the complete
  `nixarchy-omatheme` flake input, or both the package and module?
- Which default target options should Nixarchy enable on first login, and
  which must remain opt-in because they write browser-owned state?
- Should the default plugin be enabled on existing installations immediately
  or only on fresh installs?
