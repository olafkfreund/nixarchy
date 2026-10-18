---
status: approved
issue: 1314
intent: intent/2026-10-18-1314-menu-apps-stated-keys.md
---

# Spec: nixarchy-menu and nixi keep the rest of a row that a partial menu override names

## Design

Answering the intent's first question: **(a), nixarchy hands both packages
its own patched `MenuModel.js`.** Each has a route that needs no change to its
repository and no fork of its build.

One small derivation in `modules/home.nix` holds the file:

```nix
menuModelSrc = pkgs.runCommandLocal "nixarchy-menu-model" { } ''
  install -Dm444 ${omarchyPath}/shell/plugins/menu/MenuModel.js \
    "$out/shell/plugins/menu/MenuModel.js"
'';
```

`omarchyPath` (`modules/home.nix:17`) is the system's tree when there is one,
else `cfg.package`'s, so this is the same file the stock menu runs, with
#1311's patch. It is laid out as an Omarchy tree (`shell/plugins/menu/…`), so
it can stand in for nixi's `omarchySrc`. Copying the one file keeps the 128 MiB
tree out of both closures, the same reason both upstream builds copy one file.

- **nixi.** `nix/package.nix` already takes `omarchySrc` and copies
  `${omarchySrc}/shell/plugins/menu/MenuModel.js` (its `:88-92`); its own build
  then asserts that `MenuSearch.qml` imports that copy (`:257-262`). The Home
  Manager module builds from `cfg.package.override { … }` (its
  `hm-module.nix:18`), so the override survives. nixarchy sets:
  ```nix
  services.nixi.package = lib.mkDefault
    (inputs.nixi.packages.${system}.nixi.override { omarchySrc = menuModelSrc; });
  ```
- **nixarchy-menu.** `modules/home.nix:1987-1993` already passes the plugin
  through `pkgs.applyPatches` (to restyle its bar button). Its `postPatch`
  gains one rewrite of the built import in `providers/OmarchyMenu.qml`, from
  the plugin's own `…-omarchy-menu-model/MenuModel.js` to
  `${menuModelSrc}/shell/plugins/menu/MenuModel.js`, followed by a `grep -qF`
  for the new path. The match is on the derivation name
  (`/nix/store/<hash>-omarchy-menu-model/MenuModel.js`, nixarchy-menu's
  `flake.nix:49`), so a rename upstream fails the build instead of silently
  leaving the raw file.

So the three readers run one file, and the next patch to `MenuModel.js`
reaches all three without anyone remembering them.

The intent's second question: **one check in nixarchy is enough.** The bug is
in what nixarchy feeds the two apps, not in either repository, which stays
correct against upstream as it is.

### Check

`checks.menu-model-merge` (`tests/menu-model-merge.nix`) runs
`tests/menu-model-merge.js` under node against the built stock
`MenuModel.js`. It also runs the harness against the file each app
imports, as the reference configuration builds them:

- the `MenuModel.js` that `providers/OmarchyMenu.qml` imports, in the
  nixarchy-menu plugin from the evaluated `programs.nixarchy` plugin list;
- the `MenuModel.js` that `MenuSearch.qml` imports, in the evaluated
  `services.nixi.package`.

The import path is read out of the built QML, not assumed, so the check
follows what each app really loads. An unreadable or missing import fails.

### Coexistence

nixarchy now sets `services.nixi.package`, which a user may also set. It is
`lib.mkDefault`, so the user's value replaces ours outright. A package option
is a single value, not a merged environment, so neither of §14's collision
modes applies, and no fixture could fail. A user who sets their own package
gets upstream's raw file again; the manual's Nixi section says so in one
sentence. nixarchy-menu's plugin is nixarchy's own default-plugin entry, so
nothing new is shared with the user there.

## Alternatives rejected

- **(b) The same patch in each repository.** Three copies of a patch that
  exists only to work around upstream, kept in step by hand, which is the
  failure the intent wants gone. It would fix the apps outside nixarchy, but
  outside nixarchy neither app sees nixarchy's menu file.
- **A `menuModel` argument added to nixarchy-menu's `plugin`, like nixi's.**
  Cleaner to override, but it means a pull request, a pin bump and a release
  in another repository, for what one `postPatch` line already does. It is a
  reasonable later cleanup, not a prerequisite.
- **Rewriting nixarchy-menu's build command string** (`overrideAttrs` on its
  `buildCommand`). It matches on another repository's Nix source rather than
  on its output, and `applyPatches` already gives an output to edit.
- **Letting both apps import `/run/current-system/…` again** (nixi with
  `omarchySrc = null`). That is the patched file on a nixarchy NixOS machine,
  but nothing on a Home-Manager-only setup, and it is the impurity both
  repositories removed on purpose.

## Risks

- **nixarchy-menu renames `omarchy-menu-model`, or moves the import.** The
  `grep -qF` after the rewrite fails the build on every machine. Loud, not
  silent; the fix is one pattern.
- **nixi drops `omarchySrc`.** `.override` then throws at evaluation. Loud.
- **Rebuild cost.** nixi is not in `cache-allowlist.sh`, so it already builds
  on each machine; the override changes only its final derivation, not
  `nixi-bridge-modules`. The plugin was already a local `applyPatches`.
- **Edge.** `omarchyPath` there is the edge tree, carrying edge's own copy of
  #1311's patch, so the apps follow edge's menu. The edge carry needs nothing
  unless the check's file paths differ there.
- **Mode A.** Both settings sit where the module already configures nixi and
  the plugin, behind the same conditions; nothing new is set for a
  configuration with nixarchy off. `checks.options` covers both states.

## Verification

- `checks.menu-model-merge` green, running the harness on all three files.
- §1: with the nixi override removed, the check fails on nixi's file; with the
  plugin rewrite removed, it fails on nixarchy-menu's. Both outputs go in the
  PR, along with proof that each break landed (`git diff`).
- `options`, `plugin` and `session` run in CI (expensive tier, §6).
- By hand on p620 after a switch: a partial override in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` (only `label`) shows the
  row's icon and runs its action from nixarchy-menu's search and from Nixi's
  menu search.
- #1315 is then unblocked: nothing reads the raw merge any more.
