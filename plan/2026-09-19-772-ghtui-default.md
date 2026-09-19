---
status: approved
issue: 772
spec: spec/2026-09-19-772-ghtui-default.md
---

# Plan: the GitHub Actions panel ships with nixarchy and is on by default

## Approved decisions (self-contained)

This is #770 (gltui, merged as #786) again, for GitHub. Every piece has a
merged twin on `main` to copy.

- **The plugin:** `olafkfreund.github-actions` (kind `panel`), from a new input
  `nixarchy-ghtui`, pinned at `dfba799b5153` (upstream's MIT licence merge), with
  `inputs.nixpkgs.follows = "nixpkgs"`. Twin: `nixarchy-gltui` in `flake.nix`.
- **nixarchy's wrapper:** `githubActions`, a `runCommand` in `modules/home.nix`
  beside `gitlabPipelines` (`home.nix:~267`). It copies upstream's package, adds
  a `menu.managed` sentinel, and copies `LICENSE` from the input's source tree
  when the package omits it (upstream's `runtimeFiles` still does). The build
  fails if `LICENSE` is still absent.
- **On by default:** `defaultPluginSet.github`, panel-only (no `section`; a
  panel lands in `plugins[]`, as #770 proved), with
  `packages = [ gh python3 xdg-utils ]`, and `github = true` in the
  `defaultPlugins` default. The same gate as the others keeps Mode A clean.
- **nixarchy owns the menu rows:**
  - `apps.github-actions` runs `nixarchy-plugin olafkfreund.github-actions`,
    and its `when` uses the same helper;
  - `learn.github-actions-keybindings` runs
    `python3 $HOME/.config/omarchy/plugins/olafkfreund.github-actions/menu.py keys`
    (ghtui's `menu.py` accepts `keys`).
- **Seed binds** (new installs only), in the same `printf` list as P, N, O and
  H (`pkgs/omarchy/default.nix:~1947`):
  - Super+Alt+A opens the panel;
  - Super+Ctrl+Alt+A shows its keys.

  Neither collides with upstream Omarchy or with the owner's `bindings.lua`.
- **Upstream gate, as with #786, not a merge blocker:** `menu.py register`
  respects `menu.managed`. Until upstream does, the panel still writes its own
  rows, and the user's copy wins key by key (the manual already says which keys
  to delete).

## Base: the batch branch

This ships in one PR with #766 PR D and PR E and #800, on
**`feat/batch-766-800-772`** (worktree `/mnt/data/vmtest/nixarchy-batch`). Those
PRs touch the same shared blocks: the `defaultPluginSet` attrset and the
`defaultPlugins` default in `modules/home.nix`, the `overrideSpec` rows in
`modules/apps.nix`, the plugin-row floor in `tests/menu-verbs.nix`, and the
seed-bind `printf` list. So:

- cherry-pick this branch's intent, spec and plan commits onto the batch branch;
- make each step below against **the batch branch's current state** of those
  blocks, adding one entry, one row, one floor increment and two bind lines,
  not replacing anything another part added;
- rebase the batch branch onto `origin/main` before pushing (§9), and never
  merge `main` in (§8).

## Steps

Rules for every step:

- Heavy builds run only through `/mnt/data/vmtest/heavy-build.sh <log> <args>`.
- Never pipe a build whose status you need.
- `git add` new files before evaluating (§5).
- Break loops restore with `git checkout HEAD -- <path>` from a committed
  baseline, and use no `git stash`. Prove each break landed with `git diff`.
- Commit subjects are plain sentences with the trailers. A deviation goes into
  this plan in the same commit as the code.

1. **Tests first,** in `tests/options.nix`, mirroring `gitlabIsADefault`
   (`options.nix:~845`) and `gitlabMenuManaged` (`~4948`):
   - `githubIsADefault`: the id is in `validatedPlugins` on the default home,
     absent with `defaultPlugins.github = false`, standalone, and with nixarchy
     off;
   - `githubMenuManaged`: `menu.managed` and `LICENSE` exist in the resolved
     src;
   - extend `defaultPluginPackages`, or add a case, so `gh` is in
     `home.packages` only when the entry resolves.

   Commit as the baseline, then build `checks.options` → red, with each case
   named. Save the log.
2. **`flake.nix` and `flake.lock`:** add the `nixarchy-ghtui` input at
   `dfba799b5153` with `follows` → the lock gains one node and no second
   nixpkgs (`jq '.nodes|keys'`).
3. **`modules/home.nix`:** the `githubActions` wrapper and the
   `defaultPluginSet.github` entry, and `github = true` →
   `githubIsADefault`, `githubMenuManaged` and the packages case go green.
   §1 breaks: delete the entry; drop the `touch`.
4. **`modules/apps.nix` `overrideSpec`:** the two rows →
   `checks.menu-verbs`, with the plugin-row floor raised by one from the batch
   branch's value. §1 break: misspell the id in the row.
5. **`pkgs/omarchy/default.nix`:** two lines in the seed-bind `printf` →
   the `omarchy` build passes. `grep` the built seed `bindings.lua` for both A
   lines. §1 break: point the anchor at a missing line, and the build fails
   with its anchor message.
6. **Docs:**
   - `docs/manual/plugins.md`: GitHub Actions moves from "coming" to
     "on by default", with its row and key;
   - `docs/manual/configuration.md`: `defaultPlugins.github` in the opt-out
     list;
   - `docs/internals/flake.md`: the input's reasoning, size and pin-bump
     procedure;
   - a README row, then `readme-counts.sh --check`.
7. **Lint:** `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`,
   `nix run nixpkgs#deadnix -- --fail .`.
8. **Size:** the input source and closure growth (`gh`), recorded in the PR.
9. **Merge-time licence check:**
   `gh repo view olafkfreund/nixarchy-ghtui --json licenseInfo` shows `MIT`.
   If GitHub's detection still lags, paste the `LICENSE` file's first lines
   ("MIT License / Copyright (c) 2026 Olaf Krasicki-Freund") into the PR as the
   evidence instead.
10. **PR** (the batch PR): link this intent, spec and plan, include the red
    outputs from steps 1, 3, 4 and 5, and add `Closes #772`.

## Owner actions (on the owner's machine, not the PR)

- Before switching: `rm -rf ~/.config/omarchy/plugins/olafkfreund.github-actions`.
  It is a hand-copied checkout, and reconcile refuses to replace a real
  directory. It stays enabled in `shell.json`, and the managed copy takes over.
- The owner's `bindings.lua` already binds Super+Alt+A, and is not touched.

## Tests

| command | expected |
|---|---|
| `heavy-build.sh $log .#checks.x86_64-linux.options` | green. Red at each break above, with the case named |
| `nix build .#checks.x86_64-linux.menu-verbs` | green. Red on a misspelled id |
| `nix build .#omarchy` | green; the seed contains both A binds. Red on a missing anchor |
| `nix eval` of the resolved src, then `ls {menu.managed,LICENSE}` | both present |

## Rollback

Revert the batch squash commit, or just the GitHub parts: the input, the
wrapper, the entry, the rows and the binds. Machines that already enabled the
panel keep it in `shell.json` pointing at a directory reconcile removes. The
shell skips an id it cannot find, and the user can disable it in
Setup > Plugins. `gh` leaves `home.packages` with it.
