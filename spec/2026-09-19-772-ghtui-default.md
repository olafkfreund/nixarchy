---
status: approved
issue: 772
intent: intent/2026-09-19-772-ghtui-default.md
---

# Spec: the GitHub Actions panel ships with nixarchy and is on by default

## Design

**This is #770 again, for GitHub.** nixarchy-ghtui is the panel gltui was
forked from, so every piece of #786 (merged) has a one-line counterpart here,
and no new mechanism is needed.

- **Input** (`flake.nix`, next to `nixarchy-gltui`): `nixarchy-ghtui`, pinned
  to `dfba799b5153` (upstream's merge of #17, which added the MIT LICENSE),
  with `inputs.nixpkgs.follows = "nixpkgs"`. Plus a `# Why:` pointer to a new
  `docs/internals/flake.md` entry, like #770's.
- **Wrapper** (`modules/home.nix`, next to `gitlabPipelines`): `githubActions`,
  a `runCommand` that copies upstream's package, runs `touch menu.managed`, and
  copies `${inputs.nixarchy-ghtui}/LICENSE` when the package omits it.
  Upstream's `runtimeFiles` list (`manifest.json` … `keybindings.sh`) still
  leaves the LICENSE out, the same gap gltui had.
- **Default entry** (`defaultPluginSet.github`, next to `gitlab`):
  `id = "olafkfreund.github-actions"`, `src = githubActions`,
  `packages = [ pkgs.gh pkgs.python3 pkgs.xdg-utils ]`. The plugin is
  panel-only (`kinds: ["panel"]`), so #786's existing handling applies:
  upstream's `setEnabled` routes a panel into `plugins[]` whatever section the
  hook passes. `defaultPlugins.github = true` is added to the option's default
  set.
- **Menu rows** (`modules/apps.nix`, next to the GitLab rows):
  - `apps.github-actions` → `nixarchy-plugin olafkfreund.github-actions`;
  - `learn.github-actions-keybindings` → `python3 $HOME/.config/omarchy/plugins/olafkfreund.github-actions/menu.py keys`.
    ghtui's `menu.py` accepts `keys`, as gltui's does.
  - Both rows carry `when = "nixarchy-plugin --enabled olafkfreund.github-actions"`.
  - Aliases: `github`, `actions`, `workflows`, `ci`.
- **Seed binds** (`pkgs/omarchy/default.nix`, the same `printf` block that
  carries Super+Alt+P): **Super+Alt+A** → `nixarchy-plugin olafkfreund.github-actions`,
  and **Super+Ctrl+Alt+A** → the keys sheet. Upstream's Super+Shift+Alt+A (Grok)
  and Super+Ctrl+A (Audio) are different chords, and nixarchy binds neither
  combination (checked in #772's issue).
- **Docs:** `docs/manual/plugins.md` moves GitHub Actions from "coming" to "on
  by default", with its menu row and key; plus `configuration.md`'s default
  list, the README feature row and `docs/internals/flake.md`.

**The upstream `menu.managed` gate is the same as #786's, and not a merge
blocker.** ghtui's `menu.py` doesn't yet check for the sentinel. Until it does,
opening the panel still registers its own rows in the user's menu file. That is
harmless duplication, because the user's file wins key by key, and #786 merged
on the same terms. The PR lists it as an unchecked upstream item.

## Alternatives rejected

- **Generalising the gltui wrapper into a function for both panels.** Two call
  sites don't justify an abstraction. #770's wrapper is three lines, and a
  copy keeps each plugin's history readable. Revisit at the third fork.
- **Waiting for upstream `menu.managed`.** #786 already merged without it, so
  holding ghtui to a stricter bar than its own fork buys nothing.
- **Omitting `gh` and relying on the user's.** A panel whose CLI might be
  missing reads as broken, and #770 established that the plugin brings its
  tools.

## Risks

- **`gh` not logged in:** the panel shows "Authenticate with gh auth login"
  and stops polling (`actions.py`, verified in the #772 review), so there are
  no background errors.
- **Closure growth:** `gh` is roughly 50 MiB, like `glab`. It is measured and
  recorded in `docs/internals/flake.md`, as #770 did.
- **A second id in the default set:** the manifest-id assertion (#775) covers
  it. A pin that renames the id fails the build.
- **Migration:** the owner's machine has a hand-copied checkout at
  `~/.config/omarchy/plugins/olafkfreund.github-actions`, which the
  declarative install refuses to replace. It's an owner step, documented in
  the PR: move it aside before switching.

## Verification (each broken first, §1)

- `checks.options`:
  - `githubIsADefault`: present on the default home, absent when opted out,
    on standalone Home Manager, and with nixarchy off. Break: remove the entry.
  - `githubMenuManaged`: the installed copy has `menu.managed` and `LICENSE`.
    Break: drop the `touch`.
  - `defaultPluginPackages` extended to `gh`.
- `checks.menu-verbs`: the plugin-row floor rises by one, and a row naming
  `olafkfreund.github-actionz` must fail.
- `.#omarchy`: the seed-bind anchor still asserts, and the built seed ends with
  the A lines.
- `checks.plugin`: unchanged. #786's panel fixture already proves panel-only
  enablement.
- `nix fmt -- --ci`, statix, deadnix. Heavy builds go through
  `/mnt/data/vmtest/heavy-build.sh`.
