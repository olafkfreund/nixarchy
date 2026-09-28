---
status: draft
issue: 1036
author: olafkfreund
---

# Intent: Keep the default omatheme integration current and verified

## Problem

Nixarchy already includes omatheme as its default runtime theme plugin and
imports its NixOS module. However, the Nixarchy flake pins omatheme at
`42b64ed`, while the omatheme repository has since merged runtime dependency
packaging, an opt-in browser target, and palette capture/restore actions.
The default integration therefore needs a current, tested dependency pin and
compatibility coverage so the published Nixarchy installation does not ship
stale plugin behavior.

## Proposed outcome

A fresh Nixarchy installation includes and enables a pinned omatheme revision
that contains the current runtime features. The runtime engine remains
available without Stylix, while Stylix users retain their declarative
application configuration as the stable template layer. Runtime palette
changes, supported target synchronization, and palette capture/restore work
without a NixOS rebuild.

Users who manage themes independently can opt out without losing the rest of
the Nixarchy desktop or plugin system.

## Affected users and systems

- Nixarchy fresh installs and the offline ISO.
- Existing Nixarchy configurations that enable the default plugin set.
- The flake input/lock, `modules/home.nix`, `modules/nixos.nix`, and tests.
- Stylix and non-Stylix NixOS configurations.
- The first-login default-plugin enablement hook and runtime session PATH.

## Constraints

- Pin the external plugin through the Nixarchy flake; do not fetch mutable
  source at activation time.
- Preserve the existing distinction between plugin presence and one-time
  enablement, including users who turn a plugin off later.
- Keep Stylix optional and do not replace its declarative ownership model.
- Ensure the offline ISO does not require network access at first login.
- Preserve the existing Mode A/Mode B option checks and default-plugin
  ownership model.
- Validate the plugin manifest and runtime package inputs during the build,
  not only when the menu is opened.

## Open questions

- Should Nixarchy pin the current omatheme `main` commit or a release/tag once
  one exists?
- Which compatibility checks are needed to ensure Nixarchy's default module
  and plugin manifest match the pinned omatheme outputs?
- Should the browser target remain opt-in because it writes browser-owned
  state? (The existing omatheme default is opt-in.)
