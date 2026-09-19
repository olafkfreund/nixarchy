---
status: draft
issue: 802
intent: intent/2026-09-19-802-nixarchy-devenv.md
---

# Spec: nixarchy-devenv replaces the built-in devenv handling, on by default

## Design

### Blocked until the plugin is on its `main`

nixarchy pins the plugin by commit, following the nixi precedent: commit pin,
`inputs.nixpkgs.follows = "nixpkgs"`. The plugin's code currently lives only on
`feat/1-devenv-plugin` (head `2f9299b`), and olafkfreund/nixarchy-devenv#1 is
open. **A PR for #802 is merge-ready only when:**
- nixarchy-devenv#1 has merged to its `main`;
- the pin is a commit on that `main`;
- the pinned plugin still exposes what this design uses: `packages.plugin`,
  `packages.cli`, `apps.templates-check`, and template ids that include the
  eight former presets.

Implementation can start against the feature-branch commit, but the pin moves
before merge.

### The plugin, on by default when devenv is

This follows the pattern #780, #782, #786 and #803 established.
- A new flake input, `nixarchy-devenv`. `defaultPluginSet.devenv` takes
  `id = "nixarchy.devenv"`, `src = inputs.nixarchy-devenv.packages.<sys>.plugin`
  and `packages = [ <sys>.cli ]`. The CLI is `nixarchy-devenv`, on the session
  PATH like the other plugins' tools.
- **Gate:** `osConfig.programs.nixarchy.services.devenv.enable or false`,
  decided on approval, the way Podman follows podman. Without devenv the panel
  would have nothing behind it.
- `defaultPlugins.devenv = true`, with the usual opt-out.
- **LICENSE:** the plugin's package already copies `./LICENSE`
  (`nixarchy-devenv/flake.nix:18-30`), so no wrapper is needed. That's asserted
  in `checks.options`, like the other defaults.
- **Menu:** an Apps row, `apps.devenv` ("Dev environments"), through
  `nixarchy-plugin`, gated the same way. Seed bind **Super+Alt+E** for new
  installs, appended to the existing seed-bind list in
  `pkgs/omarchy/default.nix`.

### The built-in scaffolder goes; `nixarchy dev init` keeps working

- **Removed:** `pkgs/dev-init.nix`, `data/devenv-presets.nix`, and
  `nixarchy-dev-init` from the installed commands (`modules/apps.nix:2951-2957`).
- The `nixarchy dev …` dispatch (`modules/apps.nix:3029-3031`) runs
  `nixarchy-devenv …`, so `nixarchy dev init <preset>` resolves to the plugin
  CLI's `init`. The eight preset names are all plugin template ids (react, node,
  typescript, python, ml, jupyter, go, rust; `data/templates.nix:61-236`), so
  every name in the docs (`python.md`: `ml`, `jupyter`) still works.
- **Without devenv, the answer stays useful.** Today `nixarchy-dev-init` is
  installed unconditionally (`modules/apps.nix:2948-2956`), and its first act on
  a machine without devenv is to say so and name the Services entry that enables
  it. The plugin CLI is only installed where devenv is on (the gate), so the
  dispatch keeps that behaviour itself: if `nixarchy-devenv` is on PATH it runs
  it; otherwise it prints the same guidance
  (`programs.nixarchy.services.devenv.enable`, or the devenv row in Install ▸
  Service) and exits 1, rather than failing on a missing binary.
- **Stale comments** citing `pkgs/dev-init.nix` as a pattern are reworded to cite
  `pkgs/box.nix`: `pkgs/microvm.nix`, `pkgs/box.nix`, `pkgs/secret.nix`,
  `data/box-templates.nix`, `data/microvm-templates.nix`.
  `tests/demo/default.nix:441` is updated too.

### `devenv-presets` stays, under the same name, running the plugin's check

`devenv-presets` is a required status check on `main`, and it's a `build.yml`
job that runs `nix run .#devenv-presets` (`build.yml:235-270`). So **the job and
the flake attribute keep their names, and only what the attribute runs
changes.** `packages.devenv-presets` (`flake.nix:998-1060`) becomes a thin
`writeShellApplication` that runs the pinned plugin's
`apps.templates-check.program` with the eight former preset ids. That's the same
scope and the same "scaffold with a real devenv, then evaluate" proof.

**No workflow edit and no branch-protection change.** The required status keeps
reporting under its old name.

This also fixes a flaw in today's runner, which the plugin's check documents:
the old runner moved `HOME` but inherited `XDG_DATA_HOME`, and left 80 dead
entries in p620's devenv trust list. The plugin's check runs each scaffold under
`env -i`, with every XDG and devenv path inside one temporary root, and compares
the real trust list's checksum before and after.

`generator`-kind templates (`cloud`) stay outside the required check. They need
network access at create time; offline create for `cloud` is the intent's open
question 3, and it's out of scope here.

## Alternatives rejected

- **Drop the `devenv-presets` job and let the plugin's own CI prove its
  templates.** That needs a workflow edit and a branch-protection change, which
  are human-only (§4/§11). The owner chose to keep the name.
- **Keep nixarchy's own scaffolder beside the plugin.** Two catalogues would
  drift apart, which the intent rules out.
- **Turn devenv on by default so the panel appears everywhere.** Rejected on
  approval, in favour of the gate.
- **Import the plugin's Home Manager module** for its bind. It writes
  `~/.config/hypr/devenv-binds.lua`, and nixarchy never manages that directory;
  the seed bind covers new installs, as with microvm.

## Risks

- **The pin waits on another repo's merge.** If nixarchy-devenv#1 changes the
  output names before it merges, the step that reads them fails. The
  merge-readiness list above is the check.
- **`devenv-presets` gets slower or flakier** if the plugin's check does more
  than the old runner, for example a stricter hermetic `env -i`. The first CI run
  on the PR is the measure, and the eight-id limit keeps the scope the same.
- **Existing users of `nixarchy-dev-init` by that exact name** lose it. It
  wasn't documented; `nixarchy dev init` is the documented form, and it's kept.
- **A user who enabled devenv and already has the plugin** installed through the
  plugin's own Home Manager module (the owner's machine) gets it declared twice.
  The declared-plugin mechanism refuses a second declaration of the same id, the
  same coexistence as #780's nixarchy.pkg. The PR says so, and the owner removes
  their own declaration first.

## Verification

Every new check is broken first (§1). No new `checks.<name>`.

- **`checks.options`:**
  - `devenvIsADefault`: present with the devenv service on; absent when it's off,
    when opted out, standalone, or when nixarchy is off.
    - **Red first:** the tests go in before the entry exists.
  - `devenvLicence`: the plugin package contains LICENSE.
    - **Red first:** point `src` at a copy without it.
- **`checks.menu-verbs`:** the `apps.devenv` row's id is an installed manifest
  id, and the plugin-row floor goes up by one.
  - **Red first:** misspell the id.
- **The dispatch** (no test covers `nixarchy dev` today): a runtime case in
  `checks.options`, the same kind as `nixarchy-plugin`'s (#775).
  - With a stub `nixarchy-devenv` on PATH, `nixarchy dev init ml` runs it with
    `init ml`.
  - Without it, the command prints the guidance naming
    `services.devenv.enable` and exits 1.
  - **Red first:** point the dispatch at the removed `nixarchy-dev-init`, and
    both cases fail.
- **`devenv-presets`, the required check:** `nix run .#devenv-presets` scaffolds
  and evaluates all eight through the plugin.
  - **Red first:** add an id that isn't a template (`nosuchpreset`), and the run
    fails naming it.
- **The seed:** the omarchy build's seed-anchor assertion covers Super+Alt+E.
  - **Red first:** point the anchor at a line that doesn't exist.
- **Docs:** `per-project-environments.md`, `python.md`, `plugins.md` (a new
  entry), the README row, `docs/internals/flake.md` (the input's reason, sizes
  and pin-bump procedure), and `modules/AGENTS.md`. `readme-counts` checked.
