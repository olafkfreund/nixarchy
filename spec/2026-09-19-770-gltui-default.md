---
status: approved
issue: 770
intent: intent/2026-09-19-770-gltui-default.md
---

# Spec: the GitLab pipelines panel ships with nixarchy and is on by default

## Design

This follows #766 PR B (#780, nixarchy-pkg) and lands after it: it reuses PR B's
seed-bind block and its `defaultPluginSet` entry shape.

**D1. No `section` field. The hook's `right` is already correct for a panel.**
Codex proposed a nullable `section` on `defaultPluginSet` for panel-only plugins,
so the plan checked what the hook's `omarchy-plugin-enable <id> right` actually
does to one. `omarchy-plugin-enable` refuses a placement only for `kinds: bar`,
and gltui is `panel`. The shell's `setEnabled`
(`shell/services/PluginRegistry.qml:486-541` in the vendored tree) uses the
placement **only** when the manifest has `bar-widget`. Anything else is pushed
into `config.plugins`, and the placement is never read. A panel therefore lands
in `plugins[]`, which is exactly where the #766 helper and hook look for it
(`pkgs/nixarchy-plugin.nix`, and the hook's `omarchy-plugin-list` check). No
schema change. A `checks.plugin` case (Verification) makes this a checked fact instead of a
reading of upstream's code.

**D2. Add `packages` to `defaultPluginSet`.** An optional
`packages = listOf package`, default `[]`, installed with
`home.packages = concatMap (p: p.packages) (attrValues resolvedDefaults)`. That
is the same gate as the plugin itself, so Mode A, `defaultPlugins.gitlab = false`
and nixarchy-off all install nothing. It goes on the session PATH through the
Home Manager profile, and that PATH is the one Quickshell's `Process` calls
inherit. The panel runs `python3 actions.py` (`ActionsPanel.qml:159`), which
runs `glab api` (`actions.py:40`), plus `xdg-open` for links. So:
`packages = [ glab python3 xdg-utils ]`. Services, credentials and a11y stay
out of the plugin set.

**D3. The entry.**
```
defaultPluginSet.gitlab = {
  id = "olafkfreund.gitlab-pipelines";
  src = <nixarchy's wrapped package, D4>;
  packages = [ pkgs.glab pkgs.python3 pkgs.xdg-utils ];
};
```
Plus `gitlab = true` in the `defaultPlugins` default. The input is
`nixarchy-gltui`, commit-pinned, with `inputs.nixpkgs.follows = "nixpkgs"`. Its
reasoning, size and pin-bump procedure go in `docs/internals/flake.md`, as in
PR B.

**D4. nixarchy owns the menu rows, and the plugin is told so through a
sentinel file.** Every time the panel loads, `menu.py register`
(`ActionsPanel.qml:186-195`, `menu.py:61`) adds any of its default keys that are
*missing* from the user's `omarchy-menu.jsonc`. A row the user deleted is
missing, so it comes back. An environment variable cannot reliably reach a
Quickshell-spawned process, so the switch is a file:

- **Upstream (a prerequisite, in the plugin repo, not filed by us):**
  `register` returns 0 without writing when `menu.managed` sits beside
  `menu.py`. The repo also adds `LICENSE` to `runtimeFiles` (`flake.nix:15-32`
  leaves it out, although the repo now has one).
- **nixarchy:** `src` is a small `runCommand` that copies the upstream package
  and adds `menu.managed`. That wraps upstream rather than patching it (§11).
  If `LICENSE` is missing from the upstream output, the build fails, so the MIT
  notice travels with every copy.
- **Rows, in `modules/apps.nix` `overrideSpec`**, both using the upstream keys
  (the plan checks what happens to a user extension file that already carries
  them):
  - `apps.gitlab-pipelines`: action and `when` both through
    `nixarchy-plugin olafkfreund.gitlab-pipelines`.
  - `learn.gitlab-pipelines-keybindings`:
    `python3 ~/.config/omarchy/plugins/olafkfreund.gitlab-pipelines/menu.py keys`.
    That path is where `programs.nixarchy.plugins` links the plugin, and
    python3 is on PATH from D2.

**D5. Binds.** Appended to PR B's seed block, for new installs only:
- `o.bind("SUPER + ALT + P", "GitLab Pipelines", "nixarchy-plugin olafkfreund.gitlab-pipelines")`
- `o.bind("SUPER + CTRL + ALT + P", "GitLab Pipelines keybindings", "python3 ~/.config/omarchy/plugins/olafkfreund.gitlab-pipelines/menu.py keys")`

Both chords are free upstream and in nixarchy. The owner's own `bindings.lua`
already uses Super+Alt+P for this panel, and it is not touched.

**D6. The owner's machine.** `~/.config/omarchy/plugins/olafkfreund.gitlab-pipelines`
is a symlink to `/mnt/data/Source-home/GitHub/nixarchy-gltui`, and the reconcile
step refuses to replace something it does not manage. The PR says to remove the
symlink before switching. That turns off nothing: the plugin stays in
`shell.json`, the marker is written because it is already enabled, and the
managed copy takes its place.

## Alternatives rejected

- **A `section` enum:** see D1. The shell never reads a placement for a
  non-widget plugin, so a field would describe something that cannot vary.
- **An environment variable to switch self-registration off:** Quickshell
  children inherit the shell's environment, and nothing guarantees that a Home
  Manager session variable reaches it. This spec did not verify it either way.
  A file beside `menu.py` cannot miss.
- **Patching `menu.py` inside nixarchy:** that is a carried patch against a repo
  the owner controls. A one-line upstream change costs less, lasts longer, and
  fixes the same bug for anyone who installs the plugin by hand.
- **`packages` through `home.packages` written by hand beside the entry:** it
  would duplicate the gate. With a field there is one resolution and one Mode A
  test.

## Risks

- **`glab` on PATH is a new user-visible command on every machine.** It is
  read-only here, and harmless until someone runs `glab auth login`. Not logged
  in, the panel shows "Authenticate with glab auth login" (`actions.py:160`) and
  stops polling.
- **`python3` on the user's PATH** can shadow a devenv's Python outside a
  project shell. It already comes with plenty of desktops, and devenv puts its
  own first.
- **Upstream order:** if `menu.managed` support hasn't landed when this merges,
  the sentinel is ignored and rows the user deleted come back, as they do today.
  The PR checks the pinned commit has it.
- **ISO:** `glab` is about 50 MiB. Measured against `iso-budget` in the PR.

## Verification

Every check is proven red first (§1), with the break confirmed by `git diff`,
and existing checks only (no new `checks.<name>`, §4):

- **`checks.options`:**
  - `gitlabIsADefault`: the id is in `validatedPlugins` on the default home and
    absent with `defaultPlugins.gitlab = false`. Break: delete the entry.
  - `defaultPluginPackages`: `glab` is in `home.packages` on the default home,
    and absent on standalone Home Manager and with nixarchy off (the fixture
    split). Break: install `packages` without the gate, so the standalone case
    goes red.
  - `gitlabMenuManaged`: `menu.managed` and `LICENSE` exist in the resolved
    `src`. Break: drop the `touch`.
- **`checks.plugin` (VM):** the `defaults` node gains a **panel-kind fixture**,
  asserting it ends up in `plugins[]`, enabled, with a marker. That is D1 as a
  check. Break: give the fixture `bar-widget` kind without a placement path; the
  `plugins[]` assertion fails.
- **`checks.menu-verbs`:** the plugin-row floor goes up by one, and the new row's
  id resolves to an installed manifest. Break: misspell the id.
- **`omarchy` build:** the seed block's anchor assertion is PR B's, unchanged.
- **By hand, after switching:** Super+Alt+P opens the panel. A deleted
  GitLab menu row stays deleted after reopening the panel.
