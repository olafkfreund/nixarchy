---
status: approved
issue: 912
intent: intent/2026-09-23-912-ship-flatsnap.md
---

# Spec: nixarchy-flatsnap ships with nixarchy

## Decisions carried from the intent

| # | Question | Decision |
|---|---|---|
| Q1 | Who imports nix-snapd | nixarchy, through the plugin's `nixosModules.default` (the module plus nix-snapd) |
| Q2 | Default | on wherever `programs.nixarchy.enable`; `defaultPlugins.flatsnap = false` opts out |
| Q3 | Menu row | `install.flatsnap` becomes a nixarchy row; the plugin drops its `extraEntries` copy in a later release |
| Q4 | #906 | merges first; this PR does not touch `nixarchy-apply` |
| Q5 | Manual | its own page, `docs/manual/flatpak-and-snap.md`, in the `nav` |

## Design

Five edits in nixarchy. None of them changes behaviour for a machine that
declares no Flatpak and no Snap.

### D1: flake input (`flake.nix`)

```nix
# Why: docs/internals/flake.md#the-flatpak-and-snap-panel-on-by-default-912
# A commit on main (no tags); bump it the way that page says.
nixarchy-flatsnap = {
  url = "github:olafkfreund/nixarchy-flatsnap/<commit on main after #2>";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-flatpak.follows = "nix-flatpak";   # the plugin uses it only in its checks
};
```

It is pinned to a commit, like `nixarchy-ghtui` and `nixarchy-gltui`. The
plugin's own `nix-snapd` input already follows the plugin's nixpkgs, and with
it nixarchy's, so the lock gains one nix-snapd node and no second nixpkgs.

### D2: the NixOS side (`modules/nixos.nix`)

Next to `inputs.nix-flatpak.nixosModules.nix-flatpak` in the imports list:

```nix
# Flatpak & Snap from the menu (#912). `default` = the plugin's module plus
# nix-snapd; nixarchy is now the one place nix-snapd is imported. Inert until
# ~/.config/nixarchy/flatsnap.nix declares something: no snapd, no unit.
inputs.nixarchy-flatsnap.nixosModules.default
```

- **It is imported unconditionally**, like nix-flatpak and sops-nix. Imports
  cannot depend on option values, and the module gates itself: snapd and the
  reconciler exist only while `snaps != [ ] || pendingRemoval != [ ]`, and
  nix-flatpak's settings only while `flatpaks != [ ]`.
- **It is the only nix-snapd import in nixarchy.** A downstream flake that
  imports nix-snapd itself must drop that import in the same update (see
  *Rollout*). Nothing inside nixarchy can detect a duplicate import: evaluation
  fails before any assertion runs. So the release note, and the manual's
  upgrade line, say it in plain words, and quote the error text.
- The plugin's module also sets `programs.nixarchy.menu.extraEntries."install.flatsnap"`.
  Until the plugin drops that copy, it defines the same value nixarchy's row
  defines, and `types.anything` merges equal definitions. This was checked with
  `lib.evalModules` on two identical `{ label; action; }` rows.

### D3: the plugin (`modules/home.nix`)

A `defaultPluginSet` entry, shaped like `pkg`:

```nix
# Flatpak & Snap from the menu, on wherever nixarchy is (#912).
flatsnap = {
  id = "nixarchy.flatsnap";
  src = inputs.nixarchy-flatsnap.packages.${pkgs.stdenv.hostPlatform.system}.default;
};
```

- `gate` is left at its default (`true`). The `defaultPlugins` default attrset
  gains `flatsnap = true;`.
- No `packages`. The CLI in the plugin's `bin/` uses curl, jq and
  nix-instantiate, all of which are on nixarchy's base system (as for
  nixarchy-pkg's adapter).
- The plugin package is a plain copy with no symlinks, and it passes
  `omarchy plugin validate` (the plugin's `checks.plugin-no-symlinks`).

### D4: the menu row (`modules/apps.nix`)

This goes directly after `install.packages`, with values identical to the
plugin's:

```nix
# Flatpak & Snap (#912). Same shape as install.packages: the helper, and
# `when` hides the row once the plugin is turned off.
"install.flatsnap" = {
  icon = "󰏗";
  label = "Flatpak & Snap";
  action = "nixarchy-plugin nixarchy.flatsnap";
  when = "nixarchy-plugin --enabled nixarchy.flatsnap";
  description = "Paste a Flathub or Snapcraft link and install it declaratively";
};
```

`menu-verbs` accepts it once D3 is in: it reads plugin ids from the installed
plugins' manifests, and `nixarchy.flatsnap` is then one of them. It refused
exactly this row in #906 before the plugin was shipped.

### D5: documentation

- **`docs/internals/flake.md`:** a section, "The Flatpak and Snap panel, on by
  default (#912)", that says:
  - why it is an input;
  - how to bump the pin;
  - that nixarchy owns the only nix-snapd import, and what a downstream flake
    must remove.
- **`docs/manual/flatpak-and-snap.md`**, listed in `docs/_config.yml`'s `nav`
  right after "Packages". It covers:
  - what you can paste, and the keys;
  - that nothing installs until `a`;
  - *Security*: nix-snapd has no AppArmor and uses a setuid `snap-confine`, and
    classic snaps have no sandbox;
  - *Removal*: `snap remove --purge`, so there is no snapshot; the data is gone,
    so copy `~/snap/<name>` first;
  - that snapd runs only while a Snap is declared.
- **`docs/manual/plugins.md`:** a row for the new default plugin, plus
  `defaultPlugins.flatsnap = false` to opt out.

## Rollout

1. **olafkfreund/nixarchy-flatsnap#2 merges.** D1 pins the resulting commit on `main`.
2. **#906 merges.** `nixarchy-apply` copies `flatsnap.nix`.
3. **This PR merges.**
4. **`olafkfreund/nixos_config`, in one PR:** bump the `nixarchy` input and
   remove its own `nix-snapd` input and its `inputs.nix-snapd.nixosModules.default`
   import (`flake.nix:201`, `:451`). Its hosts use `services.snap` through nixarchy
   from then on. If only one of the two changes landed, every host would fail to
   evaluate, so they go together.
5. **A plugin release drops its `extraEntries` row**, and D1's pin is bumped to it.
   Nothing breaks between steps 3 and 5 (D2).

## Alternatives rejected

- **nixarchy imports only the plugin's `flatsnap` module (Q1 b).** Snap would
  work only where a host brings nix-snapd. On stock nixarchy the Snap half of the
  panel would queue things that never install. Rejected in the intent.
- **A flake-level switch for nix-snapd (Q1 c).** That means a second module
  output and a choice every user has to understand, for a module that is already
  inert until used.
- **Gating the plugin on something, like podman's plugin.** There is no
  underlying service to gate on. The panel is the way in, and the module is
  inert.
- **Vendoring the plugin's sources into `pkgs/`** (as `rebuild-panel` is). The
  plugin has its own tests, VM test and release cadence, and an input keeps
  those in one place.
- **Keeping the row only in the plugin (`extraEntries`).** That gives two sources
  of truth for a row nixarchy now ships. Rejected in the intent.

## Risks

| Risk | Where | Mitigation |
|---|---|---|
| A downstream flake that imports nix-snapd fails to evaluate after updating | nixos_config (every host), any public user doing the same | Rollout step 4 in one PR; the release note and the manual upgrade line quote the error text |
| snapd or its setuid helper appears on machines that declared nothing | every nixarchy host | The plugin's gating; a new `tests/options.nix` assertion that stock nixarchy has `services.snap.enable == false` and no `nixarchy-flatsnap-snaps` unit |
| A default-on panel puts weaker Snap confinement within reach of every user | everyone | Unchanged from the plugin: stated on every Snap card, a two-press confirm for classic, and the manual's Security section |
| Evaluation cost of one more module on every check that evaluates a system | CI | Option declarations plus a mostly empty `mkMerge`. Measure `vm-toplevel` eval before and after; the plan records the number |
| The plugin pin goes stale | maintenance | Same process as the other plugin inputs (`flake.md`) |

## Verification

1. **`tests/options.nix`**, both states of every new behaviour:
   - default nixarchy: the plugin `nixarchy.flatsnap` is installed,
     `services.snap.enable == false`, there is no `nixarchy-flatsnap-snaps`
     unit, and `install.flatsnap` is in the menu rows;
   - `defaultPlugins.flatsnap = false`: the plugin is not installed;
   - a system declaring one Snap: `services.snap.enable == true` and the
     reconciler unit exists.

   Each assertion is shown red first, by removing the D2 import or the D3 entry.
2. **`menu-verbs`** passes with the row. It failed with this exact row before the
   plugin shipped (#906 history).
3. **`nix build .#checks.x86_64-linux.{options,menu-verbs,plugin,vm-toplevel,apply-imports}`**
   is green locally, and the PR's CI is green.
4. **razer end to end.** razer is switched to this branch, with nixos_config's
   own nix-snapd import removed in a `/tmp` clone:
   1. The menu shows *Install → Flatpak & Snap* with no user wiring.
   2. A Flatpak and a Snap installed from the panel's CLI through the real apply
      both run.
   3. Removing them works.
   4. With nothing declared, snapd is inactive.

   razer is then left on nixarchy `main` or on its prior generation, and the
   bus says which.
5. **The manual builds** and its `nav` lists the new page (`.github/workflows/pages.yml`).
