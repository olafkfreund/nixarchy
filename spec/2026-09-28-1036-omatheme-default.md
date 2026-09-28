---
status: draft
issue: 1036
intent: intent/2026-09-28-1036-omatheme-default.md
---

# Spec: Keep the default omatheme integration current and verified

## Design

Keep Nixarchy's existing ownership split:

- `modules/nixos.nix` imports the omatheme NixOS module for the runtime
  engine.
- `modules/home.nix` owns installation of the default plugin manifest and its
  one-time enablement behavior.
- Stylix remains optional and continues to provide declarative application
  templates where configured; omatheme provides runtime palette switching for
  Stylix and non-Stylix installations.

Update the `nixarchy-omatheme` flake input and lock entry to the current merged
revision `45b15e4389893c17d494557338addab2d15681f7`, which includes the runtime
dependency packaging, opt-in browser target, and palette capture/restore
actions. Keep the input pinned by commit so offline images and installed
systems use the same source.

Extend the existing Nixarchy checks only where needed to prove that the pinned
input still exposes the package and module consumed by the integration. Keep
the browser target opt-in and preserve the existing Mode A, Mode B, Stylix,
non-Stylix, and user opt-out behavior.

## Alternatives rejected

- Re-implementing omatheme integration in Nixarchy: the default module and
  plugin ownership are already merged and tested in `main`.
- Floating the GitHub branch: it would make offline images and evaluations
  non-reproducible.
- Copying omatheme's plugin or runtime files into Nixarchy: it duplicates
  ownership and would make updates drift between repositories.
- Enabling the browser target by default: it writes browser-owned state and is
  explicitly opt-in in omatheme.

## Risks

- The newer omatheme revision could change a flake output or module option
  consumed by Nixarchy; evaluation and plugin checks must catch this.
- Updating the lock may increase the offline image closure; the existing
  package dependency check should expose unexpected runtime additions.
- Existing users who opted out must not receive the plugin again; the current
  one-time default-plugin marker behavior must remain covered.

## Verification

- `nix flake check --all-systems --no-build` passes for Nixarchy.
- Existing option tests pass for default, opt-out, Mode A, Mode B, Stylix, and
  non-Stylix fixtures.
- The pinned input evaluates the `nixosModules.default` module and
  `omarchroma-plugin` package used by Nixarchy.
- The diff contains no changes under the user's NixOS config directory and
  does not enable the browser target by default.
