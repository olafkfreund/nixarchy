---
status: approved
issue: 771
spec: spec/2026-09-19-771-herdr-default.md
---

# Plan: the herdr sessions widget ships with nixarchy and is on by default

## Approved decisions (self-contained)

- **The plugin:** `nixarchy.herdr` (`menu` plus `bar-widget`, in the right
  section), from `nixarchy-herdr`.
- **Input:** `flake = false` and commit-pinned. There is no `follows`, because
  the repo has no flake.
- **nixarchy's wrapper** is a `runCommand`, `packages.<sys>.nixarchy-herdr`.
  It:
  - copies the tree without `intent/`, `spec/`, `plan/`, `tests/` or
    `preview.png`, with plain copies;
  - runs `chmod +x bin/*`;
  - runs `patchShebangs bin/`, because both scripts say `#!/bin/bash` and today
    work only through envfs;
  - keeps `LICENSE`, and the build fails unless it names both Jankees van
    Woezik and olafkfreund.
- **On by default:** `defaultPluginSet.herdr`, with
  `packages = [ herdr jq iproute2 ]` (from #770), plus `herdr = true` in
  `defaultPlugins`.
- **herdr itself:** nixpkgs' `herdr` (0.9.0 at the pin) covers every call the
  widget makes. On the owner's machine, his `/etc/nixos` input (0.9.1) keeps
  priority.
- **Rows:** `apps.herdr` runs `nixarchy-plugin nixarchy.herdr`, and
  `learn.herdr-keybindings` runs `…/bin/herdr-menu-keys`.
- **Seed bind:** Super+Alt+H, for new installs only.

## Base and rebase

- **Starting point:** build on #770's branch (`feat/770-gltui-default`), which
  adds `packages`; that itself sits on #780. Start with
  `git rebase --onto origin/feat/770-gltui-default origin/main`. The intent,
  spec and plan commits move across.
- **As each base squash-merges** (#780, then #770): `git fetch`, then rebuild
  as `origin/main` plus **only this branch's own commits**, cherry-picked in
  order. Never merge `main` in (§8). Rerun the checks on the rebuilt head.

## Merge gates (block merge, not implementation)

- [ ] Upstream nixarchy-herdr: Delete asks first, from both the key and the
      click (`Card.qml:97-99,629-639`), and defaults to Cancel.
- [ ] Upstream nixarchy-herdr: Delete reports failure. `bin/herdr-sessions:821`
      loses `|| true` and passes on the exit status and stderr.
- [ ] The pin points at a commit with both. PR stays in draft until then.

The upstream changes are the owner's (§11). Nothing is filed from here.

## Steps

Rules for every step:

- Heavy builds only through `/mnt/data/vmtest/heavy-build.sh <log> <args>`.
  `gh run list` is not a gate.
- Never pipe a build whose status you need.
- `git add` new files before evaluating.
- Restore with `git checkout HEAD -- <path>` from a committed baseline, and use
  no `git stash`.
- Confirm every break landed with `git diff`.
- Commit subjects are plain sentences with the trailers.

1. **Tests first,** in `tests/options.nix`:
   - `herdrIsADefault`: present by default; absent with
     `defaultPlugins.herdr = false`, standalone, and with nixarchy off.
   - `herdrPackaged`: in the resolved src, `bin/herdr-sessions` and
     `bin/herdr-menu-keys` have `/nix/store` shebangs, and `LICENSE` contains
     both names.

   Commit the baseline, then run `checks.options` → both red. Save the log.
2. **`flake.nix` and `flake.lock`:** add the `nixarchy-herdr` input
   (`flake = false`, pinned) and the `packages.<sys>.nixarchy-herdr` wrapper →
   `nix build .#nixarchy-herdr`. Then
   `head -1 result/bin/herdr-sessions` starts with `/nix/store`, and
   `grep -c` finds both copyright names in `result/LICENSE`.
3. **`modules/home.nix`:** add the `defaultPluginSet.herdr` entry, and
   `herdr = true` in `defaultPlugins` → `herdrIsADefault` and `herdrPackaged`
   green. §1 breaks: delete the entry; drop `patchShebangs`; drop `LICENSE`
   from the copy.
4. **`tests/menu-verbs.nix`:** a new claim. Every `herdr <subcommand>` that
   `bin/herdr-sessions` sends (session list/stop/delete, api snapshot,
   agent focus/prompt, `--session`, `--remote`) appears in the pinned herdr's
   `--help` output for that level → green.
   §1 break: add a fixture copy of the script with `herdr session frobnicate`,
   and it goes red.
5. **`modules/apps.nix` `overrideSpec`:** add the two rows → the menu-verbs
   plugin-row floor goes up by one. §1 break: a misspelled id.
6. **`pkgs/omarchy/default.nix`:** the seed block gains
   `o.bind("SUPER + ALT + H", "Herdr", "nixarchy-plugin nixarchy.herdr")` →
   the `omarchy` build passes, and `grep` finds it in the seed.
7. **`tests/plugin.nix`:** on the `defaults` node, `herdr` resolves from the
   session PATH, and `herdr-sessions list` returns `"ok":true` with no sessions
   → green through `checks.plugin`. §1 break: remove `pkgs.herdr` from
   `packages`, and the result says "herdr is not installed".
8. **Docs:**
   - `docs/internals/flake.md`: why a non-flake input, the size, and the
     pin-bump procedure, including re-running step 4's claim;
   - `docs/manual/configuration.md` and the README row;
   - a note that `herdr update` cannot write to the store;
   - `readme-counts.sh --check`.
9. Run fmt, statix and deadnix. Measure ISO growth and record it in the PR.
10. **Rebase, push and open the PR:**
    - links to intent, spec and plan;
    - the red outputs from steps 1, 3, 4, 5 and 7;
    - `Refs #766` and `Closes #771`;
    - the merge-gate checklist.

    It stays in draft until the gates tick. No auto-merge.

## Owner actions (on the owner's machine)

- **Before switching:** remove the hand-copied
  `~/.config/omarchy/plugins/nixarchy.herdr` and the leftover
  `.jankeesvw.herdr.bak.*`. Reconcile refuses to replace an unmanaged directory.
  The plugin stays enabled in `shell.json`, and the hook writes its marker.
- **herdr version precedence:** after switching, run `type -a herdr` and
  `herdr --version`. The intent keeps the `/etc/nixos` input (0.9.1) first. If
  the nixpkgs 0.9.0 shows first, either drop the plugin's `herdr` package on
  this host (`defaultPluginSet` is internal, so this is an override in
  `/etc/nixos`) or order the profiles. The plan records the result in the PR.
- `bindings.lua:317` (Super+Shift+H) is not touched.

## Tests

| command | expected |
|---|---|
| `heavy-build.sh $log .#checks.x86_64-linux.options` | green; red at each break above, naming the case |
| `nix build .#checks.x86_64-linux.menu-verbs` | green; red with `frobnicate` or a misspelled id |
| `heavy-build.sh $log .#checks.x86_64-linux.plugin` | green; red without `pkgs.herdr` ("herdr is not installed") |
| `nix build .#nixarchy-herdr` | a store shebang in `bin/*`, and both copyright names in `LICENSE` |
| `nix build .#omarchy` | green, and the seed has the H bind |

## Rollback

Revert the squash commit. The input, wrapper, entry, rows and bind go, and
`herdr`, `jq` and `iproute2` leave the profile. Homes that already enabled the
widget keep an id in `shell.json` whose directory reconcile removes. The shell
skips it, and the user disables it in Setup > Plugins.

## Deviations (recorded during implementation)

- **Steps 2-3, where the wrapper lives:** in `modules/home.nix` as the
  `herdrSessions` runCommand, not a flake `packages.<sys>.nixarchy-herdr`
  output. Same place and reason as #770's gltui wrapper: `home.nix:258-263`
  says home-side packages go through the user's nixpkgs. Step 2's check reads
  the resolved `defaultPluginSet.herdr.src` instead of `.#nixarchy-herdr`.
- **Step 1, `herdrPackaged`:** a runtime assertion in the options check's
  script, reached only once every option case passes. Step 1's red run
  shows `herdrIsADefault` alone; `herdrPackaged` is proven red by step 3's
  breaks.
