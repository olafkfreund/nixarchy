---
status: approved
issue: 1069
intent: intent/2026-09-29-1069-menu-modelpath.md
---

# Spec: Super+Space opens a menu on every nixarchy install

## Design

- **`modules/nixos.nix`:** in the `environment` block, beside
  `systemPackages = [ cfg.package … ]`, add
  `pathsToLink = [ "/share/omarchy" ];`. The stock omarchy package is already
  in `systemPackages`, so this makes
  `/run/current-system/sw/share/omarchy/…/MenuModel.js` exist, which is the
  path nixarchy-menu and nixi import. It is a one-line comment plus the
  setting. `pathsToLink` is a list option, so plain assignment merges with
  other modules' entries (§7: no `mkDefault` on lists).
- **`tests/session.nix`:** after the desktop is up and the default-plugin
  hook has run, `omarchy-menu summon install` is sent as the user. The check
  then waits for a layer with namespace `omarchy-menu` in `hyprctl layers`,
  parsed in Python with no pipe into `grep -q` (#1058), and closes it with
  Escape. The assertion names #1069 and says "the menu did not open".
  `omarchy.menu` resolves to nixarchy-menu when it is enabled, so this is the
  property "summoning the menu opens one", whichever menu that is.
- **Follow-up, not in this PR:** nixarchy-menu should read `$OMARCHY_PATH`
  instead of the hard-coded path. It is the owner's repo, so this is filed
  separately.

## Alternatives rejected

- **Reverting #1054:** it restores a menu but drops the feature. The owner
  chose the hotfix.
- **Patching the plugin's import in `modules/home.nix` via `applyPatches`:**
  it fixes nixarchy-menu but not nixi, and adds a second patch on the same
  source (#1057 already patches it).

## Risks

`/share/omarchy` in the profile is the stock tree, not nixarchy's patched
`programs.nixarchy.tree`. The plugins take only code from it (`MenuModel.js`,
the keybinding script path), not menu data, which still comes from
`$OMARCHY_PATH`.

## Verification

- **Red:** `demo-scene-menus` on main is red: an empty desktop, and the gate
  fails. With the fix it must pass.
- **The session probe must fail with the `pathsToLink` line removed**, and
  pass with it.
