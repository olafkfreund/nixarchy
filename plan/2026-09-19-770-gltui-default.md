---
status: draft
issue: 770
spec: spec/2026-09-19-770-gltui-default.md
---

# Plan: the GitLab pipelines panel ships with nixarchy and is on by default

## Approved decisions (self-contained)

- **The plugin:** `olafkfreund.gitlab-pipelines` (kind `panel`), from input
  `nixarchy-gltui`, commit-pinned, with `inputs.nixpkgs.follows = "nixpkgs"`.
- **On by default:** `defaultPluginSet.gitlab`, plus `gitlab = true` in the
  `defaultPlugins` default.
- **No `section` field.** For any non-`bar-widget` kind, `setEnabled` ignores the
  placement and pushes the plugin into `plugins[]`, so the hook's `right` is
  harmless for a panel. A VM fixture checks this.
- **New optional field on `defaultPluginSet`:** `packages` (`listOf package`,
  default `[]`), installed through `home.packages` from `resolvedDefaults`. It
  uses the same gate as the plugin, so Mode A installs nothing. For gltui:
  `[ glab python3 xdg-utils ]`.
- **nixarchy owns the menu rows.**
  - `src` is nixarchy's `runCommand`: it copies upstream's package and adds a
    `menu.managed` sentinel. The build fails if `LICENSE` is absent.
  - `apps.gitlab-pipelines` runs `nixarchy-plugin olafkfreund.gitlab-pipelines`,
    and its `when` uses the same helper.
  - `learn.gitlab-pipelines-keybindings` runs `python3 …/menu.py keys`.
- **Seed binds** (new installs only), appended to PR B's block:
  - Super+Alt+P opens the panel;
  - Super+Ctrl+Alt+P shows its keys.
- **Upstream prerequisites:** see "Merge gates".

## Base and rebase

- **Starting point:** branch off `feat/766-pr-b-nixarchy-pkg` (#780, open). That
  is where the seed-bind block and PR B's entry shape come from.
  `git rebase --onto origin/feat/766-pr-b-nixarchy-pkg origin/main` moves the
  intent, spec and plan commits across.
- **After #780 squash-merges:** `git fetch`, then rebuild the branch as
  `origin/main` plus **only this branch's own commits**, cherry-picked in order.
  Never merge `main` in (§8). Rerun the checks on the rebuilt head.

## Merge gates (block merge, not implementation)

- [ ] Upstream nixarchy-gltui: `menu.py register` exits 0 without writing when
      `menu.managed` sits beside it.
- [ ] Upstream nixarchy-gltui: `LICENSE` is in `runtimeFiles` (`flake.nix:15-32`).
- [ ] The pin (`flake.lock`) points at a commit that has both. Until then the
      PR stays in draft.

The upstream changes are the owner's to make. Nothing is filed in the plugin
repo from here (§11).

## Steps

Rules for every step:

- Heavy builds (`checks.options`, `checks.plugin`, anything that builds a
  system) run **only** through `/mnt/data/vmtest/heavy-build.sh <log> <args>`.
  `gh run list` is no longer a gate (owner, 2026-09-19).
- Never pipe a build whose status you need.
- `git add` new files before evaluating (§5).
- Break loops restore with `git checkout HEAD -- <path>` from a committed
  baseline, and use no `git stash`.
- Prove every break landed with `git diff`.
- Commit subjects are plain sentences with the trailers.

1. **Tests first,** in `tests/options.nix`:
   - `gitlabIsADefault`: the id is in `validatedPlugins` on the default home,
     and absent with `defaultPlugins.gitlab = false`.
   - `defaultPluginPackages`: across the fixture split, a fixture entry's
     package is in `home.packages` only when resolved (never standalone, never
     with nixarchy off).
   - `gitlabMenuManaged`: `menu.managed` and `LICENSE` exist in the resolved
     src.

   Commit as the baseline, then build `checks.options` → all three red with
   their own messages. Save the log.
2. **`modules/home.nix`:** add `packages` to the `defaultPluginSet` submodule,
   and `home.packages = lib.concatMap (p: p.packages) (lib.attrValues resolvedDefaults);`
   inside the existing gated block → `defaultPluginPackages` green.
   §1 break: install without `resolvedDefaults`, and the standalone case goes
   red.
3. **`flake.nix` and `flake.lock`:** add the `nixarchy-gltui` input, pinned,
   with `follows`. Add the wrapped package
   `packages.<sys>.nixarchy-gltui` (a `runCommand` that copies upstream's
   `packages.default`, `touch $out/menu.managed`, and
   `test -f $out/LICENSE || exit 1`) → `nix build .#nixarchy-gltui` succeeds,
   and the lock gains one node and no second nixpkgs
   (`jq '.nodes|keys'`).
4. **`modules/home.nix`:** add the `defaultPluginSet.gitlab` entry, and
   `gitlab = true` in `defaultPlugins` → `gitlabIsADefault` and
   `gitlabMenuManaged` green. §1 breaks: delete the entry; drop the `touch`.
5. **`modules/apps.nix` `overrideSpec`:** add the two rows → verify with
   `checks.menu-verbs`, where the plugin-row floor goes up by one. §1 break:
   misspell the id in the row.
   **Check** what a user extension file that already carries these keys
   does: evaluate `menuDefaults` with a fixture extension. Record which copy
   wins in the PR (spec, open question 1).
6. **`pkgs/omarchy/default.nix`:** extend PR B's `printf` block with the two
   binds → the `omarchy` build passes. `grep` the built seed
   `bindings.lua` for both lines.
7. **`tests/plugin.nix`:** add a **panel-kind fixture** to the `defaults` node.
   Assert it is in `plugins[]` of `shell.json`, enabled, with a marker → green
   through `checks.plugin`. §1 break: switch the fixture's `kinds` to
   `bar-widget` without changing the assertion, and it goes red.
8. **Docs:**
   - `docs/internals/flake.md`: the input's reasoning, size and pin-bump
     procedure;
   - `docs/manual/configuration.md`: the plugin table, plus the `packages`
     field in `modules/AGENTS.md`;
   - a README row, then `readme-counts.sh --check`.
9. **Lint:** `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`,
   `nix run nixpkgs#deadnix -- --fail .`.
10. **ISO:** `iso-budget` input and closure growth measured (`glab` about
    50 MiB), and the number recorded in the PR.
11. **Rebase** (see "Base and rebase"), push, and open the PR with the template:
    - links to intent, spec and plan;
    - the red outputs from steps 1, 2, 4, 5 and 7;
    - `Refs #766` and `Closes #770`;
    - the merge-gate checklist.

    PR stays in draft until the gates tick. No auto-merge.

## Owner actions (on the owner's machine, not the PR)

- Before switching to a build with this change:
  `rm ~/.config/omarchy/plugins/olafkfreund.gitlab-pipelines`. It is a symlink
  to the dev checkout, and the reconcile step refuses to replace it. The plugin
  stays in `shell.json`; the hook writes the marker because it is already
  enabled, and the managed copy takes over.
- `bindings.lua` already binds Super+Alt+P and is not touched.

## Tests

| command | expected |
|---|---|
| `heavy-build.sh $log .#checks.x86_64-linux.options` | green. Red at each break above, with the case named |
| `heavy-build.sh $log .#checks.x86_64-linux.plugin` | green. Red with `bar-widget` kind: panel fixture not in `plugins[]` |
| `nix build .#checks.x86_64-linux.menu-verbs` | green. Red on a misspelled id |
| `nix build .#nixarchy-gltui && ls result/{menu.managed,LICENSE}` | both present |
| `nix build .#omarchy` | green, and the seed contains both P binds |

## Rollback

Revert the squash commit. The input, entry, rows and binds go. Machines that
already enabled the panel keep it in `shell.json`, pointing at a plugin
directory that reconcile removes. The shell then skips an id it cannot find,
and the user can disable it in Setup > Plugins. `packages` goes too, and it's
harmless because nothing else uses it yet.
