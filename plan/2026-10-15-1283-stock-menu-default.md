---
status: approved
issue: 1283
spec: spec/2026-10-15-1283-stock-menu-default.md
---

# Plan: Omarchy's own menu is the default; nixarchy-menu is one click away

## Approved decisions (from the spec; implement against these)

- `programs.nixarchy.defaultPlugins.menu` keeps meaning **installed**:
  `true` by default, and `false` removes nixarchy-menu entirely.
- **New option `programs.nixarchy.menu.default`**, an enum `"omarchy"` or
  `"nixarchy"`, default `"omarchy"`. It only decides whether the post-boot
  hook turns `nixarchy.menu` on, once, at first login. `"omarchy"` installs
  it and leaves it off.
- **Code:** `defaultIds` (installed) is unchanged. A new list,
  `enableOnceIds`, drops `nixarchy.menu` when `menu.default == "omarchy"`.
  The hook's `todo` loop reads `enableOnceIds`, and its gone-clone restore
  loop keeps `defaultIds`.
- **Existing machines are not migrated.** The hook never disables a plugin.
- **New rows under Setup ▸ Defaults ▸ Menu**, present only when nixarchy is
  on and `defaultPlugins.menu` is true:

  | id | label | action | checked |
  |---|---|---|---|
  | `setup.default.menu` | Menu (title "Default Menu") | parent | none |
  | `setup.default.menu.omarchy` | Omarchy | `omarchy-plugin-disable nixarchy.menu` | `! nixarchy-plugin --enabled nixarchy.menu` |
  | `setup.default.menu.nixarchy` | Nixarchy | `omarchy-plugin-enable nixarchy.menu` | `nixarchy-plugin --enabled nixarchy.menu` |

  Every row is complete (icon, label, action, description), since these
  are new ids. Nothing writes `shell.json` (#847).
- **Mode A is untouched**, and there is no coexistence fixture, since no
  option here can collide.

## Steps

1. **`modules/apps.nix:1114`: the option.** Beside `menu.extraEntries`,
   declare `menu.default = lib.mkOption { type = lib.types.enum [ "omarchy"
   "nixarchy" ]; default = "omarchy"; description = ...; }`.
   - The description names the two values, the runtime switch row, and that
     `defaultPlugins.menu = false` removes nixarchy-menu entirely.
   - Home Manager reads it through
     `osConfig.programs.nixarchy.menu.default or "omarchy"`, the way
     `home.nix` already reads other NixOS options.

   **Verify:** `nix eval` the vm config's value; it is `"omarchy"`.

   **Traps:**
   - `mkDefault` on scalars only (§7). This is a plain option default, not a
     config setting.
   - `git add` before evaluating (§5).

2. **`modules/home.nix` ~:486-490 and the hook ~:2140-2260: installed vs
   turned on.**
   - Add `enableOnceIds = builtins.filter (id: !(id == "nixarchy.menu" &&
     (osConfig.programs.nixarchy.menu.default or "omarchy") == "omarchy"))
     defaultIds;` beside `defaultIds`.
   - In the hook, the `for id in ${defaultIds}` that builds `todo` uses
     `enableOnceIds`.
   - `declared`, the gone-clone list, and the `placement` map keep
     `defaultIds`. The menu is still declared, and its placement is still
     needed when a user turns it on through the row.
   - `mkIf (resolvedDefaults != { })` is unchanged.
   - Update the `defaultPluginSet.menu` comment (~:1952) and the
     `defaultPlugins` description (~:768). The menu is installed by default
     and turned on only when `menu.default = "nixarchy"`; `false` still
     removes it.
   - `modules/AGENTS.md`'s "The default plugins are on from the first login"
     section gains a short bullet: the menu is the one default that is
     installed but left off (#1283), and why.

   **Verify:** `checks.options` (step 4).

   **Traps:**
   - The hook is an indented Nix string. Use no heredoc (§5); keep the
     existing `lib.escapeShellArgs` shape.
   - An editor hook may run nixpkgs-fmt, so run `nix fmt` and read
     `git diff --stat` (§5).

3. **`modules/apps.nix`: the rows.** Add the three rows from the table
   above to the override rows. Wrap them in a `lib.optionalAttrs` the way
   the Sandboxes group (`trigger.vm`) is wrapped.
   - **The gate:** `cfg.enable` and nixarchy-menu installed for the desktop
     user.
   - **Where "installed" lives:** in Home Manager
     (`programs.nixarchy.defaultPlugins.menu`, default true). Read it as
     `config.home-manager.users.${cfg.user}.programs.nixarchy.defaultPlugins.menu
     or true` when `cfg.user != null`, and as `true` otherwise.
   - **First, grep `modules/apps.nix` and `modules/nixos.nix` for an existing
     path from the NixOS side into the home default plugins**, and reuse it
     if there is one. If the read causes an infinite recursion (home.nix
     reads `osConfig`), fall back to `cfg.enable` alone. With
     `defaultPlugins.menu = false` the two child rows then fail with the
     shell's own "unknown plugin" message. Record that in the plan's
     deviations; it is not a silent choice.
   - Rows run their commands directly, as upstream's
     `setup.default.agent.*` rows do (no floating terminal).
   - Icons: pick from the Nerd Font set the neighbouring rows use.
   - `parent` is implicit from the id (MenuModel.js drops the last segment).
     `setup.default.menu.*` lands under `setup.default.menu`, which lands
     under `setup.default`.

   **Verify:** `checks.menu-verbs` (step 4) and a look at the generated jsonc.

   **Traps:**
   - The generator blanks omitted keys only for NEW ids
     (`modules/apps.nix` ~:947-965), and these are new, so give full rows.

4. **Checks.**
   - **`tests/options.nix` ~:1207 (`menuIsOnByDefault`).** Retarget it as
     `menuInstalledNotOnByDefault`:
     - **on:** `defaultHomeOn` has `plugins ? "nixarchy.menu"` and the hook
       does NOT list it in the enable-once loop;
     - **off:** with `menu.default = "nixarchy"`, the hook lists it.
     - Keep the existing `menuOffHome` (`defaultPlugins.menu = false`)
       assertion that it is neither installed nor listed.
     - `hookLists` reads the hook text. Check that it matches the `todo`
       loop's list specifically, not the `declared` string, which still
       names the menu. If it cannot tell the two apart, make it read the
       `for id in …` line.

     The PR says this check was **retargeted**, not satisfied (§1, read
     backwards).
   - **Mode A:** `menu.default` exists on a disabled config, and the hook and
     rows are absent there. Follow the file's existing `modeAInert` /
     both-states pattern.
   - **`tests/menu-verbs.nix`.** Assert from the generated
     `omarchy-menu.jsonc` (jq, stripping `//` lines the way step 9 of #1278
     did) that:
     - `setup.default.menu.omarchy` runs `omarchy-plugin-disable
       nixarchy.menu`;
     - `.nixarchy` runs `omarchy-plugin-enable nixarchy.menu`;
     - both have non-empty `checked`.
   - **`tests/session.nix` ~:784 (VM).** After the existing "summoning the
     menu opens one" block, add a probe:
     1. `omarchy-plugin-enable nixarchy.menu` (the Nixarchy row's command),
        then `omarchy-plugin-list --json` shows `nixarchy.menu` enabled and
        `omarchy.menu` not.
     2. `omarchy-menu summon install` draws the `omarchy-menu` layer.
     3. `omarchy-plugin-disable nixarchy.menu` (the Omarchy row's command),
        then `omarchy.menu` is enabled again and `nixarchy.menu` is not, and
        summon draws the layer again.

     Use the same 60 s `wait_until_succeeds` around summon that the block
     above uses (#1203), and `OMARCHY_SHELL_IPC_TIMEOUT=10s` on the list
     calls (#1220). It also proves the new default: before step 1, assert
     `omarchy.menu` is the enabled one.

   **Red proofs:**
   - **options:** put `nixarchy.menu` back into `enableOnceIds`; the
     retargeted case fails.
   - **menu-verbs:** swap the two rows' actions; it fails.
   - **session:** CI-only. Run it locally only when `gh run list` shows
     nothing in flight (§6). A red proof is to drop the disable step's
     restore (call disable on `omarchy.menu` instead), then the probe fails.
     If the VM red proof cannot be run, say so in the PR.

   **Traps:**
   - Cheap checks one at a time under
     `flock /mnt/data/vmtest/codex-build.lock`.
   - `options` and VM checks only when CI is idle (§6).

5. **Docs.**
   - `docs/manual/plugins.md`, or whichever of `plugins.md`,
     `getting-started.md` and `philosophy.md` describes nixarchy-menu as on
     by default (grep "nixarchy-menu"), says:
     - Omarchy's menu is the default;
     - nixarchy-menu is installed;
     - _Setup ▸ Defaults ▸ Menu_ switches between them;
     - `programs.nixarchy.menu.default = "nixarchy"` makes it the
       first-login choice;
     - `defaultPlugins.menu = false` removes it.
   - Fix every other page that says it replaces the menu by default.

   **Verify:** `checks.docs-lists` and `checks.doc-options` (the latter
   checks option names quoted in docs).

## Tests

| Command | Expected |
|---|---|
| `nix build .#checks.x86_64-linux.options` (CI idle) | green; red with the menu back in `enableOnceIds` |
| `nix build .#checks.x86_64-linux.menu-verbs` | green; red with the row actions swapped |
| `nix build .#checks.x86_64-linux.doc-options .#…docs-lists` (one at a time) | green |
| `nix build .#checks.x86_64-linux.session` (CI idle, or CI) | green; the switch probe passes both ways |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Model split

Steps 1–4 edit three or more files, so they go to the `coder` agent, one
step at a time via `SendMessage`. Step 5 and the session VM run stay with the
lead. A fresh Opus agent reviews the diff against this plan.

## Rollback

- Revert the merge. A machine that never had nixarchy-menu on keeps the
  stock menu (the hook only enables). One that switched with the row keeps
  its choice in `shell.json`.
- `programs.nixarchy.menu.default = "nixarchy"` restores today's
  first-login behaviour without a revert.
