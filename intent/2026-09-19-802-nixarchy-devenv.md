---
status: approved
issue: 802
author: olafkfreund
---

# Intent: nixarchy-devenv replaces the built-in devenv handling, on by default

Closes #802. Companion to olafkfreund/nixarchy-devenv#1.

## Problem

Per-project environments are one of the things nixarchy does that Omarchy
does not, and they are still a terminal job. `nixarchy dev init <preset>`
(`pkgs/dev-init.nix`, 186 lines) scaffolds a devenv project from one of eight
presets in `data/devenv-presets.nix`: go, jupyter, ml, node, python, react,
rust, typescript. After that there is nothing: no list of your environments,
no way to allow, update, start processes or remove one except by hand. Every
other nixarchy feature of this kind now has a panel on a key.

[nixarchy-devenv](https://github.com/olafkfreund/nixarchy-devenv) is that
panel, plus a `nixarchy-devenv` CLI (plugin id `nixarchy.devenv`, kinds menu
and bar-widget, bar section right). It lists every devenv environment under
your project roots, allowed ones first. From there you can:
- enter an environment in a terminal, or edit its `devenv.nix`;
- start or stop its processes, check them, update its lock, allow or revoke it;
- remove it in steps from revoke to delete, or run `devenv gc`;
- create a project from a template, with create and update streaming their log
  into the panel.

It owns the template catalogue: all eight of nixarchy's presets moved there
unchanged, plus cloud, dotnet, flutter, java, java-maven, kotlin, php and
ruby. Keeping two catalogues would be drift waiting to happen, so the built-in
one goes.

## Proposed outcome

- A normal nixarchy install has the Dev environments panel on Super+Alt+E and
  in the menu, installed and enabled once, like the other default plugins.
- **Nothing a user types today breaks.** `nixarchy dev init <preset>` still
  works, now dispatched to `nixarchy-devenv`, and every preset name existing
  docs mention (`python.md` links `nixarchy dev init ml` and `jupyter`) still
  resolves.
- The built-in scaffolder and preset list are removed: `pkgs/dev-init.nix`,
  `data/devenv-presets.nix`, and the `devenv-presets` runner in `flake.nix`
  (`:998-1060`) that CI uses to scaffold every preset. The plugin repo's
  `templates-check.nix` takes over that proof.
- The manual (`per-project-environments.md`, `python.md`, the README row)
  describes the panel and the new templates.

## Affected users and systems

- **Every nixarchy desktop:** a new default plugin and key.
- **`flake.nix`:** a new input, and the `devenv-presets` package and app removed.
- **`modules/apps.nix`:** `dev-init` removed from the installed commands
  (`:2951-2957`), and the `nixarchy dev` dispatch retargeted (`:3029-3031`).
- **`modules/home.nix`:** a `defaultPluginSet` entry.
- **`pkgs/omarchy/default.nix`:** the seed bind.
- **CI:** `build.yml`'s `devenv-presets` job (`:223-270`), and branch
  protection.
- **Stale comments:** `pkgs/dev-init.nix` is cited as a pattern in comments in
  `pkgs/microvm.nix`, `pkgs/box.nix`, `pkgs/secret.nix`,
  `data/box-templates.nix` and `data/microvm-templates.nix`. Those references
  go stale and need rewording.
- **The demo recorder:** `tests/demo/default.nix:441` names `devenv-presets`.

## Constraints

- **`devenv-presets` is a required status check on `main`.** Branch protection
  lists: lint, omarchy, system, devenv-presets, box, install. Removing or
  renaming the `build.yml` job is a workflow change *and* a branch-protection
  change. Both are human-only (AGENTS.md §4, §11). The PR proposes them and Olaf
  makes them; an agent does not. If the job simply vanished, every later PR
  would wait forever on a required check that never reports.
- **The plugin's code is not on its `main` yet.** It lives on
  `feat/1-devenv-plugin`, and its issue #1 is open. nixarchy pins a commit on
  the plugin's `main` once that merges, with `inputs.nixpkgs.follows`.
- **Mode A:** importing the module with nothing enabled changes nothing, proved
  across the Home Manager fixture split, the same as the other default plugins.
- **Licence:** public, with an MIT `LICENSE` file ("Copyright (c) 2026
  olafkfreund"); `manifest.json` says MIT. GitHub's licence detection reports
  none, the same lag seen on ghtui. The LICENSE file must ship in the package
  output.
- **Key:** Super+Alt+E is free. It is not bound upstream, and not among
  nixarchy's seeded Super+Alt keys (N, O, P, A, H, D, V). The owner's machine
  already binds it to this plugin through its Home Manager module. nixarchy uses
  its own seed-bind mechanism and does not import that module, as with microvm.
- Every new check is broken first (§1).

## Open questions

1. **"On by default" versus devenv being off by default.**
   `programs.nixarchy.services.devenv.enable` is an `mkEnableOption` (off), and
   the panel is useless without `devenv` installed. Options:
   - (a) gate the plugin on that service, as Podman follows podman;
   - (b) turn the devenv service on by default;
   - (c) install the plugin everywhere and let it say "devenv is not
     installed".

   Recommendation: (a), because it keeps "a panel with nothing behind it" out,
   which is the rule the other defaults follow.
2. **The `devenv-presets` check's replacement.** The plugin repo's
   `templates-check.nix` proves its own templates in its own CI. Is that
   enough, or should nixarchy keep a check that scaffolds the pinned plugin's
   templates on every PR, under the same required-check name, so branch
   protection stays unchanged?
3. **The `cloud` template** draws on `cloud-projects-templates` as a flake
   source. Does creating a project from it need network access at create time
   (offline installs)? Not verified.

**Decided on approval (owner, 2026-09-19):** the panel is gated on `services.devenv.enable`, the way Podman follows podman. nixarchy keeps a check under the required name `devenv-presets`, so branch protection does not change. Pinning waits for the plugin's code to reach its `main`.
