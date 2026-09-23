---
status: approved
issue: 912
spec: spec/2026-09-23-912-ship-flatsnap.md
---

# Plan: nixarchy-flatsnap ships with nixarchy

## Approved decisions (self-contained)

- **nix-snapd is imported by nixarchy**, through the plugin's
  `nixosModules.default` (the module plus nix-snapd). It is added to
  `modules/nixos.nix` next to `inputs.nix-flatpak.nixosModules.nix-flatpak`,
  unconditionally. It is the only nix-snapd import in nixarchy. The module is
  inert until `~/.config/nixarchy/flatsnap.nix` declares something: snapd and the
  `nixarchy-flatsnap-snaps` unit exist only while `snaps != [ ] || pendingRemoval != [ ]`.
- **Flake input `nixarchy-flatsnap`:** pinned to a commit on the plugin's `main`,
  with `inputs.nixpkgs.follows = "nixpkgs"` and
  `inputs.nix-flatpak.follows = "nix-flatpak"`. It carries a
  `# Why: docs/internals/flake.md#the-flatpak-and-snap-panel-on-by-default-912`
  line, like `nixarchy-ghtui`.
- **Plugin on by default:** a `defaultPluginSet.flatsnap = { id = "nixarchy.flatsnap"; src = inputs.nixarchy-flatsnap.packages.${system}.default; }`
  entry. `gate` stays at its default, and there are no extra `packages`. The
  `defaultPlugins` default attrset gains `flatsnap = true;`;
  `defaultPlugins.flatsnap = false` opts out.
- **Menu row in nixarchy:** `install.flatsnap` goes right after `install.packages`
  in `modules/apps.nix`, with values identical to the plugin's own row:
  - icon `󰏗`, label `Flatpak & Snap`;
  - `action = "nixarchy-plugin nixarchy.flatsnap"`;
  - `when = "nixarchy-plugin --enabled nixarchy.flatsnap"`;
  - description "Paste a Flathub or Snapcraft link and install it declaratively".

  Equal definitions merge under `types.anything` (checked with `lib.evalModules`),
  so the plugin's `extraEntries` copy can go in a later plugin release.
- **Docs:**
  - `docs/internals/flake.md` gets a section with that anchor.
  - A new `docs/manual/flatpak-and-snap.md` goes in `docs/_config.yml`'s `nav`
    right after "Packages". It covers paste forms, the keys, that nothing installs
    until `a`, Security (no AppArmor, setuid `snap-confine`, classic = no
    sandbox), and Removal (`--purge`, no snapshot).
  - `docs/manual/plugins.md` gets a row and the opt-out.
- **Ordering:** olafkfreund/nixarchy-flatsnap#2 and #906 merge before this. This
  PR does not touch `nixarchy-apply`.
- **Downstream:** `olafkfreund/nixos_config` bumps nixarchy **and** removes its own
  nix-snapd input and import (`flake.nix:201`, `:451`) in a single PR.
- **Tests:** razer is the standing test host. Announce on the bus before every
  switch, and report the generation razer is left on.

## Steps

One commit per step on `feat/912-ship-flatsnap`, rebased on `main` once #906 is in.

1. **`flake.nix`, the input.** Add `nixarchy-flatsnap`. Until #2 merges, pin the
   head commit of `feat/1-flatpak-snap-menu` and mark it `# TEMP pin: re-pin to
   main after nixarchy-flatsnap#2` (step 8 replaces it). Run
   `nix flake lock --update-input nixarchy-flatsnap`.
   → Verify with `nix flake metadata`: exactly one new `nix-snapd` node, and no
   second `nixpkgs` or `nix-flatpak` node.
2. **`modules/nixos.nix`, the import.** Add `inputs.nixarchy-flatsnap.nixosModules.default`
   with the comment from the spec.
   → Verify with `nix eval .#nixosConfigurations.vm.config.services.snap.enable` →
   `false`, and `…systemd.services ? nixarchy-flatsnap-snaps` → `false`.
3. **`modules/home.nix`, the plugin.** Add the `defaultPluginSet.flatsnap` entry
   and `defaultPlugins.flatsnap = true`.
   → Verify with the `defaultHomeOn` fixture: `programs.nixarchy.plugins ? "nixarchy.flatsnap"`.
4. **`modules/apps.nix`, the row.** Add `install.flatsnap` after `install.packages`.
   → Verify with `nix build .#checks.x86_64-linux.menu-verbs`: green now, where the
   same row was red in #906.
5. **`tests/options.nix`, both states.** Following `githubIsADefault`:
   - `flatsnapIsADefault = { on = defaultHomeOn has the plugin and hookLists it;
     off = noDefaultsHome, defaultHome or fixtureNixarchyOff has it; }`
   - `flatsnapInert`, on `vmCfg`: `services.snap.enable == false`, no
     `nixarchy-flatsnap-snaps` unit, and `install.flatsnap` in
     `programs.nixarchy.menu`'s generated rows.
   - `flatsnapSnapOn`: a `vm` config extended with
     `programs.nixarchy.flatsnap.snaps = [ { name = "hello-world"; } ]` has
     `services.snap.enable == true` and the unit.

   → Verify by showing each red first: drop the step 2 import (→ `flatsnapSnapOn`
   fails), drop the step 3 entry (→ `flatsnapIsADefault.on` fails), then restore
   (→ green). Paste both outputs in the PR.
6. **Docs.** `docs/internals/flake.md` section, `docs/manual/flatpak-and-snap.md`,
   the `docs/_config.yml` nav entry, and the `docs/manual/plugins.md` row.
   → Verify that `.github/workflows/pages.yml`'s nav check passes locally (its
   script), and that `nix run nixpkgs#jekyll -- build -s docs` succeeds.
7. **razer, end to end.** Announce on the bus first. In a `/tmp` clone of
   nixos_config:
   1. Point `nixarchy` at this branch and remove nix-snapd's input and import.
   2. `nixos-rebuild test` → check that snapd is inactive, the menu row is in
      `nixarchy-omarchy-menu.jsonc`, and the plugin is installed under
      `~/.config/omarchy/plugins/nixarchy.flatsnap`.
   3. Run `nixarchy-flatsnap add` for a Flatpak and a Snap, then `NIXARCHY_FLAKE=<clone>
      NH_ELEVATION_STRATEGY=passwordless nixarchy-flatsnap apply` → both run.
   4. `rm` both and apply → both gone, and a snap installed by hand survives.
   5. Roll back to razer's prior generation, delete the test generations, and post
      the generation razer is on.

   → Record the result in this plan (Deviations / results).
8. **Pin to `main`.** Once #2 has merged, re-pin D1 to its merge commit and drop
   the TEMP comment, then `nix flake lock --update-input nixarchy-flatsnap`.
   → Verify that the step 1 metadata check and `options` still pass.
9. **PR ready.** Mark #914 ready and fill in the template: what changes and why;
   the red/green outputs from step 5; the checks run; the razer result; and the
   rollout note, quoting the "`services.snap.enable` … is already declared" error
   for downstream flakes.
   → Verify that CI is green on the final head: `options`, `menu-verbs`,
   `apply-imports`, `vm-toplevel`, `install`.
10. **After merge (separate PRs, not this one):**
    1. nixos_config: bump nixarchy and drop its nix-snapd (one PR). Deploy it to razer first.
    2. A nixarchy-flatsnap release drops its `extraEntries` row, and D1's pin is bumped to it.

## Tests

```bash
nix build .#checks.x86_64-linux.options .#checks.x86_64-linux.menu-verbs \
          .#checks.x86_64-linux.apply-imports .#checks.x86_64-linux.vm-toplevel
nix eval .#nixosConfigurations.vm.config.services.snap.enable    # false
nix fmt -- --check modules/*.nix tests/options.nix
nix run nixpkgs#jekyll -- build -s docs -d /tmp/site
```

Each new assertion is seen red once (step 5). The eval cost of the extra module
on `vm-toplevel` is measured before and after, and recorded under Deviations /
results.

## Rollback

- **Before the nixos_config change:** revert this PR's merge commit. Machines that
  declared nothing are unaffected either way. Machines that declared Flatpaks keep
  them: nix-flatpak removes only what it manages, and without the module nothing
  is managed. Snaps stay installed, but snapd stops. Remove them with
  `snap remove --purge` first if they should go.
- **After the nixos_config change:** revert both, in the same order in reverse:
  restore nixos_config's nix-snapd import in the same PR that pins nixarchy back.
  Otherwise hosts with snaps lose snapd.
- **On razer:** switch back to the recorded prior generation.

## Deviations / results

(filled in during implementation)
