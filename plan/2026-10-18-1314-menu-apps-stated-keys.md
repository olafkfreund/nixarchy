---
status: approved
issue: 1314
spec: spec/2026-10-18-1314-menu-apps-stated-keys.md
---

# Plan: nixarchy-menu and nixi keep the rest of a row that a partial menu override names

## Approved decisions, carried over

1. **nixarchy hands both apps its own patched `MenuModel.js`.** No change to
   the nixarchy-menu or nixi repositories, and no fork of either build.
2. **One small derivation holds the file,** laid out as an Omarchy tree
   (`$out/shell/plugins/menu/MenuModel.js`), copied from `omarchyPath`
   (`modules/home.nix:17`). One file, never the 128 MiB tree.
3. **nixi** gets it through its existing `omarchySrc` argument:
   `services.nixi.package = lib.mkDefault (… .nixi.override { omarchySrc = …; })`.
   A user's own `services.nixi.package` wins, and then gets the raw file; the
   manual says so in one sentence.
4. **nixarchy-menu** gets it through the `applyPatches` already at
   `modules/home.nix:1987-1993`: its `postPatch` rewrites the built import in
   `providers/OmarchyMenu.qml`, matched on the derivation name
   `-omarchy-menu-model/MenuModel.js`, then `grep -qF` fails the build if the
   new path is absent.
5. **`checks.menu-model-merge`** also runs `tests/menu-model-merge.js` against
   the `MenuModel.js` each app imports, the path read out of the built QML.
6. **No coexistence fixture:** a package option is one value, so no fixture
   could fail (§14).

## Who does what

Four files change, so the coder (Sonnet) does steps 1–3, one `SendMessage`
per step. The lead does 0, 4 and 5, plus every commit and push, and runs the
build gate.

## Steps

### 0. [lead] Baseline

In `/mnt/data/vmtest/wt-1314`, under `flock /mnt/data/vmtest/codex-build.lock`:
- build `checks.x86_64-linux.menu-model-merge` (green on main);
- run `node tests/menu-model-merge.js` against the raw v4.0.5
  `shell/plugins/menu/MenuModel.js` (the `omarchy` input's path from
  `nix flake archive --json`) and capture that it **fails**. Without this, the
  §1 breaks in step 4 cannot be read.

### 1. [coder] `modules/home.nix`

- In the top `let` (beside `omarchyPath`, `:17`), add:
  ```nix
  # The stock menu's MenuModel.js, with #1311's patch, for the apps that import it (#1314).
  menuModelSrc = pkgs.runCommandLocal "nixarchy-menu-model" { } ''
    install -Dm444 ${omarchyPath}/shell/plugins/menu/MenuModel.js "$out/shell/plugins/menu/MenuModel.js"
  '';
  ```
- In the `services = { … }` block (`:850`), after `nixi.enable`:
  ```nix
  # Nixi's menu search merges rows with the stock menu's patched file (#1314).
  nixi.package = lib.mkDefault (
    inputs.nixi.packages.${pkgs.stdenv.hostPlatform.system}.nixi.override { omarchySrc = menuModelSrc; }
  );
  ```
- In the nixarchy-menu `applyPatches` `postPatch` (`:1991-1993`), after the
  existing `substituteInPlace`:
  ```sh
  # Its search merges rows with the stock menu's patched file (#1314).
  sed -i -E 's#file:///nix/store/[a-z0-9]{32}-omarchy-menu-model/MenuModel\.js#file://${menuModelSrc}/shell/plugins/menu/MenuModel.js#' providers/OmarchyMenu.qml
  grep -qF 'file://${menuModelSrc}/shell/plugins/menu/MenuModel.js' providers/OmarchyMenu.qml
  ```

Verify: `nix fmt`, then `git diff --stat` lists only `modules/home.nix`; then
`nix build .#nixosConfigurations.vm.config.home-manager.users.omarchy.programs.nixarchy.defaultPluginSet.menu.src`
and `….services.nixi.package` both build, and each built QML names
`nixarchy-menu-model`.

Traps:
- §5: the agent hook may rewrite `.nix` with `nixpkgs-fmt`. Run `nix fmt` and
  read `git diff --stat`.
- `${…}` inside the `''` string is Nix interpolation, which is wanted here;
  the sed's `{32}` is not, and is fine as written.
- §5: a flake sees only tracked files; `git add` before building.

### 2. [coder] `tests/menu-model-merge.nix` and `flake.nix:2550-2553`

- `tests/menu-model-merge.nix` takes `{ pkgs, omarchy, menuPlugin, nixi }`
  and runs the harness on three files:
  ```sh
  node ${./menu-model-merge.js} ${omarchy}/share/omarchy/shell/plugins/menu/MenuModel.js
  for qml in ${menuPlugin}/providers/OmarchyMenu.qml \
      ${nixi}/share/omarchy/plugins/io.github.olafkfreund.nixi/MenuSearch.qml; do
    model=$(grep -oE 'file:///nix/store/[^"]*/MenuModel\.js' "$qml" | head -1 || true)
    [ -n "$model" ] || { echo "menu-model-merge: $qml imports no store MenuModel.js"; exit 1; }
    echo "menu-model-merge: $qml"
    node ${./menu-model-merge.js} "''${model#file://}"
  done
  ```
  Update the header comment to name the three readers, and say that it reads
  `services.nixi.package`, not the module's `nixiPkg`: the module re-overrides
  only the adapters (`hm-module.nix:18`), which leaves `omarchySrc` as set.
  The `|| true` keeps the friendly message reachable: stdenv runs with
  `set -eu -o pipefail`, so a grep that matches nothing would otherwise end
  the build there.
- `flake.nix`: pass, after the qml check's pattern (`:2419-2420`),
  `menuPlugin = self.nixosConfigurations.vm.config.home-manager.users.omarchy.programs.nixarchy.defaultPluginSet.menu.src;`
  and `nixi = self.nixosConfigurations.vm.config.home-manager.users.omarchy.services.nixi.package;`.

Verify: the check is green.

Traps:
- §5: no heredoc in a `''` string; `''${` escapes a shell expansion.
- The test runs under `pkgs.runCommand`, i.e. bash with `set -e`, so a failed
  node exits the loop.

### 3. [coder] Docs and the `flake.nix` comment

- `docs/manual/ai.md`, section "Nixi, on SUPER + H" (`:259`): one sentence
  saying Nixi's menu search uses the stock menu's merge, and that setting your
  own `services.nixi.package` gives you upstream's instead.
- `flake.nix:1166-1170`: the comment says the module's default "is the same
  derivation this line names". It no longer is: nixarchy overrides
  `omarchySrc` (#1314). Say so in one sentence, and that `checks.nixi` still
  guards the pin while `checks.menu-model-merge` builds the package users get.
- `pkgs/AGENTS.md#the-menus-own-bugs-1305`: one sentence that nixarchy-menu
  and nixi import the same patched file through `modules/home.nix` (#1314),
  and that `checks.menu-model-merge` runs all three.

### 4. [lead] §1 breaks

Commit steps 1–3 as a temporary `wip:` commit first. For each break: apply it,
prove it landed with `git diff`, `git add -A`, build `menu-model-merge`,
capture, then `git checkout HEAD -- modules/home.nix`.

| break | expect |
|---|---|
| B1: delete the whole `nixi.package = lib.mkDefault ( … );` binding | red after `menu-model-merge: …/MenuSearch.qml`, with the harness's failure |
| B2: delete the two plugin lines (`sed`, `grep`) | red after `menu-model-merge: …/OmarchyMenu.qml` |
| B3: change the sed's `omarchy-menu-model` to `omarchy-menu-modelx` | the plugin build fails at the `grep -qF` |

Then green again.

Traps:
- §5: `git checkout HEAD --`, not `git checkout --`.
- §1: a green break may never have applied, or may be provided twice; grep
  for a second route before calling a check blind.

### 5. [lead] PR

- `menu-model-merge` is no longer seconds-long: it evaluates the `vm` home
  configuration and builds the nixi package. That is the package-build tier
  (§6): no p620 system build running, load below 12. Run it, `qml`, `nix fmt -- --ci`,
  statix and deadnix locally. `options`, `plugin` and `session` run in CI (§6).
- Squash to one commit: `nixarchy-menu and nixi merge menu rows with the stock
  menu's patched file, so a partial override keeps the rest of the row (#1314)`.
  Check `git merge-base origin/main HEAD` and `git show --stat HEAD`.
- PR body: links intent, spec and plan; says which steps the coder did; the
  B1–B3 output and step 0's raw-file failure; `Closes #1314`; says #1315 is
  unblocked.
- Arm `merge-when-green.sh`.

## Tests

| command | expect |
|---|---|
| step 0, harness on raw v4.0.5 file | fails |
| `menu-model-merge` | green, three files named |
| B1, B2 | red on the right file |
| B3 | build fails at the grep |
| `qml`, `nix fmt -- --ci`, statix, deadnix | clean |
| CI: `options`, `plugin`, `session` | green |

## Rollback

Revert the PR. Both apps go back to importing upstream's raw file, which is
today's behaviour; nothing is stateful.

## Deviations (2026-10-18)

- **Step 1's shape.** `nixi.package` was a third `nixi.*` key in the
  `services` block, which statix refuses as a repeated key (the block's own
  comment records the rule). `enable` and `package` now sit in one
  `nixi = { … }`, and `nixi.agents` stays where it was. Found in step 5; the
  B1 break was proven on the earlier shape, and deletes the same binding.
- **Step 2's header** is a few lines longer than the plan's wording, and the
  `|| true` reason sits inside the loop.
