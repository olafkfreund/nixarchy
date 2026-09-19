---
status: approved
issue: 802
spec: spec/2026-09-19-802-nixarchy-devenv.md
---

# Plan: nixarchy-devenv replaces the built-in devenv handling, on by default

Branch `feat/802-nixarchy-devenv`, already carrying the intent and the spec.
One commit per step, each subject a full sentence (AGENTS.md §8). A deviation
updates this file in the same commit as the code.

## Approved decisions

Copied from the spec so this file stands alone.

- **Pin:** `nixarchy-devenv` at **`e003f00`**, the merge of its #1 on its
  `main`, with `inputs.nixpkgs.follows = "nixpkgs"`. Verified at that commit:
  `packages.<sys>` is `{ cli, default, plugin }` (`default` = `plugin`),
  `templates-check` is an **app** (so the runner reads
  `apps.<sys>.templates-check.program`), `homeManagerModules.default` exists
  and nixarchy does **not** import it, and the template ids include all eight
  former presets.
- **The panel is a default where devenv is.** `defaultPluginSet.devenv` with
  `id = "nixarchy.devenv"`, `src = …packages.<sys>.plugin`,
  `packages = [ …packages.<sys>.cli ]`, and
  `gate = osConfig.programs.nixarchy.services.devenv.enable or false` — the way
  Podman follows podman. `defaultPlugins.devenv = true`, opt-out as usual.
- **`nixarchy dev init <preset>` keeps working**, dispatched to the plugin's
  CLI. Where devenv is off the CLI is not installed, so the dispatch itself
  prints the guidance naming `programs.nixarchy.services.devenv.enable` and
  exits 1, which is what `nixarchy-dev-init` does today.
- **Removed:** `pkgs/dev-init.nix`, `data/devenv-presets.nix`, and
  `nixarchy-dev-init` from the installed commands.
- **`devenv-presets` keeps its name.** It stays a `build.yml` job running
  `nix run .#devenv-presets`; only what the attribute runs changes, to the
  pinned plugin's templates check over the eight former preset ids. **No
  workflow edit and no branch-protection change** (§4, §11).
- **Menu:** an Apps row `apps.devenv`, through `nixarchy-plugin`, gated by
  `nixarchy-plugin --enabled`. **Seed bind Super+Alt+E**, new installs only.
- **`cloud` stays out of the required check**: it needs the network at create
  time. Offline create is out of scope.
- **Mode A stays inert**: standalone Home Manager resolves no defaults.

## Steps

1. **`flake.nix`: the input.** Add `nixarchy-devenv` beside the other plugin
   inputs (`:191-235`), pinned at `e003f00`, `inputs.nixpkgs.follows`.
   → verify by `nix flake metadata` showing the node, and `git diff flake.lock`
   adding one node and no second nixpkgs.
2. **`modules/home.nix`: the default.** A `defaultPluginSet.devenv` entry next
   to `microvm` (`:1536+`), and `devenv = true` in `defaultPlugins`' default
   (`:610-620`) with its description extended to name it and its gate.
   → verify by step 7's `checks.options` cases (written first, red).
3. **`modules/apps.nix`: the command and the dispatch.**
   - drop `(pkgs.callPackage ../pkgs/dev-init.nix { })` and its comment
     (`:2948-2957`);
   - `dev)` (`:3029-3033`) becomes: with `nixarchy-devenv` on PATH, `exec` it
     with the remaining arguments (so `dev init`, `dev list`, `dev templates`
     all reach it); without it, print the devenv guidance and exit 1;
   - the help line (`:3111`) gains the panel and the key.
   → verify by step 7's dispatch cases (red first).
4. **`modules/apps.nix`: the menu row.** `apps.devenv` after
   `apps.github-actions` (`:372`), icon `󱄅`, label "Dev environments", action
   `nixarchy-plugin nixarchy.devenv`, `when` its `--enabled`, aliases
   (devenv, environments, projects, dev shell), description ending
   "· Super+Alt+E".
   → verify by `checks.menu-verbs` with its plugin-row floor raised from 7 to
   8 (`tests/menu-verbs.nix:165`).
5. **`pkgs/omarchy/default.nix`: the seed bind.** One line after the
   Distrobox seed (`:1955`):
   `o.bind("SUPER + ALT + E", "Dev environments", "nixarchy-plugin nixarchy.devenv")`.
   → verify by the seed-anchor assertion in the omarchy build, broken first.
6. **`flake.nix`: `devenv-presets` runs the plugin's check.** Replace the body
   of `packages.devenv-presets` (`:998-1060`) with a `writeShellApplication`
   named `devenv-presets` that execs
   `${inputs.nixarchy-devenv.apps.<sys>.templates-check.program}` with the
   eight ids (go, jupyter, ml, node, python, react, rust, typescript). Keep a
   header saying why the name is fixed (required status check) and what the
   old runner got wrong (`HOME` moved, `XDG_DATA_HOME` inherited, 80 dead
   entries in the caller's devenv trust list).
   → verify by `nix run .#devenv-presets` (network) passing, and by the
   break-first in step 9.
7. **Delete the built-ins and reword what cites them.** Remove
   `pkgs/dev-init.nix` and `data/devenv-presets.nix`. Reword the comments that
   cite dev-init as a pattern, to cite `pkgs/box.nix`: `pkgs/microvm.nix`,
   `pkgs/box.nix`, `pkgs/secret.nix`, `data/box-templates.nix`,
   `data/microvm-templates.nix`, and `tests/demo/default.nix:441`.
   → verify by `grep -rn 'dev-init\|devenv-presets.nix'` finding nothing
   outside `intent/`, `spec/`, `plan/` and this PR's docs.
8. **Tests, each broken first (§1).**
   - `tests/options.nix`: `devenvIsADefault` (present with the devenv service
     on and listed in the enable hook; absent with it off, opted out,
     standalone, or nixarchy off) and `devenvLicence` (the plugin package
     carries `LICENSE`). Fixtures: a `devenvOn`/`devenvOff` pair like
     `boxesOn`/`boxesOff`, and `devenv = false` in the opt-out fixture
     (`:138`).
   - the dispatch, as a runtime case in `checks.options` in the style of
     `nixarchy-plugin`'s: with a stub `nixarchy-devenv` on PATH,
     `nixarchy dev init ml` runs it with `init ml`; without one, the output
     names `services.devenv.enable` and the status is 1.
   - `tests/menu-verbs.nix`: floor 7 → 8.
   → verify by each assertion failing before the code exists, with its message
   quoted in the PR.
9. **Break-first proofs, recorded for the PR.** For each: break, run, capture
   the message, restore with `git checkout HEAD --`.
   - `checks.options`: no `defaultPluginSet.devenv` entry → `devenvIsADefault`
     fails; `src` pointed at a copy without `LICENSE` → `devenvLicence` fails;
     dispatch pointed back at `nixarchy-dev-init` → both dispatch cases fail.
   - `checks.menu-verbs`: misspell the row's id → the row-id scan fails.
   - `devenv-presets`: add `nosuchpreset` to the id list → the run fails
     naming it.
   - the seed anchor: point it at a line that does not exist → the omarchy
     build fails.
10. **Docs.**
    - `docs/manual/per-project-environments.md`: the panel is the subject; the
      key, the tiers, the templates, and `nixarchy dev init` as the terminal
      form. Say that `devenv allow` is no longer implicit and that a new
      project gets `git init` by default — both are behaviour changes.
    - `docs/manual/python.md` (the `ml` and `jupyter` links),
      `docs/manual/development-tools.md`, `docs/manual/plugins.md` (a new
      entry, and the count), `docs/manual/configuration.md` (the opt-out),
      `README.md` (feature row and any count), `docs/index.md`,
      `docs/llms.txt`, `docs/internals/flake.md` (the input's reason, its
      closure, the pin-bump procedure, and the `devenv-presets` change),
      `docs/internals/workflows.md` if it describes that job,
      `modules/AGENTS.md` and `tests/AGENTS.md` (one line each, in the house
      "Why:" style), and `pkgs/omarchy/skills/devenv/SKILL.md`.
    → verify by `checks.readme-counts` and the docs nav check in
    `nix flake check`.
11. **Whole-repo verification.** `nix flake check`, then
    `nix flake check --all-systems --no-build`, then `nix run .#devenv-presets`.
    → verify all green, and quote `devenv-presets`' summary line in the PR.
12. **On p620, before the PR.** Remove the hand-installed test copies this
    work left, so the machine matches what the PR ships:
    `~/.config/omarchy/plugins/nixarchy.devenv`, the
    `~/.local/bin/nixarchy-devenv` symlink, `~/.config/hypr/devenv-binds.lua`,
    and the `pcall(require, "hypr.devenv-binds")` block appended to
    `~/.config/hypr/bindings.lua`. Then build the host's closure without
    switching (`nix build .#nixosConfigurations.p620.config.system.build.toplevel`).
    → verify by the build succeeding and `hyprctl binds` no longer showing a
    Super+Alt+E bind from the hand-copied file. Applying is the owner's.
13. **PR.** Against `main`, closing #802, linking intent, spec and plan, with
    the break-first messages, the `devenv-presets` timing, and the two notes
    for the owner: the double-declaration if they re-add their own Home
    Manager import, and the 80 stale entries in their devenv trust list, which
    only they should clear (`devenv revoke`, or editing
    `~/.local/share/devenv/allowed`).

## Tests

| Command | Expected |
| --- | --- |
| `nix flake check` | green, `checks.options` and `checks.menu-verbs` included |
| `nix flake check --all-systems --no-build` | aarch64 evaluates |
| `nix run .#devenv-presets` | the eight ids scaffold and evaluate through the pinned plugin; the caller's devenv allow list is unchanged |
| `nix build .#nixosConfigurations.p620.config.system.build.toplevel` | builds |
| each break-first in step 9 | fails with the message quoted in the PR |

## Rollback

- **Before merge:** the branch is self-contained; drop it.
- **After merge:** revert the merge commit. The plugin is a flake input and a
  default-plugin entry, so a revert removes the input, the entry, the row and
  the seed bind, and restores `pkgs/dev-init.nix` and
  `data/devenv-presets.nix` with the old `devenv-presets` runner, under the
  same required-check name.
- **For a user:** `programs.nixarchy.defaultPlugins.devenv = false` stops the
  install and the enable without touching their `shell.json`; a panel they
  already turned on stays on until they turn it off in Setup ▸ Plugins.
  Projects created with it are ordinary devenv projects and keep working.
