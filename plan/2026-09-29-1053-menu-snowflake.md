---
status: approved
issue: 1053
spec: spec/2026-09-29-1053-menu-snowflake.md
---

# Plan: nixarchy-menu's bar button wears the NixOS snowflake

## Approved decisions

- The patch lives in nixarchy, in the `menu` entry of the default-plugin set
  in `modules/home.nix`. nixarchy-menu is not touched.
- `src` becomes `pkgs.applyPatches` over
  `inputs.nixarchy-menu.packages.<system>.plugin`. Its `postPatch` runs one
  `substituteInPlace BarWidget.qml --replace-fail 'fontFamily: "omarchy"'`.
  The replacement keeps that line and adds `labelVisible: false` and the
  stock button's snowflake `Image`:
  - `anchors.centerIn: parent`
  - `source: "file://${pkgs.nixos-icons}/share/icons/hicolor/256x256/apps/nix-snowflake.png"`
  - side `Math.round(button.fontSize * 1.3)` for `sourceSize`, `width` and
    `height`
  - `smooth` and `mipmap` on
  - `opacity: button.dimmed ? 0.45 : 1`
- Use the PNG, never the SVG.
- `--replace-fail`, not a `.patch` (`pkgs/AGENTS.md#patching-upstream`). A
  reworded anchor fails the build.
- The snowflake is always on. There is no option for it.
- Everything else in the button stays the same: the toggle, right click,
  the `barList` Repeater and `moduleName`.
- No code overlaps with #1052 (`enableByDefault` against `src`). Whichever
  merges second rebases.

## Steps

1. `modules/home.nix`, in the `menu` entry: define the replacement text in
   the entry's scope as `snowflakeButton`, a Nix string with the QML
   indented to sit inside `WidgetButton { id: button … }`. Change `src` to
   the `applyPatches` form. Add one short comment pointing to
   `pkgs/omarchy/menu-bar-widget.qml`. → Verify:
   `nix build --no-link --print-out-paths --impure --expr` on
   `.#nixosConfigurations.vm…home-manager.users.omarchy.programs.nixarchy.defaultPluginSet.menu.src`,
   then `grep -c nix-snowflake.png "$out/BarWidget.qml"` gives 1, and
   `diff` against the unpatched source shows only the inserted lines.
2. `flake.nix`, the `qml` check: pass
   `menuPlugin = self.nixosConfigurations.vm.config.home-manager.users.omarchy.programs.nixarchy.defaultPluginSet.menu.src;`.
   → Verify: the check still evaluates.
3. `tests/qml.nix`: accept `menuPlugin`. Add `menu-plugin/BarWidget.qml` to
   the lint loop, with a `menu-plugin/*` case that lints
   `$menuPlugin/BarWidget.qml`, the same pattern as `panel/*`. Update the
   file's count of what it lints if its prose states one. → Verify:
   `nix build .#checks.x86_64-linux.qml -L` prints
   `== menu-plugin/BarWidget.qml` then `ok`.
4. `tests/options.nix`, in the #946 block: add
   `menuSrc = menuOnHome.programs.nixarchy.plugins."nixarchy.menu".src;`
   next to `menuValidated`, and a shell assertion that
   `"$menuSrc/BarWidget.qml"` contains both `nix-snowflake.png` and
   `labelVisible: false`, with a message naming #1053. → Verify: the
   options check passes. Then comment out the `substituteInPlace`, confirm
   the assertion fails, and restore it.
5. `modules/AGENTS.md`: add a sentence to the default-plugins or #946
   section, if there is one, saying that nixarchy patches the menu's bar
   button to wear the snowflake and where. → Verify: `grep -n 1053` finds
   it.
6. Run `nix fmt -- --ci` and
   `nix flake check -L --keep-going` (or the `qml` and `options` checks plus
   an eval of `vm`, if the full check is too heavy locally, with CI running
   the rest). → Verify: green.
7. Squash to one commit with a full-sentence subject, for example "The
   nixarchy-menu bar button wears the NixOS snowflake (#1053)". Open a PR
   that links the issue, the three documents and
   olafkfreund/nixos_config#2074. Merge it once CI is green, rebasing on
   #1052 first if that merged.

## Tests

| Command | Expected |
| ------- | -------- |
| grep of the built menu `src` for `nix-snowflake.png` | 1 match |
| `nix build .#checks.x86_64-linux.qml -L` | `menu-plugin/BarWidget.qml ok` |
| the options check, with the substitution removed | fails, naming #1053 |
| the options check, as shipped | passes |
| `nix fmt -- --ci` | clean |

## Rollback

`git revert` the merge. `src` returns to the plugin output unpatched, so
the menu works and shows the Omarchy mark. Downstream, nixos_config either
bumps back or accepts the Omarchy mark.
